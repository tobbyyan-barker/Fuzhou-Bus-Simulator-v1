## 五视角循环相机管理（C / Q 键切换，按序循环）：
##   0 跟车（默认）→ 1 车顶 → 2 左侧 → 3 右侧 → 4 第一人称驾驶舱 → 回到跟车
## 切换只改变 Camera3D.current，不触碰车辆物理状态。
## 跟车/驾驶舱相机来自场景（ChaseCamera/CabCamera）；
## 车顶/左侧/右侧为纯刚性附属视角，代码生成，场景无需改动。
class_name CameraManager
extends Node3D

const VIEW_CHASE := 0
const VIEW_ROOF := 1
const VIEW_LEFT := 2
const VIEW_RIGHT := 3
const VIEW_CAB := 4
const VIEW_COUNT := 5

@export_group("跟车视角")
@export var chase_distance: float = 13.0
@export var chase_height: float = 4.5
@export var chase_lerp_speed: float = 3.5
@export var chase_look_height: float = 1.8

@export_group("车顶视角")
## 相机位置（客车局部坐标，前方为 -Z）：x 左右、y 高度、z 前后
@export var roof_offset: Vector3 = Vector3(0.0, 3.6, -1.0)
## 注视点在车前方的距离（m）与高度（m）：组合出俯角，看清车头前路面
@export var roof_look_ahead: float = 12.0
@export var roof_look_height: float = 0.0
@export var roof_fov_deg: float = 62.0

@export_group("侧方视角（左/右共用参数）")
## 相机到车身中轴的横向距离（m，取正值；左侧放 -X，右侧放 +X）
@export var side_distance: float = 9.0
@export var side_height: float = 3.0
## 注视点高度（相对客车原点，m）
@export var side_look_height: float = 1.6
@export var side_fov_deg: float = 55.0

var bus: BusController
var view: int = VIEW_CHASE

@onready var cab_cam: Camera3D = $CabCamera
@onready var chase_cam: Camera3D = $ChaseCamera
var roof_cam: Camera3D
var left_cam: Camera3D
var right_cam: Camera3D


func _ready() -> void:
	roof_cam = _create_cam("RoofCamera", roof_fov_deg)
	left_cam = _create_cam("LeftCamera", side_fov_deg)
	right_cam = _create_cam("RightCamera", side_fov_deg)
	# 默认第三人称跟车视角（C/Q 循环：跟车→车顶→左侧→右侧→驾驶舱）
	_apply_view()


func _create_cam(cam_name: String, fov_deg: float) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = cam_name
	cam.fov = fov_deg
	add_child(cam)
	return cam


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		cycle_view()


## C / Q 每按一次前进一个视角，第 5 次回到跟车
func cycle_view() -> void:
	set_view((view + 1) % VIEW_COUNT)


func set_view(new_view: int) -> void:
	view = clampi(new_view, 0, VIEW_COUNT - 1)
	_apply_view()


func get_view() -> int:
	return view


func is_cab_active() -> bool:
	return view == VIEW_CAB


func _apply_view() -> void:
	chase_cam.current = view == VIEW_CHASE
	roof_cam.current = view == VIEW_ROOF
	left_cam.current = view == VIEW_LEFT
	right_cam.current = view == VIEW_RIGHT
	cab_cam.current = view == VIEW_CAB


func _physics_process(delta: float) -> void:
	if bus == null:
		return
	var bus_t := bus.global_transform
	# 驾驶舱视角：刚性绑定客车眼部位置（随车身侧倾，真实驾驶舱感）。
	# 相机默认朝向客车正前方（局部 -Z）；位置/FOV 参数从车辆资源读取，
	# Inspector 调整 mt10.tres 的 cab_eye_offset / cab_fov_deg 实时生效。
	cab_cam.global_transform = bus_t * Transform3D(Basis(), bus.params.cab_eye_offset)
	cab_cam.fov = bus.params.cab_fov_deg
	# 跟车视角：水平方向阻尼跟随 + 注视客车
	var fwd := -bus_t.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3(0, 0, -1)
	var target := bus_t.origin + Vector3.UP * chase_height - fwd * chase_distance
	chase_cam.global_position = chase_cam.global_position.lerp(
			target, clampf(delta * chase_lerp_speed, 0.0, 1.0))
	chase_cam.look_at(bus_t.origin + Vector3.UP * chase_look_height, Vector3.UP)
	# 车顶视角：刚性绑定车顶（随车身俯仰侧倾），注视车前方路面形成俯角
	roof_cam.fov = roof_fov_deg
	roof_cam.global_position = bus_t * roof_offset
	roof_cam.look_at(bus_t.origin - bus_t.basis.z * roof_look_ahead
			+ Vector3.UP * roof_look_height, Vector3.UP)
	# 左/右侧视角：刚性绑定车身中部两侧，注视车身（随车移动的侧面跟踪镜头）
	left_cam.fov = side_fov_deg
	left_cam.global_position = bus_t * Vector3(-side_distance, side_height, 0.0)
	left_cam.look_at(bus_t.origin + Vector3.UP * side_look_height, Vector3.UP)
	right_cam.fov = side_fov_deg
	right_cam.global_position = bus_t * Vector3(side_distance, side_height, 0.0)
	right_cam.look_at(bus_t.origin + Vector3.UP * side_look_height, Vector3.UP)


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
