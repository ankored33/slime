class_name GameScreenBrushes
extends RefCounted

## Brush-side runtime for GameScreen: discovery, input, controls, unlocks and collision correction.

const GameRules = preload("res://scripts/game_rules.gd")

## ツールボックスのボタン表示順。HUDで未選択時に表示する順序も兼ねる。
const BRUSH_DISPLAY_ORDER: Array[String] = [
	"finger", "tongue", "feather", "fude", "teeth",
	"toothbrush", "rotary", "rotor", "tawashi", "candle", "clip"
]

var brush_map: Dictionary = {}
var held_brush: Brush

var _wall_zones: Array[WallZone] = []
var _playfield: Control
var _brush_rack: Control
var _end_day_button: Button
var _extra_interactive: Array[Control] = []
var _tool_buttons: Dictionary = {}
var _unlocked: Dictionary = {}

## playfield にはブラシ・本体が属する座標空間のルート（ズーム対象の ZoomRoot）を渡す。
func setup(root: Control, playfield: Control, brush_rack: Control, end_day_button: Button) -> void:
	_playfield = playfield
	_brush_rack = brush_rack
	_end_day_button = end_day_button
	_collect_nodes(root)
	_create_tool_buttons()
	_configure_mouse_filters(root)

## ボタンの見た目で道具の状態を示す。保持中=アンバー枠、配置中=減光、収納中=通常、未解禁=暗くdisabled。
const TOOL_HELD_BORDER := Color(1.0, 0.85, 0.55)
const TOOL_DEPLOYED_TINT := Color(0.55, 0.6, 0.65)
const TOOL_LOCKED_TINT := Color(0.4, 0.4, 0.42, 0.55)

var _held_stylebox: StyleBoxFlat

## ツールボックス内に道具ごとのボタンを2列で並べる。押すと保持状態でブラシが出る。
func _create_tool_buttons() -> void:
	_tool_buttons.clear()
	var grid := GridContainer.new()
	grid.name = "ToolButtons"
	grid.columns = 2
	grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.offset_left = 10.0
	grid.offset_top = 34.0
	grid.offset_right = -10.0
	grid.offset_bottom = -10.0
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_brush_rack.add_child(grid)
	for brush_id in _display_ordered_ids():
		var brush: Brush = brush_map[brush_id]
		var button := Button.new()
		button.text = _display_name(brush)
		button.icon = _tool_icon(brush)
		button.expand_icon = true
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_constant_override("icon_max_width", 36)
		button.pressed.connect(toggle_from_toolbox.bind(brush_id))
		grid.add_child(button)
		_tool_buttons[brush_id] = button

## ボタン用アイコン。画像素材があればそれを、無ければブラシ色の円を使う。
func _tool_icon(brush: Brush) -> Texture2D:
	var path := "%s/%s.png" % [Brush.TEXTURE_DIR, brush.brush_id]
	if ResourceLoader.exists(path, "Texture2D"):
		return load(path)
	return _circle_icon(brush.fill_color, brush.hit_radius)

func _circle_icon(color: Color, hit_radius: float) -> Texture2D:
	var size := 48
	# 当たり判定の大小がアイコンにも出るよう、円の半径を実サイズに比例させる。
	var radius := clampf(hit_radius * 0.7, 8.0, size * 0.5 - 2.0)
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	for y in size:
		for x in size:
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

## ツールボックスのボタン操作。収納中なら保持状態で出現させ、
## 配置中なら拾い上げ、保持中なら収納する。
func toggle_from_toolbox(brush_id: String) -> void:
	var brush: Brush = brush_map.get(brush_id)
	if brush == null or not bool(_unlocked.get(brush_id, false)):
		return
	if held_brush == brush:
		_set_held_brush(null)
		# クリップが挟んでいる最中は即座に隠さない。保持を離すだけにして、
		# 落下演出（update_pinch側）が終わった時に自分で visible=false にする。
		if not brush.is_pinching:
			_stow(brush)
		return
	if not brush.visible:
		brush.visible = true
		brush.position = clamp_to_playfield(
			_to_playfield_local(_playfield.get_global_mouse_position()), brush)
	_set_held_brush(brush)

func _stow(brush: Brush) -> void:
	brush.visible = false
	brush.is_active = false
	brush.is_held = false

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
	for button: Control in _tool_buttons.values():
		controls.append(button)
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
	if not (event is InputEventMouseButton):
		return {}
	if not event.pressed:
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
		if held_brush.brush_id == "finger" or held_brush.brush_id == "clip":
			return {"pinch_requested": true}
		if held_brush.brush_id == "tongue":
			return {"kiss_requested": true}
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
		if _is_brush_in_rack(held_brush):
			# ツールボックスの上で放した道具は収納する。
			_stow(held_brush)
	held_brush = brush
	if held_brush != null:
		held_brush.is_held = true
		# 動力型（回転・振動）は保持中も動き続ける（収納時だけ止まる）。
		if held_brush.is_motorized():
			held_brush.is_active = true

