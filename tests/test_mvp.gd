## MVP 自动化测试（headless）：AC1(加载)/AC2/AC3/AC4(逻辑)/AC5/AC6
## 运行：godot --headless --path <项目根> res://tests/test_mvp.tscn
## 所有断言由真实驾驶过程（Input 注入 + 物理仿真）触发，不直接调用被测方法伪造结果。
extends Node3D

const PHYSICS_FPS := 60

var failures: Array[String] = []
var results: Array[String] = []

var main: Node3D
var bus: BusController
var route: RouteManager
var hud: Hud
var cam_mgr: CameraManager
var stop_task: StopTask


func _ready() -> void:
	await _run_suite()
	_print_report()
	get_tree().quit(1 if failures.size() > 0 else 0)


func _run_suite() -> void:
	# ---- AC1：主场景实例化（加载错误会直接打进输出，退出码为准） ----
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _sim(90)

	bus = main.bus
	route = main.map
	hud = main.hud
	cam_mgr = main.cam_mgr
	stop_task = main.stop_task
	# 传送型测试冻结同向车道（传送会人为制造重叠；同向交通行为由 feel_check/自动驾驶回归覆盖）
	main.traffic.same_lane_frozen = true
	_check("AC1-load", bus != null and route != null and stop_task != null,
			"主场景/客车/路线/任务全部实例化成功")

	# ---- AC2：全油门 3 s 后车速 > 5 km/h ----
	Input.action_press("accelerate")
	await _sim(3 * PHYSICS_FPS)
	var v_after_3s: float = bus.get_speed_kmh()
	Input.action_release("accelerate")
	Input.action_press("brake")
	await _sim(60)
	Input.action_release("brake")
	_check("AC2", v_after_3s > 5.0,
			"全油门 3 s 后 %.1f km/h（要求 > 5）" % v_after_3s)

	# ---- AC3：60 km/h 全制动 < 60 m 且不侧翻 ----
	_teleport(120.0)
	Input.action_press("accelerate")
	var guard := 0
	while bus.get_speed_kmh() < 60.0 and guard < 2400:
		await _sim(6)
		guard += 6
	Input.action_release("accelerate")
	await _sim(6)
	var v_brake_start: float = bus.get_speed_kmh()
	var pos_brake_start := bus.global_position
	Input.action_press("brake")
	guard = 0
	while bus.get_speed_kmh() > 0.5 and guard < 1800:
		await _sim(6)
		guard += 6
	Input.action_release("brake")
	var brake_dist: float = pos_brake_start.distance_to(bus.global_position)
	var upright: float = bus.global_transform.basis.y.dot(Vector3.UP)
	_check("AC3", brake_dist < 60.0 and upright > 0.7,
			"%.1f km/h 全制动 %.1f m（要求 < 60 m），车身直立度 %.2f" % [v_brake_start, brake_dist, upright])

	# ---- AC6：HUD 显示速度 vs 物理实际速度（行驶中采样） ----
	Input.action_press("accelerate")
	await _sim(90)
	var hud_v: float = hud.get_displayed_speed_kmh()
	var real_v: float = bus.get_speed_kmh()
	Input.action_release("accelerate")
	Input.action_press("brake")
	await _sim(60)
	Input.action_release("brake")
	_check("AC6", absf(hud_v - real_v) < 2.0,
			"HUD %.1f vs 实测 %.1f km/h（偏差要求 < 2）" % [hud_v, real_v])

	# ---- AC4（逻辑部分）：视角循环切换（C/Q：跟车→车顶→左侧→右侧→驾驶舱→回跟车） ----
	var view_start: int = cam_mgr.get_view()
	var distinct: bool = true
	var saw_cab: bool = false
	var prev: int = view_start
	for i in cam_mgr.VIEW_COUNT:
		cam_mgr.cycle_view()
		await _sim(2)
		if cam_mgr.get_view() == prev:
			distinct = false
		prev = cam_mgr.get_view()
		if cam_mgr.is_cab_active():
			saw_cab = true
	var loop_closed: bool = cam_mgr.get_view() == view_start
	_check("AC4-logic", distinct and saw_cab and loop_closed,
			"C/Q 五视角循环正常（跟车→车顶→左侧→右侧→驾驶舱，5 键回环；视觉确认见 GUI 测试）")

	# ---- AC5：真实驾驶进站 → 停稳 3 s → stop_completed ----
	_teleport(route.get_total_length() - 120.0, 140.0)  # 清空 140 m 进站通道
	Input.action_press("accelerate")
	guard = 0
	while bus.global_position.distance_to(stop_task.stop_position) > 25.0 and guard < 1200:
		await _sim(6)
		guard += 6
	Input.action_release("accelerate")
	Input.action_press("brake")
	guard = 0
	while bus.get_speed_kmh() > 1.0 and guard < 600:
		await _sim(6)
		guard += 6
	Input.action_release("brake")
	await _sim(30)
	var d_stop: float = _flat_dist(bus.global_position, stop_task.stop_position)
	# 距站点过远：部分油门平滑蠕行进站（模拟司机 inching forward）
	var creep_rounds := 0
	while d_stop > 4.5 and creep_rounds < 8:
		creep_rounds += 1
		Input.action_press("accelerate", 0.3)
		guard = 0
		var d_before: float = d_stop
		while d_stop > 4.2 and bus.get_speed_kmh() < 8.0 and guard < 900:
			await _sim(6)
			guard += 6
			d_stop = _flat_dist(bus.global_position, stop_task.stop_position)
		Input.action_release("accelerate")
		Input.action_press("brake")
		guard = 0
		while bus.get_speed_kmh() > 1.0 and guard < 240:
			await _sim(6)
			guard += 6
		Input.action_release("brake")
		d_stop = _flat_dist(bus.global_position, stop_task.stop_position)
		if d_before - d_stop < 0.3:
			break  # 蠕行失效保护，防止死循环
	d_stop = _flat_dist(bus.global_position, stop_task.stop_position)
	# 临时诊断：AC5 失败时输出附近交通车与客车状态
	if d_stop > 5.0 or not stop_task.completed:
		var bus_s: float = route.get_nearest_s(bus.global_position)
		print("AC5_DBG bus_s=%.1f pos=(%.1f, %.1f) speed=%.1f mode=%s light_state=%s" % [
				bus_s, bus.global_position.x, bus.global_position.z,
				bus.get_speed_kmh(), bus.gearbox.mode,
				main.traffic_lights.get_state(2) if main.traffic_lights.get_light_count() > 2 else "n/a"])
		for v in main.traffic.get_vehicles():
			var vs: float = v.s
			if vs > bus_s - 40.0 and vs < bus_s + 160.0:
				print("AC5_DBG veh kind=%s dir=%d s=%.1f speed=%.1f lat_off=%.1f" % [
						v.kind, v.dir, vs, v.speed_mps * 3.6,
						(v.node.global_position - route.get_transform_at(vs).origin).dot(
								route.get_transform_at(vs).basis.x)])
	# 保持 3 s 以上
	await _sim(220)
	_check("AC5", stop_task.completed and d_stop <= 5.0,
			"到站判定 completed=%s，停车点距站点 %.1f m（要求 ≤ 5 m，蠕行 %d 段）" % [
					str(stop_task.completed), d_stop, creep_rounds])


# ---------------- 工具 ----------------

func _sim(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _teleport(s: float, clear_ahead: float = 0.0) -> void:
	Input.action_release("accelerate")
	Input.action_release("brake")
	bus.global_transform = route.get_transform_at(s, RouteManager.RIGHT_LANE_OFFSET)
	# 传送清场：移走附近交通车（防重叠炸飞）；clear_ahead 清空前方同向车（防挡路）
	main.traffic.relocate_conflicts(bus.global_position, 30.0, clear_ahead)
	bus.linear_velocity = Vector3.ZERO
	bus.angular_velocity = Vector3.ZERO
	bus.sleeping = false
	cam_mgr.snap_chase()
	await _sim(30)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _check(ac: String, ok: bool, detail: String) -> void:
	var line: String = "[%s] %s — %s" % [ac, "PASS" if ok else "FAIL", detail]
	results.append(line)
	print(line)
	if not ok:
		failures.append(ac)


func _print_report() -> void:
	print("========================================")
	print("TEST_SUMMARY total=%d pass=%d fail=%d" % [
			results.size(), results.size() - failures.size(), failures.size()])
	if failures.size() > 0:
		print("FAILED_AC: " + ", ".join(failures))
