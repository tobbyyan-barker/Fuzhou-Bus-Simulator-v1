## 红绿灯系统：双侧车道信号灯（右侧车道 + 对向车道）+ 秒数倒计时 + 停车提醒。
## 每处灯位在路线两侧各立一组灯：右侧灯面向客车（+s 方向来车），左侧灯面向对向车。
## 状态机：GREEN → YELLOW → RED 循环，周期固定、相位错开，保证确定性可测试。
## 接近红灯时：发 announce_requested 信号（车内语音播报）+ warning 状态（HUD 红色横幅）。
## 全部图元程序化拼装（零外部素材），Label3D 显示当前状态剩余秒数。
class_name TrafficLightManager
extends Node3D

signal announce_requested(text: String)

## 灯位里程（选在直道段，避免弯道遮挡）
@export var light_positions: Array[float] = [500.0, 1150.0, 2000.0]
## 各灯相位偏移（错开，行驶途中红绿交替出现）
@export var phase_offsets: Array[float] = [0.0, 16.0, 33.0]

const GREEN_S := 25.0
const YELLOW_S := 3.0
const RED_S := 20.0
const CYCLE_S := GREEN_S + YELLOW_S + RED_S
## 停车线距灯位的里程（米）
const STOP_LINE_MARGIN := 5.0
## 提醒触发距离（米）：客车距停车线小于该值且非绿灯即警示
const WARN_DISTANCE := 60.0
## 两次语音播报之间的最小间隔（秒，防刷屏）
const ANNOUNCE_COOLDOWN := 6.0

var route: RouteManager
var bus: BusController

## 供 HUD / 自动驾驶 / 测试读取的警示状态
var warning_active: bool = false
var warning_text: String = ""

## 测试钩子：>= 0 时仿真时钟从该值起走（确定性相位）
var time_start: float = -1.0

var _time: float = 0.0
var _lights: Array[Dictionary] = []
var _was_warning := false
var _last_announce_t: float = -100.0


func setup(r: RouteManager) -> void:
	route = r
	_build_all()


func _physics_process(delta: float) -> void:
	if time_start >= 0.0:
		_time = time_start
		time_start = -1.0
	_time += delta
	for i in _lights.size():
		_update_visuals(i)
	_update_warning()


# ---------------- 状态查询 API ----------------

## 灯 i 的当前状态："GREEN" / "YELLOW" / "RED"
func get_state(i: int) -> String:
	var t := _phase(i)
	if t < GREEN_S:
		return "GREEN"
	elif t < GREEN_S + YELLOW_S:
		return "YELLOW"
	return "RED"


## 灯 i 当前状态剩余秒数
func get_remaining(i: int) -> float:
	var t := _phase(i)
	if t < GREEN_S:
		return GREEN_S - t
	elif t < GREEN_S + YELLOW_S:
		return GREEN_S + YELLOW_S - t
	return CYCLE_S - t


## 沿行驶方向（dir=+1 客车/同向车，dir=-1 对向车）的下一处需要停车的灯：
## 返回距自身停车线的距离；INF = 无需停车（绿灯 / 已越线 / 前方无灯）。
func get_stop_line_gap(from_s: float, dir: int) -> float:
	var idx := _next_light_idx(from_s, dir)
	if idx < 0 or get_state(idx) == "GREEN":
		return INF
	var d: float = (light_positions[idx] - STOP_LINE_MARGIN * dir - from_s) * dir
	if d < -0.5:
		return INF  # 已越线，放行
	return d


func get_light_count() -> int:
	return _lights.size()


## 供测试断言：灯 i 的倒计时 Label 文本非空且为数字
func get_countdown_text(i: int, side: int) -> String:
	var l: Label3D = _lights[i].get("label_right" if side > 0 else "label_left")
	return l.text if l != null else ""


# ---------------- 内部实现 ----------------

func _phase(i: int) -> float:
	var off: float = phase_offsets[i] if i < phase_offsets.size() else 0.0
	return fmod(_time + off, CYCLE_S)


func _next_light_idx(from_s: float, dir: int) -> int:
	var best := -1
	if dir > 0:
		var best_s := INF
		for i in light_positions.size():
			if light_positions[i] > from_s + 1.0 and light_positions[i] < best_s:
				best_s = light_positions[i]
				best = i
	else:
		var best_s := -INF
		for i in light_positions.size():
			if light_positions[i] < from_s - 1.0 and light_positions[i] > best_s:
				best_s = light_positions[i]
				best = i
	return best


func _update_visuals(i: int) -> void:
	var st := get_state(i)
	var rem := get_remaining(i)
	var txt := str(ceili(rem))
	for side_key in ["right", "left"]:
		var mats: Dictionary = _lights[i]["lamps_" + side_key]
		var label: Label3D = _lights[i]["label_" + side_key]
		for state_key in ["red", "yellow", "green"]:
			var m: StandardMaterial3D = mats[state_key]
			var on: bool = state_key.to_upper() == st
			m.emission_enabled = true
			m.emission_energy_multiplier = 6.0 if on else 0.0
			m.albedo_color = _lamp_color(state_key) if on else Color(0.13, 0.13, 0.13)
		label.text = txt
		match st:
			"GREEN":
				label.modulate = Color(0.3, 1.0, 0.35)
			"YELLOW":
				label.modulate = Color(1.0, 0.85, 0.25)
			_:
				label.modulate = Color(1.0, 0.3, 0.3)


