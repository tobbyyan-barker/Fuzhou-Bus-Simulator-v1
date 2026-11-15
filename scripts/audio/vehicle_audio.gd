## 客车音效系统（V0.3）：发动机 / 行驶 / 制动音效 + 内外听感适配 + 转向灯节拍音
## 设计原则：
## 1. 只监听车辆状态（速度/油门/刹车踏板，经 BusController 只读 getter），
##    不改动任何车辆动力学参数或相机逻辑；
## 2. 全部音效为运行时合成 PCM（AudioSynth，零外部素材）；替换为真实客车
##    录音时只需换 stream，本类的状态驱动接口（音量/音调/触发）不变；
## 3. 内外听感：所有车辆声音走 "Vehicle" 总线（低通 + 增益随视角连续过渡），
##    再叠加各声道独立的驾驶舱衰减偏置——视角切换只渐变参数，不中断声音。
## 转速模型说明：RPM 不是车速——由油门行程主导、带升降滞后（模拟油门拉杆/
## 飞轮惯性），松油门滑行时叠加与车速弱耦合的发动机制动转速；输出到
## pitch_scale = rpm / idle_rpm 实现连续变调。
class_name VehicleAudio
extends Node

## 发动机状态（测试可读）
const STATE_OFF := 0
const STATE_CRANKING := 1
const STATE_RUNNING := 2
const STATE_STOPPING := 3

const BUS_NAME := "Vehicle"

@export var bus: BusController
@export var cam_mgr: CameraManager

@export_group("发动机")
@export var engine_db := -12.0
@export var idle_rpm := 720.0
@export var max_rpm := 2100.0
## 松油门滑行时的发动机制动转速耦合上限（rpm，叠加在怠速之上、随车速比例）
@export var coast_coupled_rpm := 800.0
@export var rpm_rise_lag_s := 0.35
@export var rpm_fall_lag_s := 0.9
@export var crank_seconds := 1.1
@export var spool_seconds := 1.2

@export_group("行驶音效")
@export var road_db := -18.0
@export var wind_db := -22.0
@export var road_start_kmh := 2.0
@export var road_full_kmh := 55.0

@export_group("制动")
@export var brake_db := -16.0
## 踏板从低于该值升到不低于该值 → 触发一次气刹放气
@export var brake_trigger_pedal := 0.18
## 放气声冷却（s）：冷却期内踏板反复踩放不重复触发，避免刺耳叠加
@export var brake_cooldown_s := 0.7
## 行车制动后停稳 → 驻车弹簧制动声的最小制动车速（km/h）
@export var parking_min_speed_kmh := 8.0

@export_group("转向灯节拍")
@export var click_db := -13.0

@export_group("内外听感（Vehicle 总线）")
@export var view_mix_rate := 4.0
@export var interior_cutoff_hz := 1800.0
@export var exterior_cutoff_hz := 16000.0
@export var interior_bus_gain_db := -3.5
## 各声道在驾驶舱内的额外衰减（dB）；车外为 0（喇叭由 horn.gd 走同一总线）
@export var interior_engine_db := -2.0
@export var interior_road_db := -3.0
@export var interior_wind_db := -6.0
@export var interior_brake_db := -4.0
@export var interior_click_db := -1.0

@export_group("过渡平滑")
@export var vol_lerp_rate := 6.0
@export var pitch_lerp_rate := 5.0

## 状态（测试/诊断可读）
var engine_state: int = STATE_OFF
var rpm: float = 0.0
var engine_loop_playing: bool = false
var brake_hiss_count: int = 0
var parking_count: int = 0
var click_count: int = 0

var _engine_loop: AudioStreamPlayer
var _crank: AudioStreamPlayer
var _road: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _hiss: AudioStreamPlayer
var _parking: AudioStreamPlayer
var _click_a: AudioStreamPlayer
var _click_b: AudioStreamPlayer

var _engine_vol := -60.0
var _engine_vol_t := -60.0
var _engine_pitch := 0.62
var _engine_pitch_t := 0.62
var _road_vol := -60.0
var _road_vol_t := -60.0
var _road_pitch := 0.9
var _road_pitch_t := 0.9
var _wind_vol := -60.0
var _wind_vol_t := -60.0
var _view_mix := 0.0  # 0 = 车外听感，1 = 驾驶舱内听感

