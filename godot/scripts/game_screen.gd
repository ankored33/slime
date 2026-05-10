extends Control

@export var follow_speed := 16.0

var _held_brush: Brush
var _gauge_map: Dictionary = {}
var _slime_state := {
	"left": {"polish": 0.0, "pain": 0.0},
	"right": {"polish": 0.0, "pain": 0.0}
}

@onready var _playfield: Control = $Playfield
@onready var _debug_label: Label = $Hud/DebugLabel

func _ready() -> void:
	_collect_gauges()
	_update_gauges()
	_refresh_debug_text()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pick_brush(event.position)
		else:
			_held_brush = null
	elif event is InputEventMouseMotion and _held_brush != null:
		_held_brush.position = _to_playfield_local(event.position)
		_apply_brush_effects(_held_brush)

func _process(delta: float) -> void:
	if _held_brush == null:
		return
	var local_mouse := _to_playfield_local(get_global_mouse_position())
	_held_brush.position = _held_brush.position.lerp(local_mouse, min(1.0, follow_speed * delta))
	_apply_brush_effects(_held_brush)

func _collect_gauges() -> void:
	for gauge in get_tree().get_nodes_in_group("named_gauges"):
		_gauge_map[gauge.gauge_id] = gauge

func _pick_brush(mouse_position: Vector2) -> void:
	var local_mouse := _to_playfield_local(mouse_position)
	var nearest: Brush
	var nearest_distance := INF
	for brush in get_tree().get_nodes_in_group("brushes"):
		var distance := brush.position.distance_to(local_mouse)
		if distance <= brush.hit_radius * 1.4 and distance < nearest_distance:
			nearest = brush
			nearest_distance = distance
	_held_brush = nearest

func _apply_brush_effects(brush: Brush) -> void:
	for slime in get_tree().get_nodes_in_group("slime_targets"):
		if brush.global_position.distance_to(slime.global_position) <= brush.hit_radius + slime.get_hit_radius():
			var side := String(slime.side)
			var state: Dictionary = _slime_state.get(side, {})
			state["polish"] = clamp(float(state.get("polish", 0.0)) + brush.polish_gain_per_sec * get_process_delta_time(), 0.0, 100.0)
			state["pain"] = clamp(float(state.get("pain", 0.0)) + brush.pain_gain_per_sec * get_process_delta_time() * 0.35, 0.0, 100.0)
			_slime_state[side] = state
	_update_gauges()
	_refresh_debug_text()

func _update_gauges() -> void:
	_set_gauge("polish-L", _slime_state["left"]["polish"])
	_set_gauge("pain-L", _slime_state["left"]["pain"])
	_set_gauge("polish-R", _slime_state["right"]["polish"])
	_set_gauge("pain-R", _slime_state["right"]["pain"])

func _set_gauge(gauge_id: String, current: float) -> void:
	var gauge: NamedGauge = _gauge_map.get(gauge_id)
	if gauge != null:
		gauge.set_gauge_value(current, 100.0)

func _refresh_debug_text() -> void:
	_debug_label.text = "Drag a brush over a slime target.\nWall / slime / gauge are now scene nodes with exported data."

func _to_playfield_local(global_position: Vector2) -> Vector2:
	return _playfield.get_global_transform().affine_inverse() * global_position
