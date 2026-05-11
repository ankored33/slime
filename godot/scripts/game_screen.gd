extends Control

signal day_finished(result: Dictionary)

@export var follow_speed := 16.0
@export var finish_threshold := 160.0

var _held_brush: Brush
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

@onready var _playfield: Control = $Playfield
@onready var _debug_label: Label = $Hud/DebugLabel
@onready var _title_label: Label = $Hud/CharaNameLabel
@onready var _meta_label: Label = $Hud/LevelLabel
@onready var _danger_label: RichTextLabel = $Hud/ConditionLabel
@onready var _day_label: Label = $Hud/DayLabel
@onready var _brush_name_label: Label = $Hud/BrushNameLabel
@onready var _brush_spec_label: Label = $Hud/BrushSpecLabel
@onready var _finish_progress: ProgressBar = $Hud/FinishProgress
@onready var _day_finish_label: Label = $Hud/DayStats/Margin/FinishCount
@onready var _end_day_button: Button = $Hud/Controls/EndDayButton
@onready var _brush_a_toggle: Button = $Hud/Controls/BrushAToggle
@onready var _brush_b_toggle: Button = $Hud/Controls/BrushBToggle
@onready var _brush_a_special: Button = $Hud/Controls/BrushASpecial
@onready var _brush_b_special: Button = $Hud/Controls/BrushBSpecial
@onready var _left_slime: SlimeTarget = $Playfield/LeftSlime
@onready var _right_slime: SlimeTarget = $Playfield/RightSlime

func _ready() -> void:
	_configure_mouse_filters()
	_collect_gauges()
	_collect_brushes()
	_collect_walls()
	_end_day_button.pressed.connect(_on_end_day_pressed)
	_brush_a_toggle.pressed.connect(_on_brush_toggle_pressed.bind("brush-a"))
	_brush_b_toggle.pressed.connect(_on_brush_toggle_pressed.bind("brush-b"))
	_brush_a_special.pressed.connect(_on_brush_special_pressed.bind("brush-a"))
	_brush_b_special.pressed.connect(_on_brush_special_pressed.bind("brush-b"))
	_update_gauges()
	_update_brush_controls()
	_refresh_debug_text()
	reset_day()

func _configure_mouse_filters() -> void:
	# Keep only actionable controls (buttons) consuming mouse input.
	var interactive_controls: Array[Control] = [
		_end_day_button,
		_brush_a_toggle,
		_brush_b_toggle,
		_brush_a_special,
		_brush_b_special
	]
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
	var interactive_controls: Array[Control] = [
		_end_day_button,
		_brush_a_toggle,
		_brush_b_toggle,
		_brush_a_special,
		_brush_b_special
	]
	for node in interactive_controls:
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
	for brush in _brush_map.values():
		if brush.is_active:
			_apply_brush_effects(brush, delta)
	if _held_brush != null and not _held_brush.is_active:
		_apply_brush_effects(_held_brush, delta * 0.3)
	_resolve_brush_overlaps()
	_apply_wall_push_out()
	_check_finish()
	_check_failure()
	_update_gauges()
	_update_brush_controls()
	_refresh_debug_text()

func setup_species(species: Dictionary) -> void:
	_species = species.duplicate(true)
	_title_label.text = str(_species.get("name", "Slime"))
	var left_config: Dictionary = _species.get("left", {})
	var right_config: Dictionary = _species.get("right", {})
	_apply_slime_layout(_left_slime, left_config)
	_apply_slime_layout(_right_slime, right_config)
	_left_slime.apply_species(_species, "L", left_config)
	_right_slime.apply_species(_species, "R", right_config)
	_meta_label.text = "LV %d" % int(_species.get("level", 1))
	_day_label.text = "1 Day"
	reset_day()

func _apply_slime_layout(slime: SlimeTarget, cfg: Dictionary) -> void:
	var pos_variant: Variant = cfg.get("position", null)
	if pos_variant is Vector2:
		slime.position = pos_variant

