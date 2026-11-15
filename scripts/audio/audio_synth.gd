## V0.3 音效合成器：全部车辆音效为运行时合成的 16-bit PCM（AudioStreamWAV）
## 合规说明（ASSET_LICENSES.md 登记）：零外部音频文件，非真实客车录音。
## 设计目标：为「动态变调」而合成——发动机谐波与点火周期锁相、
## 循环长度取整周期 + 端部交叉淡化，保证 pitch_scale 拉伸/压缩时无缝循环。
## 后续替换为真实客车录音：把对应 make_*() 返回值换成 .wav/.ogg 循环流即可，
## VehicleAudio 的调用接口（循环/一次性、音量/音调控制）不变。
class_name AudioSynth
extends Object

const SAMPLE_RATE := 44100


## ---- 通用工具 ----

static func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var n: int = samples.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var s16: int = int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		data[i * 2] = s16 & 0xFF
		data[i * 2 + 1] = (s16 >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = n
	return wav


## 循环接缝处理：把结尾淡入开头（谐波部分本就整周期循环，主要为平滑噪声分量）
static func _crossfade_tail(out: PackedFloat32Array, fade_samples: int) -> void:
	var n: int = out.size()
	var f: int = mini(fade_samples, n / 4)
	if f < 2:
		return
	for i in f:
		var w: float = float(i) / float(f)
		out[n - f + i] = lerpf(out[n - f + i], out[i], w)


static func _white_noise(n: int, seed_val: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var noise := PackedFloat32Array()
	noise.resize(n)
	for i in n:
		noise[i] = rng.randf_range(-1.0, 1.0)
	return noise


## ---- 发动机 ----

## 发动机稳态循环（2.0 s，参考怠速 720 rpm）：
## 六缸四冲程点火频率 = 720/60×3 = 36 Hz；谐波堆栈与点火周期锁相，
## 叠加每点火周期的燃烧粗糙度（指数衰减噪声）与半阶"突突"摆动。
## 运行时 pitch_scale = rpm / 720，实现转速驱动的连续变调。
static func make_engine_loop() -> AudioStreamWAV:
	const DUR := 2.0
	const F0 := 36.0
	var n: int = int(DUR * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var noise := _white_noise(n, 20261115)
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var ph: float = fmod(F0 * t, 1.0)
		var v: float = 0.0
		for k in 14:
			var h: float = float(k + 1)
			v += pow(1.0 / h, 1.25) * sin(TAU * h * ph)
		var burst: float = exp(-5.0 * ph)
		v += 0.32 * burst * noise[i]
		v += 0.22 * sin(TAU * 0.5 * F0 * t)
		v *= 0.9 + 0.1 * sin(TAU * 0.25 * t)
		out[i] = v * 0.22
	_crossfade_tail(out, int(0.04 * SAMPLE_RATE))
	return _to_wav(out, true)


## 起动曲轴（1.15 s 一次性）：起动机啸叫（130→165 Hz 扫频）+
## 转速递增（7→11 循环/s）的低频"扑通扑通"压缩脉冲
static func make_crank() -> AudioStreamWAV:
	var n: int = int(1.15 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var noise := _white_noise(n, 20261116)
	var ph := 0.0
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var progress: float = float(i) / float(n)
		var rate: float = lerpf(7.0, 11.0, progress)
		ph = fmod(ph + rate / SAMPLE_RATE, 1.0)
		var burst: float = exp(-7.0 * ph)
		var v: float = 0.55 * burst * noise[i] + 0.35 * burst * sin(TAU * 55.0 * ph)
		v += 0.10 * sin(TAU * lerpf(130.0, 165.0, progress) * t)
		out[i] = v * 0.5
	return _to_wav(out, false)


## ---- 行驶音效 ----

## 轮胎/路面摩擦循环（2.0 s）：单极低通白噪声（约 300 Hz 截止的隆隆滚动声），
## 运行时音量随车速拉起、音调随车速微调
static func make_road_loop() -> AudioStreamWAV:
	var n: int = int(2.0 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var noise := _white_noise(n, 20261117)
	var y := 0.0
	for i in n:
		y += 0.045 * (noise[i] - y)
		out[i] = y * 2.4
	_crossfade_tail(out, int(0.05 * SAMPLE_RATE))
	return _to_wav(out, true)


## 风噪循环（2.0 s）：高通（差分）+ 轻低通平滑的气流声，
## 运行时音量按车速平方关系拉起（高速风噪主导）
static func make_wind_loop() -> AudioStreamWAV:
	var n: int = int(2.0 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var noise := _white_noise(n, 20261118)
	var y := 0.0
	var prev := 0.0
	for i in n:
		var hp: float = noise[i] - prev
		prev = noise[i]
		y += 0.12 * (hp - y)
		out[i] = y * 0.9
	_crossfade_tail(out, int(0.05 * SAMPLE_RATE))
	return _to_wav(out, true)


## ---- 制动 ----

## 气刹放气（0.55 s 一次性）：带通噪声（高通差分 + 低通平滑 ≈ 1–3 kHz），
## 8 ms 起音 + 指数衰减，模拟踏板行程对应的储气筒排气
static func make_air_hiss() -> AudioStreamWAV:
	var n: int = int(0.55 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var noise := _white_noise(n, 20261119)
	var y := 0.0
	var prev := 0.0
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var attack: float = minf(t / 0.008, 1.0)
		var env: float = attack * exp(-5.5 * t)
		var hp: float = noise[i] - prev
		prev = noise[i]
		y += 0.25 * (hp - y)
		out[i] = y * env * 1.7
	return _to_wav(out, false)


## 驻车弹簧制动（0.4 s 一次性）：62 Hz 低频闷响 + 0.12 s 后的短促排气尾音，
## 在长时间行车制动后停稳时播放一次
static func make_parking_brake() -> AudioStreamWAV:
	var n: int = int(0.4 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var noise := _white_noise(n, 20261120)
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var v: float = 0.6 * sin(TAU * 62.0 * t) * exp(-14.0 * t)
		if t > 0.12:
			v += 0.35 * noise[i] * exp(-22.0 * (t - 0.12))
		out[i] = v
	return _to_wav(out, false)


## ---- 转向灯继电器 ----

## 继电器咔嗒（45 ms 一次性）：基频正弦 + 少量噪声，快速指数衰减。
## 左/右方向用不同基频（A=1700 Hz / B=1300 Hz），交替形成"嗒-嗒"节拍
static func make_click(hz: float) -> AudioStreamWAV:
	var n: int = int(0.045 * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var noise := _white_noise(n, 20261121)
	for i in n:
		var t: float = float(i) / SAMPLE_RATE
		var env: float = exp(-110.0 * t)
		var v: float = (sin(TAU * hz * t) + 0.25 * noise[i]) * env * 0.7
		out[i] = v
	return _to_wav(out, false)
