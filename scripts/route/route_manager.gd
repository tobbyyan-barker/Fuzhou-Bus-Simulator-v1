## 鼓山测试场：程序化路线生成 + 路网构建 + 里程统计
## 路线（虚构，非真实地理数据）：起步长直道 700 m → 右缓弯 22° → 8% 上坡 250 m
## → 高架直道 300 m → 左缓弯 22° → 8% 下坡 250 m → 终点长直道 820 m（巴士站）
## 全长约 2.47 km。程序化生成保证里程精确、可复现、测试可预期。
class_name RouteManager
extends Node3D

const ROAD_WIDTH := 8.0
const ROAD_THICKNESS := 0.3
const CURB_WIDTH := 0.35
const GUARDRAIL_HEIGHT := 0.9

var waypoints: Array[Vector3] = []
var cumulative: Array[float] = []
var total_length: float = 0.0

var bus: VehicleBody3D
var _mileage_m: float = 0.0


func _ready() -> void:
	_build_route()
	_build_ground()
	_build_road_meshes()
	_build_stop_area()


# ---------------- 路线生成 ----------------

class Walker:
	var pos := Vector3.ZERO
	var heading := 0.0  # 弧度；0 = 朝 -Z

	static func dir(h: float) -> Vector3:
		return Vector3(sin(h), 0.0, -cos(h))

	func forward(length: float, slope: float) -> void:
		var d := dir(heading)
		pos += Vector3(d.x, 0.0, d.z) * length + Vector3.UP * (slope * length)

	func arc(radius: float, total_angle: float) -> void:
		var steps := maxi(3, int(absf(total_angle) / deg_to_rad(5.0)))
		var step_a := total_angle / steps
		var arc_len := absf(radius * step_a)
		for _i in steps:
			heading += step_a
			var d := dir(heading)
			pos += Vector3(d.x, 0.0, d.z) * arc_len


func _build_route() -> void:
	var w := Walker.new()
	waypoints.append(w.pos)
	w.forward(700.0, 0.0)
	waypoints.append(w.pos)
	w.arc(200.0, deg_to_rad(22.0))
	waypoints.append(w.pos)
	w.forward(250.0, 0.08)
	waypoints.append(w.pos)
	w.forward(300.0, 0.0)
	waypoints.append(w.pos)
	w.arc(200.0, deg_to_rad(-22.0))
	waypoints.append(w.pos)
	w.forward(250.0, -0.08)
	waypoints.append(w.pos)
	w.forward(820.0, 0.0)
	waypoints.append(w.pos)
	cumulative.append(0.0)
	for i in range(1, waypoints.size()):
		cumulative.append(cumulative[i - 1] + waypoints[i - 1].distance_to(waypoints[i]))
	total_length = cumulative[cumulative.size() - 1]


# ---------------- 公共 API ----------------

func get_spawn_transform() -> Transform3D:
	return get_transform_at(1.5)


func get_stop_position() -> Vector3:
	return waypoints[waypoints.size() - 1]


func get_transform_at(s: float) -> Transform3D:
	s = clampf(s, 0.0, total_length - 0.5)
	var i := 1
	while i < cumulative.size() - 1 and cumulative[i] < s:
		i += 1
	var a := waypoints[i - 1]
	var b := waypoints[i]
	var seg_len := maxf(cumulative[i] - cumulative[i - 1], 0.001)
	var t := (s - cumulative[i - 1]) / seg_len
	var p := a.lerp(b, t)
	var fwd := (b - a).normalized()
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), p + Vector3.UP * 0.3)


func get_mileage_km() -> float:
	return _mileage_m / 1000.0


func get_total_length() -> float:
	return total_length


## 自动驾驶：返回 pos 沿路线前进 look_ahead 米的瞄准点
func get_point_ahead(pos: Vector3, look_ahead: float) -> Vector3:
	var s := get_nearest_s(pos)
	return get_transform_at(minf(s + look_ahead, total_length - 1.0)).origin


func get_nearest_s(pos: Vector3) -> float:
	var best_s := 0.0
	var best_d := INF
	for i in range(1, waypoints.size()):
		var a := waypoints[i - 1]
		var b := waypoints[i]
		var ab := b - a
		var seg_len_sq := ab.length_squared()
		if seg_len_sq < 0.001:
			continue
		var t := clampf((pos - a).dot(ab) / seg_len_sq, 0.0, 1.0)
		var proj := a + ab * t
		var d := pos.distance_squared_to(proj)
		if d < best_d:
			best_d = d
			best_s = cumulative[i - 1] + ab.length() * t
	return best_s


