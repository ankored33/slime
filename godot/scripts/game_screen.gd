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

# こすり系ブラシは、接触してからではなく当たり判定付近に入った時点で先端を向ける。
const BRUSH_FACING_RANGE_MARGIN := 48.0

# キャラ画像の上でのホイールズーム倍率。上回転でマウス位置を中心に1段階ズームし、
# 下回転で等倍へ戻る。ツールボックスとHUDはズーム対象外。
const CHARA_ZOOM := 2.0

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
@onready var _danger_label: RichTextLabel = $Hud/ConditionLabel
@onready var _day_label: Label = $Hud/DayLabel
@onready var _brush_name_label: Label = $Hud/BrushNameLabel
@onready var _brush_spec_label: Label = $Hud/BrushSpecLabel
@onready var _finish_progress: ProgressBar = $Hud/FinishProgress
@onready var _finish_label: Label = $Hud/FinishLabel
@onready var _day_finish_label: Label = $Hud/DayStats/Margin/FinishCount
@onready var _end_day_button: Button = $Hud/Controls/EndDayButton
@onready var _left_slime: SlimeTarget = $Playfield/ZoomRoot/LeftSlime
@onready var _right_slime: SlimeTarget = $Playfield/ZoomRoot/RightSlime
@onready var _chara_image: TextureRect = $Playfield/ZoomRoot/CharaImage
@onready var _expression_label: Label = $Playfield/ZoomRoot/CharaImage/ExpressionLabel
@onready var _flash_rect: ColorRect = $FlashRect

func _ready() -> void:
	_slimes.assign([_left_slime, _right_slime])
	_collect_gauges()
	_end_day_button.pressed.connect(_on_end_day_pressed)
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
	reset_day()

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
	elif action.has("pinch_released"):
		_tool_actions.end_pinch()

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

func _process(delta: float) -> void:
	if not _is_running or _menu_paused:
		return
	_day_time += delta
	_update_finish_rate(delta)
	_brushes.update_drag(get_global_mouse_position(), follow_speed, delta)
	_tool_actions.update_pinch(
		get_global_mouse_position(), delta, _fx.finish_active or _fx.fail_active)
	_fx.update(delta)
	var touch_info := _compute_touch_info()
	if not _fx.finish_active and not _fx.fail_active:
		for brush in _brushes.brush_map.values():
			if brush.is_effective():
				_apply_brush_effects(brush, delta)
		_tool_actions.update_wax_drops(delta, _slime_state, _current_level())
	if not _fx.fail_active:
		_apply_pain_recovery(touch_info["touched_sides"], delta)
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
	var left_config: Dictionary = _species.get("left", {})
	var right_config: Dictionary = _species.get("right", {})
	_apply_slime_layout(_left_slime, left_config)
	_apply_slime_layout(_right_slime, right_config)
	_left_slime.apply_species(_species, "L", left_config)
	_right_slime.apply_species(_species, "R", right_config)
	_setup_breast_layers()
	var level := int(_species.get("level", 1))
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
		var cfg: Dictionary = _species.get(pair[0], {})
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
	_day_time = 0.0
	_last_finish_at = -1000.0
	_rate_accum = 0
	_rate_window = 0.0
	_finish_rate = 0.0
	_is_running = true
	_menu_paused = false
	_current_expression = ""
	_fx.reset()
	_tool_actions.clear()
	_slime_state = {
		"left": {"polish": 0.0, "pain": 0.0},
		"right": {"polish": 0.0, "pain": 0.0}
	}
	_brushes.reset()
	_zoom_root.scale = Vector2.ONE
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
		if brush.position.distance_to(slime.position) <= brush.hit_radius + slime.get_hit_radius():
			var side := String(slime.side)
			var state: Dictionary = _slime_state.get(side, {})
			state["polish"] = clamp(float(state.get("polish", 0.0)) + float(rates["polish"]) * delta, 0.0, GameRules.GAUGE_MAX)
			state["pain"] = clamp(float(state.get("pain", 0.0)) + float(rates["pain"]) * delta, 0.0, GameRules.PAIN_CAP)
			state["pain"] = clamp(float(state["pain"]) - float(rates["soothe"]) * delta, 0.0, GameRules.PAIN_CAP)
			_slime_state[side] = state

## アクティブなブラシが触れていない部位は痛みが自然回復する。
func _apply_pain_recovery(touched_sides: Dictionary, delta: float) -> void:
	for side in ["left", "right"]:
		if bool(touched_sides.get(side, false)):
			continue
		var state: Dictionary = _slime_state[side]
		state["pain"] = maxf(0.0, float(state["pain"]) - GameRules.PAIN_RECOVERY_PER_SEC * delta)
		_slime_state[side] = state

func _brush_effect_rates(brush: Brush, level: int) -> Dictionary:
	# 通常ブラシはこすった速度、回転ブラシはON中の自動回転で効く。
	var rub := brush.get_action_multiplier()
	return {
		"polish": brush.get_effective_polish_gain() * GameRules.polish_bonus(level) * rub,
		"pain": brush.get_effective_pain_gain() * GameRules.pain_resist(level) * rub * PAIN_GAIN_SCALE,
		"soothe": brush.get_effective_soothe_gain() * rub
	}

