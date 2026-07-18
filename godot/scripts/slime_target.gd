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

## true なら画像を等倍（原寸ピクセル）で表示し、当たり判定半径も画像サイズから取る。
var image_native_size := false

## 対応する胸レイヤーの縮小に合わせて乳首を少し縮ませる（0.9〜1.0）。
## 拡大方向には反応しない。breast_layer.gd が毎フレーム設定する。
## 胸レイヤーが無いターゲットは常に1.0のまま。
var nipple_shrink := 1.0:
	set(value):
		nipple_shrink = clampf(value, 0.9, 1.0)
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
@onready var _sprite: Sprite2D = $Sprite2D

var _hearts: CPUParticles2D
var _heart_burst: CPUParticles2D

func _ready() -> void:
	add_to_group("slime_targets")
	if not Engine.is_editor_hint():
		_setup_heart_particles()
	_sync_visuals()

func _setup_heart_particles() -> void:
	_hearts = CPUParticles2D.new()
	_hearts.name = "HeartParticles"
	_hearts.emitting = false
	_hearts.amount = 24
	_hearts.lifetime = 1.2
	_hearts.local_coords = false
	_hearts.texture = FxTextures.heart()
	_hearts.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_hearts.direction = Vector2.UP
	_hearts.spread = 25.0
	_hearts.initial_velocity_min = 60.0
	_hearts.initial_velocity_max = 120.0
	_hearts.gravity = Vector2(0.0, -40.0)
	_hearts.scale_amount_min = 0.6
	_hearts.scale_amount_max = 1.2
	_hearts.angular_velocity_min = -90.0
	_hearts.angular_velocity_max = 90.0
	_hearts.color = Color(1.0, 0.5, 0.65, 1.0)
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_hearts.color_ramp = fade
	add_child(_hearts)

	# FINISH瞬間の一斉バースト用。通常のハートより強く弾ける。
	_heart_burst = CPUParticles2D.new()
	_heart_burst.name = "HeartBurst"
	_heart_burst.emitting = false
	_heart_burst.one_shot = true
	_heart_burst.explosiveness = 1.0
	_heart_burst.amount = 36
	_heart_burst.lifetime = 1.5
	_heart_burst.local_coords = false
	_heart_burst.texture = FxTextures.heart()
	_heart_burst.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_heart_burst.direction = Vector2.UP
	_heart_burst.spread = 180.0
	_heart_burst.initial_velocity_min = 160.0
	_heart_burst.initial_velocity_max = 320.0
	_heart_burst.gravity = Vector2(0.0, 140.0)
	_heart_burst.scale_amount_min = 0.8
	_heart_burst.scale_amount_max = 1.7
	_heart_burst.angular_velocity_min = -180.0
	_heart_burst.angular_velocity_max = 180.0
	_heart_burst.color = Color(1.0, 0.6, 0.75, 1.0)
	var burst_fade := Gradient.new()
	burst_fade.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	burst_fade.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_heart_burst.color_ramp = burst_fade
	add_child(_heart_burst)

func set_hearts_active(on: bool) -> void:
	if _hearts != null:
		_hearts.emitting = on

func burst_hearts() -> void:
	if _heart_burst != null:
		_heart_burst.restart()

const SQUISH_STIFFNESS := 70.0
const SQUISH_DAMPING := 5.0
const MAX_SQUISH_RATIO := 0.25
const PRESS_RESPONSE := 10.0

## 押されたときの位置ずれ。押し込み量に比例し、離すとバネで元の位置へ戻る。
const PUSH_RATIO := 0.35
const MAX_PUSH_DISTANCE := 16.0
## 挟んで引っ張られたときの最大変位。押されたときより大きく動く。
const MAX_PULL_DISTANCE := 48.0

## 回転ブラシ接触中の微振動。反発方向へ超微量はじかれて戻る動きを繰り返す。
const TREMBLE_AMPLITUDE := 5.0
const TREMBLE_FREQUENCY := 16.0
const TREMBLE_RESPONSE := 12.0

var _squish := 0.0
var _squish_velocity := 0.0
var _push_offset := Vector2.ZERO
var _push_velocity := Vector2.ZERO
var _pull_active := false
var _tremble_dir := Vector2.ZERO
var _tremble_phase := 0.0
var _tremble_strength := 0.0
var _tremble_offset := Vector2.ZERO

## 押し込み・挟み引っ張り・微振動による現在の変位（胸レイヤーの追従元）。
func get_push_offset() -> Vector2:
	return _push_offset + _tremble_offset

func get_hit_radius() -> float:
	# Squishy hitbox: compressed while pressed, briefly overshoots on release.
	return clampf(radius - _squish, radius * (1.0 - MAX_SQUISH_RATIO), radius * (1.0 + MAX_SQUISH_RATIO * 0.5))

func apply_pressure(depth: float, delta: float, push := Vector2.ZERO, tremble_dir := Vector2.ZERO) -> void:
	if depth > 0.0:
		var target := minf(depth * 0.6, radius * MAX_SQUISH_RATIO)
		_squish = lerpf(_squish, target, minf(1.0, PRESS_RESPONSE * delta))
		_squish_velocity = 0.0
	else:
		var accel := -SQUISH_STIFFNESS * _squish - SQUISH_DAMPING * _squish_velocity
		_squish_velocity += accel * delta
		_squish += _squish_velocity * delta
	_update_push(push, delta)
	_update_tremble(tremble_dir, delta)

