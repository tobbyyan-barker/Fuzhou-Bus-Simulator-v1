## 双视角相机管理：第一人称驾驶舱（C 键切换）↔ 第三人称阻尼跟车
class_name CameraManager
extends Node3D

@export var chase_distance: float = 13.0
@export var chase_height: float = 4.5
@export var chase_lerp_speed: float = 3.5
@export var chase_look_height: float = 1.8

var bus: BusController

@onready var cab_cam: Camera3D = $CabCamera
@onready var chase_cam: Camera3D = $ChaseCamera


func _ready() -> void:
	cab_cam.current = true
	chase_cam.current = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		toggle()


func toggle() -> void:
	var to_cab: bool = not cab_cam.current
	cab_cam.current = to_cab
	chase_cam.current = not to_cab


func is_cab_active() -> bool:
	return cab_cam.current


func _physics_process(delta: float) -> void:
	if bus == null:
		return
	var bus_t := bus.global_transform
	# 驾驶舱视角：刚性绑定客车眼部位置（随车身侧倾，真实驾驶舱感）
	cab_cam.global_transform = bus_t * bus.params.cab_eye_transform
	# 跟车视角：水平方向阻尼跟随 + 注视客车
	var fwd := -bus_t.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
	var target := bus_t.origin + Vector3.UP * chase_height - fwd * chase_distance
	chase_cam.global_position = chase_cam.global_position.lerp(
			target, clampf(delta * chase_lerp_speed, 0.0, 1.0))
	chase_cam.look_at(bus_t.origin + Vector3.UP * chase_look_height, Vector3.UP)


## 瞬移后调用，避免跟车相机长距离追赶
func snap_chase() -> void:
	if bus == null:
		return
	var fwd := -bus.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
	chase_cam.global_position = bus.global_position \
			+ Vector3.UP * chase_height - fwd * chase_distance
	chase_cam.look_at(bus.global_position + Vector3.UP * chase_look_height, Vector3.UP)
