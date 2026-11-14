## 主场景编排：实例化地图/客车/相机/HUD/任务，接线并处理命令行模式。
## 支持的命令行用户参数（`--` 之后传入）：
##   --auto   自动驾驶演示（用于 GUI 自动化测试）
##   --bench  性能采样：600 帧后输出平均 FPS 并退出（AC7）
extends Node3D

var map: RouteManager
var bus: BusController
var cam_mgr: CameraManager
var hud: Hud
var stop_task: StopTask
var autopilot: Autopilot
var traffic: TrafficManager
var horn: Horn

var _bench_active: bool = false
var _bench_frames: int = 0
var _bench_elapsed: float = 0.0
var _auto_quit_timer: float = -1.0


func _ready() -> void:
	map = $Map
	bus = $Bus
	cam_mgr = $CameraManager
	hud = $HUD
	stop_task = $StopTask
	traffic = $Traffic
	horn = $Horn
	traffic.setup(map)

	_ensure_input_map()

	bus.global_transform = map.get_spawn_transform()
	map.bus = bus
	cam_mgr.bus = bus
	cam_mgr.snap_chase()
	hud.bus = bus
	hud.route = map
	hud.stop_task = stop_task
	stop_task.bus = bus
	stop_task.stop_position = map.get_stop_position()
	stop_task.stop_completed.connect(_on_stop_completed)

	var args := OS.get_cmdline_user_args()
	if "--auto" in args:
		autopilot = Autopilot.new()
		autopilot.bus = bus
		autopilot.route = map
		add_child(autopilot)
		autopilot.active = true
		print("AUTOPILOT_ON")
	if "--bench" in args:
		_bench_active = true
		print("BENCH_START")


func _process(delta: float) -> void:
	if _bench_active:
		_bench_frames += 1
		if _bench_frames > 120:
			# 跳过前 120 帧着色器编译预热，测稳态性能
			_bench_elapsed += delta
			if _bench_frames >= 720:
				var fps: float = 600.0 / maxf(_bench_elapsed, 0.001)
				var frame_ms: float = 1000.0 * _bench_elapsed / 600.0
				print("BENCH_RESULT avg_fps=%.1f frame_ms=%.2f frames=600 (warmup=120 skipped)" % [fps, frame_ms])
				print("AC7_MEASURED frame_ms=%.2f (target<16.7)" % frame_ms)
				get_tree().quit(0)
	if _auto_quit_timer > 0.0:
		_auto_quit_timer -= delta
		if _auto_quit_timer <= 0.0:
			get_tree().quit(0)


func _on_stop_completed(elapsed_s: float) -> void:
	print("AUTO_STOP_COMPLETED elapsed=%.1f" % elapsed_s)
	# 自动演示模式下 3 s 后退出，便于命令行捕获结果
	if autopilot != null and autopilot.active:
		_auto_quit_timer = 3.0


## 兜底：确保 InputMap 动作存在（防止 project.godot 输入序列化异常导致动作缺失）
func _ensure_input_map() -> void:
	var key_actions := {
		"accelerate": KEY_W,
		"brake": KEY_S,
		"steer_left": KEY_A,
		"steer_right": KEY_D,
		"toggle_camera": KEY_C,
		"handbrake": KEY_SPACE,
		"gear_r": KEY_R,
		"gear_n": KEY_N,
		"horn": KEY_H,
	}
	for action in key_actions:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = key_actions[action]
			InputMap.action_add_event(action, ev)
