## 转向灯（V0.3 最小实现：节拍音 + HUD 指示，不涉及灯光渲染系统）
## 逗号/句号（, / .）切换左/右转向灯，重复按同侧 = 关闭。
## 激活时按继电器节拍（约 86 次/分）交替播放两种咔嗒声并驱动 HUD 箭头闪烁。
## 手动取消（不做事后自动回位——真实客车的方向盘回位取消属后续功能）。
class_name TurnIndicator
extends Node

enum Dir { NONE, LEFT, RIGHT }

## 节拍周期（s）：on/off 各半，继电器 ≈ 86 次/分
const INTERVAL := 0.7

@export var audio: VehicleAudio
@export var hud: Hud

var direction: int = Dir.NONE

var _timer := 0.0
var _is_a := true
var _blink_on := false


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("signal_left"):
		set_direction(Dir.LEFT if direction != Dir.LEFT else Dir.NONE)
	elif Input.is_action_just_pressed("signal_right"):
		set_direction(Dir.RIGHT if direction != Dir.RIGHT else Dir.NONE)
	if direction != Dir.NONE:
		_timer -= delta
		if _timer <= 0.0:
			_timer = INTERVAL
			_blink_on = not _blink_on
			if _blink_on and audio != null:
				audio.play_click(_is_a)
				_is_a = not _is_a
	_update_hud()


## 外部设置方向（测试/后续自动驾驶用）；NONE 表示关闭
func set_direction(new_dir: int) -> void:
	direction = new_dir
	_timer = 0.0
	_blink_on = false
	_update_hud()


func is_active() -> bool:
	return direction != Dir.NONE


func _update_hud() -> void:
	if hud == null:
		return
	if direction == Dir.NONE or not _blink_on:
		hud.set_turn_indicator(Dir.NONE)
	else:
		hud.set_turn_indicator(direction)