## アクティブなブラシの接触状態と、いま掛かっている上昇量/秒（補正込み）。
## touched_sides は side名 → 接触中フラグ（痛み自然回復の判定に使う）。
func _compute_touch_info() -> Dictionary:
	var touching := false
	var touched_sides := {}
	var polish_rate := 0.0
	var pain_rate := 0.0
	var level := int(_species.get("level", 1))
	for brush: Brush in _brushes.brush_map.values():
		if not brush.visible or not brush.is_effective():
			continue
		var rates := _brush_effect_rates(brush, level)
		for slime in _slimes:
			if brush.position.distance_to(slime.position) <= brush.get_contact_radius() + slime.get_hit_radius():
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
	var texture := _resolve_expression_texture(expression_id)
	_chara_image.texture = texture
	_expression_label.visible = texture == null
	_expression_label.text = "立ち絵：%s" % ExpressionRules.display_name(expression_id)
	# 表情が変わった瞬間だけボイス再生を試みる（素材が無ければ無音、連射は抑制済み）。
	GameAudio.play_voice(str(_species.get("id", "")), expression_id)

## キャラ定義の expressions 辞書を優先し、次に既定の表情パスを探す。
## 表情素材が無い場合は、磨き画面用の固定背景 game_background を使う。
func _resolve_expression_texture(expression_id: String) -> Texture2D:
	var expressions: Dictionary = _species.get("expressions", {})
	var path := str(expressions.get(expression_id, ""))
	if path == "":
		path = ExpressionRules.default_image_path(str(_species.get("id", "")), expression_id)
	if ResourceLoader.exists(path):
		var texture := load(path)
		if texture is Texture2D:
			return texture
	var background_path := str(_species.get("game_background", ""))
	if background_path != "" and ResourceLoader.exists(background_path):
		var background := load(background_path)
		if background is Texture2D:
			return background
	return null

func _update_gauges() -> void:
	_set_gauge("polish-L", _slime_state["left"]["polish"])
	_set_gauge("pain-L", _slime_state["left"]["pain"])
	_set_gauge("polish-R", _slime_state["right"]["polish"])
	_set_gauge("pain-R", _slime_state["right"]["pain"])
	_finish_progress.max_value = finish_threshold
	_finish_progress.value = _get_combined_polish()
	var day_text := "本日のFINISH: %s" % NumberFormat.group(_day_finish_count)
	if _finish_rate >= 0.5:
		day_text += "（毎秒 %s）" % NumberFormat.ja_unit(_finish_rate)
	_day_finish_label.text = day_text
	var peak_pain: float = maxf(float(_slime_state["left"]["pain"]), float(_slime_state["right"]["pain"]))
	if peak_pain >= GameRules.GAUGE_MAX * 0.8:
		_danger_label.text = "[b]状態[/b]\n痛み：限界寸前"
		_danger_label.modulate = Color(1.0, 0.45, 0.45, 1.0)
	elif peak_pain >= GameRules.GAUGE_MAX * 0.55:
		_danger_label.text = "[b]状態[/b]\n痛み：上昇中"
		_danger_label.modulate = Color(1.0, 0.82, 0.45, 1.0)
	else:
		_danger_label.text = "[b]状態[/b]\n痛み：安定"
		_danger_label.modulate = Color(0.75, 0.92, 0.85, 1.0)

func _set_gauge(gauge_id: String, current: float) -> void:
	var gauge: NamedGauge = _gauge_map.get(gauge_id)
	if gauge != null:
		gauge.set_gauge_value(current, GameRules.GAUGE_MAX)

func _on_end_day_pressed() -> void:
	GameAudio.play_se("ui_click")
	_finish_day(false)

func _update_brush_controls() -> void:
	_brushes.update_controls(_brush_name_label, _brush_spec_label)

func _get_combined_polish() -> float:
	return float(_slime_state["left"]["polish"]) + float(_slime_state["right"]["polish"])

func _current_level() -> int:
	return int(_species.get("level", 1))

func _check_finish() -> void:
	var level := int(_species.get("level", 1))
	var chain := GameRules.chain_finishes(
		_get_combined_polish(), finish_threshold, GameRules.retention_ratio(level))
	var count := int(chain["count"])
	if count <= 0:
		return
	_day_finish_count += count
	_rate_accum += count
	for side in ["left", "right"]:
		var state: Dictionary = _slime_state[side]
		state["polish"] = float(state["polish"]) * float(chain["factor"])
		_slime_state[side] = state
	if count == 1 and _day_time - _last_finish_at >= FULL_FINISH_FX_MIN_INTERVAL:
		_start_finish_fx()
	else:
		_fx.pulse_chain()
	_last_finish_at = _day_time

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
	return int(_species.get("level", 1))

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
		"species_id": str(_species.get("id", "")),
		"species_name": CharacterDefs.display_name(_species),
		"day_finish_count": _day_finish_count,
		"banked_finish_count": banked_finish,
		"failed_by_pain": failed_by_pain
	})
