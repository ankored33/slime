class_name FxTextures
extends RefCounted

## Runtime-generated placeholder textures. Swap for real art later by
## assigning a texture in the consuming node instead.

static func heart(size: int = 32) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for py in range(size):
		for px in range(size):
			var inside := 0
			for sy in range(2):
				for sx in range(2):
					var u := (float(px) + 0.25 + 0.5 * float(sx)) / float(size)
					var v := (float(py) + 0.25 + 0.5 * float(sy)) / float(size)
					var x := (u - 0.5) * 2.9
					var y := (0.5 - v) * 2.9 + 0.15
					if _heart_inside(x, y):
						inside += 1
			if inside > 0:
				img.set_pixel(px, py, Color(1.0, 1.0, 1.0, float(inside) / 4.0))
	return ImageTexture.create_from_image(img)

static func _heart_inside(x: float, y: float) -> bool:
	var a := x * x + y * y - 1.0
	return a * a * a - x * x * y * y * y <= 0.0
