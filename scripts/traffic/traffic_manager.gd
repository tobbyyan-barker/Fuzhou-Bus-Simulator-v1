## 对向车道交通流：机动车（轿车/货车）+ 非机动车（电动自行车）
## 沿路线 -x 侧（对向车道，横向偏 2 m）从路线终点向起点逆向行驶，循环回收。
## 车辆为图元程序化拼装（无外部素材），AnimatableBody3D 带碰撞——
## 客车与之相撞有真实碰撞响应（对向车不会被撞停，保持匀速通行）。
## 固定随机种子保证测试可复现。
class_name TrafficManager
extends Node3D

## 对向车道中心相对路线中线的横向偏移（-x = 客车前进方向的左侧）
const LANE_OFFSET := -2.0
## 低于该里程即回收至路线末端重新进入
const RECYCLE_AT_S := 5.0
## 固定随机种子（可复现性）
const RNG_SEED := 2026

@export var car_count: int = 3
@export var truck_count: int = 1
@export var ebike_count: int = 2

var route: RouteManager

## 车辆记录：{kind: String, s: float, speed_mps: float, node: AnimatableBody3D}
var vehicles: Array[Dictionary] = []

var _rng := RandomNumberGenerator.new()
var _spawned: bool = false


func setup(r: RouteManager) -> void:
	route = r


func _physics_process(delta: float) -> void:
	if route == null:
		return
	if not _spawned:
		_spawn_all()
		_spawned = true
	for v in vehicles:
		v.s -= v.speed_mps * delta
		if v.s < RECYCLE_AT_S:
			# 回收：从路线末端重新进入（带随机散布）
			v.s = route.get_total_length() - _rng.randf_range(10.0, 60.0)
		v.node.global_transform = _pose_at(v.s)


## 供测试断言读取
func get_vehicles() -> Array[Dictionary]:
	return vehicles


func _spawn_all() -> void:
	_rng.seed = RNG_SEED
	var kinds: Array[String] = []
	for _i in car_count:
		kinds.append("car")
	for _i in truck_count:
		kinds.append("truck")
	for _i in ebike_count:
		kinds.append("ebike")
	kinds.shuffle()
	var total: float = route.get_total_length()
	for i in kinds.size():
		var kind: String = kinds[i]
		var s: float = total * (float(i) + 0.5) / float(kinds.size()) \
				+ _rng.randf_range(-30.0, 30.0)
		s = clampf(s, 60.0, total - 10.0)
		var node: AnimatableBody3D = _build_body(kind)
		# 关键：先摆到路线位置再入树！否则节点以原点姿态注册进物理空间，
		# 与出生在起点附近的客车深度重叠 → 物理解算器天量分离冲量（见 DEVLOG 故障 #7）
		node.transform = _pose_at(s)
		add_child(node)
		var speed_kmh: float = _speed_for(kind)
		vehicles.append({
			"kind": kind,
			"s": s,
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


## 对向车道姿态：路线姿态 + 左侧偏移 + 掉头 180°
func _pose_at(s: float) -> Transform3D:
	var t: Transform3D = route.get_transform_at(s)
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
