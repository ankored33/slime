class_name BreastLayer
extends Sprite2D

## 磨き画面の胸レイヤー。立ち絵と同一キャンバスの透過PNGを CharaImage と同じ
## cover 配置で重ね、乳首ターゲットの変位に応じて根元（付け根）を固定したまま
## 伸び縮みさせて、胸ごと動いて見せる。
## 表情差分（顔だけの重ね絵）が切り替わっても載り続ける（characters.gd の breast キー参照）。

## 乳首の変位に対する追従率（1.0で乳首と同じ量を伸縮に変換する）。
const FOLLOW_RATIO := 0.6
## 追従の滑らかさ（大きいほど機敏に、小さいほど遅れてついてくる）。
const FOLLOW_SPEED := 10.0
## この変位量で伸縮率が最大になる（≒挟み引っ張りの最大変位）。
const STRETCH_REFERENCE := 48.0
## 最大伸縮率（0.35なら等倍±35%まで）。
const MAX_STRETCH := 0.35

var _target: SlimeTarget
var _base_scale := Vector2.ONE
## 根元が身体の内側（画面左の胸なら右、画面右の胸なら左）にあるための符号。
var _x_sign := 1.0
var _offset := Vector2.ZERO

## root_local: 根元（伸縮しても動かない固定点）のテクスチャ内ピクセル座標。
## characters.gd の breast_root で手打ち指定する（characters.gd 参照）。
## side: "left"/"right"（画面上の位置）。伸縮の符号を左右で反転させるために使う。
func setup(tex: Texture2D, frame_size: Vector2, target: SlimeTarget, side: String, root_local: Vector2) -> void:
	texture = tex
	centered = false
	_target = target
	var tex_size := tex.get_size()
	var cover_scale := maxf(frame_size.x / tex_size.x, frame_size.y / tex_size.y)
	_base_scale = Vector2(cover_scale, cover_scale)
	scale = _base_scale
	_x_sign = -1.0 if side == "left" else 1.0

	# offset で描画原点を根元にずらしておくと、scale をどう変えても
	# 根元の画面上の位置は position のまま動かなくなる。
	offset = -root_local
	var base_position := (frame_size - tex_size * cover_scale) / 2.0
	position = base_position + root_local * cover_scale

func _process(delta: float) -> void:
	if _target == null:
		return
	var desired := _target.get_push_offset() * FOLLOW_RATIO
	_offset = _offset.lerp(desired, minf(1.0, FOLLOW_SPEED * delta))
	var frac_x := clampf(_x_sign * _offset.x / STRETCH_REFERENCE, -1.0, 1.0) * MAX_STRETCH
	var frac_y := clampf(-_offset.y / STRETCH_REFERENCE, -1.0, 1.0) * MAX_STRETCH
	scale = _base_scale * Vector2(1.0 + frac_x, 1.0 + frac_y)
	# 乳首は胸が縮んだ分だけ追従して縮ませる（拡大方向は無視、下限は nipple_shrink 側でクランプ）。
	_target.nipple_shrink = minf(1.0 + frac_x, 1.0 + frac_y)
