class_name GameScreenBrushes
extends RefCounted

## Brush-side runtime for GameScreen: discovery, input, controls, unlocks and collision correction.

const GameRules = preload("res://scripts/game_rules.gd")

var brush_map: Dictionary = {}
var held_brush: Brush

var _wall_zones: Array[WallZone] = []
var _toggle_buttons: Dictionary = {}
var _special_buttons: Dictionary = {}
var _playfield: Control
var _button_rows: VBoxContainer
var _end_day_button: Button

func setup(
	root: Control,
	playfield: Control,
	button_rows: VBoxContainer,
	end_day_button: Button,
	toggle_callback: Callable,
	special_callback: Callable
) -> void:
	_playfield = playfield
	_button_rows = button_rows
	_end_day_button = end_day_button
	_collect_nodes(root)
	_build_controls(toggle_callback, special_callback)
	_configure_mouse_filters(root)

func _collect_nodes(root: Node) -> void:
	brush_map.clear()
	_wall_zones.clear()
	for brush in root.get_tree().get_nodes_in_group("brushes"):
		brush_map[brush.brush_id] = brush
	for wall: WallZone in root.get_tree().get_nodes_in_group("wall_zones"):
		_wall_zones.append(wall)

func _sorted_ids() -> Array:
	var ids := brush_map.keys()
	ids.sort()
	return ids

func _build_controls(toggle_callback: Callable, special_callback: Callable) -> void:
	for brush_id: String in _sorted_ids():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var toggle := Button.new()
		toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		toggle.pressed.connect(toggle_callback.bind(brush_id))
		row.add_child(toggle)
		var special := Button.new()
		special.pressed.connect(special_callback.bind(brush_id))
		row.add_child(special)
		_button_rows.add_child(row)
		_toggle_buttons[brush_id] = toggle
		_special_buttons[brush_id] = special

func _interactive_controls() -> Array[Control]:
	var controls: Array[Control] = [_end_day_button]
	for button: Button in _toggle_buttons.values():
		controls.append(button)
	for button: Button in _special_buttons.values():
		controls.append(button)
	return controls

func _configure_mouse_filters(root: Node) -> void:
	var interactive_set: Dictionary = {}
	for node in _interactive_controls():
		interactive_set[node] = true
	for node in _find_control_descendants(root):
		node.mouse_filter = (
			Control.MOUSE_FILTER_STOP if interactive_set.has(node)
			else Control.MOUSE_FILTER_IGNORE
		)

func _find_control_descendants(root: Node) -> Array[Control]:
	var out: Array[Control] = []
	for child in root.get_children():
		if child is Control:
			out.append(child)
		out.append_array(_find_control_descendants(child))
	return out

func handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_over_interactive_ui(event.position):
			return
		if event.pressed:
			_pick_brush(event.position)
		else:
			held_brush = null
	elif event is InputEventMouseMotion and held_brush != null:
		held_brush.position = clamp_to_playfield(_to_playfield_local(event.position), held_brush)

func _is_over_interactive_ui(global_pos: Vector2) -> bool:
	for node in _interactive_controls():
		if node != null and node.get_global_rect().has_point(global_pos):
			return true
	return false

func update_drag(global_mouse_position: Vector2, follow_speed: float, delta: float) -> void:
	if held_brush == null:
		return
	var local_mouse := _to_playfield_local(global_mouse_position)
	held_brush.position = held_brush.position.lerp(
		clamp_to_playfield(local_mouse, held_brush),
		minf(1.0, follow_speed * delta)
	)

func _pick_brush(mouse_position: Vector2) -> void:
	var local_mouse := _to_playfield_local(mouse_position)
	var nearest: Brush
	var nearest_distance: float = INF
	for brush: Brush in brush_map.values():
		if not brush.visible:
			continue
		var distance: float = brush.position.distance_to(local_mouse)
		if distance <= brush.hit_radius * 1.4 and distance < nearest_distance:
			nearest = brush
			nearest_distance = distance
	held_brush = nearest

func _to_playfield_local(global_position: Vector2) -> Vector2:
	return _playfield.get_global_transform().affine_inverse() * global_position

