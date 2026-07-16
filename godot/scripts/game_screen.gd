extends Control

signal day_finished(result: Dictionary)

const ExpressionRules = preload("res://scripts/expression_rules.gd")

@export var follow_speed := 16.0
@export var finish_fx_duration := 5.0
@export var fail_fx_duration := 2.5

# FINISH演出が終わってから憔悴表情を保つ時間。
const EXHAUST_DURATION := 4.0

# 演出オーバーレイの色。FINISHは白ピンクの閃光、失敗は暗い赤の暗転。
const FINISH_FLASH_COLOR := Color(1.0, 0.88, 0.93)
const FAIL_FLASH_COLOR := Color(0.35, 0.02, 0.06)

# Level-driven; refreshed in setup_species.
var finish_threshold := GameRules.finish_threshold(1)

# 右パネル上部のブラシ置き場。開始・リセット時にブラシをここへ戻す。
const BRUSH_RACK_SLOTS := {
	"brush-a": Vector2(1050, 180),
	"brush-b": Vector2(1195, 180),
	"brush-c": Vector2(1050, 265),
	"brush-d": Vector2(1195, 265)
}

var _held_brush: Brush
var _finish_fx_time_left := 0.0
var _fail_fx_time_left := 0.0
var _exhaust_time_left := 0.0
var _current_expression := ""
var _gauge_map: Dictionary = {}
var _brush_map: Dictionary = {}
var _wall_zones: Array[WallZone] = []
var _slime_state := {
	"left": {"polish": 0.0, "pain": 0.0},
	"right": {"polish": 0.0, "pain": 0.0}
}
var _species: Dictionary = {}
var _day_finish_count := 0
var _is_running := false

var _brush_toggle_buttons: Dictionary = {}
var _brush_special_buttons: Dictionary = {}

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
@onready var _brush_button_rows: VBoxContainer = $Hud/Controls/BrushButtons
@onready var _left_slime: SlimeTarget = $Playfield/LeftSlime
@onready var _right_slime: SlimeTarget = $Playfield/RightSlime
@onready var _chara_image: TextureRect = $Playfield/CharaImage
@onready var _expression_label: Label = $Playfield/CharaImage/ExpressionLabel
@onready var _flash_rect: ColorRect = $FlashRect

func _ready() -> void:
	_collect_gauges()
	_collect_brushes()
	_collect_walls()
	_build_brush_controls()
	_configure_mouse_filters()
	_end_day_button.pressed.connect(_on_end_day_pressed)
	_update_gauges()
	_update_brush_controls()
	reset_day()

func _sorted_brush_ids() -> Array:
	var ids := _brush_map.keys()
	ids.sort()
	return ids

func _build_brush_controls() -> void:
	for brush_id: String in _sorted_brush_ids():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var toggle := Button.new()
		toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toggle.pressed.connect(_on_brush_toggle_pressed.bind(brush_id))
		row.add_child(toggle)
		var special := Button.new()
		special.pressed.connect(_on_brush_special_pressed.bind(brush_id))
		row.add_child(special)
		_brush_button_rows.add_child(row)
		_brush_toggle_buttons[brush_id] = toggle
		_brush_special_buttons[brush_id] = special

func _interactive_controls() -> Array[Control]:
	var controls: Array[Control] = [_end_day_button]
	for button: Button in _brush_toggle_buttons.values():
		controls.append(button)
	for button: Button in _brush_special_buttons.values():
		controls.append(button)
	return controls

