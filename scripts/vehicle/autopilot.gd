## 自动驾驶（纯追踪转向 + 速度控制）：用于 GUI 自动演示与图形界面测试。
## 挂在 main 场景，通过 BusController 外部控制接口驱动，不占用键盘输入。
class_name Autopilot
extends Node

var bus: BusController
var route: RouteManager
var active: bool = false

@export var target_speed_kmh: float = 55.0
## 制动减速度估计（m/s²），用于进站刹停点计算
@export var brake_decel: float = 2.3


func _physics_process(_delta: float) -> void:
	if not active or bus == null or route == null:
		return
	bus.use_external_control = true

	# ---- 纯追踪转向：瞄准前方 30 m 的路线点 ----
	var aim := route.get_point_ahead(bus.global_position, 30.0)
	var local := bus.global_transform.basis.inverse() * (aim - bus.global_position)
	# local.x > 0 → 目标在右侧 → 转负（ steer 正 = 左）
	var steer_cmd := clampf(-local.x / 15.0, -1.0, 1.0)

	# ---- 速度控制 + 进站逻辑 ----
	var sp := bus.get_speed_kmh()
	var v_ms := sp / 3.6
	var dist_stop: float = Vector2(
			bus.global_position.x - route.get_stop_position().x,
			bus.global_position.z - route.get_stop_position().z).length()
	var brake_dist := (v_ms * v_ms) / (2.0 * brake_decel)

	var throttle := 0.0
	var brake := 0.0
	if dist_stop < brake_dist + 6.0:
		if sp < 2.0 and dist_stop > 4.0:
			throttle = 0.15  # 蠕行进站
		else:
			brake = 1.0
	elif sp < target_speed_kmh:
		throttle = 1.0
	else:
		brake = 0.15

	bus.set_external_control(throttle, brake, steer_cmd)