func apply_unlocks(level: int) -> void:
	for brush: Brush in brush_map.values():
		var unlocked := GameRules.is_brush_unlocked(brush.brush_id, level)
		brush.visible = unlocked
		if not unlocked:
			brush.is_active = false
			brush.special_time_left = 0.0

func reset(rack_slots: Dictionary) -> void:
	held_brush = null
	for brush: Brush in brush_map.values():
		brush.is_active = false
		brush.special_time_left = 0.0
		if rack_slots.has(brush.brush_id):
			brush.position = rack_slots[brush.brush_id]

func deactivate_all() -> void:
	held_brush = null
	for brush: Brush in brush_map.values():
		brush.is_active = false

func get_brush(brush_id: String) -> Brush:
	return brush_map.get(brush_id)

func update_controls(name_label: Label, spec_label: Label) -> void:
	for brush_id: String in _toggle_buttons:
		var brush: Brush = brush_map.get(brush_id)
		if brush == null:
			continue
		var toggle: Button = _toggle_buttons[brush_id]
		var special: Button = _special_buttons[brush_id]
		var locked := not brush.visible
		toggle.disabled = locked
		special.disabled = locked
		if locked:
			toggle.text = "%s: Lv%d解禁" % [_display_name(brush), GameRules.brush_unlock_level(brush_id)]
			special.text = "特殊技"
		else:
			toggle.text = "%s: %s" % [_display_name(brush), "ON" if brush.is_active else "OFF"]
			special.text = "特殊技*" if brush.is_special_active() else "特殊技"
	var selected_brush := held_brush
	if selected_brush == null:
		for brush_id: String in _sorted_ids():
			var brush: Brush = brush_map[brush_id]
			if brush.visible:
				selected_brush = brush
				break
	if selected_brush == null:
		return
	name_label.text = _display_name(selected_brush)
	var spec := "快感 %d / 痛み %d" % [
		int(round(selected_brush.polish_gain_per_sec)),
		int(round(selected_brush.pain_gain_per_sec))
	]
	if selected_brush.pain_soothe_per_sec > 0.0:
		spec += " / 癒し %d" % int(round(selected_brush.pain_soothe_per_sec))
	spec += " / サイズ %d" % int(round(selected_brush.hit_radius))
	spec_label.text = spec

func _display_name(brush: Brush) -> String:
	if brush.display_name != "":
		return brush.display_name
	return brush.brush_id.capitalize().replace("-", " ")

func resolve_collisions(slimes: Array[Node]) -> void:
	_resolve_brush_overlaps()
	_apply_wall_push_out()
	_apply_slime_push_out(slimes)

func _resolve_brush_overlaps() -> void:
	var brushes: Array[Brush] = []
	for brush: Brush in brush_map.values():
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
				a.position = clamp_to_playfield(a.position - push, a)
				b.position = clamp_to_playfield(b.position + push, b)

func _apply_wall_push_out() -> void:
	for brush: Brush in brush_map.values():
		if not brush.visible:
			continue
		for wall in _wall_zones:
			brush.position = GameRules.push_out_from_rect(brush.position, brush.hit_radius, wall.get_rect())

func _apply_slime_push_out(slimes: Array[Node]) -> void:
	for brush: Brush in brush_map.values():
		if not brush.visible:
			continue
		for slime: SlimeTarget in slimes:
			var min_dist: float = brush.hit_radius + slime.get_hit_radius()
			var delta_vec: Vector2 = brush.position - slime.position
			var dist := delta_vec.length()
			if dist >= min_dist:
				continue
			if dist <= 0.0001:
				delta_vec = Vector2.RIGHT
			brush.position = clamp_to_playfield(
				slime.position + delta_vec.normalized() * min_dist,
				brush
			)

func clamp_to_playfield(local_pos: Vector2, brush: Brush) -> Vector2:
	var play_rect := Rect2(Vector2.ZERO, _playfield.size)
	return Vector2(
		clampf(local_pos.x, play_rect.position.x + brush.hit_radius, play_rect.end.x - brush.hit_radius),
		clampf(local_pos.y, play_rect.position.y + brush.hit_radius, play_rect.end.y - brush.hit_radius)
	)
