## 闽通 MT-10 客车控制器：油门/制动/转向/挡位 → VehicleBody3D
## 所有物理参数从 data/vehicles/*.tres 读取，代码不写死数值。
class_name BusController
extends VehicleBody3D

const FALLBACK_PARAMS := "res://data/vehicles/mt10.tres"

@export var params: BusParams

var gearbox: Gearbox

## 自动驾驶/测试外部控制（headless 测试用 Input 注入，GUI 演示用外部控制）
var use_external_control: bool = false
var ext_throttle: float = 0.0
var ext_brake: float = 0.0
var ext_steer: float = 0.0

var _steer_wheels: Array[VehicleWheel3D] = []
var _traction_wheels: Array[VehicleWheel3D] = []
var _all_wheels: Array[VehicleWheel3D] = []
var _steering: float = 0.0
## 踏板平滑状态（键盘阶跃 → 渐进踏板行程，见 params.pedal_*）
var _throttle_pedal: float = 0.0
var _brake_pedal: float = 0.0


func _ready() -> void:
	if params == null:
		params = load(FALLBACK_PARAMS)
	gearbox = $Gearbox
	gearbox.set_reverse_lock_kmh(params.reverse_lock_speed_kmh)
	mass = params.mass_kg
	# 显式归零线性阻尼（部分 Godot 4.x 版本项目默认值非零，形成速度上限）
	linear_damp = 0.0
	angular_damp = 1.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = params.center_of_mass
	for child in get_children():
		if child is VehicleWheel3D:
			var w: VehicleWheel3D = child
			_apply_wheel_params(w)
			_all_wheels.append(w)
			if w.use_as_steering:
				_steer_wheels.append(w)
			if w.use_as_traction:
				_traction_wheels.append(w)


func set_external_control(throttle: float, brake: float, steer: float) -> void:
	ext_throttle = clampf(throttle, 0.0, 1.0)
	ext_brake = clampf(brake, 0.0, 1.0)
	ext_steer = clampf(steer, -1.0, 1.0)


func _physics_process(delta: float) -> void:
	var throttle: float = Input.get_action_strength("accelerate")
	var brake_in: float = Input.get_action_strength("brake")
	var steer_in: float = Input.get_axis("steer_right", "steer_left")
	if use_external_control:
		# 外部控制（自动驾驶/演示）已是连续踏板值，不再叠加平滑
		_throttle_pedal = clampf(ext_throttle, 0.0, 1.0)
		_brake_pedal = clampf(ext_brake, 0.0, 1.0)
		throttle = _throttle_pedal
		brake_in = _brake_pedal
		steer_in = ext_steer
	else:
		# 键盘阶跃输入 → 渐进踏板行程（踩下慢、松开快），改善手感
		_throttle_pedal = move_toward(_throttle_pedal, throttle,
			_pedal_rate(throttle, _throttle_pedal) * delta)
		_brake_pedal = move_toward(_brake_pedal, brake_in,
			_pedal_rate(brake_in, _brake_pedal) * delta)
		throttle = _throttle_pedal
		brake_in = _brake_pedal
	var handbrake: bool = Input.is_action_pressed("handbrake")
	_handbrake_active = handbrake

	# 注意：传带符号前向速度——倒挡锁只在"仍在向前冲"时触发，
	# 纯倒车（负速度）不得误锁（见 DEVLOG 故障记录 #5）
	gearbox.update(throttle, get_signed_forward_speed_kmh())

	# ---- 驱动力（速度调速器限制极速） ----
	# 注意符号：Godot VehicleWheel 的前向摩擦轴 = 车轴×接触法线，本车布局下指向 +Z；
	# 而车头建模在 -Z，故取负使正油门朝车头方向驱动（见 DEVLOG 故障记录 #2）。
	var engine_force := 0.0
	if gearbox.mode == "D":
		engine_force = -params.max_engine_force * throttle * _speed_governor()
	elif gearbox.mode == "R":
		engine_force = params.max_engine_force * params.reverse_force_ratio \
				* throttle * _reverse_governor()
	for w in _traction_wheels:
		w.engine_force = engine_force

	# ---- 制动（行车制动 + 驱动轮手刹 + 滚动阻力） ----
	var idle_drag: float = 0.0
	if throttle < 0.05 and brake_in < 0.05:
		idle_drag = params.rolling_brake
	var brake_force := params.max_brake_force * brake_in
	var hb_force: float = params.max_brake_force * (1.0 if handbrake else 0.0)
	for w in _all_wheels:
		var b: float = brake_force + idle_drag
		if w.use_as_traction:
			b += hb_force
		w.brake = b
	# 手刹 = 紧急驻车（用户需求）：速度立即清零并冻结姿态
	if handbrake:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO

	# ---- 转向（速率式打轮 + 随速限角：打轮慢、回正快、高速自动收窄转角） ----
	var steer_max_deg: float = params.get_max_steer_deg(get_speed_kmh())
	var steer_target: float = steer_in * deg_to_rad(steer_max_deg)
	var steer_rate_deg: float = params.steer_release_deg_per_s \
			if absf(steer_target) < absf(_steering) else params.steer_attack_deg_per_s
	_steering = move_toward(_steering, steer_target, deg_to_rad(steer_rate_deg) * delta)
	for w in _steer_wheels:
		w.steering = _steering


## 踏板渐变速率：踩下用 attack（慢），松开用 release（快）
func _pedal_rate(raw: float, current: float) -> float:
	return params.pedal_release_rate if raw < current else params.pedal_attack_rate


## 倒车雷达：车尾水平射线，返回最近障碍距离（m）；无障碍返回 -1
func get_reverse_obstacle_distance_m() -> float:
	var back: Vector3 = global_transform.basis.z  # 车头为 -Z，车尾为 +Z
	back.y = 0.0
	if back.length() < 0.01:
		return -1.0
	back = back.normalized()
	var origin: Vector3 = global_position + Vector3.UP * 0.6 + back * 5.5
	var query := PhysicsRayQueryParameters3D.create(origin, origin + back * 12.0)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return -1.0
	return origin.distance_to(hit[&"position"])


func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6


## 手刹是否处于拉起状态（HUD 红色感叹号提示用）
func is_handbraking() -> bool:
	return _handbrake_active


var _handbrake_active: bool = false


func get_signed_forward_speed_kmh() -> float:
	return linear_velocity.dot(-global_transform.basis.z) * 3.6


func get_gear_text() -> String:
	return gearbox.get_display_text()


func _speed_governor() -> float:
	return clampf(1.0 - get_speed_kmh() / params.top_speed_kmh, 0.0, 1.0)


func _reverse_governor() -> float:
	return clampf(1.0 - get_speed_kmh() / params.reverse_top_kmh, 0.0, 1.0)


func _apply_wheel_params(w: VehicleWheel3D) -> void:
	w.wheel_radius = params.wheel_radius
	w.wheel_friction_slip = params.wheel_friction_slip
	w.wheel_rest_length = params.suspension_rest_length
	w.suspension_stiffness = params.suspension_stiffness
	w.suspension_max_force = params.suspension_max_force
	w.suspension_travel = params.suspension_travel
	w.damping_compression = params.damping_compression
	w.damping_relaxation = params.damping_relaxation