func _lamp_color(state_key: String) -> Color:
	match state_key:
		"red":
			return Color(1.0, 0.1, 0.1)
		"yellow":
			return Color(1.0, 0.8, 0.1)
		_:
			return Color(0.15, 1.0, 0.25)


## 警示与语音：接近红灯（或黄灯）→ HUD 横幅 + 语音播报（上升沿触发，带冷却）
func _update_warning() -> void:
	warning_active = false
	warning_text = ""
	if bus == null or route == null:
		_was_warning = false
		return
	var bus_s := route.get_nearest_s(bus.global_position)
	var idx := _next_light_idx(bus_s, 1)
	if idx >= 0:
		var st := get_state(idx)
		var d: float = light_positions[idx] - STOP_LINE_MARGIN - bus_s
		if d > 0.0 and d < WARN_DISTANCE and st != "GREEN":
			var st_zh := "红灯" if st == "RED" else "黄灯"
			warning_active = true
			warning_text = "⚠ 前方%s · %d m · 请停车（剩 %d s）" % [
					st_zh, roundi(d), ceili(get_remaining(idx))]
			if not _was_warning and _time - _last_announce_t > ANNOUNCE_COOLDOWN:
				var msg := "前方红灯，请注意减速停车" if st == "RED" else "前方黄灯，请注意减速"
				announce_requested.emit(msg)
				_last_announce_t = _time
	# 绿灯起步播报：客车在灯前 20 m 内停着等灯，红灯转绿时提示起步
	for i in _lights.size():
		if _lights[i].prev_state == "RED" and get_state(i) == "GREEN":
			var d_light: float = absf(light_positions[i] - STOP_LINE_MARGIN - bus_s)
			if d_light < 20.0 and bus.get_speed_kmh() < 2.0 \
					and _time - _last_announce_t > ANNOUNCE_COOLDOWN:
				announce_requested.emit("绿灯亮起，请起步")
				_last_announce_t = _time
		_lights[i].prev_state = get_state(i)
	_was_warning = warning_active


# ---------------- 灯体构建（纯图元） ----------------

func _build_all() -> void:
	for i in light_positions.size():
		var info := {
			"s": light_positions[i],
			"prev_state": "GREEN",
		}
		var right := _build_fixture(light_positions[i], 1)
		info["lamps_right"] = right["lamps"]
		info["label_right"] = right["label"]
		var left := _build_fixture(light_positions[i], -1)
		info["lamps_left"] = left["lamps"]
		info["label_left"] = left["label"]
		_lights.append(info)


## 单侧灯组：灯杆 + 三色灯腔 + 倒计时牌 + 停车线。
## side=+1 右侧（客车方向），side=-1 左侧（对向方向）。
## 返回 {"lamps": {red,yellow,green}, "label": Label3D}（左侧自动加 left_ 前缀）
func _build_fixture(s: float, side: int) -> Dictionary:
	var t: Transform3D = route.get_transform_at(s)
	var pole_off: Vector3 = t.basis.x * (5.2 * side)
	# 灯腔朝向来车：右侧灯面板朝 -forward（客车来向），左侧灯朝 +forward（对向来向）
	var fixture_basis: Basis = t.basis if side > 0 else Basis(-t.basis.x, t.basis.y, -t.basis.z)
	var fixture_origin: Vector3 = t.origin + pole_off

	# 灯杆
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.07
	pm.bottom_radius = 0.09
	pm.height = 5.4
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.2, 0.21, 0.24)
	pole_mat.metallic = 0.6
	pm.material = pole_mat
	pole.mesh = pm
	pole.position = fixture_origin + Vector3.UP * 2.7
	add_child(pole)

	# 灯箱
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 1.75, 0.4)
	var box_mat := StandardMaterial3D.new()
	box_mat.albedo_color = Color(0.08, 0.08, 0.09)
	box_mat.roughness = 0.4
	bm.material = box_mat
	box.mesh = bm
	box.transform = Transform3D(fixture_basis, fixture_origin + Vector3.UP * 4.55)
	add_child(box)

	# 三色灯（朝向来车一侧，local +z）
	var box_center: Vector3 = fixture_origin + Vector3.UP * 4.55
	var lamps := {}
	var lamp_y := {"red": 5.15, "yellow": 4.55, "green": 3.95}
	for state_key in ["red", "yellow", "green"]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.13, 0.13, 0.13)
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 0.0
		lamps[state_key] = mat
		var lamp := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.15
		sm.height = 0.3
		lamp.mesh = sm
		lamp.material_override = mat
		lamp.position = box_center + fixture_basis * Vector3(0, lamp_y[state_key] - 4.55, 0.24)
		add_child(lamp)

	# 倒计时牌（billboard 常显）
	var label := Label3D.new()
	label.text = "0"
	label.font_size = 96
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.modulate = Color(1, 1, 1)
	label.position = box_center + fixture_basis * Vector3(0, -1.3, 0.15)
	add_child(label)

	# 停车线（白色横条，跨对应车道；视觉）
	var line_s: float = s - STOP_LINE_MARGIN * side
	var lt: Transform3D = route.get_transform_at(line_s)
	var lane_off: Vector3 = lt.basis.x * (2.0 * side)
	var line := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(3.6, 0.02, 0.45)
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.92, 0.92, 0.92)
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.material = line_mat
	line.mesh = lm
	line.transform = Transform3D(lt.basis, lt.origin + lane_off + Vector3.UP * 0.02)
	add_child(line)

	return {"lamps": lamps, "label": label}