var _state_timer := 0.0
var _auto_start_delay := 0.4
var _auto_started := false
var _prev_brake_pedal := 0.0
var _brake_cooldown := 0.0
var _was_braking_fast := false
var _parking_cooldown := 0.0
var _lp: AudioEffectLowPassFilter
var _amp: AudioEffectAmplify


func _ready() -> void:
	_setup_bus()
	_engine_loop = _player(AudioSynth.make_engine_loop())
	_crank = _player(AudioSynth.make_crank())
	_road = _player(AudioSynth.make_road_loop())
	_wind = _player(AudioSynth.make_wind_loop())
	_hiss = _player(AudioSynth.make_air_hiss())
	_parking = _player(AudioSynth.make_parking_brake())
	_click_a = _player(AudioSynth.make_click(1700.0))
	_click_b = _player(AudioSynth.make_click(1300.0))
	# 行驶底噪循环常开（音量从静音拉起，静止时接近无声）
	_road.play()
	_wind.play()


func _player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = BUS_NAME
	p.stream = stream
	add_child(p)
	return p


func _setup_bus() -> void:
	var idx: int = AudioServer.get_bus_index(BUS_NAME)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, BUS_NAME)
		AudioServer.set_bus_send(idx, "Master")
	if AudioServer.get_bus_effect_count(idx) == 0:
		_lp = AudioEffectLowPassFilter.new()
		_lp.cutoff_hz = exterior_cutoff_hz
		_amp = AudioEffectAmplify.new()
		_amp.volume_db = 0.0
		AudioServer.add_bus_effect(idx, _lp)
		AudioServer.add_bus_effect(idx, _amp)
	else:
		_lp = AudioServer.get_bus_effect(idx, 0)
		_amp = AudioServer.get_bus_effect(idx, 1)


func _physics_process(delta: float) -> void:
	if bus == null:
		return
	_state_timer += delta
	_brake_cooldown -= delta
	_parking_cooldown -= delta
	_update_engine(delta)
	_update_driving()
	_update_brake()
	_update_view_mix(delta)
	_apply_smoothing(delta)


## ---- 发动机：点火/熄火状态机 + 近似转速模型 ----

func toggle_ignition() -> void:
	if engine_state == STATE_OFF:
		engine_state = STATE_CRANKING
		_state_timer = 0.0
		rpm = idle_rpm * 0.62
		_crank.play()
		_engine_loop.play()
		engine_loop_playing = true
	elif engine_state == STATE_RUNNING or engine_state == STATE_CRANKING:
		engine_state = STATE_STOPPING
		_state_timer = 0.0
		_crank.stop()


func _update_engine(delta: float) -> void:
	if Input.is_action_just_pressed("engine_toggle"):
		toggle_ignition()
	if engine_state == STATE_OFF and not _auto_started:
		# 场景就绪后自动点火（听到起动声）；此后 E 键由玩家控制点火/熄火
		_auto_start_delay -= delta
		if _auto_start_delay <= 0.0:
			_auto_started = true
			toggle_ignition()
	match engine_state:
		STATE_CRANKING:
			_engine_pitch_t = 0.62
			_engine_vol_t = engine_db - 9.0 \
					+ 3.0 * clampf(_state_timer / crank_seconds, 0.0, 1.0)
			if _state_timer >= crank_seconds:
				engine_state = STATE_RUNNING
				_state_timer = 0.0
		STATE_RUNNING:
			var throttle: float = bus.get_throttle_pedal()
			var v: float = bus.get_speed_kmh()
			var target: float = idle_rpm + throttle * (max_rpm - idle_rpm)
			var speed_ratio: float = clampf(v / 60.0, 0.0, 1.0)
			if throttle < 0.05 and v > 3.0:
				# 松油门滑行：发动机与车轮弱耦合（发动机制动的转速回落）
				target = maxf(target, idle_rpm + coast_coupled_rpm * speed_ratio)
			var lag: float = rpm_rise_lag_s if target > rpm else rpm_fall_lag_s
			rpm = lerpf(rpm, target, clampf(delta / maxf(lag, 0.01), 0.0, 1.0))
			_engine_pitch_t = maxf(0.5, rpm / idle_rpm)
			var load: float = clampf((rpm - idle_rpm) / maxf(max_rpm - idle_rpm, 1.0), 0.0, 1.0)
			_engine_vol_t = engine_db - 6.0 + 8.0 * throttle + 4.0 * load
		STATE_STOPPING:
			_engine_pitch_t = 0.45
			_engine_vol_t = engine_db - 10.0 \
					- 12.0 * clampf(_state_timer / spool_seconds, 0.0, 1.0)
			if _state_timer >= spool_seconds:
				engine_state = STATE_OFF
				engine_loop_playing = false
				_engine_loop.stop()
				rpm = 0.0
		STATE_OFF:
			_engine_vol_t = -60.0


