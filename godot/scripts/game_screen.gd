extends Control

signal day_finished(result: Dictionary)

const ExpressionRules = preload("res://scripts/expression_rules.gd")
const GameAudio = preload("res://scripts/game_audio.gd")
const GameScreenBrushes = preload("res://scripts/game_screen_brushes.gd")
const GameScreenFxScript = preload("res://scripts/game_screen_fx.gd")
const GameScreenToolActionsScript = preload("res://scripts/game_screen_tool_actions.gd")
const DebugPanelScript = preload("res://scripts/debug_panel.gd")

@export var follow_speed := 16.0
@export var finish_fx_duration := 5.0
@export var fail_fx_duration := 2.5

# 痛み上昇の全体係数（快感とのバランス調整用）。
const PAIN_GAIN_SCALE := 0.35

# 前回FINISHからこの秒数以上空いた単発FINISHは5秒のフル演出（儀式期）。
# それ未満で連続する場合は進行を止めない軽量パルスに切り替え、
# 数字の伸びそのものを主役にする（連鎖期）。
const FULL_FINISH_FX_MIN_INTERVAL := 3.0

# FINISHレート表示の集計間隔（この秒数ごとに回数を平均してレート更新）。
const RATE_SAMPLE_WINDOW := 0.5

# この毎秒レートを超えたら、正確な数字を追うのをやめて点滅する専用表示に切り替える
# （高感度帯は表示が実態に追いつかないほど加速するため）。
const FINISH_RATE_DISPLAY_CAP := 1000.0
const FINISH_BLINK_HZ := 4.0

# こすり系ブラシは、接触してからではなく当たり判定付近に入った時点で先端を向ける。
const BRUSH_FACING_RANGE_MARGIN := 48.0

# キャラ画像の上でのホイールズーム倍率。上回転でマウス位置を中心に1段階ズームし、
# 下回転で等倍へ戻る。ツールボックスとHUDはズーム対象外。
const CHARA_ZOOM := 2.0

# ズーム中、WASDで画像をずらす速度（画面px/秒）。等倍時は無効。
const ZOOM_PAN_SPEED := 480.0

# Level-driven; refreshed in setup_species.
var finish_threshold := GameRules.finish_threshold(1)

var _current_expression := ""
var _gauge_map: Dictionary = {}
var _brushes := GameScreenBrushes.new()
var _fx := GameScreenFxScript.new()
var _tool_actions := GameScreenToolActionsScript.new()
var _slimes: Array[SlimeTarget] = []
var _slime_state := {
	"left": {"polish": 0.0, "pain": 0.0},
	"right": {"polish": 0.0, "pain": 0.0}
}
var _species: Dictionary = {}
var _breast_layers: Array[BreastLayer] = []
var _day_finish_count := 0
## brush_id → このフレームで実際にそのツールが与えた快感量。_process の頭で毎回リセットし、
## FINISH判定の瞬間に最大のものを「そのFINISHのツール」として採用する
## （同時に複数効いていても、その瞬間の快感量が最大の1つに単純化する）。
var _polish_this_tick_by_tool: Dictionary = {}
## brush_id → 本日その日にツールへ計上されたFINISH数。日をまたいでは保持しない。
var _finish_count_by_tool: Dictionary = {}
var _day_time := 0.0
var _last_finish_at := -1000.0
var _rate_accum := 0
var _rate_window := 0.0
var _finish_rate := 0.0
var _is_running := false
var _menu_paused := false
var _debug_panel: PanelContainer
var _debug_expression_override := ""

