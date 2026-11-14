## 自动驾驶（纯追踪转向 + 速度控制）：用于 GUI 自动演示与图形界面测试。
## 挂在 main 场景，通过 BusController 外部控制接口驱动，不占用键盘输入。
## 速度控制感知三类约束：总站 / 红灯停车线 / 同车道前车（速度匹配跟车）。
## 慢车（电动车等 < 25 km/h 且在移动）在对向车道安全窗口内时借道超越。
class_name Autopilot
extends Node

var bus: BusController
var route: RouteManager
var lights: TrafficLightManager
var traffic: TrafficManager
var active: bool = false

@export var target_speed_kmh: float = 55.0
## 制动减速度估计（m/s²），用于进站/红灯刹停点计算
@export var brake_decel: float = 2.3
## 前车速度匹配生效距离（米）
const FOLLOW_RANGE_M := 30.0
## 超车触发：前车慢于该速度（km/h）且在移动
const OVERTAKE_LEAD_MAX_KMH := 25.0
## 超车需要对向车道的净空窗口（米）
const OVERTAKE_CLEAR_AHEAD_M := 250.0
const OVERTAKE_CLEAR_BEHIND_M := 60.0
## 超车换回本车道的冷却（秒）
const OVERTAKE_COOLDOWN_S := 3.0

var _dbg_timer: float = 0.0
var _wait_reason: String = ""
var _overtaking: bool = false
var _overtake_cooldown: float = 0.0


func _physics_process(delta: float) -> void:
	if not active or bus == null or route == null:
		return
	bus.use_external_control = true
	_dbg_timer += delta
	_overtake_cooldown = maxf(_overtake_cooldown - delta, 0.0)
	var bus_s := route.get_nearest_s(bus.global_position)

	# ---- 决策：车道选择（正常右车道 / 超车借对向车道） ----
	var lane_off: float = RouteManager.RIGHT_LANE_OFFSET
	var ahead: Variant = traffic.get_vehicle_ahead(bus_s) if traffic != null else null
	var d_line: float = lights.get_stop_line_gap(bus_s, 1) if lights != null else INF
	var dist_station: float = _flat_dist(bus.global_position, route.get_stop_position())
	_update_overtake(ahead, d_line, dist_station, bus_s)
	if _overtaking:
		lane_off = -RouteManager.RIGHT_LANE_OFFSET

	# ---- 纯追踪转向：瞄准前方 30 m 的目标车道点 ----
	var aim := route.get_point_ahead(bus.global_position, 30.0, lane_off)
	var local := bus.global_transform.basis.inverse() * (aim - bus.global_position)
	# local.x > 0 → 目标在右侧 → 转负（ steer 正 = 左）
	var steer_cmd := clampf(-local.x / 15.0, -1.0, 1.0)

	# ---- 速度控制：硬停车约束（红灯/总站/停着的前车） + 速度匹配（移动前车） ----
	var sp := bus.get_speed_kmh()
	var v_ms := sp / 3.6
	var brake_dist := (v_ms * v_ms) / (2.0 * brake_decel)
	var target_kmh: float = target_speed_kmh
	var stop_dist: float = dist_station
	_wait_reason = ""

	if not _overtaking and d_line != INF:
		stop_dist = minf(stop_dist, d_line)
		if d_line < brake_dist + 6.0:
			_wait_reason = "red_light"
	if ahead != null and not _overtaking:
		var gap: float = ahead.gap
		var lead_kmh: float = ahead.speed_mps * 3.6
		if ahead.speed_mps < 1.0:
			# 前车停着（红灯队列）：跟停，保持 2 m 间距
			stop_dist = minf(stop_dist, maxf(gap - 2.0, 0.5))
			_wait_reason = "lead_stopped"
		elif gap < FOLLOW_RANGE_M:
			# 速度匹配：与前车速度成比例的目标，车距稳定在 ~29 m
			var f := clampf((gap - 5.0) / 25.0, 0.0, 1.2)
			target_kmh = minf(target_kmh, lead_kmh * f + 1.0)
			_wait_reason = "following"
		if gap < 8.0 and ahead.speed_mps < 1.0:
			_wait_reason = "lead_stopped"

	var throttle := 0.0
	var brake := 0.0
	if stop_dist < brake_dist + 6.0:
		if sp < 2.0 and stop_dist > 4.0 and _wait_reason == "":
			throttle = 0.15  # 蠕行进站（仅总站；红灯/前车等待不蠕行）
		else:
			brake = 1.0
	elif sp < target_kmh:
		throttle = 1.0
	else:
		brake = 0.15

	bus.set_external_control(throttle, brake, steer_cmd)

	if _dbg_timer > 5.0:
		_dbg_timer = 0.0
		print("AUTO_DBG s=%.2f pos=(%.1f, %.1f) v=%.1f dist_stop=%.1f steer=%.2f mode=%s wait=%s overtake=%s" % [
				bus_s, bus.global_position.x, bus.global_position.z,
				bus.get_speed_kmh(), dist_station,
				bus._steering, bus.gearbox.mode, _wait_reason, str(_overtaking)])


## 超车状态机：进入（慢车+净空+非红灯+远离总站）/ 退出（超过后拉开安全距离再并回）
func _update_overtake(ahead: Variant, d_line: float, dist_station: float, bus_s: float) -> void:
	if _overtaking:
		# 退出条件：本车道前后无近车（被超车辆已在身后 20 m 外），或红灯将至强制返回
		var merge_ok := _merge_clear(bus_s)
		if d_line != INF and d_line < 30.0 and merge_ok:
			_overtaking = false
			_overtake_cooldown = OVERTAKE_COOLDOWN_S
		elif merge_ok:
			_overtaking = false
			_overtake_cooldown = OVERTAKE_COOLDOWN_S
		return
	if _overtake_cooldown > 0.0:
		return
	if ahead == null or d_line != INF or dist_station < 150.0:
		return
	var lead_kmh: float = ahead.speed_mps * 3.6
	if lead_kmh >= OVERTAKE_LEAD_MAX_KMH or ahead.speed_mps < 0.5:
		return  # 只超移动中的慢车（停着的车多半在等红灯）
	if ahead.gap < 35.0 and _oncoming_clear(bus_s):
		_overtaking = true


## 并回本车道安全检查：右车道前方 25 m / 身后 20 m 内无车
func _merge_clear(bus_s: float) -> bool:
	if traffic == null:
		return true
	for v in traffic.vehicles:
		if v.dir < 0:
			continue
		var rel: float = v.s - bus_s
		if rel > -20.0 and rel < 25.0:
			return false
	return true


## 对向车道净空检查：超车窗口内无对向车（前后各留安全距离）
func _oncoming_clear(bus_s: float) -> bool:
	if traffic == null:
		return true
	for v in traffic.vehicles:
		if v.dir >= 0:
			continue
		if v.s > bus_s - OVERTAKE_CLEAR_BEHIND_M and v.s < bus_s + OVERTAKE_CLEAR_AHEAD_M:
			return false
	return true


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