func reset_day() -> void:
	_day_finish_count = 0
	_is_running = true
	_held_brush = null
	_slime_state = {
		"left": {"polish": 0.0, "pain": 0.0},
		"right": {"polish": 0.0, "pain": 0.0}
	}
	for brush in _brush_map.values():
		brush.is_active = false
		brush.special_time_left = 0.0
	_update_gauges()
	_update_brush_controls()
	_refresh_debug_text()

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
		var distance: float = brush.position.distance_to(local_mouse)
		if distance <= brush.hit_radius * 1.4 and distance < nearest_distance:
			nearest = brush
			nearest_distance = distance
	_held_brush = nearest

func _apply_brush_effects(brush: Brush, delta: float) -> void:
	for slime: SlimeTarget in get_tree().get_nodes_in_group("slime_targets"):
		if brush.global_position.distance_to(slime.global_position) <= brush.hit_radius + slime.get_hit_radius():
			var side := String(slime.side)
			var state: Dictionary = _slime_state.get(side, {})
			var level := int(_species.get("level", 1))
			var polish_bonus: float = 1.0 + float(max(0, level - 1)) * 0.08
			var pain_resist: float = maxf(0.45, 1.0 - float(max(0, level - 1)) * 0.04)
			state["polish"] = clamp(float(state.get("polish", 0.0)) + brush.get_effective_polish_gain() * polish_bonus * delta, 0.0, 100.0)
			state["pain"] = clamp(float(state.get("pain", 0.0)) + brush.get_effective_pain_gain() * pain_resist * delta * 0.35, 0.0, 100.0)
			_slime_state[side] = state

func _update_gauges() -> void:
	_set_gauge("polish-L", _slime_state["left"]["polish"])
	_set_gauge("pain-L", _slime_state["left"]["pain"])
	_set_gauge("polish-R", _slime_state["right"]["polish"])
	_set_gauge("pain-R", _slime_state["right"]["pain"])
	_finish_progress.max_value = finish_threshold
	_finish_progress.value = _get_combined_polish()
	_day_finish_label.text = "Today Finish: %d" % _day_finish_count
	var peak_pain: float = maxf(float(_slime_state["left"]["pain"]), float(_slime_state["right"]["pain"]))
	if peak_pain >= 80.0:
		_danger_label.text = "[b]Condition[/b]\nPain critical"
		_danger_label.modulate = Color(1.0, 0.45, 0.45, 1.0)
	elif peak_pain >= 55.0:
		_danger_label.text = "[b]Condition[/b]\nPain rising"
		_danger_label.modulate = Color(1.0, 0.82, 0.45, 1.0)
	else:
		_danger_label.text = "[b]Condition[/b]\nPain stable"
		_danger_label.modulate = Color(0.75, 0.92, 0.85, 1.0)

func _set_gauge(gauge_id: String, current: float) -> void:
	var gauge: NamedGauge = _gauge_map.get(gauge_id)
	if gauge != null:
		gauge.set_gauge_value(current, 100.0)

func _refresh_debug_text() -> void:
	_debug_label.text = "Status\nDrag brushes to reposition.\nCombined polish: %d / %d\nPain updates in real time." % [
		int(round(_get_combined_polish())),
		int(round(finish_threshold))
	]

func _to_playfield_local(global_position: Vector2) -> Vector2:
	return _playfield.get_global_transform().affine_inverse() * global_position

func _on_end_day_pressed() -> void:
	_finish_day(false)

func _on_brush_toggle_pressed(brush_id: String) -> void:
	var brush: Brush = _brush_map.get(brush_id)
	if brush == null:
		return
	brush.is_active = not brush.is_active
	_update_brush_controls()

func _on_brush_special_pressed(brush_id: String) -> void:
	var brush: Brush = _brush_map.get(brush_id)
	if brush == null:
		return
	brush.trigger_special()
	_update_brush_controls()

