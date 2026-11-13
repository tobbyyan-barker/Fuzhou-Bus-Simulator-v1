## 到站判定任务：站点 5 m 半径内、车速 < 2 km/h、持续 3 s → 发出 stop_completed
## 只依赖传入的客车速度与位置（与渲染解耦，保证 headless 可测）。
class_name StopTask
extends Node

signal stop_completed(elapsed_s: float)

@export var bus: VehicleBody3D
@export var stop_position: Vector3
@export var radius_m: float = 5.0
@export var speed_limit_kmh: float = 2.0
@export var hold_time_s: float = 3.0

var completed: bool = false
var hold_timer: float = 0.0
var _elapsed: float = 0.0


func _physics_process(delta: float) -> void:
	_elapsed += delta
	if completed or bus == null:
		return
	var dist := _flat_distance(bus.global_position, stop_position)
	var speed := bus.linear_velocity.length() * 3.6
	if dist <= radius_m and speed <= speed_limit_kmh:
		hold_timer += delta
		if hold_timer >= hold_time_s:
			completed = true
			stop_completed.emit(_elapsed)
	else:
		hold_timer = 0.0


func get_status_text() -> String:
	if completed:
		return "到站成功！用时 %.0f s" % _elapsed
	if bus == null:
		return "任务：驶向鼓山测试场总站"
	var dist := _flat_distance(bus.global_position, stop_position)
	if dist <= radius_m:
		return "停稳保持中 %.1f / %.1f s" % [hold_timer, hold_time_s]
	return "距站点 %d m" % roundi(dist)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
