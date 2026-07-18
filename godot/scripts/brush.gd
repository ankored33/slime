@tool
class_name Brush
extends Area2D

@export var brush_id := ""
@export var display_name := ""
@export var hit_radius := 20.0:
	set(value):
		hit_radius = max(value, 2.0)
		_sync_visuals()

## 本体への接触判定は見た目（hit_radius）より内側に縮める。
## 絵が少し重なってから効き始めるほうが「触れている感」が出るため。
const CONTACT_RATIO := 0.8

@export var polish_gain_per_sec := 200.0
@export var pain_gain_per_sec := 80.0
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

# 画像素材のドロップイン先。<brush_id>.png を置くだけでプレースホルダ多角形と差し替わる。
# <brush_id>_pinch.png も置くと、つまみアクション中だけその画像に切り替わる。
const TEXTURE_DIR := "res://assets/brushes"

var _sprite: Sprite2D
var _base_texture: Texture2D
var _pinch_texture: Texture2D

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _body: Polygon2D = $Body

func _ready() -> void:
	add_to_group("brushes")
	_load_texture()
	_sync_visuals()

func _load_texture() -> void:
	if brush_id == "":
		return
	var path := "%s/%s.png" % [TEXTURE_DIR, brush_id]
	if ResourceLoader.exists(path, "Texture2D"):
		_base_texture = load(path)
		_apply_texture(_base_texture)
	var pinch_path := "%s/%s_pinch.png" % [TEXTURE_DIR, brush_id]
	if ResourceLoader.exists(pinch_path, "Texture2D"):
		_pinch_texture = load(pinch_path)

## つまみアクション中、画像を本体中心方向（ローカル-Y）へ寄せて食い込んで見せる量。
const PINCH_APPROACH := 20.0

## つまみアクション中の見た目切り替え。専用画像が無いブラシでは何もしない。
func set_pinching(on: bool) -> void:
	if _base_texture == null or _pinch_texture == null:
		return
	_apply_texture(_pinch_texture if on else _base_texture)
	_sprite.position = Vector2(0.0, -PINCH_APPROACH) if on else Vector2.ZERO

func _apply_texture(texture: Texture2D) -> void:
	if _sprite == null:
		_sprite = Sprite2D.new()
		add_child(_sprite)
	_sprite.texture = texture
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

## 本体（スライムターゲット）との接触に使う半径。見た目・壁・ラック判定は hit_radius のまま。
func get_contact_radius() -> float:
	return hit_radius * CONTACT_RATIO

## こすり判定で効果を出すブラシかどうか（回転ブラシ・固有アクション型を除く）。
func uses_rub() -> bool:
	return not is_rotating and brush_id not in ["candle", "teeth"]

## こすり系ブラシは接触中、画像の上端を本体の中心へ向ける。離れたら直立に戻る。
const FACING_TURN_SPEED := 12.0

func update_contact_facing(target_local: Variant, delta: float) -> void:
	if not uses_rub():
		return
	var desired := 0.0
	if target_local != null:
		# 本体と同じ親（ズーム空間）のローカル座標で受け取る。
		var to_target := (target_local as Vector2) - position
		if to_target.length() > 0.001:
			# 画像のローカル -Y（上）が to_target の向きになる回転角。
			desired = to_target.angle() + PI / 2.0
	rotation = lerp_angle(rotation, desired, minf(1.0, FACING_TURN_SPEED * delta))

func get_action_multiplier() -> float:
	# 固有アクション型の道具は本体をこすっても磨き効果が出ない。
	if brush_id in ["candle", "teeth"]:
		return 0.0
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

	_body.visible = _sprite == null
	if _sprite != null:
		# 画像の最大辺を当たり判定の直径に合わせて伸縮する（キャンバス余白込みで発注済み）。
		var tex_size: Vector2 = _sprite.texture.get_size()
		_sprite.scale = Vector2.ONE * (hit_radius * 2.0 / maxf(tex_size.x, tex_size.y))
		var brightness := 1.0
		if is_active:
			brightness += 0.18
		if is_held:
			brightness += 0.12
		_sprite.modulate = Color(brightness, brightness, brightness, 1.0)
		return

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