func _is_brush_in_rack(brush: Brush) -> bool:
	if _brush_rack == null:
		return false
	# ラックはズーム対象外なので、その矩形をブラシ側（ズーム空間）のローカル座標へ
	# 変換してから、円全体が内側に収まっている場合だけ収納扱いにする。
	var inv := _playfield.get_global_transform().affine_inverse()
	var rack_rect := _brush_rack.get_global_rect()
	var top_left: Vector2 = inv * rack_rect.position
	var bottom_right: Vector2 = inv * rack_rect.end
	return Rect2(top_left, bottom_right - top_left) \
		.grow(-brush.hit_radius).has_point(brush.position)

func _to_playfield_local(global_position: Vector2) -> Vector2:
	return _playfield.get_global_transform().affine_inverse() * global_position

func apply_unlocks(level: int) -> void:
	for brush: Brush in brush_map.values():
		var unlocked := GameRules.is_brush_unlocked(brush.brush_id, level)
		_unlocked[brush.brush_id] = unlocked
		var button: Button = _tool_buttons.get(brush.brush_id)
		if button != null:
			# 未解禁も枠は常に表示し続け、パネルの大きさが解禁数で変動しないようにする。
			button.disabled = not unlocked
			button.text = _display_name(brush) if unlocked else "%s\n未解禁(Lv%d)" % [
				_display_name(brush), GameRules.brush_unlock_level(brush.brush_id)]
		if not unlocked:
			if held_brush == brush:
				_set_held_brush(null)
			_stow(brush)

func reset() -> void:
	_set_held_brush(null)
	for brush: Brush in brush_map.values():
		_stow(brush)

func deactivate_all() -> void:
	_set_held_brush(null)
	for brush: Brush in brush_map.values():
		brush.is_active = false
		brush.is_held = false

func update_controls(name_label: Label, spec_label: Label) -> void:
	_update_tool_button_states()
	var selected_brush := held_brush
	if selected_brush == null:
		for brush_id: String in _display_ordered_ids():
			if bool(_unlocked.get(brush_id, false)):
				selected_brush = brush_map[brush_id]
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
	if selected_brush.brush_id == "clip":
		spec_label.text = "磨き効果なし / 接触中に右クリック：閉じて固定（挟んでいる間、痛み継続） / " \
			+ "もう一度右クリックで手を離す：引っ張りながら垂れ下がって静止（痛みスパイク）"
		return
	var spec := "快感 %d / 痛み %d" % [
		int(round(selected_brush.polish_gain_per_sec)),
		int(round(selected_brush.pain_gain_per_sec))
	]
	if selected_brush.pain_soothe_per_sec > 0.0:
		spec += " / 癒し %d" % int(round(selected_brush.pain_soothe_per_sec))
	spec += " / サイズ %d" % int(round(selected_brush.hit_radius))
	if selected_brush.is_rotating:
		spec += " / 自動回転"
	if selected_brush.is_vibrating:
		spec += " / 自動振動"
	if selected_brush.brush_id == "finger":
		spec += " / 右クリック：挟む/離す"
	if selected_brush.brush_id == "tongue":
		spec += " / 口に重ねて右クリック：口づけON/OFF"
	spec_label.text = spec

func _update_tool_button_states() -> void:
	for brush_id: String in _tool_buttons:
		var brush: Brush = brush_map[brush_id]
		var button: Button = _tool_buttons[brush_id]
		if not bool(_unlocked.get(brush_id, false)):
			button.modulate = TOOL_LOCKED_TINT
			for state in ["normal", "hover", "pressed"]:
				button.remove_theme_stylebox_override(state)
		elif brush == held_brush:
			button.modulate = Color.WHITE
			for state in ["normal", "hover", "pressed"]:
				button.add_theme_stylebox_override(state, _get_held_stylebox())
		else:
			button.modulate = TOOL_DEPLOYED_TINT if brush.visible else Color.WHITE
			for state in ["normal", "hover", "pressed"]:
				button.remove_theme_stylebox_override(state)

func _get_held_stylebox() -> StyleBoxFlat:
	if _held_stylebox == null:
		_held_stylebox = StyleBoxFlat.new()
		_held_stylebox.bg_color = Color(0.32, 0.25, 0.12, 0.9)
		_held_stylebox.border_color = TOOL_HELD_BORDER
		_held_stylebox.set_border_width_all(2)
		_held_stylebox.set_corner_radius_all(4)
	return _held_stylebox

func _display_name(brush: Brush) -> String:
	if brush.display_name != "":
		return brush.display_name
	return brush.brush_id.capitalize().replace("-", " ")

func resolve_collisions(slimes: Array[SlimeTarget], pinch_brush: Brush = null) -> void:
	_resolve_brush_overlaps()
	_apply_wall_push_out()
	_apply_slime_push_out(slimes, pinch_brush)

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

func _apply_slime_push_out(slimes: Array[SlimeTarget], pinch_brush: Brush = null) -> void:
	for brush: Brush in brush_map.values():
		if not brush.visible:
			continue
		if brush == pinch_brush:
			# 挟んで固定中の指は本体に食い込んだままでよい。
			continue
		for slime: SlimeTarget in slimes:
			var min_dist: float = brush.get_contact_radius() + slime.get_hit_radius()
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
