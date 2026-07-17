class_name GameScreenToolActions
extends RefCounted

const WaxDropScript = preload("res://scripts/wax_drop.gd")

var _playfield: Control
var _brushes
var _slimes: Array[SlimeTarget] = []
var _wax_drops: Array[WaxDrop] = []

var pinch_brush: Brush
var pinch_slime: SlimeTarget
var _pinch_grab_offset := Vector2.ZERO

var wax_drop_count: int:
	get:
		return _wax_drops.size()

func setup(playfield: Control, brushes, slimes: Array[SlimeTarget]) -> void:
	_playfield = playfield
	_brushes = brushes
	_slimes = slimes

func spawn_wax_drop(origin: Vector2, blocked: bool = false) -> void:
	if blocked:
		return
	var drop: WaxDrop = WaxDropScript.new()
	drop.position = origin
	_playfield.add_child(drop)
	_wax_drops.append(drop)

func update_wax_drops(delta: float, slime_state: Dictionary, level: int) -> void:
	for index in range(_wax_drops.size() - 1, -1, -1):
		var drop := _wax_drops[index]
		var previous := drop.advance(delta)
		var hit := false
		for slime in _slimes:
			if _segment_distance_to_point(previous, drop.position, slime.position) \
					<= drop.radius + slime.get_hit_radius():
				_apply_wax_impact(slime_state, String(slime.side), level)
				hit = true
				break
		if hit or drop.is_expired(_playfield.size.y):
			_wax_drops.remove_at(index)
			drop.queue_free()

func apply_teeth_bite(slime_state: Dictionary, level: int, blocked: bool = false) -> void:
	if blocked:
		return
	var teeth: Brush = _brushes.held_brush
	if teeth == null or teeth.brush_id != "teeth":
		return
	for slime in _slimes:
		# 衝突補正後は円同士がちょうど接するため、丸め誤差ぶんだけ許容する。
		if teeth.position.distance_to(slime.position) \
				> teeth.hit_radius + slime.get_hit_radius() + 1.0:
			continue
		var side := String(slime.side)
		var state: Dictionary = slime_state[side]
		state["pain"] = clampf(
			float(state["pain"]) + GameRules.BITE_PAIN_IMPACT * GameRules.pain_resist(level),
			0.0, GameRules.PAIN_CAP
		)
		slime_state[side] = state

## 右クリック押下で接触中の本体を挟み、解放までマウスで引っ張る。
func start_pinch(blocked: bool = false) -> void:
	if blocked:
		return
	var finger: Brush = _brushes.held_brush
	if finger == null or finger.brush_id != "finger":
		return
	for slime in _slimes:
		if finger.position.distance_to(slime.position) \
				> finger.hit_radius + slime.get_hit_radius() + 1.0:
			continue
		pinch_brush = finger
		pinch_slime = slime
		_pinch_grab_offset = slime.position - finger.position
		return

func end_pinch() -> void:
	pinch_brush = null
	pinch_slime = null

func update_pinch(global_mouse_position: Vector2, delta: float, blocked: bool = false) -> void:
	if pinch_slime == null:
		return
	if _brushes.held_brush != pinch_brush or not pinch_brush.visible or blocked:
		end_pinch()
		return
	var mouse_local: Vector2 = _playfield.get_global_transform().affine_inverse() \
			* global_mouse_position
	pinch_slime.apply_pull(mouse_local + _pinch_grab_offset, delta)
	# 指は挟んだ位置関係のまま本体に張り付く。
	pinch_brush.position = pinch_slime.position - _pinch_grab_offset

func clear() -> void:
	end_pinch()
	for drop in _wax_drops:
		if is_instance_valid(drop):
			drop.queue_free()
	_wax_drops.clear()

func _apply_wax_impact(slime_state: Dictionary, side: String, level: int) -> void:
	var state: Dictionary = slime_state[side]
	state["polish"] = clampf(
		float(state["polish"]) + GameRules.WAX_POLISH_IMPACT * GameRules.polish_bonus(level),
		0.0, GameRules.GAUGE_MAX
	)
	state["pain"] = clampf(
		float(state["pain"]) + GameRules.WAX_PAIN_IMPACT * GameRules.pain_resist(level),
		0.0, GameRules.PAIN_CAP
	)
	slime_state[side] = state

func _segment_distance_to_point(start: Vector2, end: Vector2, point: Vector2) -> float:
	var segment := end - start
	if segment.length_squared() <= 0.0001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * t)
