@tool
class_name SlimeTarget
extends Area2D

@export_enum("left", "right") var side := "left"
@export var role := "slime"
@export var slime_id := ""
@export var display_name := "Slime"
@export var radius := 110.0:
	set(value):
		radius = max(value, 8.0)
		_sync_visuals()

@export var fill_color := Color(0.454902, 1.0, 0.8, 0.92):
	set(value):
		fill_color = value
		_sync_visuals()

@export var outline_color := Color(1, 1, 1, 0.95):
	set(value):
		outline_color = value
		_sync_visuals()

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _body: Polygon2D = $Body
@onready var _outline: Line2D = $Outline
@onready var _label: Label = $Label

func _ready() -> void:
	add_to_group("slime_targets")
	_sync_visuals()

func get_hit_radius() -> float:
	return radius

func _sync_visuals() -> void:
	if not is_node_ready():
		return

	var shape := CircleShape2D.new()
	shape.radius = radius
	_collision.shape = shape

	var points := PackedVector2Array()
	var outline_points := PackedVector2Array()
	for i in range(24):
		var angle := TAU * float(i) / 24.0
		var point := Vector2.RIGHT.rotated(angle) * radius
		points.append(point)
		outline_points.append(point)
	outline_points.append(outline_points[0])

	_body.polygon = points
	_body.color = fill_color
	_outline.points = outline_points
	_outline.default_color = outline_color
	_outline.width = 4.0
	_label.text = display_name
	_label.position = Vector2(-radius, radius + 12.0)
	_label.size = Vector2(radius * 2.0, 28.0)
