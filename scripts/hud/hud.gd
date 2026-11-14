## HUD：速度 / 挡位 / 里程 / 任务提示（AC6：显示速度与物理速度偏差 < 2 km/h）
class_name Hud
extends CanvasLayer

@export var bus: BusController
@export var route: RouteManager
@export var stop_task: StopTask
@export var lights: TrafficLightManager

var _displayed_speed_kmh: float = 0.0

@onready var speed_label: Label = $SpeedLabel
@onready var gear_label: Label = $GearLabel
@onready var mileage_label: Label = $MileageLabel
@onready var task_label: Label = $TaskLabel
@onready var hint_label: Label = $HintLabel
@onready var reverse_label: Label = $ReverseLabel
@onready var handbrake_label: Label = $HandbrakeLabel
@onready var signal_label: Label = $SignalLabel

const HINT := "W/S 油门·刹车   A/D 转向   C/Q 视角   R 倒挡   N 空挡   H 喇叭   空格 手刹（紧急停车）"
const GEAR_COLOR_REVERSE := Color(1.0, 0.28, 0.28, 1.0)


func _ready() -> void:
	hint_label.text = HINT
	mileage_label.text = "里程 0.00 km"
	speed_label.text = "0 km/h"
	gear_label.text = "D 前进"
	reverse_label.visible = false


func _process(_delta: float) -> void:
	if bus == null:
		return
	_displayed_speed_kmh = bus.get_speed_kmh()
	speed_label.text = "%d km/h" % roundi(_displayed_speed_kmh)
	gear_label.text = bus.get_gear_text()
	if route != null:
		mileage_label.text = "里程 %.2f km" % route.get_mileage_km()
	if stop_task != null:
		task_label.text = stop_task.get_status_text()
	# 倒挡强提示：挡位变红 + 顶部横幅（含倒车雷达距离）
	if bus.gearbox != null and bus.gearbox.mode == "R":
		gear_label.add_theme_color_override("font_color", GEAR_COLOR_REVERSE)
		speed_label.add_theme_color_override("font_color", GEAR_COLOR_REVERSE)
		var d: float = bus.get_reverse_obstacle_distance_m()
		reverse_label.text = "倒车中 — 后方 %s" % ("畅通（12 m 内无障碍）" if d < 0.0 else "%.1f m" % d)
		reverse_label.visible = true
	else:
		gear_label.remove_theme_color_override("font_color")
		speed_label.remove_theme_color_override("font_color")
		reverse_label.visible = false
	# 手刹紧急停车：右上角红色感叹号
	handbrake_label.visible = bus.is_handbraking()
	# 红绿灯警示横幅（红灯/黄灯接近时）
	if lights != null and lights.warning_active:
		signal_label.text = lights.warning_text
		signal_label.visible = true
	else:
		signal_label.visible = false


## 供 AC6 自动化测试读取（与画面显示同源）
func get_displayed_speed_kmh() -> float:
	return _displayed_speed_kmh
