## 客车喇叭：程序化合成双音气喇叭（350+440 Hz 双频叠加 + 6 Hz 颤音 + 快起音）
## 音频数据为运行时合成的 16-bit PCM，无任何外部素材（合规：ASSET_LICENSES.md 登记 0 外部素材）
## H 键按住持续鸣笛，松开即停。
class_name Horn
extends Node

var player: AudioStreamPlayer

const SAMPLE_RATE := 44100
const LOOP_SECONDS := 1.2
## 主音 + 泛音（模拟气喇叭金属感）
const TONE_A_HZ := 350.0
const TONE_B_HZ := 440.0


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.bus = "Master"
	player.volume_db = -4.0
	player.stream = _build_stream()
	add_child(player)


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("horn"):
		player.play()
	elif Input.is_action_just_released("horn"):
		player.stop()


## 外部触发（自动驾驶演示/测试用）
func press() -> void:
	player.play()


func release() -> void:
	player.stop()


func is_playing() -> bool:
	return player.playing


func _build_stream() -> AudioStreamWAV:
	var n: int = int(SAMPLE_RATE * LOOP_SECONDS)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		# 25 ms 起音包络（避免爆音），稳态后轻微颤音
		var env: float = minf(t / 0.025, 1.0)
		var trem: float = 0.85 + 0.15 * sin(TAU * 6.0 * t)
		var v: float = 0.45 * sin(TAU * TONE_A_HZ * t) \
				+ 0.38 * sin(TAU * TONE_B_HZ * t) \
				+ 0.12 * sin(TAU * 2.0 * TONE_A_HZ * t)
		var s16: int = int(clampf(v * env * trem, -1.0, 1.0) * 26000.0)
		data[i * 2] = s16 & 0xFF
		data[i * 2 + 1] = (s16 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	# 循环区间（样本帧）：按住 H 时无缝持续
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = int(0.05 * SAMPLE_RATE)  # 跳过起音段，循环稳态
	wav.loop_end = n
	return wav