func _configure_mouse_filters() -> void:
	# Keep only actionable controls (buttons) consuming mouse input.
	var interactive_controls := _interactive_controls()
	var interactive_set: Dictionary = {}
	for node in interactive_controls:
		interactive_set[node] = true
	for node in _find_control_descendants(self):
		if interactive_set.has(node):
			node.mouse_filter = Control.MOUSE_FILTER_STOP
		else:
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _find_control_descendants(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	for child in root.get_children():
		if child is Control:
			out.append(child)
		out.append_array(_find_control_descendants(child))
	return out

func _input(event: InputEvent) -> void:
	if not _is_running:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_over_interactive_ui(event.position):
			return
		if event.pressed:
			_pick_brush(event.position)
		else:
			_held_brush = null
	elif event is InputEventMouseMotion and _held_brush != null:
		_held_brush.position = _clamp_brush_to_playfield(_to_playfield_local(event.position), _held_brush)

func _is_over_interactive_ui(global_pos: Vector2) -> bool:
	for node in _interactive_controls():
		if node != null and node.get_global_rect().has_point(global_pos):
			return true
	return false

func _process(delta: float) -> void:
	if not _is_running:
		return
	if _held_brush != null:
		var local_mouse := _to_playfield_local(get_global_mouse_position())
		_held_brush.position = _held_brush.position.lerp(
			_clamp_brush_to_playfield(local_mouse, _held_brush),
			min(1.0, follow_speed * delta)
		)
	_update_finish_fx(delta)
	_update_fail_fx(delta)
	_exhaust_time_left = maxf(0.0, _exhaust_time_left - delta)
	if not _is_finish_fx_active() and not _is_fail_fx_active():
		for brush in _brush_map.values():
			if brush.is_active:
				_apply_brush_effects(brush, delta)
	_update_slime_squish(delta)
	_resolve_brush_overlaps()
	_apply_wall_push_out()
	_apply_slime_push_out()
	if not _is_finish_fx_active() and not _is_fail_fx_active():
		_check_finish()
		_check_failure()
	_update_expression()
	_update_gauges()
	_update_brush_controls()

func setup_species(species: Dictionary) -> void:
	_species = species.duplicate(true)
	_title_label.text = str(_species.get("name", "スライム"))
	var left_config: Dictionary = _species.get("left", {})
	var right_config: Dictionary = _species.get("right", {})
	_apply_slime_layout(_left_slime, left_config)
	_apply_slime_layout(_right_slime, right_config)
	_left_slime.apply_species(_species, "L", left_config)
	_right_slime.apply_species(_species, "R", right_config)
	var level := int(_species.get("level", 1))
	finish_threshold = GameRules.finish_threshold(level)
	_apply_brush_unlocks(level)
	_meta_label.text = "LV %d" % level
	_day_label.text = "1日目"
	reset_day()

func _apply_brush_unlocks(level: int) -> void:
	for brush: Brush in _brush_map.values():
		var unlocked := GameRules.is_brush_unlocked(brush.brush_id, level)
		brush.visible = unlocked
		if not unlocked:
			brush.is_active = false
			brush.special_time_left = 0.0

func _apply_slime_layout(slime: SlimeTarget, cfg: Dictionary) -> void:
	var pos_variant: Variant = cfg.get("position", null)
	if pos_variant is Vector2:
		slime.position = pos_variant

func _is_finish_fx_active() -> bool:
	return _finish_fx_time_left > 0.0

func _start_finish_fx() -> void:
	_finish_fx_time_left = finish_fx_duration
	_finish_label.visible = true
	_finish_label.pivot_offset = _finish_label.size / 2.0
	_finish_label.scale = Vector2(0.4, 0.4)
	var tween := create_tween()
	tween.tween_property(_finish_label, "scale", Vector2(1.3, 1.3), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_finish_label, "scale", Vector2.ONE, 0.3)
	for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
		slime.burst_hearts()

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
	_held_brush = null
	for brush: Brush in _brush_map.values():
		brush.is_active = false

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
	_held_brush = null
	_finish_fx_time_left = 0.0
	_fail_fx_time_left = 0.0
	_exhaust_time_left = 0.0
	_current_expression = ""
	_finish_label.visible = false
	_finish_label.scale = Vector2.ONE
	_clear_fx_overlay()
	_slime_state = {
		"left": {"polish": 0.0, "pain": 0.0},
		"right": {"polish": 0.0, "pain": 0.0}
	}
	for brush: Brush in _brush_map.values():
		brush.is_active = false
		brush.special_time_left = 0.0
		if BRUSH_RACK_SLOTS.has(brush.brush_id):
			brush.position = BRUSH_RACK_SLOTS[brush.brush_id]
	for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
		slime.reset_pressure()
		slime.set_hearts_active(false)
	_update_expression()
	_update_gauges()
	_update_brush_controls()

func _collect_gauges() -> void:
	for gauge in get_tree().get_nodes_in_group("named_gauges"):
		_gauge_map[gauge.gauge_id] = gauge

func _collect_brushes() -> void:
	for brush in get_tree().get_nodes_in_group("brushes"):
		_brush_map[brush.brush_id] = brush

func _collect_walls() -> void:
	_wall_zones.clear()
	for wall: WallZone in get_tree().get_nodes_in_group("wall_zones"):
		_wall_zones.append(wall)

func _pick_brush(mouse_position: Vector2) -> void:
	var local_mouse := _to_playfield_local(mouse_position)
	var nearest: Brush
	var nearest_distance: float = INF
	for brush: Brush in _brush_map.values():
		if not brush.visible:
			continue
		var distance: float = brush.position.distance_to(local_mouse)
		if distance <= brush.hit_radius * 1.4 and distance < nearest_distance:
			nearest = brush
			nearest_distance = distance
	_held_brush = nearest

func _update_slime_squish(delta: float) -> void:
	# Pressure depth uses the base radius so the spring has a stable input.
	for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
		var deepest := 0.0
		var touched_by_active := false
		for brush: Brush in _brush_map.values():
			if not brush.visible:
				continue
			var overlap: float = brush.hit_radius + slime.radius - brush.global_position.distance_to(slime.global_position)
			deepest = maxf(deepest, overlap)
			if brush.is_active and overlap > 0.0:
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
			state["polish"] = clamp(float(state.get("polish", 0.0)) + brush.get_effective_polish_gain() * polish_bonus * delta, 0.0, 100.0)
			state["pain"] = clamp(float(state.get("pain", 0.0)) + brush.get_effective_pain_gain() * pain_resist * delta * 0.35, 0.0, 100.0)
			_slime_state[side] = state

## アクティブなブラシの接触状態と、いま掛かっている上昇量/秒（補正込み）。
func _compute_touch_info() -> Dictionary:
	var touching := false
	var polish_rate := 0.0
	var pain_rate := 0.0
	var level := int(_species.get("level", 1))
	var polish_bonus := GameRules.polish_bonus(level)
	var pain_resist := GameRules.pain_resist(level)
	for brush: Brush in _brush_map.values():
		if not brush.visible or not brush.is_active:
			continue
		for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
			if brush.global_position.distance_to(slime.global_position) <= brush.hit_radius + slime.get_hit_radius():
				touching = true
				# _apply_brush_effects と同じ係数で「ゲージが実際に動く速さ」を比較する。
				polish_rate += brush.get_effective_polish_gain() * polish_bonus
				pain_rate += brush.get_effective_pain_gain() * pain_resist * 0.35
	return {"touching": touching, "polish_rate": polish_rate, "pain_rate": pain_rate}

func _update_expression() -> void:
	var info := _compute_touch_info()
	var expression := ExpressionRules.pick({
		"touching": bool(info["touching"]),
		"polish_ratio": _get_combined_polish() / maxf(finish_threshold, 0.001),
		"polish_rate": float(info["polish_rate"]),
		"pain_rate": float(info["pain_rate"]),
		"climax": _is_finish_fx_active(),
		"despair": _is_fail_fx_active(),
		"exhausted": _exhaust_time_left > 0.0
	})
	_apply_expression(expression)

func _apply_expression(expression_id: String) -> void:
	if expression_id == _current_expression:
		return
	_current_expression = expression_id
	var texture := _resolve_expression_texture(expression_id)
	_chara_image.texture = texture
	_expression_label.visible = texture == null
	_expression_label.text = "立ち絵：%s" % ExpressionRules.display_name(expression_id)

## キャラ定義の expressions 辞書を優先し、無ければ既定パス
## assets/chara/<キャラid>/<表情id>.png を探す。どちらも無ければ null。
func _resolve_expression_texture(expression_id: String) -> Texture2D:
	var expressions: Dictionary = _species.get("expressions", {})
	var path := str(expressions.get(expression_id, ""))
	if path == "":
		path = ExpressionRules.default_image_path(str(_species.get("id", "")), expression_id)
	if ResourceLoader.exists(path):
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

func _to_playfield_local(global_position: Vector2) -> Vector2:
	return _playfield.get_global_transform().affine_inverse() * global_position

func _on_end_day_pressed() -> void:
	_finish_day(false)

func _on_brush_toggle_pressed(brush_id: String) -> void:
	var brush: Brush = _brush_map.get(brush_id)
	if brush == null or not brush.visible:
		return
	brush.is_active = not brush.is_active
	_update_brush_controls()

func _on_brush_special_pressed(brush_id: String) -> void:
	var brush: Brush = _brush_map.get(brush_id)
	if brush == null or not brush.visible:
		return
	brush.trigger_special()
	_update_brush_controls()

func _update_brush_controls() -> void:
	for brush_id: String in _brush_toggle_buttons:
		var brush: Brush = _brush_map.get(brush_id)
		if brush == null:
			continue
		var toggle: Button = _brush_toggle_buttons[brush_id]
		var special: Button = _brush_special_buttons[brush_id]
		var locked := not brush.visible
		toggle.disabled = locked
		special.disabled = locked
		if locked:
			toggle.text = "%s: Lv%d解禁" % [_brush_display_name(brush), GameRules.brush_unlock_level(brush_id)]
			special.text = "特殊技"
		else:
			toggle.text = "%s: %s" % [_brush_display_name(brush), "ON" if brush.is_active else "OFF"]
			special.text = "特殊技*" if brush.is_special_active() else "特殊技"
	var selected_brush: Brush = _held_brush
	if selected_brush == null:
		for brush_id: String in _sorted_brush_ids():
			var brush: Brush = _brush_map[brush_id]
			if brush.visible:
				selected_brush = brush
				break
	if selected_brush != null:
		_brush_name_label.text = _brush_display_name(selected_brush)
		_brush_spec_label.text = "快感 %d / 痛み %d / サイズ %d" % [
			int(round(selected_brush.polish_gain_per_sec)),
			int(round(selected_brush.pain_gain_per_sec)),
			int(round(selected_brush.hit_radius))
		]

func _brush_display_name(brush: Brush) -> String:
	if brush.display_name != "":
		return brush.display_name
	return brush.brush_id.capitalize().replace("-", " ")

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

func _resolve_brush_overlaps() -> void:
	var brushes: Array[Brush] = []
	for brush: Brush in _brush_map.values():
		if brush.visible:
			brushes.append(brush)
	for i in range(brushes.size()):
		for j in range(i + 1, brushes.size()):
			var a := brushes[i]
			var b := brushes[j]
			var delta := b.position - a.position
			var distance := delta.length()
			var min_dist := a.hit_radius + b.hit_radius
			if distance <= 0.0001:
				delta = Vector2.RIGHT
				distance = 1.0
			if distance < min_dist:
				var push := delta.normalized() * ((min_dist - distance) * 0.5)
				a.position = _clamp_brush_to_playfield(a.position - push, a)
				b.position = _clamp_brush_to_playfield(b.position + push, b)

func _apply_wall_push_out() -> void:
	if _wall_zones.is_empty():
		return
	for brush: Brush in _brush_map.values():
		if not brush.visible:
			continue
		for wall in _wall_zones:
			brush.position = GameRules.push_out_from_rect(brush.position, brush.hit_radius, wall.get_rect())

func _apply_slime_push_out() -> void:
	# Brushes can sink into the squished radius but never pass through.
	for brush: Brush in _brush_map.values():
		if not brush.visible:
			continue
		for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
			var min_dist: float = brush.hit_radius + slime.get_hit_radius()
			var delta_vec: Vector2 = brush.position - slime.position
			var dist := delta_vec.length()
			if dist >= min_dist:
				continue
			if dist <= 0.0001:
				delta_vec = Vector2.RIGHT
			brush.position = _clamp_brush_to_playfield(
				slime.position + delta_vec.normalized() * min_dist,
				brush
			)

func _clamp_brush_to_playfield(local_pos: Vector2, brush: Brush) -> Vector2:
	var play_rect := Rect2(Vector2.ZERO, _playfield.size)
	return Vector2(
		clampf(local_pos.x, play_rect.position.x + brush.hit_radius, play_rect.end.x - brush.hit_radius),
		clampf(local_pos.y, play_rect.position.y + brush.hit_radius, play_rect.end.y - brush.hit_radius)
	)

func _finish_day(failed_by_pain: bool) -> void:
	if not _is_running:
		return
	_is_running = false
	for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
		slime.set_hearts_active(false)
	var banked_finish := GameRules.banked_finish(_day_finish_count, failed_by_pain)
	day_finished.emit({
		"species_id": str(_species.get("id", "")),
		"species_name": str(_species.get("name", "Slime")),
		"day_finish_count": _day_finish_count,
		"banked_finish_count": banked_finish,
		"failed_by_pain": failed_by_pain
	})
