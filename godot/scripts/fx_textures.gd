class_name FxTextures
extends RefCounted

## FXで使う小物画像。ハートは実素材（assets/fx/hearts/）から毎回ランダムに1枚選ぶ。

const HEART_DIR := "res://assets/fx/hearts"
const HEART_FILES := [
	"heart_a.png", "heart_b.png", "heart_c.png", "heart_d.png",
	"heart_e.png", "heart_f.png", "heart_g.png", "heart_double.png"
]

static func random_heart() -> Texture2D:
	var path := "%s/%s" % [HEART_DIR, HEART_FILES.pick_random()]
	return load(path)
