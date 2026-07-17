class_name WaxDrop
extends Node2D

## ろうそくから落ちる一滴。移動と仮グラフィックだけを担当する。

var radius := GameRules.WAX_DROP_RADIUS
var velocity := Vector2(0.0, GameRules.WAX_DROP_SPEED)
var lifetime := GameRules.WAX_DROP_LIFETIME

func _ready() -> void:
	var body := Polygon2D.new()
	var points := PackedVector2Array([Vector2(0.0, -radius * 1.5)])
	for i in range(12):
		var angle := TAU * float(i) / 12.0
		points.append(Vector2.RIGHT.rotated(angle) * radius)
	body.polygon = points
	body.color = Color(1.0, 0.82, 0.38, 0.95)
	add_child(body)

func advance(delta: float) -> Vector2:
	var previous := position
	velocity.y += GameRules.WAX_DROP_GRAVITY * delta
	position += velocity * delta
	lifetime -= delta
	return previous

func is_expired(playfield_height: float) -> bool:
	return lifetime <= 0.0 or position.y - radius > playfield_height
