## 自动挡变速箱（v0.1.0 仅 D / N / R，手动挡留至 v0.2.0）
## R 键在 D/R 间切换；N 键切入空挡；空挡下踩油门自动回 D。
class_name Gearbox
extends Node

signal mode_changed(new_mode: String)

## 当前挡位："D" / "N" / "R"
var mode: String = "D"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("gear_r"):
		set_mode("R" if mode != "R" else "D")
	elif event.is_action_pressed("gear_n"):
		set_mode("N")


func set_mode(new_mode: String) -> void:
	if new_mode == mode:
		return
	mode = new_mode
	mode_changed.emit(mode)


## 由 BusController 每物理帧调用（空挡自动回 D、前冲误挂 R 保护）
## speed_kmh 为带符号前向速度：正=向前，负=倒车
func update(throttle: float, signed_speed_kmh: float) -> void:
	if mode == "N" and throttle > 0.1:
		set_mode("D")
	# 仅当客车仍在"向前"高速滑行时禁止保持 R 挡（误操作保护）
	# 纯倒车为负速度，不触发——R 挡可持续倒车直到用户主动切回 D
	if mode == "R" and signed_speed_kmh > _reverse_lock_kmh:
		set_mode("N")


## 锁挡阈值由宿主控制器注入（默认 8 km/h）
var _reverse_lock_kmh: float = 8.0


func set_reverse_lock_kmh(kmh: float) -> void:
	_reverse_lock_kmh = maxf(kmh, 0.0)


func get_display_text() -> String:
	match mode:
		"D":
			return "D 前进"
		"R":
			return "R 倒挡"
		_:
			return "N 空挡"