@onready var _playfield: Control = $Playfield
@onready var _zoom_root: Control = $Playfield/ZoomRoot
@onready var _brush_rack: Control = $Playfield/BrushRack
@onready var _title_label: Label = $Hud/CharaNameLabel
@onready var _meta_label: Label = $Hud/LevelLabel
@onready var _dialogue_label: RichTextLabel = $Hud/DialogueLabel
@onready var _day_label: Label = $Hud/DayLabel
@onready var _brush_name_label: Label = $Hud/BrushNameLabel
@onready var _brush_spec_label: Label = $Hud/BrushSpecLabel
@onready var _finish_progress: ProgressBar = $Hud/FinishProgress
@onready var _finish_label: Label = $Hud/FinishLabel
@onready var _day_finish_label: Label = $Hud/DayStats/Margin/FinishCount
@onready var _end_day_button: Button = $Hud/EndDayButton
@onready var _end_day_confirm_dialog: ConfirmationDialog = $EndDayConfirmDialog
@onready var _left_slime: SlimeTarget = $Playfield/ZoomRoot/LeftSlime
@onready var _right_slime: SlimeTarget = $Playfield/ZoomRoot/RightSlime
@onready var _chara_image: TextureRect = $Playfield/ZoomRoot/CharaImage
@onready var _face_image: TextureRect = $Playfield/ZoomRoot/CharaImage/FaceImage
@onready var _expression_label: Label = $Playfield/ZoomRoot/CharaImage/ExpressionLabel
@onready var _flash_rect: ColorRect = $FlashRect

func _ready() -> void:
	_slimes.assign([_left_slime, _right_slime])
	_collect_gauges()
	_end_day_button.pressed.connect(_on_end_day_pressed)
	_end_day_confirm_dialog.confirmed.connect(_on_end_day_confirmed)
	_end_day_confirm_dialog.canceled.connect(_on_end_day_canceled)
	_end_day_confirm_dialog.get_ok_button().text = "終える"
	_end_day_confirm_dialog.get_cancel_button().text = "キャンセル"
	# ブラシ・道具はズーム空間（ZoomRoot ローカル）を作業座標系にする。
	_brushes.setup(self, _zoom_root, _brush_rack, _end_day_button)
	_tool_actions.setup(_zoom_root, _brushes, _slimes)
	_fx.setup(
		self, _playfield, _flash_rect, _finish_label, _slimes,
		finish_fx_duration, fail_fx_duration)
	_fx.fail_finished.connect(_finish_day.bind(true))
	if OS.is_debug_build():
		_debug_panel = DebugPanelScript.new(self)
		_debug_panel.visible = false
		add_child(_debug_panel)
		_brushes.register_interactive(_debug_panel)
	_update_gauges()
	_update_brush_controls()
	# ここで reset_day() は呼ばない: _is_running を立てると setup_species() 前から
	# _process() のゲームループが回り出し、まだ空の _species を読みにいってしまう。
	# setup_species() が末尾で reset_day() を呼ぶので、最初の日はそちらに任せる。

func _input(event: InputEvent) -> void:
	if _debug_panel != null and event is InputEventKey \
			and event.pressed and not event.echo and event.keycode == KEY_F1:
		_debug_panel.visible = not _debug_panel.visible
		return
	if not _is_running or _menu_paused:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_handle_zoom_wheel(event.button_index == MOUSE_BUTTON_WHEEL_UP, event.position)
		return
	var action := _brushes.handle_input(event)
	var blocked := _fx.finish_active or _fx.fail_active
	if action.has("wax_origin"):
		_tool_actions.spawn_wax_drop(action["wax_origin"], blocked)
	elif action.has("bite_requested"):
		_tool_actions.apply_teeth_bite(_slime_state, _current_level(), blocked)
	elif action.has("pinch_requested"):
		_tool_actions.start_pinch(blocked)
	elif action.has("kiss_requested"):
		_tool_actions.start_kiss(_mouth_position(), _mouth_radius(), blocked)
	elif action.has("pinch_released"):
		_tool_actions.end_pinch()
		_tool_actions.end_kiss()

## キャラ画像の上（左右パネルを除く中央部）でのみ反応するホイールズーム。
## 上回転: マウス位置を中心に CHARA_ZOOM 倍（1段階のみ）。下回転: 等倍へ戻す。
func _handle_zoom_wheel(zoom_in: bool, screen_pos: Vector2) -> void:
	if not _chara_image.get_global_rect().has_point(screen_pos):
		return
	if zoom_in == (_zoom_root.scale.x > 1.0):
		return
	if zoom_in:
		_zoom_root.pivot_offset = _zoom_root.get_global_transform().affine_inverse() * screen_pos
		_zoom_root.scale = Vector2.ONE * CHARA_ZOOM
	else:
		_zoom_root.scale = Vector2.ONE
		_zoom_root.position = Vector2.ZERO

