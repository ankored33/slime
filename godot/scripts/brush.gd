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
@export var fill_color := Color(1, 0.862745, 0.529412, 0.95):
	set(value):
		fill_color = value
		_sync_visuals()

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _body: Polygon2D = $Body

func _ready() -> void:
	add_to_group("brushes")
	_sync_visuals()

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
	_body.color = fill_color
