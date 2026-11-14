## 车内语音播报：使用系统 TTS（Windows SAPI，运行时系统功能，非外部素材）。
## GUI 模式真实发声（优先选择中文语音）；headless 无 TTS 时仅记录日志——
## 日志同时作为自动化测试的断言依据（不得以日志代替真实发声判定）。
class_name VoiceAnnouncer
extends Node

## 播报历史（供测试断言）
var log: Array[String] = []

var _voice_id: String = ""
var _tts_ok: bool = false


func _ready() -> void:
	_tts_ok = DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH)
	if _tts_ok:
		for v in DisplayServer.tts_get_voices():
			var lang := String(v.get("language", ""))
			var name := String(v.get("name", ""))
			if "zh" in lang.to_lower() or "zh" in name.to_lower() or "chinese" in name.to_lower():
				_voice_id = String(v.get("id", ""))
				break


func speak(text: String) -> void:
	log.append(text)
	if _tts_ok:
		DisplayServer.tts_speak(text, _voice_id)
	print("VOICE_ANNOUNCE tts=%s text=%s" % [str(_tts_ok), text])


func has_announced_containing(keyword: String) -> bool:
	for t in log:
		if keyword in t:
			return true
	return false
