extends Control

signal day_finished(result: Dictionary)

const ExpressionRules = preload("res://scripts/expression_rules.gd")
const GameAudio = preload("res://scripts/game_audio.gd")
const GameScreenBrushes = preload("res://scripts/game_screen_brushes.gd")
const DebugPanelScript = preload("res://scripts/debug_panel.gd")
const WaxDropScript = preload("res://scripts/wax_drop.gd")

@export var follow_speed := 16.0
@export var finish_fx_duration := 5.0
@export var fail_fx_duration := 2.5

# FINISH演出が終わってから憔悴表情を保つ時間。
const EXHAUST_DURATION := 4.0

# 痛み上昇の全体係数（快感とのバランス調整用）。
const PAIN_GAIN_SCALE := 0.35

# 演出オーバーレイの色。FINISHは白ピンクの閃光、失敗は暗い赤の暗転。
const FINISH_FLASH_COLOR := Color(1.0, 0.88, 0.93)
const FAIL_FLASH_COLOR := Color(0.35, 0.02, 0.06)

# Level-driven; refreshed in setup_species.
var finish_threshold := GameRules.finish_threshold(1)

# 右パネル上部のブラシ置き場。開始・リセット時にブラシをここへ戻す。
const BRUSH_RACK_SLOTS := {
	"finger": Vector2(1050, 150),
	"tongue": Vector2(1195, 150),
	"feather": Vector2(1050, 215),
	"fude": Vector2(1195, 215),
	"teeth": Vector2(1050, 280),
	"toothbrush": Vector2(1195, 280),
	"rotary": Vector2(1050, 345),
	"tawashi": Vector2(1195, 345),
	"candle": Vector2(1122, 375)
}

var _finish_fx_time_left := 0.0
var _fail_fx_time_left := 0.0
var _exhaust_time_left := 0.0
var _current_expression := ""
var _gauge_map: Dictionary = {}
var _brushes := GameScreenBrushes.new()
var _slime_state := {
	"left": {"polish": 0.0, "pain": 0.0},
	"right": {"polish": 0.0, "pain": 0.0}
}
var _species: Dictionary = {}
var _day_finish_count := 0
var _is_running := false
var _debug_panel: PanelContainer
var _debug_expression_override := ""
var _wax_drops: Array[WaxDrop] = []

@onready var _playfield: Control = $Playfield
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
@onready var _left_slime: SlimeTarget = $Playfield/LeftSlime
@onready var _right_slime: SlimeTarget = $Playfield/RightSlime
@onready var _chara_image: TextureRect = $Playfield/CharaImage
@onready var _expression_label: Label = $Playfield/CharaImage/ExpressionLabel
@onready var _flash_rect: ColorRect = $FlashRect

func _ready() -> void:
	_collect_gauges()
	_end_day_button.pressed.connect(_on_end_day_pressed)
	_brushes.setup(self, _playfield, _end_day_button)
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
	if not _is_running:
		return
	var action := _brushes.handle_input(event)
	if action.has("wax_origin"):
		_spawn_wax_drop(action["wax_origin"])

func _process(delta: float) -> void:
	if not _is_running:
		return
	_brushes.update_drag(get_global_mouse_position(), follow_speed, delta)
	_update_finish_fx(delta)
	_update_fail_fx(delta)
	_exhaust_time_left = maxf(0.0, _exhaust_time_left - delta)
	var touch_info := _compute_touch_info()
	if not _is_finish_fx_active() and not _is_fail_fx_active():
		for brush in _brushes.brush_map.values():
			if brush.is_effective():
				_apply_brush_effects(brush, delta)
		_update_wax_drops(delta)
	if not _is_fail_fx_active():
		_apply_pain_recovery(touch_info["touched_sides"], delta)
	_update_slime_squish(delta)
	_brushes.resolve_collisions(get_tree().get_nodes_in_group("slime_targets"))
	if not _is_finish_fx_active() and not _is_fail_fx_active():
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

func _is_finish_fx_active() -> bool:
	return _finish_fx_time_left > 0.0

