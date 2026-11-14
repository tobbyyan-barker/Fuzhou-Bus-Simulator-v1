## 出生点物理监视 v2：2x2 隔离（TRAFFIC_OFF / LANE0 环境变量）
extends Node3D


func _ready() -> void:
	var traffic_off: bool = OS.get_environment("TRAFFIC_OFF") == "1"
	var lane0: bool = OS.get_environment("LANE0") == "1"
	print("DBG_CONFIG traffic_off=%s lane0=%s" % [str(traffic_off), str(lane0)])
	var main = load("res://scenes/main.tscn").instantiate()
	if traffic_off:
		var tf: Node = main.get_node("Traffic")
		tf.set("car_count", 0)
		tf.set("truck_count", 0)
		tf.set("ebike_count", 0)
		tf.set_physics_process(false)
	add_child(main)
	if lane0:
		main.bus.global_transform = main.map.get_transform_at(1.5, 0.0)
	await _sim(30)
	var bus = main.bus
	for round_i in range(4):
		await _sim(20)
		var v: float = bus.get_speed_kmh()
		var pos: Vector3 = bus.global_position
		var tv: Array = main.traffic.get_vehicles()
		print("SPAWN_DBG v=%.1f km/h pos=(%.1f, %.2f, %.1f) upright=%.2f traffic=%d" % [
				v, pos.x, pos.y, pos.z, bus.global_transform.basis.y.dot(Vector3.UP), tv.size()])
	get_tree().quit(0)


func _sim(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
