class_name FxTextures
extends RefCounted

## FXで使う小物画像。ハートは実素材（assets/fx/hearts/）から毎回ランダムに選ぶ。

const HEART_DIR := "res://assets/fx/hearts"
const HEART_FILES := [
	"heart_a.png", "heart_b.png", "heart_c.png", "heart_d.png",
	"heart_e.png", "heart_f.png", "heart_g.png", "heart_double.png"
]

## count 種類のハートを重複無しで選ぶ（1回のパーティクル群に混ぜて出すため）。
## count が素材数を超える場合は素材数まで。
static func random_hearts(count: int) -> Array[Texture2D]:
	var files := HEART_FILES.duplicate()
	files.shuffle()
	var out: Array[Texture2D] = []
	for i in range(mini(count, files.size())):
		out.append(load("%s/%s" % [HEART_DIR, files[i]]))
	return out
