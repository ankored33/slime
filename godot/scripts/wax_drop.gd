class_name WaxDrop
extends Node2D

## ろうそくから落ちる一滴。移動と仮グラフィックだけを担当する。

var radius := GameRules.WAX_DROP_RADIUS
var velocity := Vector2(0.0, GameRules.WAX_DROP_SPEED)
var lifetime := GameRules.WAX_DROP_LIFETIME

func _ready() -> void:
	# 背景やブラシより手前に出し、小さくても見失わないようにする。
	z_index = 30
	queue_redraw()

func _draw() -> void:
	# 素材が用意されるまでの、輪郭と照りを付けた簡易しずくグラフィック。
	var points := PackedVector2Array([
		Vector2(0.0, -radius * 1.5),
		Vector2(radius * 0.55, -radius * 0.45),
		Vector2(radius, radius * 0.25),
		Vector2(radius * 0.8, radius * 0.85),
		Vector2(radius * 0.35, radius * 1.2),
		Vector2(0.0, radius * 1.3),
		Vector2(-radius * 0.35, radius * 1.2),
		Vector2(-radius * 0.8, radius * 0.85),
		Vector2(-radius, radius * 0.25),
		Vector2(-radius * 0.55, -radius * 0.45)
	])
	draw_colored_polygon(points, Color(1.0, 0.78, 0.24, 1.0))
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(0.45, 0.22, 0.04, 1.0), 2.0, true)
	draw_circle(Vector2(-radius * 0.3, radius * 0.15), radius * 0.22,
		Color(1.0, 1.0, 0.82, 0.9))

func advance(delta: float) -> Vector2:
	var previous := position
	velocity.y += GameRules.WAX_DROP_GRAVITY * delta
	position += velocity * delta
	lifetime -= delta
	return previous

func is_expired(playfield_height: float) -> bool:
	return lifetime <= 0.0 or position.y - radius > playfield_height
