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


## 由 BusController 每物理帧调用（空挡自动回 D 等安全逻辑）
func update(throttle: float, speed_kmh: float) -> void:
	if mode == "N" and throttle > 0.1:
		set_mode("D")


func get_display_text() -> String:
	match mode:
		"D":
			return "D 前进"
		"R":
			return "R 倒挡"
		_:
			return "N 空挡"
