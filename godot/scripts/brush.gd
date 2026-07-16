@tool
class_name Brush
extends Area2D

@export var brush_id := ""
@export var display_name := ""
@export var hit_radius := 20.0:
	set(value):
		hit_radius = max(value, 2.0)
		_sync_visuals()

@export var polish_gain_per_sec := 20.0
@export var pain_gain_per_sec := 8.0
## 当てている間、毎秒この量だけ痛みを減らす（癒し系ブラシ用）。
@export var pain_soothe_per_sec := 0.0
## 回転ブラシだけがON/OFFでき、静止中も回転によって効果を出す。
@export var is_rotating := false
@export var rotation_speed := 4.5
@export var fill_color := Color(1, 0.862745, 0.529412, 0.95):
	set(value):
		fill_color = value
		_sync_visuals()

var is_active := false:
	set(value):
		is_active = value
		_sync_visuals()

var is_held := false:
	set(value):
		is_held = value
		_sync_visuals()

# こすり判定用。フレーム間の移動速度を平滑化して保持する。
var _prev_position := Vector2.INF
var _rub_speed := 0.0

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _body: Polygon2D = $Body

func _ready() -> void:
	add_to_group("brushes")
	_sync_visuals()

func _process(delta: float) -> void:
	if is_rotating and is_active:
		rotation += rotation_speed * delta
	if not Engine.is_editor_hint():
		_track_rub_speed(delta)

func _track_rub_speed(delta: float) -> void:
	if _prev_position == Vector2.INF:
		_prev_position = position
		return
	# 1フレームの瞬間移動（押し出しや配置替え）でこすり扱いにならないよう頭打ちにする。
	var speed := minf((position - _prev_position).length() / maxf(delta, 0.0001), 1200.0)
	_rub_speed = lerpf(_rub_speed, speed, minf(1.0, 10.0 * delta))
	_prev_position = position

func get_rub_speed() -> float:
	return _rub_speed

func get_action_multiplier() -> float:
	if is_rotating:
		return 1.0 if is_active else 0.0
	return GameRules.rub_multiplier(_rub_speed)

func is_effective() -> bool:
	return get_action_multiplier() > 0.0

func get_effective_polish_gain() -> float:
	return polish_gain_per_sec

func get_effective_pain_gain() -> float:
	return pain_gain_per_sec

func get_effective_soothe_gain() -> float:
	return pain_soothe_per_sec

func _sync_visuals() -> void:
	if not is_node_ready():
		return
	var shape := CircleShape2D.new()
	shape.radius = hit_radius
	_collision.shape = shape

	var points := PackedVector2Array()
	for i in range(20):
		var angle := TAU * float(i) / 20.0
		var point_radius := hit_radius
		if is_rotating and i % 2 == 1:
			point_radius *= 0.78
		points.append(Vector2.RIGHT.rotated(angle) * point_radius)
	_body.polygon = points
	var tint := fill_color
	if is_active:
		tint = tint.lightened(0.18)
	if is_held:
		tint = tint.lightened(0.12)
	_body.color = tint