func _start_finish_fx() -> void:
	_finish_fx_time_left = finish_fx_duration
	_clear_wax_drops()
	_finish_label.visible = true
	_finish_label.pivot_offset = _finish_label.size / 2.0
	_finish_label.scale = Vector2(0.4, 0.4)
	var tween := create_tween()
	tween.tween_property(_finish_label, "scale", Vector2(1.3, 1.3), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_finish_label, "scale", Vector2.ONE, 0.3)
	for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
		slime.burst_hearts()
	GameAudio.play_se("climax")

func _update_finish_fx(delta: float) -> void:
	if _finish_fx_time_left <= 0.0:
		return
	_finish_fx_time_left = maxf(0.0, _finish_fx_time_left - delta)
	var elapsed := finish_fx_duration - _finish_fx_time_left
	var flash := FINISH_FLASH_COLOR
	flash.a = _finish_flash_alpha(elapsed)
	_flash_rect.color = flash
	_apply_shake(maxf(0.0, 1.0 - elapsed / 1.2) * 16.0)
	if _finish_fx_time_left == 0.0:
		_finish_label.visible = false
		_clear_fx_overlay()
		_exhaust_time_left = EXHAUST_DURATION

## 閃光→急速フェード→余韻（薄いピンク）→演出終了までにゼロ、の3段カーブ。
func _finish_flash_alpha(elapsed: float) -> float:
	if elapsed < 0.2:
		return lerpf(0.0, 0.9, elapsed / 0.2)
	if elapsed < 1.6:
		return lerpf(0.9, 0.16, (elapsed - 0.2) / 1.4)
	var tail := maxf(finish_fx_duration - 1.6, 0.001)
	return lerpf(0.16, 0.0, clampf((elapsed - 1.6) / tail, 0.0, 1.0))

func _apply_shake(amplitude: float) -> void:
	if amplitude <= 0.05:
		_playfield.position = Vector2.ZERO
		return
	_playfield.position = Vector2(
		randf_range(-amplitude, amplitude),
		randf_range(-amplitude, amplitude)
	)

func _clear_fx_overlay() -> void:
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_playfield.position = Vector2.ZERO

func _is_fail_fx_active() -> bool:
	return _fail_fx_time_left > 0.0

func _start_fail_fx() -> void:
	# 痛み限界: 絶望表情を見せてから日終了へ移る。
	_fail_fx_time_left = fail_fx_duration
	_clear_wax_drops()
	_brushes.deactivate_all()
	GameAudio.play_se("despair")

func _update_fail_fx(delta: float) -> void:
	if _fail_fx_time_left <= 0.0:
		return
	_fail_fx_time_left = maxf(0.0, _fail_fx_time_left - delta)
	var elapsed := fail_fx_duration - _fail_fx_time_left
	var flash := FAIL_FLASH_COLOR
	flash.a = minf(elapsed / 0.4, 1.0) * 0.5
	_flash_rect.color = flash
	_apply_shake(maxf(0.0, 1.0 - elapsed / 0.8) * 10.0)
	if _fail_fx_time_left == 0.0:
		_apply_shake(0.0)
		_finish_day(true)

func reset_day() -> void:
	_day_finish_count = 0
	_is_running = true
	_finish_fx_time_left = 0.0
	_fail_fx_time_left = 0.0
	_exhaust_time_left = 0.0
	_current_expression = ""
	_finish_label.visible = false
	_finish_label.scale = Vector2.ONE
	_clear_fx_overlay()
	_clear_wax_drops()
	_slime_state = {
		"left": {"polish": 0.0, "pain": 0.0},
		"right": {"polish": 0.0, "pain": 0.0}
	}
	_brushes.reset(BRUSH_RACK_SLOTS)
	for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
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
	for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
		var deepest := 0.0
		var touched_by_active := false
		for brush: Brush in _brushes.brush_map.values():
			if not brush.visible:
				continue
			var overlap: float = brush.hit_radius + slime.radius - brush.global_position.distance_to(slime.global_position)
			deepest = maxf(deepest, overlap)
			if brush.is_effective() and overlap > 0.0:
				touched_by_active = true
		slime.apply_pressure(deepest, delta)
		var state: Dictionary = _slime_state.get(String(slime.side), {})
		var polish_winning: bool = float(state.get("polish", 0.0)) > float(state.get("pain", 0.0))
		slime.set_hearts_active(touched_by_active and polish_winning)

