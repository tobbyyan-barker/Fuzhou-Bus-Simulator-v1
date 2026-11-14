## 双向车道交通流：机动车（轿车/货车）+ 非机动车（电动自行车）。
## 对向车道（-x 侧，偏 -2 m）：从路线终点向起点逆向行驶。
## 同向车道（+x 侧，偏 +2 m，客车行驶车道）：与客车同向前行。
## 车辆为图元程序化拼装（无外部素材），AnimatableBody3D 带碰撞——客车与之相撞有真实碰撞响应。
## 红绿灯感知：接近红灯时按制动减速度曲线减速、停在停车线前，绿灯恢复。
## 同车道跟车：与同向车保持间距，防止车辆互相穿透。
## 回收时避开客车当前位置（防止重叠炸飞，见 DEVLOG 故障 #7）。
## 固定随机种子保证测试可复现。
class_name TrafficManager
extends Node3D

## 对向车道中心相对路线中线的横向偏移（-x = 客车前进方向的左侧）
const LANE_OFFSET := -2.0
## 同向车道偏移（+x = 客车右侧）
const SAME_LANE_OFFSET := 2.0
## 低于该里程即回收（对向车）
const RECYCLE_AT_S := 5.0
## 高于该里程即回收（同向车）
const RECYCLE_AT_END := 12.0
## 固定随机种子（可复现性）
const RNG_SEED := 2026
## 交通车过红灯的制动减速度（m/s²）
const LIGHT_BRAKE_DECEL := 3.0
## 同车道跟车参数
const FOLLOW_GAP_M := 22.0
const FOLLOW_MIN_GAP_M := 6.0

@export var oncoming_car_count: int = 3
@export var oncoming_truck_count: int = 1
@export var oncoming_ebike_count: int = 2
@export var same_dir_car_count: int = 2
@export var same_dir_truck_count: int = 1
@export var same_dir_ebike_count: int = 2

var route: RouteManager
var lights: TrafficLightManager
## 客车引用：同向车回收时避开其位置
var bus: BusController
## 测试开关：暂停同向车道推进（对向车不受影响）。
## 供传送型测试（test_mvp）清场——同向车道与本车物理交互，
## 传送会人为制造重叠；同向交通行为由 feel_check 与自动驾驶回归覆盖。
var same_lane_frozen: bool = false

## 车辆记录：{kind, dir, s, cruise_mps, speed_mps, node}
## dir = +1 同向（右车道，s 递增）；dir = -1 对向（左车道，s 递减）
var vehicles: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _spawned: bool = false


func setup(r: RouteManager, l: TrafficLightManager = null) -> void:
	route = r
	lights = l


func _physics_process(delta: float) -> void:
	if route == null:
		return
	if not _spawned:
		_spawn_all()
		_spawned = true
	for v in vehicles:
		if same_lane_frozen and v.dir > 0:
			continue
		var target := _target_speed_for(v)
		var rate: float = 1.5 if target > v.speed_mps else LIGHT_BRAKE_DECEL
		v.speed_mps = move_toward(v.speed_mps, target, rate * delta)
		v.s += v.dir * v.speed_mps * delta
		_recycle(v)
		v.node.global_transform = _pose_at(v.s, v.dir)


## 供测试断言读取
func get_vehicles() -> Array[Dictionary]:
	return vehicles


## 同向车道上 s 前方最近的车辆（供自动驾驶跟车/超车决策）
## 返回 {vehicle, gap, speed_mps}，gap 为车头间距；无则 null
func get_vehicle_ahead(bus_s: float, bus_len: float = 12.0) -> Variant:
	var best: Variant = null
	var best_gap := INF
	for v in vehicles:
		if v.dir < 0:
			continue
		var gap: float = v.s - bus_s - (bus_len + _length_of(v.kind)) * 0.5 - 1.0
		if gap > 0.0 and gap < best_gap:
			best_gap = gap
			best = {"vehicle": v, "gap": gap, "speed_mps": v.speed_mps}
	return best


## 测试辅助：把过于靠近 pos 的车辆移到远处（客车传送后清场，防止重叠炸飞）。
## 同向车推到前方 300 m（行驶远离客车，不会倒车追尾）；对向车推到前方 300 m
## （在左侧车道正常驶过，与右侧车道客车无接触）。
func relocate_conflicts(pos: Vector3, radius: float = 30.0) -> void:
	if route == null:
		return
	var bus_s := route.get_nearest_s(pos)
	for v in vehicles:
		if v.node.global_position.distance_to(pos) < radius:
			v.s = _find_clear_s(bus_s + 300.0, v.dir)
			v.speed_mps = v.cruise_mps
			v.node.global_transform = _pose_at(v.s, v.dir)


