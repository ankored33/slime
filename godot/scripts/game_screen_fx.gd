class_name GameScreenFx
extends RefCounted

const GameAudio = preload("res://scripts/game_audio.gd")

signal fail_finished

const EXHAUST_DURATION := 4.0
const FINISH_FLASH_COLOR := Color(1.0, 0.88, 0.93)
const FAIL_FLASH_COLOR := Color(0.35, 0.02, 0.06)

var _host: Node
var _playfield: Control
var _flash_rect: ColorRect
var _finish_label: Label
var _slimes: Array[SlimeTarget] = []
var _finish_duration := 5.0
var _fail_duration := 2.5
var _finish_time_left := 0.0
var _fail_time_left := 0.0
var _exhaust_time_left := 0.0

var finish_active: bool:
	get:
		return _finish_time_left > 0.0

var fail_active: bool:
	get:
		return _fail_time_left > 0.0

var exhausted: bool:
	get:
		return _exhaust_time_left > 0.0

func setup(
		host: Node,
		playfield: Control,
		flash_rect: ColorRect,
		finish_label: Label,
		slimes: Array[SlimeTarget],
		finish_duration: float,
		fail_duration: float
) -> void:
	_host = host
	_playfield = playfield
	_flash_rect = flash_rect
	_finish_label = finish_label
	_slimes = slimes
	_finish_duration = finish_duration
	_fail_duration = fail_duration

func reset() -> void:
	_finish_time_left = 0.0
	_fail_time_left = 0.0
	_exhaust_time_left = 0.0
	_finish_label.visible = false
	_finish_label.scale = Vector2.ONE
	_clear_overlay()

func start_finish() -> void:
	_finish_time_left = _finish_duration
	_finish_label.visible = true
	_finish_label.pivot_offset = _finish_label.size / 2.0
	_finish_label.scale = Vector2(0.4, 0.4)
	var tween := _host.create_tween()
	tween.tween_property(_finish_label, "scale", Vector2(1.3, 1.3), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_finish_label, "scale", Vector2.ONE, 0.3)
	for slime in _slimes:
		slime.burst_hearts()
	GameAudio.play_se("climax")

func start_fail() -> void:
	_fail_time_left = _fail_duration
	GameAudio.play_se("despair")

func update(delta: float) -> void:
	_update_finish(delta)
	_update_fail(delta)
	_exhaust_time_left = maxf(0.0, _exhaust_time_left - delta)

func _update_finish(delta: float) -> void:
	if _finish_time_left <= 0.0:
		return
	_finish_time_left = maxf(0.0, _finish_time_left - delta)
	var elapsed := _finish_duration - _finish_time_left
	var flash := FINISH_FLASH_COLOR
	flash.a = _finish_flash_alpha(elapsed)
	_flash_rect.color = flash
	_apply_shake(maxf(0.0, 1.0 - elapsed / 1.2) * 16.0)
	if _finish_time_left == 0.0:
		_finish_label.visible = false
		_clear_overlay()
		_exhaust_time_left = EXHAUST_DURATION

func _update_fail(delta: float) -> void:
	if _fail_time_left <= 0.0:
		return
	_fail_time_left = maxf(0.0, _fail_time_left - delta)
	var elapsed := _fail_duration - _fail_time_left
	var flash := FAIL_FLASH_COLOR
	flash.a = minf(elapsed / 0.4, 1.0) * 0.5
	_flash_rect.color = flash
	_apply_shake(maxf(0.0, 1.0 - elapsed / 0.8) * 10.0)
	if _fail_time_left == 0.0:
		_apply_shake(0.0)
		fail_finished.emit()

func _finish_flash_alpha(elapsed: float) -> float:
	if elapsed < 0.2:
		return lerpf(0.0, 0.9, elapsed / 0.2)
	if elapsed < 1.6:
		return lerpf(0.9, 0.16, (elapsed - 0.2) / 1.4)
	var tail := maxf(_finish_duration - 1.6, 0.001)
	return lerpf(0.16, 0.0, clampf((elapsed - 1.6) / tail, 0.0, 1.0))

func _apply_shake(amplitude: float) -> void:
	if amplitude <= 0.05:
		_playfield.position = Vector2.ZERO
		return
	_playfield.position = Vector2(
		randf_range(-amplitude, amplitude),
		randf_range(-amplitude, amplitude)
	)

func _clear_overlay() -> void:
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_playfield.position = Vector2.ZERO
