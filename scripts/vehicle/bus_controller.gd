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


func _ready() -> void:
	if params == null:
		params = load(FALLBACK_PARAMS)
	gearbox = $Gearbox
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
		throttle = ext_throttle
		brake_in = ext_brake
		steer_in = ext_steer
	var handbrake: bool = Input.is_action_pressed("handbrake")

	gearbox.update(throttle, get_speed_kmh())

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

	# ---- 转向（低通平滑，模拟大客车方向盘转速） ----
	var steer_target: float = steer_in * deg_to_rad(params.max_steer_deg)
	_steering = lerpf(_steering, steer_target, clampf(delta * params.steer_lerp_rate, 0.0, 1.0))
	for w in _steer_wheels:
		w.steering = _steering


func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6


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
