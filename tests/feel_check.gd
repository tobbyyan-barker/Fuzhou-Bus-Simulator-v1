## 手感量化诊断（保留：每次调整驾驶手感参数后运行回归）
## 模拟真实键盘操作：轻点 A 0.3 s / 轻点 S 0.3 s，量化转向角、掉速与侧倾
extends Node3D

const PHYSICS_FPS := 60

var main: Node3D
var bus: BusController
var route: RouteManager
var hud: Hud
var cam_mgr: CameraManager


func _ready() -> void:
	await _run()
	get_tree().quit(0)


func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _sim(90)
	bus = main.bus
	route = main.map
	hud = main.hud
	cam_mgr = main.cam_mgr

	# ---- 1. 刹车轻点测试：30 km/h 巡航，轻点 S 0.3 s，测掉速 ----
	_teleport(120.0)
	Input.action_press("accelerate")
	await _sim(180)  # 3 s 加速
	Input.action_release("accelerate")
	await _sim(30)   # 松油门滑行 0.5 s
	var v_before: float = bus.get_speed_kmh()
	Input.action_press("brake")
	await _sim(18)   # 轻点 0.3 s
	Input.action_release("brake")
	await _sim(12)
	var v_after: float = bus.get_speed_kmh()
	print("FEEL_BRAKE_TAP: 30 km/h 区间轻点 0.3 s，%s -> %s km/h，掉速 %.1f km/h" % [
			"%.1f" % v_before, "%.1f" % v_after, v_before - v_after])

	# ---- 2. 转向轻点测试：~30 km/h 轻点 A 0.3 s，测转角与侧倾 ----
	_teleport(120.0)
	Input.action_press("accelerate")
	await _sim(180)
	Input.action_release("accelerate")
	await _sim(30)
	var steer_speed: float = bus.get_speed_kmh()
	var max_deg: float = bus.params.get_max_steer_deg(steer_speed)
	Input.action_press("steer_left")
	await _sim(18)   # 轻点 0.3 s
	Input.action_release("steer_left")
	var steer_at_tap_deg: float = rad_to_deg(_steer_of(bus))
	await _sim(120)  # 松手后回正 2 s
	var upright_tap: float = bus.global_transform.basis.y.dot(Vector3.UP)
	var steer_recentered_deg: float = rad_to_deg(_steer_of(bus))
	print("FEEL_STEER_TAP: %.1f km/h 轻点 A 0.3 s -> 转角 %.1f°（限角上限 %.1f°），回正后 %.1f°，直立度 %.3f" % [
			steer_speed, steer_at_tap_deg, max_deg, steer_recentered_deg, upright_tap])

	# ---- 3. 高速满舵防翻测试：~40 km/h 持续满舵 3 s（按住期间采样峰值转角） ----
	_teleport(120.0)
	Input.action_press("accelerate")
	await _sim(300)
	Input.action_release("accelerate")
	var full_speed: float = bus.get_speed_kmh()
	var peak_steer_deg: float = 0.0
	Input.action_press("steer_left")
	for _i in range(180):
		await _sim(1)
		peak_steer_deg = maxf(peak_steer_deg, absf(rad_to_deg(_steer_of(bus))))
	Input.action_release("steer_left")
	await _sim(60)
	var upright_full: float = bus.global_transform.basis.y.dot(Vector3.UP)
	print("FEEL_STEER_FULL: %.1f km/h 满舵 3 s -> 峰值转角 %.1f°（限角上限 %.1f°），直立度 %.3f（>0.8 不翻）" % [
			full_speed, peak_steer_deg, bus.params.get_max_steer_deg(full_speed), upright_full])

	# ---- 4. 倒挡 HUD 与雷达显示 ----
	_teleport(120.0)
	await _sim(60)
	_press_action("gear_r")
	await _sim(10)
	var reverse_shown: bool = hud.reverse_label.visible
	var gear_text: String = hud.gear_label.text
	var radar: float = bus.get_reverse_obstacle_distance_m()
	print("FEEL_REVERSE_HUD: 挂 R 后横幅显示=%s，挡位文本='%s'，雷达=%s" % [
			str(reverse_shown), gear_text, "畅通" if radar < 0.0 else "%.1f m" % radar])
	# 倒车实际动一下：持续踩油门 6 s，速度必须越过 8 km/h 锁挡阈值，
	# 全程挡位必须保持 R（回归：此前绝对速度误锁导致 R→N→D 跳挡）
	Input.action_press("accelerate")
	var mode_samples: Array[String] = []
	var max_rev_speed: float = 0.0
	for _i in range(360):
		await _sim(1)
		mode_samples.append(bus.gearbox.mode)
		max_rev_speed = maxf(max_rev_speed, bus.get_speed_kmh())
	Input.action_release("accelerate")
	var all_r: bool = mode_samples.all(func(m: String) -> bool: return m == "R")
	print("FEEL_REVERSE_DRIVE: R 挡持续踩 6 s 峰值 %.1f km/h（>8 过阈值），挡位保持 R=%s（要求 true）" % [
			max_rev_speed, str(all_r)])
	# 松油门刹停后挡位仍应保持 R
	Input.action_press("brake")
	await _sim(120)
	Input.action_release("brake")
	print("FEEL_REVERSE_HOLD: 停车后挡位='%s'（应为 R，直到用户主动切 D）" % bus.gearbox.mode)

	# ---- 5. 高速误挂 R 保护（先归位 D 挡再测） ----
	bus.gearbox.set_mode("D")
	_teleport(120.0)
	Input.action_press("accelerate")
	await _sim(240)
	Input.action_release("accelerate")
	var high_speed: float = bus.get_speed_kmh()
	_press_action("gear_r")
	await _sim(20)
	print("FEEL_REVERSE_LOCK: %.1f km/h 时按 R -> 当前挡位='%s'（应为 N 或 D，不得为 R）" % [
			high_speed, bus.gearbox.mode])

	# ---- 6. 手刹紧急停车：速度立即清零 + HUD 右上角红色感叹号 ----
	bus.gearbox.set_mode("D")
	_teleport(120.0)
	Input.action_press("accelerate")
	await _sim(180)
	Input.action_release("accelerate")
	var v_pre_hb: float = bus.get_speed_kmh()
	Input.action_press("handbrake")
	await _sim(6)  # 0.1 s
	var v_post_hb: float = bus.get_speed_kmh()
	var hb_shown: bool = hud.handbrake_label.visible
	Input.action_release("handbrake")
	await _sim(6)
	var hb_hidden: bool = not hud.handbrake_label.visible
	print("FEEL_HANDBRAKE: %.1f km/h 拉手刹 0.1 s -> %.2f km/h（要求 <1），感叹号显示=%s 释放后隐藏=%s" % [
			v_pre_hb, v_post_hb, str(hb_shown), str(hb_hidden)])

	# ---- 7. 喇叭：按住持续播放，松开停止 ----
	Input.action_press("horn")
	await _sim(6)
	var horn_on: bool = main.horn.is_playing()
	Input.action_release("horn")
	await _sim(6)
	var horn_off: bool = not main.horn.is_playing()
	print("FEEL_HORN: 按下播放=%s（要求 true），松开停止=%s（要求 true）" % [str(horn_on), str(horn_off)])

	# ---- 8. 对向车道交通流：数量/逆向运动/车道保持 ----
	var tv: Array = main.traffic.get_vehicles()
	var s_before: Array[float] = []
	for v in tv:
		s_before.append(v.s)
	await _sim(120)  # 2 s
	var all_reversed: bool = true
	var lane_ok: bool = true
	for i in tv.size():
		var v: Dictionary = tv[i]
		if v.s >= s_before[i]:
			all_reversed = false
		var t: Transform3D = route.get_transform_at(v.s)
		var lat: float = (v.node.global_position - t.origin).dot(t.basis.x)
		if absf(lat - TrafficManager.LANE_OFFSET) > 0.6:
			lane_ok = false
	var kinds: Array[String] = []
	for v in tv:
		kinds.append(v.kind)
	print("FEEL_TRAFFIC: %d 辆对向来车（%s），2 s 内全部逆向行进=%s，车道偏移保持=%s" % [
			tv.size(), "、".join(kinds), str(all_reversed), str(lane_ok)])

	print("FEEL_SUMMARY done")


func _steer_of(b: BusController) -> float:
	for c in b.get_children():
		if c is VehicleWheel3D and c.use_as_steering:
			return c.steering
	return 0.0


func _press_action(action_name: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action_name
	ev.pressed = true
	Input.parse_input_event(ev)


func _sim(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func _teleport(s: float) -> void:
	Input.action_release("accelerate")
	Input.action_release("brake")
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	bus.global_transform = route.get_transform_at(s, RouteManager.RIGHT_LANE_OFFSET)
	bus.linear_velocity = Vector3.ZERO
	bus.angular_velocity = Vector3.ZERO
	bus.sleeping = false
	cam_mgr.snap_chase()
	await _sim(30)