## 在 preferred 附近找一个与同车道其他车辆间距 ≥ 30 m 的里程（步进探测）
func _find_clear_s(preferred: float, dir: int) -> float:
	var total := route.get_total_length()
	var s: float = clampf(preferred, 10.0, total - 12.0)
	for _attempt in 12:
		var clear := true
		for other in vehicles:
			if other.dir != dir:
				continue
			if absf(other.s - s) < 30.0:
				clear = false
				break
		if clear:
			return s
		s += 47.0
		if s > total - 12.0:
			s = 10.0
	return s


# ---------------- 速度决策 ----------------

## 目标速度 = min(巡航速度, 红灯允许速度, 跟车允许速度)
func _target_speed_for(v: Dictionary) -> float:
	var target: float = v.cruise_mps
	# 红绿灯：红灯/黄灯时按制动曲线减速停在停车线前
	if lights != null:
		var d: float = lights.get_stop_line_gap(v.s, v.dir)
		if d != INF:
			target = minf(target, sqrt(2.0 * LIGHT_BRAKE_DECEL * maxf(d - 0.5, 0.0)))
	# 同车道跟车
	var gap := _lead_gap(v)
	if gap < FOLLOW_GAP_M:
		target = minf(target, maxf(0.0, (gap - FOLLOW_MIN_GAP_M) * 0.7))
	return maxf(target, 0.0)


## 同车道最近前车净距（已越线/无前车返回 INF）
func _lead_gap(v: Dictionary) -> float:
	var best := INF
	for other in vehicles:
		if other == v or other.dir != v.dir:
			continue
		var gap: float = (other.s - v.s) * v.dir - _length_of(other.kind)
		if gap > 0.0 and gap < best:
			best = gap
	return best


func _length_of(kind: String) -> float:
	match kind:
		"car":
			return 4.4
		"truck":
			return 7.0
		_:
			return 1.7


# ---------------- 生成与回收 ----------------

func _spawn_all() -> void:
	_rng.seed = RNG_SEED
	var entries: Array = []
	for _i in oncoming_car_count:
		entries.append({"kind": "car", "dir": -1})
	for _i in oncoming_truck_count:
		entries.append({"kind": "truck", "dir": -1})
	for _i in oncoming_ebike_count:
		entries.append({"kind": "ebike", "dir": -1})
	for _i in same_dir_car_count:
		entries.append({"kind": "car", "dir": 1})
	for _i in same_dir_truck_count:
		entries.append({"kind": "truck", "dir": 1})
	for _i in same_dir_ebike_count:
		entries.append({"kind": "ebike", "dir": 1})
	entries.shuffle()
	var total: float = route.get_total_length()
	for i in entries.size():
		var e: Dictionary = entries[i]
		var kind: String = e.kind
		var dir: int = e.dir
		var s: float = total * (float(i) + 0.5) / float(entries.size()) \
				+ _rng.randf_range(-30.0, 30.0)
		# 同向车不生成在客车出生段（s < 60），避免起步即相遇
		s = clampf(s, 60.0 if dir > 0 else 40.0, total - 10.0)
		var node: AnimatableBody3D = _build_body(kind)
		# 关键：先摆到路线位置再入树！否则节点以原点姿态注册进物理空间，
		# 与出生在起点附近的客车深度重叠 → 物理解算器天量分离冲量（见 DEVLOG 故障 #7）
		node.transform = _pose_at(s, dir)
		add_child(node)
		var speed_kmh: float = _speed_for(kind)
		vehicles.append({
			"kind": kind,
			"dir": dir,
			"s": s,
			"cruise_mps": speed_kmh / 3.6,
			"speed_mps": speed_kmh / 3.6,
			"node": node,
		})


func _speed_for(kind: String) -> float:
	match kind:
		"car":
			return _rng.randf_range(45.0, 55.0)
		"truck":
			return _rng.randf_range(35.0, 40.0)
		_:
			return _rng.randf_range(15.0, 20.0)


func _recycle(v: Dictionary) -> void:
	var total := route.get_total_length()
	if v.dir < 0:
		if v.s < RECYCLE_AT_S:
			v.s = total - _rng.randf_range(10.0, 60.0)
	else:
		if v.s > total - RECYCLE_AT_END:
			# 同向车回收：优先重生在客车前方 150–400 m（保持路上有车）；
			# 客车已近终点则重生在后方（跟随抵达，不与客车重叠）
			var bus_s: float = route.get_nearest_s(bus.global_position) if bus != null else 0.0
			var s_new: float = bus_s + _rng.randf_range(150.0, 400.0)
			if s_new > total - 40.0:
				s_new = maxf(bus_s - _rng.randf_range(150.0, 300.0), 10.0)
			v.s = _find_clear_s(s_new, 1)