## ---- 行驶音效：路面摩擦 + 风噪（音量随车速，静止近无声） ----

func _update_driving() -> void:
	var v: float = bus.get_speed_kmh()
	var x: float = clampf((v - road_start_kmh) / maxf(road_full_kmh - road_start_kmh, 1.0), 0.0, 1.0)
	_road_vol_t = road_db + lerpf(-30.0, 0.0, x)
	_road_pitch_t = 0.88 + 0.32 * x
	var y: float = clampf(pow(v / 95.0, 2.0), 0.0, 1.0)
	_wind_vol_t = wind_db + lerpf(-32.0, 0.0, y)


## ---- 制动：气刹放气（沿触发 + 冷却）+ 停稳驻车声 ----

func _update_brake() -> void:
	var pedal: float = bus.get_brake_pedal()
	if _prev_brake_pedal < brake_trigger_pedal and pedal >= brake_trigger_pedal \
			and _brake_cooldown <= 0.0:
		_brake_cooldown = brake_cooldown_s
		brake_hiss_count += 1
		_hiss.volume_db = brake_db + 5.0 * pedal + _interior_off(interior_brake_db)
		_hiss.play()
	_prev_brake_pedal = pedal
	var v: float = bus.get_speed_kmh()
	if pedal > 0.3 and v > parking_min_speed_kmh:
		_was_braking_fast = true
	if _was_braking_fast and v < 1.0 and _parking_cooldown <= 0.0:
		_was_braking_fast = false
		_parking_cooldown = 3.0
		parking_count += 1
		_parking.volume_db = brake_db + _interior_off(interior_brake_db)
		_parking.play()


## ---- 内外听感：视角 → 总线低通/增益 + 声道偏置（连续过渡，不中断） ----

func _update_view_mix(delta: float) -> void:
	var interior: bool = cam_mgr != null and cam_mgr.view == CameraManager.VIEW_CAB
	_view_mix = move_toward(_view_mix, 1.0 if interior else 0.0, view_mix_rate * delta)
	if _lp != null:
		_lp.cutoff_hz = lerpf(exterior_cutoff_hz, interior_cutoff_hz, _view_mix)
	if _amp != null:
		_amp.volume_db = lerpf(0.0, interior_bus_gain_db, _view_mix)


func _interior_off(offset_db: float) -> float:
	return lerpf(0.0, offset_db, _view_mix)


func _apply_smoothing(delta: float) -> void:
	var k_v: float = clampf(delta * vol_lerp_rate, 0.0, 1.0)
	var k_p: float = clampf(delta * pitch_lerp_rate, 0.0, 1.0)
	_engine_vol = lerpf(_engine_vol, _engine_vol_t, k_v)
	_engine_pitch = lerpf(_engine_pitch, _engine_pitch_t, k_p)
	_road_vol = lerpf(_road_vol, _road_vol_t, k_v)
	_road_pitch = lerpf(_road_pitch, _road_pitch_t, k_p)
	_wind_vol = lerpf(_wind_vol, _wind_vol_t, k_v)
	if engine_loop_playing:
		_engine_loop.volume_db = _engine_vol + _interior_off(interior_engine_db)
		_engine_loop.pitch_scale = _engine_pitch
	_road.volume_db = _road_vol + _interior_off(interior_road_db)
	_road.pitch_scale = _road_pitch
	_wind.volume_db = _wind_vol + _interior_off(interior_wind_db)


## ---- 转向灯节拍（TurnIndicator 调用） ----

func play_click(is_a: bool) -> void:
	var p: AudioStreamPlayer = _click_a if is_a else _click_b
	p.volume_db = click_db + _interior_off(interior_click_db)
	p.play()
	click_count += 1


## ---- 测试/诊断读取接口 ----

func get_engine_pitch() -> float:
	return _engine_pitch

func get_engine_volume_db() -> float:
	return _engine_loop.volume_db

func get_road_volume_db() -> float:
	return _road.volume_db

func get_wind_volume_db() -> float:
	return _wind.volume_db

func get_view_mix() -> float:
	return _view_mix
