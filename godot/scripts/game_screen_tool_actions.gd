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

## クリップが手を離され、乳首を引っ張って垂れ下がったまま静止している間 true。
## （再び持ち上げれば通常のドラッグに戻る。end_pinch されるまでは挟んだまま。）
var clip_falling := false
var _clip_hang_anchor := Vector2.ZERO
## 手を離した直後の1フレームだけ立てる。ゲージ操作は apply_clip_effects 側に分離しているため、
## どちら側に痛みスパイクを与えるかをここで一時的に受け渡す。
var _clip_just_released := false
var _clip_release_side := ""

## 口づけ切り替えがONの間 true。
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

## 右クリックで挟む/離すを切り替える（指・クリップ共通）。指は離すとその場で
## end_pinch（バネで元へ戻る）、クリップは離すと _begin_clip_fall（垂れ下がって静止）になる。
func toggle_pinch(blocked: bool = false) -> void:
	if pinch_brush != null:
		if pinch_brush.brush_id == "clip":
			_begin_clip_fall()
		else:
			end_pinch()
	else:
		start_pinch(blocked)

## 接触中の本体を挟み、切り替え解除までマウスで引っ張る。指・クリップ共通の機構で、
## どちらが呼ぶかは呼び出し側（handle_input の分岐）がすでに保持中の道具で判定済み。
func start_pinch(blocked: bool = false) -> void:
	if blocked or pinch_brush != null:
		return
	var tool: Brush = _brushes.held_brush
	if tool == null:
		return
	for slime in _slimes:
		if tool.position.distance_to(slime.position) \
				> tool.get_contact_radius() + slime.get_hit_radius() + 1.0:
			continue
		pinch_brush = tool
		pinch_slime = slime
		_pinch_grab_offset = slime.position - tool.position
		tool.set_pinching(true)
		return

func end_pinch() -> void:
	if pinch_brush != null:
		pinch_brush.set_pinching(false)
	pinch_brush = null
	pinch_slime = null
	clip_falling = false

## 位置・追従の物理だけを扱う（ゲージ操作は apply_clip_effects 側に分離）。
## クリップが _begin_clip_fall で垂れ下がり状態に入った後は、道具の持ち替え状態に
## 関わらずそちらを優先する（手を離した後もそのまま静止し続けるのが狙いのため）。
func update_pinch(global_mouse_position: Vector2, delta: float, blocked: bool = false) -> void:
	if pinch_slime == null:
		return
	if clip_falling:
		_update_clip_fall(delta)
		return
	if _brushes.held_brush != pinch_brush or not pinch_brush.visible or blocked:
		end_pinch()
		return
	var mouse_local: Vector2 = _playfield.get_global_transform().affine_inverse() \
			* global_mouse_position
	pinch_slime.apply_pull(mouse_local + _pinch_grab_offset, delta)
	# 指・クリップは挟んだ位置関係のまま本体に張り付く。
	pinch_brush.position = pinch_slime.position - _pinch_grab_offset

func _begin_clip_fall() -> void:
	clip_falling = true
	_clip_hang_anchor = pinch_slime.position + Vector2.DOWN * GameRules.CLIP_HANG_DROP
	_clip_just_released = true
	_clip_release_side = String(pinch_slime.side)

## 手を離した後、乳首をつまみと同じ apply_pull で下方向へ引っ張り続ける。目標が
## SlimeTarget の最大変位を大きく超えているため、すぐ可動域いっぱいに頭打ちして
## そのまま静止する（新しい判定を足さず、既存のクランプだけで実現している）。
func _update_clip_fall(delta: float) -> void:
	pinch_slime.apply_pull(_clip_hang_anchor + _pinch_grab_offset, delta)
	pinch_brush.position = pinch_slime.position - _pinch_grab_offset

## クリップの痛み演出。挟んでいる間（ドラッグ中・垂れ下がり中とも）は継続的に軽い痛みを、
## 手を離した瞬間はスパイクを与える。update_pinch とは別に、ゲージへ触れる処理だけを分離してある。
func apply_clip_effects(slime_state: Dictionary, level: int, delta: float, blocked: bool = false) -> void:
	if not blocked and pinch_brush != null and pinch_brush.brush_id == "clip":
		var side := String(pinch_slime.side)
		var state: Dictionary = slime_state[side]
		state["pain"] = clampf(
			float(state["pain"]) + GameRules.CLIP_CLAMP_PAIN_PER_SEC * GameRules.pain_resist(level) * delta,
			0.0, GameRules.PAIN_CAP
		)
		slime_state[side] = state
	if _clip_just_released:
		_clip_just_released = false
		var state: Dictionary = slime_state[_clip_release_side]
		state["pain"] = clampf(
			float(state["pain"]) + GameRules.CLIP_RELEASE_PAIN_IMPACT * GameRules.pain_resist(level),
			0.0, GameRules.PAIN_CAP
		)
		slime_state[_clip_release_side] = state

## 右クリックで口づけの開始/終了を切り替える。開始には口への接触が必要。
func toggle_kiss(mouth_position: Vector2, mouth_radius: float, blocked: bool = false) -> void:
	if kiss_active:
		end_kiss()
	else:
		start_kiss(mouth_position, mouth_radius, blocked)

## 口づけ開始を試みる。口に触れていなければ何もしない。
func start_kiss(mouth_position: Vector2, mouth_radius: float, blocked: bool = false) -> void:
	if blocked:
		return
	if _tongue_touches_mouth(mouth_position, mouth_radius):
		kiss_active = true

func end_kiss() -> void:
	kiss_active = false

## 口づけ切り替えON中、舌が口に触れている間は継続的に快感を与え痛みを癒す
## （動力型ブラシと同様の常時刺激）。口から離れている間は一時停止し、モードは維持。
## 舌を手放す・FINISH/失敗演出に入る（clear）で終わる。
## 戻り値: このフレームで与えた快感量の合計（ツール貢献表示用）。
func update_kiss(
		mouth_position: Vector2, mouth_radius: float,
		slime_state: Dictionary, level: int, delta: float, blocked: bool = false) -> float:
	if not kiss_active:
		return 0.0
	var tongue: Brush = _brushes.held_brush
	if tongue == null or tongue.brush_id != "tongue" or not tongue.visible:
		end_kiss()
		return 0.0
	if blocked or not _tongue_touches_mouth(mouth_position, mouth_radius):
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
	_clip_just_released = false
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