## 车道姿态：dir=+1 同向（右车道，车头朝前）；dir=-1 对向（左车道，掉头 180°）
func _pose_at(s: float, dir: int) -> Transform3D:
	var t: Transform3D = route.get_transform_at(s)
	if dir > 0:
		var origin: Vector3 = t.origin + t.basis.x * SAME_LANE_OFFSET + Vector3.DOWN * 0.3
		return Transform3D(t.basis, origin)
	var origin: Vector3 = t.origin + t.basis.x * LANE_OFFSET + Vector3.DOWN * 0.3
	var b: Basis = Basis(-t.basis.x, t.basis.y, -t.basis.z)
	return Transform3D(b, origin)


# ---------------- 车辆拼装（纯图元） ----------------

const CAR_PALETTE: Array[Color] = [
	Color(0.72, 0.22, 0.18), Color(0.20, 0.35, 0.68), Color(0.85, 0.82, 0.35),
	Color(0.55, 0.57, 0.60), Color(0.15, 0.55, 0.40),
]


func _build_body(kind: String) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	match kind:
		"car":
			_build_car(body)
		"truck":
			_build_truck(body)
		_:
			_build_ebike(body)
	return body


func _mat(color: Color, metallic: float = 0.15) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = 0.6
	return m


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_wheel(parent: Node3D, pos: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.28
	mi.mesh = mesh
	mi.material_override = _mat(Color(0.08, 0.08, 0.08), 0.0)
	mi.position = pos
	# 圆柱默认轴向 Y，转 90° 使轴向对齐 X（车轮朝向）
	mi.rotate_object_local(Vector3(0, 0, 1), PI * 0.5)
	parent.add_child(mi)


func _add_collision(parent: Node3D, size: Vector3, center_y: float) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = Vector3(0, center_y, 0)
	parent.add_child(cs)


## 轿车：4.4 m × 1.75 m，双盒车身 + 4 轮
func _build_car(parent: Node3D) -> void:
	var paint: Color = CAR_PALETTE[_rng.randi_range(0, CAR_PALETTE.size() - 1)]
	_add_box(parent, Vector3(1.75, 0.6, 4.4), Vector3(0, 0.85, 0), _mat(paint, 0.35))
	_add_box(parent, Vector3(1.55, 0.55, 2.2), Vector3(0, 1.4, -0.2),
			_mat(Color(0.12, 0.14, 0.18), 0.5))
	for x in [-0.78, 0.78]:
		for z in [-1.4, 1.4]:
			_add_wheel(parent, Vector3(x, 0.33, z), 0.33)
	_add_collision(parent, Vector3(1.75, 1.75, 4.4), 0.87)


## 货车：7 m × 2.3 m，货厢 + 驾驶室 + 4 大轮
func _build_truck(parent: Node3D) -> void:
	_add_box(parent, Vector3(2.3, 2.3, 4.6), Vector3(0, 1.9, 0.9),
			_mat(Color(0.30, 0.45, 0.62), 0.2))
	_add_box(parent, Vector3(2.2, 1.4, 2.0), Vector3(0, 1.2, -2.4),
			_mat(Color(0.75, 0.55, 0.15), 0.3))
	for x in [-1.0, 1.0]:
		for z in [-2.3, 2.3]:
			_add_wheel(parent, Vector3(x, 0.45, z), 0.45)
	_add_collision(parent, Vector3(2.3, 3.1, 7.0), 1.55)


## 电动自行车：1.7 m × 0.5 m，细车架 + 骑行人 + 2 轮
func _build_ebike(parent: Node3D) -> void:
	_add_box(parent, Vector3(0.18, 0.5, 1.5), Vector3(0, 0.55, 0),
			_mat(Color(0.2, 0.22, 0.55), 0.25))
	_add_box(parent, Vector3(0.5, 0.06, 0.06), Vector3(0, 1.05, -0.55),
			_mat(Color(0.1, 0.1, 0.1), 0.0))
	var rider := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.16
	capsule.height = 0.95
	rider.mesh = capsule
	rider.material_override = _mat(Color(0.95, 0.55, 0.1), 0.0)
	rider.position = Vector3(0, 1.3, 0.1)
	parent.add_child(rider)
	for z in [-0.6, 0.6]:
		_add_wheel(parent, Vector3(0, 0.3, z), 0.3)
	_add_collision(parent, Vector3(0.5, 1.9, 1.7), 0.95)