func _apply_brush_effects(brush: Brush, delta: float) -> void:
	for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
		if brush.global_position.distance_to(slime.global_position) <= brush.hit_radius + slime.get_hit_radius():
			var side := String(slime.side)
			var state: Dictionary = _slime_state.get(side, {})
			var level := int(_species.get("level", 1))
			var polish_bonus := GameRules.polish_bonus(level)
			var pain_resist := GameRules.pain_resist(level)
			# 通常ブラシはこすった速度、回転ブラシはON中の自動回転で効く。
			var rub := brush.get_action_multiplier()
			state["polish"] = clamp(float(state.get("polish", 0.0)) + brush.get_effective_polish_gain() * polish_bonus * rub * delta, 0.0, 100.0)
			state["pain"] = clamp(float(state.get("pain", 0.0)) + brush.get_effective_pain_gain() * pain_resist * rub * delta * PAIN_GAIN_SCALE, 0.0, 100.0)
			state["pain"] = clamp(float(state["pain"]) - brush.get_effective_soothe_gain() * rub * delta, 0.0, 100.0)
			_slime_state[side] = state

func _spawn_wax_drop(origin: Vector2) -> void:
	if _is_finish_fx_active() or _is_fail_fx_active():
		return
	var drop: WaxDrop = WaxDropScript.new()
	drop.position = origin
	_playfield.add_child(drop)
	_wax_drops.append(drop)

func _update_wax_drops(delta: float) -> void:
	for index in range(_wax_drops.size() - 1, -1, -1):
		var drop := _wax_drops[index]
		var previous := drop.advance(delta)
		var hit := false
		for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
			if _segment_distance_to_point(previous, drop.position, slime.position) \
					<= drop.radius + slime.get_hit_radius():
				_apply_wax_impact(String(slime.side))
				hit = true
				break
		if hit or drop.is_expired(_playfield.size.y):
			_wax_drops.remove_at(index)
			drop.queue_free()

func _apply_wax_impact(side: String) -> void:
	var state: Dictionary = _slime_state[side]
	var level := int(_species.get("level", 1))
	state["polish"] = clampf(
		float(state["polish"]) + GameRules.WAX_POLISH_IMPACT * GameRules.polish_bonus(level),
		0.0, 100.0
	)
	state["pain"] = clampf(
		float(state["pain"]) + GameRules.WAX_PAIN_IMPACT * GameRules.pain_resist(level),
		0.0, 100.0
	)
	_slime_state[side] = state

func _segment_distance_to_point(start: Vector2, end: Vector2, point: Vector2) -> float:
	var segment := end - start
	if segment.length_squared() <= 0.0001:
		return point.distance_to(start)
	var t := clampf((point - start).dot(segment) / segment.length_squared(), 0.0, 1.0)
	return point.distance_to(start + segment * t)

func _clear_wax_drops() -> void:
	for drop in _wax_drops:
		if is_instance_valid(drop):
			drop.queue_free()
	_wax_drops.clear()

## アクティブなブラシが触れていない部位は痛みが自然回復する。
func _apply_pain_recovery(touched_sides: Dictionary, delta: float) -> void:
	for side in ["left", "right"]:
		if bool(touched_sides.get(side, false)):
			continue
		var state: Dictionary = _slime_state[side]
		state["pain"] = maxf(0.0, float(state["pain"]) - GameRules.PAIN_RECOVERY_PER_SEC * delta)
		_slime_state[side] = state

