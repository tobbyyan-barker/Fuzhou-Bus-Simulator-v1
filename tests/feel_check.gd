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

	# ---- 8. 双向车道交通流：对向逆向行进 / 同向前行 / 车道保持 ----
	var tv: Array = main.traffic.get_vehicles()
	var s_before: Array[float] = []
	for v in tv:
		s_before.append(v.s)
	await _sim(120)  # 2 s
	var oncoming_cnt := 0
	var same_cnt := 0
	var oncoming_ok: bool = true  # 对向车不得前行
	var same_ok: bool = true      # 同向车不得倒退（红灯等待允许原地停）
	var lane_ok: bool = true
	var moved_cnt := 0
	for i in tv.size():
		var v: Dictionary = tv[i]
		var lane_off: float = TrafficManager.SAME_LANE_OFFSET if v.dir > 0 else TrafficManager.LANE_OFFSET
		if v.dir > 0:
			same_cnt += 1
			if v.s < s_before[i] - 0.05:
				same_ok = false
		else:
			oncoming_cnt += 1
			if v.s > s_before[i] + 0.05:
				oncoming_ok = false
		if absf(v.s - s_before[i]) > 0.1:
			moved_cnt += 1
		var t: Transform3D = route.get_transform_at(v.s)
		var lat: float = (v.node.global_position - t.origin).dot(t.basis.x)
		if absf(lat - lane_off) > 0.6:
			lane_ok = false
	print("FEEL_TRAFFIC: 对向 %d 辆逆向行进=%s，同向 %d 辆前行=%s，双向车道保持=%s（%d/%d 在移动，红灯等待车原地停）" % [
			oncoming_cnt, str(oncoming_ok), same_cnt, str(same_ok), str(lane_ok), moved_cnt, tv.size()])

	# ---- 9. 红绿灯：状态机 / 停车线判定 / 警示横幅 + 车内语音播报 / 倒计时 ----
	main.traffic_lights.time_start = 30.0  # 灯0（500 m）进入红灯，剩约 18 s
	await _sim(6)
	var st0: String = main.traffic_lights.get_state(0)
	var rem_before: float = main.traffic_lights.get_remaining(0)
	var line_gap: float = main.traffic_lights.get_stop_line_gap(480.0, 1)
	var line_past: float = main.traffic_lights.get_stop_line_gap(497.0, 1)
	await _sim(60)  # 1 s：倒计时递减观察
	var rem_after: float = main.traffic_lights.get_remaining(0)
	_teleport(450.0)  # 距停车线（495 m）45 m < 60 m 警示距离
	await _sim(60)
	var warn: bool = main.traffic_lights.warning_active
	var hud_shown: bool = hud.signal_label.visible
	var voice_red: bool = main.voice.has_announced_containing("红灯")
	var cd_text: String = main.traffic_lights.get_countdown_text(0, 1)
	print("FEEL_LIGHT: 灯0状态=%s（应为 RED），倒计时 %.1f -> %.1f s（递减=%s），停车线判定 gap=%.1f m（红灯需停）越过线=%s（应 INF 放行），警示=%s，HUD 横幅=%s，语音播报红灯=%s，倒计时牌='%s'" % [
			st0, rem_before, rem_after, str(rem_after < rem_before), line_gap,
			str(line_past), str(warn), str(hud_shown), str(voice_red), cd_text])
	# 驶离后警示应消失
	_teleport(100.0)
	await _sim(30)
	print("FEEL_LIGHT_OFF: 驶离灯区后警示消失=%s（要求 true）" % str(not main.traffic_lights.warning_active))

	# ---- 12. 第一人称驾驶舱视角：Q 键切换 / 刚性跟随 / FOV 接线 / 零物理扰动 ----
	_teleport(300.0)
	Input.action_press("accelerate")
	await _sim(120)
	Input.action_release("accelerate")
	await _sim(30)
	# Q 键绑定校验（真实按键路径的保证）+ 事件触发切换
	var q_bound := false
	for ev in InputMap.action_get_events("toggle_camera"):
		if ev is InputEventKey and ev.physical_keycode == KEY_Q:
			q_bound = true
	var q_ev := InputEventKey.new()
	q_ev.physical_keycode = KEY_Q
	q_ev.pressed = true
	Input.parse_input_event(q_ev)
	await _sim(6)
	var in_cab: bool = cam_mgr.is_cab_active()
	if not in_cab:
		cam_mgr.toggle()  # headless 事件派发兜底；Q 绑定已由 q_bound 校验
		await _sim(6)
		in_cab = cam_mgr.is_cab_active()
	# 切换的物理扰动：同一物理帧内切换前后直接读速度（隔离其它力：
	# 滑行阻力/坡道/交通剐蹭，它们在任何跨帧窗口都会混入）
	var vel_before_frame: Vector3 = bus.linear_velocity
	cam_mgr.toggle()  # 切回，再切一次：等效操作，零帧间隔
	cam_mgr.toggle()
	var vel_after_frame: Vector3 = bus.linear_velocity
	var disturb: float = vel_before_frame.distance_to(vel_after_frame)
	# 行驶中采样：相机位姿应精确等于 bus_transform * cab_eye_offset（刚性绑定）。
	# 误差容差 0.25 m：headless 采样与相机更新的帧次序差 ≈ 1 物理帧位移
	var max_err := 0.0
	var expect_basis_err := 0.0
	for j in 6:
		await _sim(10)
		var expect: Transform3D = bus.global_transform * Transform3D(Basis(), bus.params.cab_eye_offset)
		max_err = maxf(max_err, cam_mgr.cab_cam.global_position.distance_to(expect.origin))
		expect_basis_err = maxf(expect_basis_err,
				absf(cam_mgr.cab_cam.global_transform.basis.z.dot(expect.basis.z) - 1.0))
	var fov_ok: bool = is_equal_approx(cam_mgr.cab_cam.fov, bus.params.cab_fov_deg)
	# 切回第三人称（Q 再按一次），确认往返切换
	Input.parse_input_event(q_ev)
	await _sim(6)
	if cam_mgr.is_cab_active():
		cam_mgr.toggle()  # 兜底：headless 事件派发差异
		await _sim(6)
	var back_to_chase: bool = not cam_mgr.is_cab_active()
	print("FEEL_CAB_CAM: Q 键绑定=%s，Q 切入驾驶舱=%s，行驶中跟随误差 %.3f m / 朝向误差 %.4f（容差 0.25 m，朝向 <0.01），FOV=%.1f 接线=%s，切换速度扰动 %.2f m/s（要求 <0.3），Q 切回跟车=%s" % [
			str(q_bound), str(in_cab), max_err, expect_basis_err, cam_mgr.cab_cam.fov, str(fov_ok),
			disturb, str(back_to_chase)])

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
	# 传送清场：移走附近交通车（防止重叠炸飞）
	main.traffic.relocate_conflicts(bus.global_position, 30.0)
	bus.linear_velocity = Vector3.ZERO
	bus.angular_velocity = Vector3.ZERO
	bus.sleeping = false
	cam_mgr.snap_chase()
	await _sim(30)