## ズーム中のWASD操作。画像（ZoomRoot）をずらし、ズーム領域（Arena全体）が
## 画面から切れないよう端でクランプする。
## （キャラだけでなくブラシ類も一緒にずれる。ラックとHUDは対象外）
##
## クランプ基準はCharaImage単体ではなくZoomRoot全体にすること。CharaImage基準だと
## クリック位置（pivot_offset）が画像中央から外れるだけで、ズームした瞬間に
## クランプがpositionを強制的にずらしてしまい（左右の可動域が約160pxしかなく、
## 乳首付近でズームすると187px前後の強制ジャンプが起きる）、「クリック点を中心に
## ズーム」が成立しなくなる。ZoomRoot全体基準なら position=0 が常に有効範囲内に
## 収まるため、この問題が起きない。
func _update_zoom_pan(delta: float) -> void:
	if _zoom_root.scale.x <= 1.0:
		return
	# position を直接動かすと画面内容は反対方向に動くため、見た目がキー方向と
	# 一致するよう符号を反転させる（Wで見えている範囲が上へ、Aで左へ動く）。
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_D):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_W):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_S):
		dir.y -= 1.0
	if dir != Vector2.ZERO:
		_zoom_root.position += dir.normalized() * ZOOM_PAN_SPEED * delta
	_clamp_zoom_pan()

func _clamp_zoom_pan() -> void:
	var scale := _zoom_root.scale.x
	var piv := _zoom_root.pivot_offset
	var viewport := _zoom_root.size
	var pos_min := (piv - viewport) * (scale - 1.0)
	var pos_max := piv * (scale - 1.0)
	_zoom_root.position = _zoom_root.position.clamp(pos_min, pos_max)

func _process(delta: float) -> void:
	if not _is_running or _menu_paused:
		return
	_day_time += delta
	_update_finish_rate(delta)
	_update_zoom_pan(delta)
	_brushes.update_drag(get_global_mouse_position(), follow_speed, delta)
	_tool_actions.update_pinch(
		get_global_mouse_position(), delta, _fx.finish_active or _fx.fail_active)
	_fx.update(delta)
	var touch_info := _compute_touch_info()
	_polish_this_tick_by_tool = {}
	if not _fx.finish_active and not _fx.fail_active:
		for brush in _brushes.brush_map.values():
			if brush.is_effective():
				_apply_brush_effects(brush, delta)
		var wax_polish := _tool_actions.update_wax_drops(delta, _slime_state, _current_level())
		if wax_polish > 0.0:
			_polish_this_tick_by_tool["candle"] = \
				float(_polish_this_tick_by_tool.get("candle", 0.0)) + wax_polish
		var kiss_polish := _tool_actions.update_kiss(
			_mouth_position(), _mouth_radius(), _slime_state, _current_level(), delta)
		if kiss_polish > 0.0:
			_polish_this_tick_by_tool["tongue"] = \
				float(_polish_this_tick_by_tool.get("tongue", 0.0)) + kiss_polish
	if not _fx.fail_active:
		_apply_pain_recovery(touch_info["touched_sides"], delta)
		_apply_polish_decay(touch_info["touched_sides"], delta)
	_update_slime_squish(delta)
	_brushes.resolve_collisions(_slimes, _tool_actions.pinch_brush)
	_update_brush_facing(delta)
	if not _fx.finish_active and not _fx.fail_active:
		_check_finish()
		_check_failure()
	_update_expression(touch_info)
	_update_gauges()
	_update_brush_controls()

func setup_species(species: Dictionary) -> void:
	_species = species.duplicate(true)
	var display_name := CharacterDefs.display_name(_species)
	_title_label.text = display_name if display_name != "" else "スライム"
	_chara_image.texture = _load_texture(str(_species["game_background"]))
	var left_config: Dictionary = _species["left"]
	var right_config: Dictionary = _species["right"]
	_apply_slime_layout(_left_slime, left_config)
	_apply_slime_layout(_right_slime, right_config)
	_left_slime.apply_species(_species, "L", left_config)
	_right_slime.apply_species(_species, "R", right_config)
	_setup_breast_layers()
	var level := int(_species["level"])
	finish_threshold = GameRules.finish_threshold(level)
	_brushes.apply_unlocks(level)
	_meta_label.text = "LV %d" % level
	_day_label.text = "1日目"
	reset_day()

