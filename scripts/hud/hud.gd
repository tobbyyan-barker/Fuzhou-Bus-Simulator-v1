## HUD：速度 / 挡位 / 里程 / 任务提示（AC6：显示速度与物理速度偏差 < 2 km/h）
class_name Hud
extends CanvasLayer

@export var bus: BusController
@export var route: RouteManager
@export var stop_task: StopTask

var _displayed_speed_kmh: float = 0.0

@onready var speed_label: Label = $SpeedLabel
@onready var gear_label: Label = $GearLabel
@onready var mileage_label: Label = $MileageLabel
@onready var task_label: Label = $TaskLabel
@onready var hint_label: Label = $HintLabel

const HINT := "W/S 油门·刹车   A/D 转向   C 切换视角   R 切倒挡   N 空挡   空格 手刹"


func _ready() -> void:
	hint_label.text = HINT
	mileage_label.text = "里程 0.00 km"
	speed_label.text = "0 km/h"
	gear_label.text = "D 前进"


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


## 供 AC6 自动化测试读取（与画面显示同源）
func get_displayed_speed_kmh() -> float:
	return _displayed_speed_kmh