## 挟まれて引っ張られている間の位置更新。望みの位置へ寄せるが、
## 可動範囲（MAX_PULL_DISTANCE）を超える分は届かず、引っ張り抵抗になる。
## apply_pressure より先に毎フレーム呼ぶこと（そのフレームの押し込み変位を上書きする）。
func apply_pull(desired_position: Vector2, delta: float) -> void:
	var target := (_push_offset + desired_position - position).limit_length(MAX_PULL_DISTANCE)
	var next := _push_offset.lerp(target, minf(1.0, PRESS_RESPONSE * delta))
	_push_velocity = Vector2.ZERO
	position += next - _push_offset
	_push_offset = next
	_pull_active = true

## 位置は「元の位置 + _push_offset」を保つよう差分で動かす。
## 元の位置を別途持たないため、レイアウト変更で位置が変わっても追従する。
func _update_push(push: Vector2, delta: float) -> void:
	if _pull_active:
		# このフレームは apply_pull が変位を決めた。押し込みやバネ戻りで上書きしない。
		_pull_active = false
		return
	var next := _push_offset
	if push != Vector2.ZERO:
		var target := (push * PUSH_RATIO).limit_length(MAX_PUSH_DISTANCE)
		next = _push_offset.lerp(target, minf(1.0, PRESS_RESPONSE * delta))
		_push_velocity = Vector2.ZERO
	else:
		var accel := -SQUISH_STIFFNESS * _push_offset - SQUISH_DAMPING * _push_velocity
		_push_velocity += accel * delta
		next = _push_offset + _push_velocity * delta
	position += next - _push_offset
	_push_offset = next

## 回転ブラシに触れられている間の微振動。abs(sin) で「はじかれて戻る」片側だけの
## 揺れにし、接触が切れたら強さをなだらかにゼロへ戻す。
## 当たり判定（position）には影響させず、見た目の子ノードだけをずらす。
func _update_tremble(dir: Vector2, delta: float) -> void:
	if dir != Vector2.ZERO:
		_tremble_dir = dir
	var target_strength := 1.0 if dir != Vector2.ZERO else 0.0
	_tremble_strength = lerpf(_tremble_strength, target_strength, minf(1.0, TREMBLE_RESPONSE * delta))
	_tremble_phase = fmod(_tremble_phase + TREMBLE_FREQUENCY * delta, 1.0)
	_tremble_offset = _tremble_dir * (TREMBLE_AMPLITUDE * _tremble_strength * absf(sin(_tremble_phase * TAU)))
	_apply_tremble_visual()

func _apply_tremble_visual() -> void:
	_sprite.position = _tremble_offset
	_body.position = _tremble_offset
	_outline.position = _tremble_offset

func reset_pressure() -> void:
	_squish = 0.0
	_squish_velocity = 0.0
	position -= _push_offset
	_push_offset = Vector2.ZERO
	_push_velocity = Vector2.ZERO
	_pull_active = false
	_tremble_dir = Vector2.ZERO
	_tremble_phase = 0.0
	_tremble_strength = 0.0
	_tremble_offset = Vector2.ZERO
	_apply_tremble_visual()
	nipple_shrink = 1.0

func apply_species(species: Dictionary, side_label: String, side_config: Dictionary = {}) -> void:
	slime_id = str(species.get("id", ""))
	display_name = "%s %s" % [str(species.get("name", "Slime")), side_label]
	var side_radius: Variant = side_config.get("radius", null)
	if side_radius != null:
		radius = float(side_radius)
	fill_color = species.get("color", fill_color)
	var image_path := str(side_config.get("image", ""))
	if image_path != "":
		var texture := load(image_path)
		if texture is Texture2D:
			_sprite.texture = texture
	else:
		_sprite.texture = null
	image_native_size = bool(side_config.get("image_native_size", false)) and _sprite.texture != null
	if image_native_size:
		var tex_size := _sprite.texture.get_size()
		radius = maxf(tex_size.x, tex_size.y) / 2.0
	_sync_visuals()

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
	if _sprite.texture != null:
		var tex_size := _sprite.texture.get_size()
		if image_native_size:
			_sprite.scale = Vector2.ONE * nipple_shrink
		elif tex_size.x > 0.0 and tex_size.y > 0.0:
			var target_diameter := radius * 2.0
			var scale_x := target_diameter / tex_size.x * nipple_shrink
			var scale_y := target_diameter / tex_size.y * nipple_shrink
			_sprite.scale = Vector2(scale_x, scale_y)
		_sprite.visible = true
		_body.visible = false
		_outline.visible = false
	else:
		_sprite.visible = false
		_body.visible = true
		_outline.visible = true
	if _hearts != null:
		_hearts.emission_sphere_radius = radius * 0.6
		_hearts.position = Vector2(0.0, -radius * 0.3)
	if _heart_burst != null:
		_heart_burst.emission_sphere_radius = radius * 0.5
