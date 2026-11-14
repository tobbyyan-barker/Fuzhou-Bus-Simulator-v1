## 车辆参数资源（数据驱动，Phase 2 增加车型只需新增 .tres + 场景）
## 闽通 MT-10：10.5 m 级城市客车（虚构品牌）
class_name BusParams
extends Resource

@export_group("身份")
@export var display_name: String = "闽通 MT-10"

@export_group("车身物理")
@export var mass_kg: float = 12000.0
## 重心高度：侧翻阈值 = g·半轮距/重心高（轮距 2.4 m、重心 0.75 m 时约 15.7 m/s²）
@export var center_of_mass: Vector3 = Vector3(0.0, 0.75, 0.0)

@export_group("动力")
## 每个驱动轮的峰值 engine_force（2 驱动轮合计 32 kN，0-60 km/h 约 7 s）
@export var max_engine_force: float = 35000.0
## 每个车轮的制动强度（AC3 调参项）
@export var max_brake_force: float = 250.0
## 松油门时的滚动阻力（模拟客车阻力，防止无限滑行）
@export var rolling_brake: float = 100.0
@export var reverse_force_ratio: float = 0.35
@export var top_speed_kmh: float = 110.0
@export var reverse_top_kmh: float = 20.0

@export_group("转向")
## 停车/低速时的最大前轮转角（泊车需要大角度）
@export var max_steer_deg: float = 38.0
## 侧向加速度预算（m/s²）：随速限角的物理依据——任何车速下满舵侧向
## 加速度 v²·tan(δ)/L 不超过该值。须低于侧翻阈值 g·(半轮距/重心高)≈15（轮距 2.4 m + 重心 0.75 m）
@export var steer_lat_accel_budget: float = 10.0
## 高速端转角下限（deg），防止公式在极速给出过小转角
@export var steer_floor_deg: float = 6.0
## 轴距（m）：转向角 → 侧向加速度换算用
@export var wheelbase_m: float = 6.1
## 打轮/回正速率（deg/s）：打满 38° 约 0.4 s；回正更快
@export var steer_attack_deg_per_s: float = 120.0
@export var steer_release_deg_per_s: float = 160.0

@export_group("踏板渐变")
## 油门/刹车踏板踩下与释放速率（1/s）：键盘阶跃输入转换为渐进踏板行程，
## 轻点 ≈ 短促小幅制动，符合真实客车气刹响应
@export var pedal_attack_rate: float = 1.5
@export var pedal_release_rate: float = 6.0

@export_group("倒挡")
## 车速高于此值时禁止挂入/保持 R 挡（误操作保护，自动弹回 N）
@export var reverse_lock_speed_kmh: float = 8.0

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


## 当前车速下允许的最大前轮转角（deg）：
## 由侧向加速度预算反推 δ = atan(a·L/v²)，低速夹紧到 max_steer_deg
func get_max_steer_deg(speed_kmh: float) -> float:
	var v: float = speed_kmh / 3.6
	if v < 1.5:
		return max_steer_deg
	var delta_rad: float = atan(steer_lat_accel_budget * wheelbase_m / (v * v))
	return clampf(rad_to_deg(delta_rad), steer_floor_deg, max_steer_deg)
