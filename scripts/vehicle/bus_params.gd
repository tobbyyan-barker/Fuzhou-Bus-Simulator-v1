## 车辆参数资源（数据驱动，Phase 2 增加车型只需新增 .tres + 场景）
## 闽通 MT-10：10.5 m 级城市客车（虚构品牌）
class_name BusParams
extends Resource

@export_group("身份")
@export var display_name: String = "闽通 MT-10"

@export_group("车身物理")
@export var mass_kg: float = 12000.0
## 重心偏高——体现大客车侧倾敏感特性
@export var center_of_mass: Vector3 = Vector3(0.0, 0.95, 0.0)

@export_group("动力")
## 每个驱动轮的峰值 engine_force（2 驱动轮合计 32 kN，0-60 km/h 约 7 s）
@export var max_engine_force: float = 35000.0
## 每个车轮的制动强度（AC3 调参项）
@export var max_brake_force: float = 800.0
## 松油门时的滚动阻力（模拟客车阻力，防止无限滑行）
@export var rolling_brake: float = 100.0
@export var reverse_force_ratio: float = 0.35
@export var top_speed_kmh: float = 110.0
@export var reverse_top_kmh: float = 20.0

@export_group("转向")
@export var max_steer_deg: float = 38.0
@export var steer_lerp_rate: float = 5.0

@export_group("车轮与悬挂")
@export var wheel_radius: float = 0.5
@export var wheel_friction_slip: float = 2.0
## 关键几何约束：wheel_rest_length + wheel_radius 必须大于悬挂连接点高度，
## 否则车轮射线检测余量不足，客车会穿透地面（见 DEVLOG 故障记录 #1）
@export var suspension_rest_length: float = 0.35
@export var suspension_stiffness: float = 40.0
@export var suspension_max_force: float = 35000.0
@export var suspension_travel: float = 5.0
@export var damping_compression: float = 1.2
@export var damping_relaxation: float = 1.5

@export_group("驾驶舱")
## 第一人称相机眼部位置（客车局部坐标，前方为 -Z）
@export var cab_eye_transform: Transform3D = Transform3D(Basis(), Vector3(-0.75, 2.35, -3.7))