## アクティブなブラシの接触状態と、いま掛かっている上昇量/秒（補正込み）。
## touched_sides は side名 → 接触中フラグ（痛み自然回復の判定に使う）。
func _compute_touch_info() -> Dictionary:
	var touching := false
	var touched_sides := {}
	var polish_rate := 0.0
	var pain_rate := 0.0
	var level := int(_species.get("level", 1))
	var polish_bonus := GameRules.polish_bonus(level)
	var pain_resist := GameRules.pain_resist(level)
	for brush: Brush in _brushes.brush_map.values():
		if not brush.visible or not brush.is_effective():
			continue
		for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
			if brush.global_position.distance_to(slime.global_position) <= brush.hit_radius + slime.get_hit_radius():
				touching = true
				touched_sides[String(slime.side)] = true
				# _apply_brush_effects と同じ係数で「ゲージが実際に動く速さ」を比較する。
				var rub := brush.get_action_multiplier()
				polish_rate += brush.get_effective_polish_gain() * polish_bonus * rub
				pain_rate += brush.get_effective_pain_gain() * pain_resist * rub * PAIN_GAIN_SCALE
				pain_rate -= brush.get_effective_soothe_gain() * rub
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
		"climax": _is_finish_fx_active(),
		"despair": _is_fail_fx_active(),
		"exhausted": _exhaust_time_left > 0.0
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
	_day_finish_label.text = "本日のFINISH: %d" % _day_finish_count
	var peak_pain: float = maxf(float(_slime_state["left"]["pain"]), float(_slime_state["right"]["pain"]))
	if peak_pain >= 80.0:
		_danger_label.text = "[b]状態[/b]\n痛み：限界寸前"
		_danger_label.modulate = Color(1.0, 0.45, 0.45, 1.0)
	elif peak_pain >= 55.0:
		_danger_label.text = "[b]状態[/b]\n痛み：上昇中"
		_danger_label.modulate = Color(1.0, 0.82, 0.45, 1.0)
	else:
		_danger_label.text = "[b]状態[/b]\n痛み：安定"
		_danger_label.modulate = Color(0.75, 0.92, 0.85, 1.0)

func _set_gauge(gauge_id: String, current: float) -> void:
	var gauge: NamedGauge = _gauge_map.get(gauge_id)
	if gauge != null:
		gauge.set_gauge_value(current, 100.0)

func _on_end_day_pressed() -> void:
	GameAudio.play_se("ui_click")
	_finish_day(false)

func _update_brush_controls() -> void:
	_brushes.update_controls(_brush_name_label, _brush_spec_label)

func _get_combined_polish() -> float:
	return float(_slime_state["left"]["polish"]) + float(_slime_state["right"]["polish"])

func _check_finish() -> void:
	if _get_combined_polish() < finish_threshold:
		return
	_day_finish_count += 1
	var level := int(_species.get("level", 1))
	var retention_ratio := GameRules.retention_ratio(level)
	for side in ["left", "right"]:
		var state: Dictionary = _slime_state[side]
		state["polish"] = float(state["polish"]) * retention_ratio
		_slime_state[side] = state
	_start_finish_fx()

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
	state[key] = clampf(float(state[key]) + amount, 0.0, 100.0)
	_slime_state[side] = state

func debug_reset_gauges() -> void:
	_slime_state = {
		"left": {"polish": 0.0, "pain": 0.0},
		"right": {"polish": 0.0, "pain": 0.0}
	}

func debug_trigger_finish() -> void:
	if not _is_running or _is_finish_fx_active() or _is_fail_fx_active():
		return
	for side in ["left", "right"]:
		var state: Dictionary = _slime_state[side]
		state["polish"] = minf(finish_threshold * 0.5, 100.0)
		_slime_state[side] = state
	_check_finish()

func debug_trigger_fail() -> void:
	if not _is_running or _is_fail_fx_active():
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
	_clear_wax_drops()
	# デバッグの倍速を磨き画面の外へ持ち出さない。
	Engine.time_scale = 1.0
	GameAudio.update_loop("brush", "")
	GameAudio.update_loop("heartbeat", "")
	for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
		slime.set_hearts_active(false)
	var banked_finish := GameRules.banked_finish(_day_finish_count, failed_by_pain)
	day_finished.emit({
		"species_id": str(_species.get("id", "")),
		"species_name": CharacterDefs.display_name(_species),
		"day_finish_count": _day_finish_count,
		"banked_finish_count": banked_finish,
		"failed_by_pain": failed_by_pain
	})
