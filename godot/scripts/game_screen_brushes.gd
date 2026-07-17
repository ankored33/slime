class_name GameScreenBrushes
extends RefCounted

## Brush-side runtime for GameScreen: discovery, input, controls, unlocks and collision correction.

const GameRules = preload("res://scripts/game_rules.gd")

## HUDで未選択時に表示する順序。シーンのブラシ棚と同じ並びにする。
const BRUSH_DISPLAY_ORDER: Array[String] = [
	"finger", "tongue", "feather", "fude", "teeth",
	"toothbrush", "rotary", "tawashi", "candle"
]

var brush_map: Dictionary = {}
var held_brush: Brush

var _wall_zones: Array[WallZone] = []
var _playfield: Control
var _brush_rack: Control
var _end_day_button: Button
var _extra_interactive: Array[Control] = []

func setup(root: Control, playfield: Control, brush_rack: Control, end_day_button: Button) -> void:
	_playfield = playfield
	_brush_rack = brush_rack
	_end_day_button = end_day_button
	_collect_nodes(root)
	_configure_mouse_filters(root)

func _collect_nodes(root: Node) -> void:
	brush_map.clear()
	_wall_zones.clear()
	for brush in root.get_tree().get_nodes_in_group("brushes"):
		brush_map[brush.brush_id] = brush
	for wall: WallZone in root.get_tree().get_nodes_in_group("wall_zones"):
		_wall_zones.append(wall)

func _display_ordered_ids() -> Array[String]:
	var ids: Array[String] = []
	for brush_id in BRUSH_DISPLAY_ORDER:
		if brush_map.has(brush_id):
			ids.append(brush_id)
	var extras := brush_map.keys()
	extras.sort()
	for brush_id: String in extras:
		if not ids.has(brush_id):
			ids.append(brush_id)
	return ids

## セットアップ後に追加されるUI（デバッグパネル等）をクリック透過の対象外にする。
func register_interactive(control: Control) -> void:
	_extra_interactive.append(control)

func _interactive_controls() -> Array[Control]:
	var controls: Array[Control] = [_end_day_button]
	controls.append_array(_extra_interactive)
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

## 通常の持ち替えを処理し、右クリック時は保持中の道具に対応する固有アクションを返す。
func handle_input(event: InputEvent) -> Dictionary:
	if not (event is InputEventMouseButton and event.pressed):
		return {}
	if _is_over_interactive_ui(event.position):
		return {}
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if held_brush == null:
			return {}
		if held_brush.brush_id == "candle":
			return {"wax_origin": held_brush.position + Vector2(0.0, held_brush.hit_radius * 0.7)}
		if held_brush.brush_id == "teeth":
			return {"bite_requested": true}
		return {}
	if event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_held_brush(_pick_brush(event.position))
	return {}

func _is_over_interactive_ui(global_pos: Vector2) -> bool:
	for node in _interactive_controls():
		if node != null and node.is_visible_in_tree() \
				and node.get_global_rect().has_point(global_pos):
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

func _pick_brush(mouse_position: Vector2) -> Brush:
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
	return nearest

func _toggle_held_brush(brush: Brush) -> void:
	if brush == null:
		return
	if held_brush == brush:
		_set_held_brush(null)
	else:
		_set_held_brush(brush)

func _set_held_brush(brush: Brush) -> void:
	if held_brush == brush:
		return
	if held_brush != null:
		held_brush.is_held = false
		# 回転ブラシはプレイ領域に置いた時だけ自動回転を始める。
		if held_brush.is_rotating:
			held_brush.is_active = not _is_brush_in_rack(held_brush)
	held_brush = brush
	if held_brush != null:
		held_brush.is_held = true
		# 持ち上げている間は回転を止める。
		if held_brush.is_rotating:
			held_brush.is_active = false

func _is_brush_in_rack(brush: Brush) -> bool:
	if _brush_rack == null:
		return false
	# 円全体が棚の内側に収まっている場合だけ収納扱いにする。
	return _brush_rack.get_rect().grow(-brush.hit_radius).has_point(brush.position)

func _to_playfield_local(global_position: Vector2) -> Vector2:
	return _playfield.get_global_transform().affine_inverse() * global_position

func apply_unlocks(level: int) -> void:
	for brush: Brush in brush_map.values():
		var unlocked := GameRules.is_brush_unlocked(brush.brush_id, level)
		brush.visible = unlocked
		if not unlocked:
			brush.is_active = false
			brush.is_held = false
			if held_brush == brush:
				_set_held_brush(null)

func reset(rack_slots: Dictionary) -> void:
	_set_held_brush(null)
	for brush: Brush in brush_map.values():
		brush.is_active = false
		brush.is_held = false
		if rack_slots.has(brush.brush_id):
			brush.position = rack_slots[brush.brush_id]

func deactivate_all() -> void:
	_set_held_brush(null)
	for brush: Brush in brush_map.values():
		brush.is_active = false
		brush.is_held = false

func get_brush(brush_id: String) -> Brush:
	return brush_map.get(brush_id)

func update_controls(name_label: Label, spec_label: Label) -> void:
	var selected_brush := held_brush
	if selected_brush == null:
		for brush_id: String in _display_ordered_ids():
			var brush: Brush = brush_map[brush_id]
			if brush.visible:
				selected_brush = brush
				break
	if selected_brush == null:
		return
	name_label.text = _display_name(selected_brush)
	if selected_brush == held_brush:
		name_label.text += " [保持中]"
	if selected_brush.brush_id == "candle":
		spec_label.text = "磨き効果なし / 保持して右クリック：ろうを落とす"
		return
	if selected_brush.brush_id == "teeth":
		spec_label.text = "磨き効果なし / 接触中に右クリック：噛む（痛み %d）" % int(GameRules.BITE_PAIN_IMPACT)
		return
	var spec := "快感 %d / 痛み %d" % [
		int(round(selected_brush.polish_gain_per_sec)),
		int(round(selected_brush.pain_gain_per_sec))
	]
	if selected_brush.pain_soothe_per_sec > 0.0:
		spec += " / 癒し %d" % int(round(selected_brush.pain_soothe_per_sec))
	spec += " / サイズ %d" % int(round(selected_brush.hit_radius))
	if selected_brush.is_rotating:
		spec += " / 置くと自動回転"
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