func _update_brush_controls() -> void:
	var brush_a: Brush = _brush_map.get("brush-a")
	var brush_b: Brush = _brush_map.get("brush-b")
	if brush_a != null:
		_brush_a_toggle.text = "Brush A: ON" if brush_a.is_active else "Brush A: OFF"
		_brush_a_special.text = "Brush A Special*" if brush_a.is_special_active() else "Brush A Special"
	if brush_b != null:
		_brush_b_toggle.text = "Brush B: ON" if brush_b.is_active else "Brush B: OFF"
		_brush_b_special.text = "Brush B Special*" if brush_b.is_special_active() else "Brush B Special"
	var selected_brush: Brush = _held_brush if _held_brush != null else brush_a
	if selected_brush != null:
		_brush_name_label.text = selected_brush.brush_id.capitalize().replace("-", " ")
		_brush_spec_label.text = "Polish %d / Pain %d / Size %d" % [
			int(round(selected_brush.polish_gain_per_sec)),
			int(round(selected_brush.pain_gain_per_sec)),
			int(round(selected_brush.hit_radius))
		]

func _get_combined_polish() -> float:
	return float(_slime_state["left"]["polish"]) + float(_slime_state["right"]["polish"])

func _check_finish() -> void:
	if _get_combined_polish() < finish_threshold:
		return
	_day_finish_count += 1
	var level := int(_species.get("level", 1))
	var retention_ratio: float = minf(0.6, float(max(0, level - 1)) * 0.08)
	for side in ["left", "right"]:
		var state: Dictionary = _slime_state[side]
		state["polish"] = float(state["polish"]) * retention_ratio
		_slime_state[side] = state

func _check_failure() -> void:
	var peak_pain: float = maxf(float(_slime_state["left"]["pain"]), float(_slime_state["right"]["pain"]))
	if peak_pain >= 100.0:
		_finish_day(true)

func _resolve_brush_overlaps() -> void:
	var brushes: Array[Brush] = []
	for brush: Brush in _brush_map.values():
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
		for wall in _wall_zones:
			brush.position = _push_out_from_rect(brush.position, brush.hit_radius, wall.get_rect())

func _push_out_from_rect(center: Vector2, radius: float, rect: Rect2) -> Vector2:
	var nearest := Vector2(
		clampf(center.x, rect.position.x, rect.position.x + rect.size.x),
		clampf(center.y, rect.position.y, rect.position.y + rect.size.y)
	)
	var delta := center - nearest
	var distance := delta.length()
	if distance >= radius:
		return center
	if distance > 0.0001:
		return center + delta.normalized() * (radius - distance)

	# Exact overlap on rect edge or inside; escape through the shortest axis.
	var left_gap := absf(center.x - rect.position.x)
	var right_gap := absf((rect.position.x + rect.size.x) - center.x)
	var top_gap := absf(center.y - rect.position.y)
	var bottom_gap := absf((rect.position.y + rect.size.y) - center.y)
	var min_gap := minf(minf(left_gap, right_gap), minf(top_gap, bottom_gap))
	if min_gap == left_gap:
		return Vector2(rect.position.x - radius, center.y)
	if min_gap == right_gap:
		return Vector2(rect.position.x + rect.size.x + radius, center.y)
	if min_gap == top_gap:
		return Vector2(center.x, rect.position.y - radius)
	return Vector2(center.x, rect.position.y + rect.size.y + radius)

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
	var banked_finish := _day_finish_count
	if failed_by_pain:
		banked_finish = int(floor(float(_day_finish_count) * 0.5))
	day_finished.emit({
		"species_id": str(_species.get("id", "")),
		"species_name": str(_species.get("name", "Slime")),
		"day_finish_count": _day_finish_count,
		"banked_finish_count": banked_finish,
		"failed_by_pain": failed_by_pain
	})
