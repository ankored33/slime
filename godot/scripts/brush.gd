@tool
class_name Brush
extends Area2D

@export var brush_id := ""
@export var hit_radius := 20.0:
	set(value):
		hit_radius = max(value, 2.0)
		_sync_visuals()

@export var polish_gain_per_sec := 20.0
@export var pain_gain_per_sec := 8.0
@export var special_multiplier := 1.75
@export var fill_color := Color(1, 0.862745, 0.529412, 0.95):
	set(value):
		fill_color = value
		_sync_visuals()

var is_active := false:
	set(value):
		is_active = value
		_sync_visuals()

var special_time_left := 0.0

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _body: Polygon2D = $Body

func _ready() -> void:
	add_to_group("brushes")
	_sync_visuals()

func _process(delta: float) -> void:
	if special_time_left > 0.0:
		special_time_left = max(0.0, special_time_left - delta)
		_sync_visuals()

func get_effective_polish_gain() -> float:
	return polish_gain_per_sec * (_get_special_multiplier() if is_active else 1.0)

func get_effective_pain_gain() -> float:
	return pain_gain_per_sec * (_get_special_multiplier() if is_active else 1.0)

func trigger_special(duration: float = 3.0) -> void:
	special_time_left = max(special_time_left, duration)
	_sync_visuals()

func is_special_active() -> bool:
	return special_time_left > 0.0

func _sync_visuals() -> void:
	if not is_node_ready():
		return
	var shape := CircleShape2D.new()
	shape.radius = hit_radius
	_collision.shape = shape

	var points := PackedVector2Array()
	for i in range(20):
		var angle := TAU * float(i) / 20.0
		points.append(Vector2.RIGHT.rotated(angle) * hit_radius)
	_body.polygon = points
	var tint := fill_color
	if is_active:
		tint = tint.lightened(0.18)
	if is_special_active():
		tint = tint.lightened(0.28)
	_body.color = tint

func _get_special_multiplier() -> float:
	return special_multiplier if is_special_active() else 1.0
