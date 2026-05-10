@tool
class_name WallZone
extends StaticBody2D

@export var role := "wall"
@export var size := Vector2(160.0, 80.0):
	set(value):
		size = Vector2(max(value.x, 16.0), max(value.y, 16.0))
		_sync_visuals()

@export var fill_color := Color(0.243137, 0.294118, 0.388235, 0.75):
	set(value):
		fill_color = value
		_sync_visuals()

@export var outline_color := Color(0.772549, 0.827451, 0.952941, 0.95):
	set(value):
		outline_color = value
		_sync_visuals()

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _fill: Polygon2D = $Fill
@onready var _outline: Line2D = $Outline

func _ready() -> void:
	add_to_group("wall_zones")
	_sync_visuals()

func get_rect() -> Rect2:
	return Rect2(position - size * 0.5, size)

func _sync_visuals() -> void:
	if not is_node_ready():
		return

	var rect_shape := RectangleShape2D.new()
	rect_shape.size = size
	_collision.shape = rect_shape

	var half := size * 0.5
	var corners := [
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	]
	_fill.polygon = PackedVector2Array(corners)
	_fill.color = fill_color
	_outline.points = PackedVector2Array(corners + [corners[0]])
	_outline.default_color = outline_color
	_outline.width = 3.0
