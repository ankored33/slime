class_name GameSettings
extends RefCounted

## 音声以外の表示設定（今のところエフェクトの不透明度のみ）。
## GameAudio の音量設定と同じ仕組みだが、音声を扱わない GameAudio とは
## 別ファイル・別クラスに分けている。user://fx_settings.json に永続化。

const SETTINGS_PATH := "user://fx_settings.json"

static var _fx_opacity := 1.0
static var _loaded := false

static func get_fx_opacity() -> float:
	_ensure_loaded()
	return _fx_opacity

static func set_fx_opacity(value: float) -> void:
	_ensure_loaded()
	_fx_opacity = clampf(value, 0.0, 1.0)
	_save()

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary and data.has("fx_opacity"):
		_fx_opacity = clampf(float(data["fx_opacity"]), 0.0, 1.0)

static func _save() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("エフェクト設定を保存できませんでした: %s" % SETTINGS_PATH)
		return
	file.store_string(JSON.stringify({"fx_opacity": _fx_opacity}))
