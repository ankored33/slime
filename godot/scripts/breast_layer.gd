class_name BreastLayer
extends Sprite2D

## 磨き画面の胸レイヤー。立ち絵と同一キャンバスの透過PNGを CharaImage と同じ
## cover 配置で重ね、乳首ターゲットの変位に部分追従させて胸ごと動いて見せる。
## 表情差分で立ち絵が差し替わっても載り続ける（characters.gd の breast キー参照）。

## 乳首の変位に対する追従率（1.0で乳首と同じだけ動く）。
const FOLLOW_RATIO := 0.6
## 追従の滑らかさ（大きいほど機敏に、小さいほど遅れてついてくる）。
const FOLLOW_SPEED := 10.0

var _target: SlimeTarget
var _base_position := Vector2.ZERO
var _offset := Vector2.ZERO

func setup(tex: Texture2D, frame_size: Vector2, target: SlimeTarget) -> void:
	texture = tex
	centered = false
	_target = target
	var tex_size := tex.get_size()
	var cover_scale := maxf(frame_size.x / tex_size.x, frame_size.y / tex_size.y)
	scale = Vector2(cover_scale, cover_scale)
	_base_position = (frame_size - tex_size * cover_scale) / 2.0
	position = _base_position

func _process(delta: float) -> void:
	if _target == null:
		return
	var desired := _target.get_push_offset() * FOLLOW_RATIO
	_offset = _offset.lerp(desired, minf(1.0, FOLLOW_SPEED * delta))
	position = _base_position + _offset
