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

## 舌を口に重ねて右クリックを押し続けている間だけ true。
var kiss_active := false

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

## 戻り値: このフレームで着弾したろうが与えた快感量の合計（ツール貢献表示用）。
func update_wax_drops(delta: float, slime_state: Dictionary, level: int) -> float:
	var polish_added := 0.0
	for index in range(_wax_drops.size() - 1, -1, -1):
		var drop := _wax_drops[index]
		var previous := drop.advance(delta)
		var hit := false
		for slime in _slimes:
			if _segment_distance_to_point(previous, drop.position, slime.position) \
					<= drop.radius + slime.get_hit_radius():
				polish_added += _apply_wax_impact(slime_state, String(slime.side), level)
				hit = true
				break
		if hit or drop.is_expired(_playfield.size.y):
			_wax_drops.remove_at(index)
			drop.queue_free()
	return polish_added

func apply_teeth_bite(slime_state: Dictionary, level: int, blocked: bool = false) -> void:
	if blocked:
		return
	var teeth: Brush = _brushes.held_brush
	if teeth == null or teeth.brush_id != "teeth":
		return
	for slime in _slimes:
		# 衝突補正後は円同士がちょうど接するため、丸め誤差ぶんだけ許容する。
		if teeth.position.distance_to(slime.position) \
				> teeth.get_contact_radius() + slime.get_hit_radius() + 1.0:
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
				> finger.get_contact_radius() + slime.get_hit_radius() + 1.0:
			continue
		pinch_brush = finger
		pinch_slime = slime
		_pinch_grab_offset = slime.position - finger.position
		finger.set_pinching(true)
		return

func end_pinch() -> void:
	if pinch_brush != null:
		pinch_brush.set_pinching(false)
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

## 右クリックを押している間だけ有効化を試みる。口に触れていなければ何もしない。
func start_kiss(mouth_position: Vector2, mouth_radius: float, blocked: bool = false) -> void:
	if blocked:
		return
	if _tongue_touches_mouth(mouth_position, mouth_radius):
		kiss_active = true

func end_kiss() -> void:
	kiss_active = false

## 右クリック中、舌が口に触れ続けている間だけ継続的に快感を与え痛みを癒す。
## 離れる・保持ブラシが変わる・FINISH/失敗演出に入るのいずれかで自動的に終わる。
## 戻り値: このフレームで与えた快感量の合計（ツール貢献表示用）。
func update_kiss(
		mouth_position: Vector2, mouth_radius: float,
		slime_state: Dictionary, level: int, delta: float, blocked: bool = false) -> float:
	if not kiss_active:
		return 0.0
	if blocked or not _tongue_touches_mouth(mouth_position, mouth_radius):
		end_kiss()
		return 0.0
	var polish_added := 0.0
	for side in ["left", "right"]:
		var state: Dictionary = slime_state[side]
		var polish_gain := GameRules.KISS_POLISH_PER_SEC * 0.5 * GameRules.polish_bonus(level) * delta
		state["polish"] = maxf(0.0, float(state["polish"]) + polish_gain)
		polish_added += polish_gain
		state["pain"] = clampf(float(state["pain"])
			- GameRules.KISS_SOOTHE_PER_SEC * 0.5 * delta, 0.0, GameRules.PAIN_CAP)
		slime_state[side] = state
	return polish_added

func _tongue_touches_mouth(mouth_position: Vector2, mouth_radius: float) -> bool:
	var tongue: Brush = _brushes.held_brush
	if tongue == null or tongue.brush_id != "tongue" or not tongue.visible:
		return false
	return tongue.position.distance_to(mouth_position) \
		<= tongue.get_contact_radius() + mouth_radius + 1.0

func clear() -> void:
	end_pinch()
	end_kiss()
	for drop in _wax_drops:
		if is_instance_valid(drop):
			drop.queue_free()
	_wax_drops.clear()

func _apply_wax_impact(slime_state: Dictionary, side: String, level: int) -> float:
	var state: Dictionary = slime_state[side]
	var polish_gain := GameRules.WAX_POLISH_IMPACT * GameRules.polish_bonus(level)
	# 通常ブラシと同様、内部快感値には上限を設けない。高感度帯では一滴で
	# FINISH数回分を蓄積し、次の判定でまとめて連鎖計上できるようにする。
	state["polish"] = maxf(0.0, float(state["polish"]) + polish_gain)
	state["pain"] = clampf(
		float(state["pain"]) + GameRules.WAX_PAIN_IMPACT * GameRules.pain_resist(level),
		0.0, GameRules.PAIN_CAP
	)
	slime_state[side] = state
	return polish_gain

func _segment_distance_to_point(start: Vector2, end: Vector2, point: Vector2) -> float:
	var segment := end - start
	if segment.length_squared() <= 0.0001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * t)