func _physics_process(delta: float) -> void:
	if bus != null:
		var v := Vector3(bus.linear_velocity.x, 0.0, bus.linear_velocity.z)
		_mileage_m += v.length() * delta


# ---------------- 路网构建 ----------------

func _build_ground() -> void:
	var mn := Vector3(waypoints[0])
	var mx := Vector3(waypoints[0])
	for p in waypoints:
		mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
		mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
	var center := (mn + mx) * 0.5
	var size := Vector3((mx.x - mn.x) + 500.0, 0.3, (mx.z - mn.z) + 500.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.42, 0.24)
	mat.roughness = 1.0
	_add_box(Transform3D(Basis(), Vector3(center.x, -0.35, center.z)), size, mat, true)


func _build_road_meshes() -> void:
	var road_mat := StandardMaterial3D.new()
	road_mat.albedo_color = Color(0.16, 0.16, 0.18)
	road_mat.roughness = 0.95
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.9, 0.9, 0.9)
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var curb_mat := StandardMaterial3D.new()
	curb_mat.albedo_color = Color(0.72, 0.72, 0.7)
	curb_mat.roughness = 0.9
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.78, 0.8, 0.83)
	rail_mat.metallic = 0.7
	rail_mat.roughness = 0.35

	for i in range(1, waypoints.size()):
		var a := waypoints[i - 1]
		var b := waypoints[i]
		var seg_len := a.distance_to(b)
		var fwd := (b - a).normalized()
		var basis := Basis.looking_at(fwd, Vector3.UP)
		var mid := (a + b) * 0.5

		# 路面（顶面对齐航点高度）
		_add_box(
				Transform3D(basis, mid + Vector3.DOWN * (ROAD_THICKNESS * 0.5)),
				Vector3(ROAD_WIDTH, ROAD_THICKNESS, seg_len), road_mat, true)
		# 中央虚线带（视觉）
		_add_box(Transform3D(basis, mid + Vector3.UP * 0.012),
				Vector3(0.15, 0.02, seg_len * 0.85), line_mat, false)
		# 两侧路缘（视觉）
		for side in [-1.0, 1.0]:
			var off: Vector3 = basis.x * (side * (ROAD_WIDTH * 0.5 + CURB_WIDTH * 0.5))
			_add_box(Transform3D(basis, mid + off + Vector3.UP * 0.09),
					Vector3(CURB_WIDTH, 0.24, seg_len), curb_mat, false)
		# 坡道段护栏（防坠落，带碰撞）
		var horiz := Vector2(b.x - a.x, b.z - a.z).length()
		var slope := (b.y - a.y) / maxf(horiz, 0.001)
		if absf(slope) > 0.02:
			for side in [-1.0, 1.0]:
				var off: Vector3 = basis.x * (side * (ROAD_WIDTH * 0.5 + 0.55))
				_add_box(Transform3D(basis, mid + off + Vector3.UP * 0.55),
						Vector3(0.12, GUARDRAIL_HEIGHT, seg_len), rail_mat, true)


func _build_stop_area() -> void:
	var stop := get_stop_position()
	var fwd := (stop - waypoints[waypoints.size() - 2]).normalized()
	var basis := Basis.looking_at(fwd, Vector3.UP)

	var plat_mat := StandardMaterial3D.new()
	plat_mat.albedo_color = Color(0.6, 0.58, 0.55)
	plat_mat.roughness = 0.95
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.25, 0.27, 0.3)
	pole_mat.metallic = 0.6
	var sign_mat := StandardMaterial3D.new()
	sign_mat.albedo_color = Color(0.12, 0.35, 0.72)
	sign_mat.roughness = 0.4

	# 站台（右侧，带碰撞）
	var plat_pos := stop + basis.x * (ROAD_WIDTH * 0.5 + 2.0)
	plat_pos.y = stop.y + 0.13
	_add_box(Transform3D(basis, plat_pos), Vector3(3.2, 0.26, 16.0), plat_mat, true)

	# 站牌：立柱 + 牌面（视觉）
	var pole_pos: Vector3 = plat_pos + basis.z * 7.0
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.06
	pm.bottom_radius = 0.06
	pm.height = 2.6
	pm.material = pole_mat
	pole.mesh = pm
	pole.position = pole_pos + Vector3.UP * 1.3
	add_child(pole)
	var sign := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.4, 0.5, 0.06)
	sm.material = sign_mat
	sign.mesh = sm
	sign.position = pole_pos + Vector3.UP * 2.35
	add_child(sign)


func _add_box(t: Transform3D, size: Vector3, mat: Material, with_collision: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	if with_collision:
		var body := StaticBody3D.new()
		body.transform = t
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		body.add_child(mi)
		add_child(body)
	else:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.transform = t
		add_child(mi)