func _apply_slime_layout(slime: SlimeTarget, cfg: Dictionary) -> void:
	var pos_variant: Variant = cfg.get("position", null)
	if pos_variant is Vector2:
		slime.position = pos_variant

## side_config に breast 画像があるキャラは、立ち絵の上に胸レイヤーを重ねて
## 乳首ターゲットの動きへ追従させる。無ければ従来どおり1枚絵のまま。
func _setup_breast_layers() -> void:
	for layer in _breast_layers:
		layer.queue_free()
	_breast_layers.clear()
	for pair: Array in [["left", _left_slime], ["right", _right_slime]]:
		var cfg: Dictionary = _species[pair[0]]
		var path := str(cfg.get("breast", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var tex := load(path)
		if tex is not Texture2D:
			continue
		var root_variant: Variant = cfg.get("breast_root", null)
		if root_variant is not Vector2:
			continue
		var layer := BreastLayer.new()
		_chara_image.add_child(layer)
		layer.setup(tex, _chara_image.size, pair[1], pair[0], root_variant)
		_breast_layers.append(layer)
	# 立ち絵プレースホルダのラベルはレイヤーより手前を保つ。
	_chara_image.move_child(_expression_label, -1)

func _start_finish_fx() -> void:
	_tool_actions.clear()
	_fx.start_finish()

func _start_fail_fx() -> void:
	# 痛み限界: 絶望表情を見せてから日終了へ移る。
	_tool_actions.clear()
	_brushes.deactivate_all()
	_fx.start_fail()

## ESCメニューが開いている間、ゲージ進行やブラシ操作を止める。日の状態は保持したまま。
func pause_for_menu() -> void:
	_menu_paused = true
	GameAudio.update_loop("brush", "")
	GameAudio.update_loop("heartbeat", "")

func resume_from_menu() -> void:
	_menu_paused = false

## ESCメニューからタイトルへ戻る時に、その日の進行を保存せず打ち切る。
func abandon_day() -> void:
	if not _is_running:
		return
	_is_running = false
	_menu_paused = false
	_tool_actions.clear()
	Engine.time_scale = 1.0
	GameAudio.update_loop("brush", "")
	GameAudio.update_loop("heartbeat", "")
	for slime in _slimes:
		slime.set_hearts_active(false)

func reset_day() -> void:
	_day_finish_count = 0
	_polish_this_tick_by_tool = {}
	_finish_count_by_tool = {}
	_day_time = 0.0
	_last_finish_at = -1000.0
	_rate_accum = 0
	_rate_window = 0.0
	_finish_rate = 0.0
	_is_running = true
	_menu_paused = false
	_end_day_confirm_dialog.hide()
	_current_expression = ""
	_fx.reset()
	_tool_actions.clear()
	_slime_state = {
		"left": {"polish": 0.0, "pain": 0.0},
		"right": {"polish": 0.0, "pain": 0.0}
	}
	_brushes.reset()
	_zoom_root.scale = Vector2.ONE
	_zoom_root.position = Vector2.ZERO
	for slime in _slimes:
		slime.reset_pressure()
		slime.set_hearts_active(false)
	_update_expression()
	_update_gauges()
	_update_brush_controls()

func _collect_gauges() -> void:
	for gauge in get_tree().get_nodes_in_group("named_gauges"):
		_gauge_map[gauge.gauge_id] = gauge

func _update_slime_squish(delta: float) -> void:
	# Pressure depth uses the base radius so the spring has a stable input.
	# 距離はズームの影響を受けない ZoomRoot ローカル座標で測る（半径もローカル値のため）。
	for slime in _slimes:
		var deepest := 0.0
		var push := Vector2.ZERO
		var tremble_dir := Vector2.ZERO
		var touched_by_active := false
		for brush: Brush in _brushes.brush_map.values():
			if not brush.visible:
				continue
			var overlap: float = brush.get_contact_radius() + slime.radius - brush.position.distance_to(slime.position)
			deepest = maxf(deepest, overlap)
			if overlap > 0.0:
				var away := slime.position - brush.position
				if away.length() <= 0.0001:
					away = Vector2.DOWN
				push += away.normalized() * overlap
				# ON中の回転ブラシに触れられている間は反発方向へ微振動する。
				if brush.is_rotating and brush.is_effective():
					tremble_dir = away.normalized()
			if brush.is_effective() and overlap > 0.0:
				touched_by_active = true
		slime.apply_pressure(deepest, delta, push, tremble_dir)
		var state: Dictionary = _slime_state.get(String(slime.side), {})
		var polish_winning: bool = float(state.get("polish", 0.0)) > float(state.get("pain", 0.0))
		slime.set_hearts_active(touched_by_active and polish_winning)

## こすり系ブラシは当たり判定付近で、最寄りの本体中心へ画像の上を向ける。
func _update_brush_facing(delta: float) -> void:
	for brush: Brush in _brushes.brush_map.values():
		if not brush.visible or not brush.uses_rub():
			continue
		var nearest_pos: Variant = null
		var nearest_dist := INF
		for slime in _slimes:
			var dist := brush.position.distance_to(slime.position)
			var facing_range := brush.get_contact_radius() + slime.get_hit_radius() \
				+ BRUSH_FACING_RANGE_MARGIN
			if dist <= facing_range and dist < nearest_dist:
				nearest_dist = dist
				nearest_pos = slime.position
		brush.update_contact_facing(nearest_pos, delta)

func _apply_brush_effects(brush: Brush, delta: float) -> void:
	var rates := _brush_effect_rates(brush, _current_level())
	for slime in _slimes:
		if _is_brush_touching_slime(brush, slime):
			var side := String(slime.side)
			var state: Dictionary = _slime_state.get(side, {})
			# 快感には上限を設けない（高感度帯は1フレームでしきい値の何倍にも達する）。
			# ゲージ表示側（named_gauge.gd）が GAUGE_MAX でクランプして見せるので、
			# 表示が壊れることはない。
			var polish_gain := float(rates["polish"]) * delta
			state["polish"] = maxf(0.0, float(state.get("polish", 0.0)) + polish_gain)
			state["pain"] = clamp(float(state.get("pain", 0.0)) + float(rates["pain"]) * delta, 0.0, GameRules.PAIN_CAP)
			state["pain"] = clamp(float(state["pain"]) - float(rates["soothe"]) * delta, 0.0, GameRules.PAIN_CAP)
			_slime_state[side] = state
			if polish_gain > 0.0:
				_polish_this_tick_by_tool[brush.brush_id] = \
					float(_polish_this_tick_by_tool.get(brush.brush_id, 0.0)) + polish_gain

## アクティブなブラシが触れていない部位は痛みが自然回復する。
func _apply_pain_recovery(touched_sides: Dictionary, delta: float) -> void:
	for side in ["left", "right"]:
		if bool(touched_sides.get(side, false)):
			continue
		var state: Dictionary = _slime_state[side]
		state["pain"] = maxf(0.0, float(state["pain"]) - GameRules.PAIN_RECOVERY_PER_SEC * delta)
		_slime_state[side] = state

## アクティブなブラシが触れていない部位は快感が自然に減衰する。
func _apply_polish_decay(touched_sides: Dictionary, delta: float) -> void:
	for side in ["left", "right"]:
		if bool(touched_sides.get(side, false)):
			continue
		var state: Dictionary = _slime_state[side]
		state["polish"] = maxf(0.0, float(state["polish"]) - GameRules.POLISH_DECAY_PER_SEC * delta)
		_slime_state[side] = state

func _brush_effect_rates(brush: Brush, level: int) -> Dictionary:
	# 通常ブラシはこすった速度、回転ブラシはON中の自動回転で効く。
	var rub := brush.get_action_multiplier()
	return {
		"polish": brush.get_effective_polish_gain() * GameRules.polish_bonus(level) * rub,
		"pain": brush.get_effective_pain_gain() * GameRules.pain_resist(level) * rub * PAIN_GAIN_SCALE,
		"soothe": brush.get_effective_soothe_gain() * rub
	}

## ゲーム効果上の接触判定。効果適用・表情・痛み回復で必ず同じ条件を使う。
## 押し込み表現は変形量を求めるため base radius 基準の overlap を別途計算する。
func _is_brush_touching_slime(brush: Brush, slime: SlimeTarget) -> bool:
	return brush.position.distance_to(slime.position) \
		<= brush.get_contact_radius() + slime.get_hit_radius()

## アクティブなブラシの接触状態と、いま掛かっている上昇量/秒（補正込み）。
## touched_sides は side名 → 接触中フラグ（痛み自然回復の判定に使う）。
func _compute_touch_info() -> Dictionary:
	var touching := false
	var touched_sides := {}
	var polish_rate := 0.0
	var pain_rate := 0.0
	var level := int(_species["level"])
	for brush: Brush in _brushes.brush_map.values():
		if not brush.visible or not brush.is_effective():
			continue
		var rates := _brush_effect_rates(brush, level)
		for slime in _slimes:
			if _is_brush_touching_slime(brush, slime):
				touching = true
				touched_sides[String(slime.side)] = true
				# _apply_brush_effects と同じ係数で「ゲージが実際に動く速さ」を比較する。
				polish_rate += float(rates["polish"])
				pain_rate += float(rates["pain"]) - float(rates["soothe"])
	return {
		"touching": touching,
		"touched_sides": touched_sides,
		"polish_rate": polish_rate,
		"pain_rate": pain_rate
	}

func _update_expression(info: Dictionary = {}) -> void:
	if info.is_empty():
		info = _compute_touch_info()
	var polish_ratio := _get_combined_polish() / maxf(finish_threshold, 0.001)
	var expression := ExpressionRules.pick({
		"touching": bool(info["touching"]),
		"polish_ratio": polish_ratio,
		"polish_rate": float(info["polish_rate"]),
		"pain_rate": float(info["pain_rate"]),
		"climax": _fx.finish_active or _is_chain_climax(),
		"despair": _fx.fail_active,
		"exhausted": _fx.exhausted
	})
	if _debug_expression_override != "":
		expression = _debug_expression_override
	_apply_expression(expression)
	_update_sound_loops(expression, polish_ratio)

## 接触ループSE（表情連動）と絶頂寸前の心音ループを更新する。素材が無ければ無音。
func _update_sound_loops(expression: String, polish_ratio: float) -> void:
	GameAudio.update_loop("brush", ExpressionRules.touch_loop_se(expression))
	var heartbeat := polish_ratio >= ExpressionRules.IDLE_HIGH \
		and expression != ExpressionRules.CLIMAX \
		and expression != ExpressionRules.DESPAIR
	GameAudio.update_loop("heartbeat", "heartbeat" if heartbeat else "")

func _apply_expression(expression_id: String) -> void:
	if expression_id == _current_expression:
		return
	_current_expression = expression_id
	var texture := _resolve_face_texture(expression_id)
	_face_image.texture = texture
	_face_image.visible = texture != null
	_expression_label.visible = texture == null
	_expression_label.text = "顔差分：%s" % ExpressionRules.display_name(expression_id)
	_update_dialogue(expression_id)
	# 表情が変わった瞬間だけボイス再生を試みる（素材が無ければ無音、連射は抑制済み）。
	GameAudio.play_voice(str(_species["id"]), expression_id)

## 表情idに対応するセリフを表示する。characters.gd の dialogue は表情id→候補配列で、
## その表情に入るたびランダムに1つ選ぶ（未設定・空配列なら空欄のまま）。
func _update_dialogue(expression_id: String) -> void:
	var dialogue: Dictionary = _species["dialogue"]
	var lines: Array = dialogue.get(expression_id, [])
	var line := str(lines.pick_random()) if not lines.is_empty() else ""
	_dialogue_label.text = "「%s」" % line if line != "" else ""

## キャラ定義の expressions 辞書を優先し、次に既定の表情パスを探す。
## 立ち絵ベース（game_background、setup_species で一度だけ設定）の上に重ねる
## 顔だけの差分（背景・体は透過）を返す。無ければ null（ベースがそのまま見える）。
func _resolve_face_texture(expression_id: String) -> Texture2D:
	var expressions: Dictionary = _species["expressions"]
	var path := str(expressions.get(expression_id, ""))
	if path == "":
		path = ExpressionRules.default_image_path(str(_species["id"]), expression_id)
	return _load_texture(path)

func _load_texture(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		var texture := load(path)
		if texture is Texture2D:
			return texture
	return null

func _update_gauges() -> void:
	_set_gauge("polish-L", _slime_state["left"]["polish"])
	_set_gauge("pain-L", _slime_state["left"]["pain"])
	_set_gauge("polish-R", _slime_state["right"]["polish"])
	_set_gauge("pain-R", _slime_state["right"]["pain"])
	_finish_progress.max_value = finish_threshold
	_finish_progress.value = _get_combined_polish()
	if _finish_rate >= FINISH_RATE_DISPLAY_CAP:
		_day_finish_label.text = "本日のFINISH: %s（∞ 大量発生中）" % NumberFormat.group(_day_finish_count)
		var blink := 0.4 + 0.6 * absf(sin(_day_time * FINISH_BLINK_HZ * TAU))
		_day_finish_label.modulate = Color(1.0, 1.0, 1.0, blink)
	else:
		var day_text := "本日のFINISH: %s" % NumberFormat.group(_day_finish_count)
		if _finish_rate >= 0.5:
			day_text += "（毎秒 %s）" % NumberFormat.ja_unit(_finish_rate)
		_day_finish_label.text = day_text
		_day_finish_label.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _set_gauge(gauge_id: String, current: float) -> void:
	var gauge: NamedGauge = _gauge_map.get(gauge_id)
	if gauge != null:
		gauge.set_gauge_value(current, GameRules.GAUGE_MAX)

func _on_end_day_pressed() -> void:
	pause_for_menu()
	_end_day_confirm_dialog.popup_centered()

func _on_end_day_confirmed() -> void:
	GameAudio.play_se("ui_click")
	_end_day_confirm_dialog.hide()
	resume_from_menu()
	_finish_day(false)

func _on_end_day_canceled() -> void:
	_end_day_confirm_dialog.hide()
	resume_from_menu()

func _update_brush_controls() -> void:
	_brushes.update_controls(_brush_name_label, _brush_spec_label)

func _get_combined_polish() -> float:
	return float(_slime_state["left"]["polish"]) + float(_slime_state["right"]["polish"])

func _current_level() -> int:
	return int(_species["level"])

func _mouth_position() -> Vector2:
	var mouth: Dictionary = _species.get("mouth", {})
	return mouth.get("position", Vector2.ZERO) as Vector2

func _mouth_radius() -> float:
	var mouth: Dictionary = _species.get("mouth", {})
	return float(mouth.get("radius", 40.0))

func _check_finish() -> void:
	var count := GameRules.finish_count(_get_combined_polish(), finish_threshold)
	if count <= 0:
		return
	_day_finish_count += count
	_rate_accum += count
	_credit_finish_to_tool(count)
	for side in ["left", "right"]:
		var state: Dictionary = _slime_state[side]
		state["polish"] = 0.0
		_slime_state[side] = state
	if count == 1 and _day_time - _last_finish_at >= FULL_FINISH_FX_MIN_INTERVAL:
		_start_finish_fx()
	else:
		_fx.pulse_chain()
	_last_finish_at = _day_time

## そのフレームで最も快感を与えていたツールへ、このFINISH分をまとめて計上する。
func _credit_finish_to_tool(count: int) -> void:
	var winner := "other"
	var winner_amount := 0.0
	for brush_id in _polish_this_tick_by_tool:
		var amount := float(_polish_this_tick_by_tool[brush_id])
		if amount > winner_amount:
			winner_amount = amount
			winner = brush_id
	_finish_count_by_tool[winner] = int(_finish_count_by_tool.get(winner, 0)) + count

## 直近の集計窓のFINISH回数からレート（回/秒）を更新する。
func _update_finish_rate(delta: float) -> void:
	_rate_window += delta
	if _rate_window < RATE_SAMPLE_WINDOW:
		return
	_finish_rate = float(_rate_accum) / _rate_window
	_rate_accum = 0
	_rate_window = 0.0

## 連鎖中（直前のFINISHから間もない）は絶頂表情に張り付かせる。
func _is_chain_climax() -> bool:
	return _day_finish_count > 0 and (_day_time - _last_finish_at) < 0.5

func _check_failure() -> void:
	var peak_pain: float = maxf(float(_slime_state["left"]["pain"]), float(_slime_state["right"]["pain"]))
	if peak_pain >= GameRules.PAIN_LIMIT:
		_start_fail_fx()

# --- デバッグパネル用フック（debug_panel.gd から呼ばれる。リリースでは未使用） ---

func debug_get_level() -> int:
	return int(_species["level"])

func debug_set_level(level: int) -> void:
	level = clampi(level, 1, GameRules.MAX_LEVEL)
	_species["level"] = level
	finish_threshold = GameRules.finish_threshold(level)
	_brushes.apply_unlocks(level)
	_meta_label.text = "LV %d" % level

func debug_add_gauge(side: String, key: String, amount: float) -> void:
	var state: Dictionary = _slime_state[side]
	var ceiling := GameRules.PAIN_CAP if key == "pain" else GameRules.GAUGE_MAX
	state[key] = clampf(float(state[key]) + amount, 0.0, ceiling)
	_slime_state[side] = state

func debug_reset_gauges() -> void:
	_slime_state = {
		"left": {"polish": 0.0, "pain": 0.0},
		"right": {"polish": 0.0, "pain": 0.0}
	}

func debug_trigger_finish() -> void:
	if not _is_running or _fx.finish_active or _fx.fail_active:
		return
	for side in ["left", "right"]:
		var state: Dictionary = _slime_state[side]
		state["polish"] = minf(finish_threshold * 0.5, GameRules.GAUGE_MAX)
		_slime_state[side] = state
	_check_finish()

func debug_trigger_fail() -> void:
	if not _is_running or _fx.fail_active:
		return
	var state: Dictionary = _slime_state["left"]
	state["pain"] = GameRules.PAIN_LIMIT
	_slime_state["left"] = state
	_check_failure()

func debug_expression_override() -> String:
	return _debug_expression_override

func debug_cycle_expression() -> void:
	var ids: Array[String] = [
		ExpressionRules.IDLE_A, ExpressionRules.IDLE_B,
		ExpressionRules.IDLE_C, ExpressionRules.IDLE_D,
		ExpressionRules.TOUCH_A, ExpressionRules.TOUCH_B,
		ExpressionRules.TOUCH_C, ExpressionRules.TOUCH_D,
		ExpressionRules.CLIMAX, ExpressionRules.DESPAIR, ExpressionRules.EXHAUSTED
	]
	var index := ids.find(_debug_expression_override)
	_debug_expression_override = ids[(index + 1) % ids.size()]

func debug_clear_expression() -> void:
	_debug_expression_override = ""

func _finish_day(failed_by_pain: bool) -> void:
	if not _is_running:
		return
	_is_running = false
	_tool_actions.clear()
	# デバッグの倍速を磨き画面の外へ持ち出さない。
	Engine.time_scale = 1.0
	GameAudio.update_loop("brush", "")
	GameAudio.update_loop("heartbeat", "")
	for slime in _slimes:
		slime.set_hearts_active(false)
	var banked_finish := GameRules.banked_finish(_day_finish_count, failed_by_pain)
	day_finished.emit({
		"species_id": str(_species["id"]),
		"species_name": CharacterDefs.display_name(_species),
		"day_finish_count": _day_finish_count,
		"banked_finish_count": banked_finish,
		"failed_by_pain": failed_by_pain,
		"finish_count_by_tool": _finish_count_by_tool_display()
	})

## brush_id をツール表示名（例: "指"）に解決した { 表示名: FINISH数 } を返す。
func _finish_count_by_tool_display() -> Dictionary:
	var result := {}
	for brush_id in _finish_count_by_tool:
		var label := str(brush_id)
		var brush: Brush = _brushes.brush_map.get(brush_id)
		if brush != null and brush.display_name != "":
			label = brush.display_name
		result[label] = _finish_count_by_tool[brush_id]
	return result
