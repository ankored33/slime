extends SceneTree

## Headless unit tests for GameRules and ExpressionRules.
## Run: godot --headless --path godot -s res://tests/run_tests.gd

const GameRules = preload("res://scripts/game_rules.gd")
const ExpressionRules = preload("res://scripts/expression_rules.gd")

var _failures := 0
var _passes := 0

func _init() -> void:
	_test_level_for_finish_total()
	_test_finish_threshold()
	_test_polish_bonus()
	_test_pain_resist()
	_test_retention_ratio()
	_test_brush_unlocks()
	_test_banked_finish()
	_test_push_out_from_rect()
	_test_expression_pick()
	print("---")
	print("Passed: %d, Failed: %d" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)

func _check(condition: bool, label: String) -> void:
	if condition:
		_passes += 1
	else:
		_failures += 1
		printerr("FAIL: %s" % label)

func _check_eq(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, "%s (expected %s, got %s)" % [label, expected, actual])

func _check_near(actual: float, expected: float, label: String) -> void:
	_check(absf(actual - expected) < 0.0001, "%s (expected %f, got %f)" % [label, expected, actual])

func _test_level_for_finish_total() -> void:
	_check_eq(GameRules.level_for_finish_total(0), 1, "level: 0 finish -> Lv1")
	_check_eq(GameRules.level_for_finish_total(1), 1, "level: 1 finish -> Lv1")
	_check_eq(GameRules.level_for_finish_total(2), 2, "level: 2 finish -> Lv2")
	_check_eq(GameRules.level_for_finish_total(4), 2, "level: 4 finish -> Lv2")
	_check_eq(GameRules.level_for_finish_total(5), 3, "level: 5 finish -> Lv3")
	_check_eq(GameRules.level_for_finish_total(20), 6, "level: 20 finish -> Lv6")
	_check_eq(GameRules.level_for_finish_total(53), 9, "level: 53 finish -> Lv9")
	_check_eq(GameRules.level_for_finish_total(54), 10, "level: 54 finish -> Lv10")
	_check_eq(GameRules.level_for_finish_total(999), GameRules.MAX_LEVEL, "level: capped at MAX_LEVEL")
	_check_eq(GameRules.level_for_finish_total(-5), 1, "level: negative finish clamps to Lv1")
	_check_eq(GameRules.level_for_finish_total(0, 5), 5, "level: saved level wins when higher")
	_check_eq(GameRules.level_for_finish_total(0, 99), GameRules.MAX_LEVEL, "level: saved level capped")
	_check_eq(GameRules.level_for_finish_total(0, -3), 1, "level: bad saved level clamps to Lv1")

func _test_finish_threshold() -> void:
	_check_near(GameRules.finish_threshold(1), 170.0, "threshold: Lv1 is near the ceiling")
	_check_near(GameRules.finish_threshold(5), 134.0, "threshold: Lv5")
	_check_near(GameRules.finish_threshold(10), 90.0, "threshold: Lv10 floors at 90")
	_check_near(GameRules.finish_threshold(100), 90.0, "threshold: floored at 90")

func _test_polish_bonus() -> void:
	_check_near(GameRules.polish_bonus(1), 0.6, "polish_bonus: Lv1 is dull")
	_check_near(GameRules.polish_bonus(5), 1.2, "polish_bonus: Lv5")
	_check_near(GameRules.polish_bonus(10), 1.95, "polish_bonus: Lv10 roughly 2x")
	_check_near(GameRules.polish_bonus(0), 0.6, "polish_bonus: Lv0 clamps to baseline")

func _test_pain_resist() -> void:
	_check_near(GameRules.pain_resist(1), 1.0, "pain_resist: Lv1 baseline")
	_check_near(GameRules.pain_resist(5), 0.8, "pain_resist: Lv5")
	_check_near(GameRules.pain_resist(10), 0.55, "pain_resist: Lv10")
	_check_near(GameRules.pain_resist(100), 0.5, "pain_resist: floored at 0.5")

func _test_retention_ratio() -> void:
	_check_near(GameRules.retention_ratio(1), 0.0, "retention: Lv1 keeps nothing")
	_check_near(GameRules.retention_ratio(4), 0.21, "retention: Lv4")
	_check_near(GameRules.retention_ratio(10), 0.63, "retention: Lv10")
	_check_near(GameRules.retention_ratio(100), 0.65, "retention: capped at 0.65")

func _test_brush_unlocks() -> void:
	_check(GameRules.is_brush_unlocked("brush-a", 1), "unlock: soft brush from Lv1")
	_check(not GameRules.is_brush_unlocked("brush-c", 1), "unlock: feather locked at Lv1")
	_check(GameRules.is_brush_unlocked("brush-c", 2), "unlock: feather at Lv2")
	_check(not GameRules.is_brush_unlocked("brush-b", 2), "unlock: firm locked at Lv2")
	_check(GameRules.is_brush_unlocked("brush-b", 3), "unlock: firm at Lv3")
	_check(not GameRules.is_brush_unlocked("brush-d", 4), "unlock: fine-point locked at Lv4")
	_check(GameRules.is_brush_unlocked("brush-d", 5), "unlock: fine-point at Lv5")
	_check_eq(GameRules.brush_unlock_level("brush-d"), 5, "unlock: fine-point level lookup")
	_check_eq(GameRules.brush_unlock_level("unknown"), 1, "unlock: unknown id defaults to Lv1")

func _test_banked_finish() -> void:
	_check_eq(GameRules.banked_finish(7, false), 7, "banked: voluntary end keeps all")
	_check_eq(GameRules.banked_finish(7, true), 3, "banked: pain fail halves rounding down")
	_check_eq(GameRules.banked_finish(0, true), 0, "banked: zero stays zero")
	_check_eq(GameRules.banked_finish(1, true), 0, "banked: single finish lost on fail")

func _test_push_out_from_rect() -> void:
	var rect := Rect2(Vector2(100, 100), Vector2(200, 100))
	var far := Vector2(50, 50)
	_check_eq(GameRules.push_out_from_rect(far, 10.0, rect), far, "push_out: far point untouched")

	var touching := Vector2(95, 150)
	var pushed := GameRules.push_out_from_rect(touching, 10.0, rect)
	_check_near(pushed.x, 90.0, "push_out: overlapping left edge pushed to radius distance")
	_check_near(pushed.y, 150.0, "push_out: push is axis-aligned on left edge")

	var inside := Vector2(110, 150)
	var escaped := GameRules.push_out_from_rect(inside, 10.0, rect)
	_check_eq(escaped, Vector2(90, 150), "push_out: inside point escapes via nearest (left) edge")

	var deep_center := Vector2(200, 150)
	var escaped_center := GameRules.push_out_from_rect(deep_center, 10.0, rect)
	var outside := not Rect2(rect.position - Vector2(9.9, 9.9), rect.size + Vector2(19.8, 19.8)).has_point(escaped_center) \
		or escaped_center.distance_to(deep_center) > 0.0
	_check(outside and escaped_center != deep_center, "push_out: deep center is moved out")
	_check_eq(escaped_center, Vector2(200, 90), "push_out: deep center escapes via shortest axis (top)")

func _test_expression_pick() -> void:
	# 優先度: 絶望 > 絶頂 > それ以外
	_check_eq(ExpressionRules.pick({"despair": true, "climax": true, "touching": true}),
		ExpressionRules.DESPAIR, "expr: despair wins over everything")
	_check_eq(ExpressionRules.pick({"climax": true, "touching": true, "polish_ratio": 1.0}),
		ExpressionRules.CLIMAX, "expr: climax wins over touch")

	# ブラシ当て: 痛み上昇が快感上昇を上回れば「痛い」
	_check_eq(ExpressionRules.pick({"touching": true, "pain_rate": 10.0, "polish_rate": 5.0}),
		ExpressionRules.TOUCH_A, "expr: pain-dominant touch -> 痛い")
	_check_eq(ExpressionRules.pick({"touching": true, "pain_rate": 5.0, "polish_rate": 5.0, "polish_ratio": 0.0}),
		ExpressionRules.TOUCH_B, "expr: equal rates are not pain-dominant")

	# ブラシ当て: ゲージ比率で b -> c -> d
	_check_eq(ExpressionRules.pick({"touching": true, "polish_rate": 10.0, "polish_ratio": 0.1}),
		ExpressionRules.TOUCH_B, "expr: touch low gauge -> 恥じらい")
	_check_eq(ExpressionRules.pick({"touching": true, "polish_rate": 10.0, "polish_ratio": 0.5}),
		ExpressionRules.TOUCH_C, "expr: touch mid gauge -> 快感")
	_check_eq(ExpressionRules.pick({"touching": true, "polish_rate": 10.0, "polish_ratio": 0.8}),
		ExpressionRules.TOUCH_D, "expr: touch high gauge -> 大快感")

	# ブラシ無し: 憔悴はアイドル時のみ、接触が優先
	_check_eq(ExpressionRules.pick({"exhausted": true}),
		ExpressionRules.EXHAUSTED, "expr: exhausted after finish")
	_check_eq(ExpressionRules.pick({"exhausted": true, "touching": true, "polish_rate": 10.0, "polish_ratio": 0.5}),
		ExpressionRules.TOUCH_C, "expr: touching overrides exhausted")

	# ブラシ無し: ゲージ比率で a -> b -> c -> d
	_check_eq(ExpressionRules.pick({}), ExpressionRules.IDLE_A, "expr: empty gauge -> 怒り・軽蔑")
	_check_eq(ExpressionRules.pick({"polish_ratio": 0.3}), ExpressionRules.IDLE_B, "expr: idle low-mid -> 恥じらい")
	_check_eq(ExpressionRules.pick({"polish_ratio": 0.7}), ExpressionRules.IDLE_C, "expr: idle high -> 大快感耐え")
	_check_eq(ExpressionRules.pick({"polish_ratio": 0.95}), ExpressionRules.IDLE_D, "expr: near finish -> 媚び")

	# 素材の既定パス
	_check_eq(ExpressionRules.default_image_path("general", "climax"),
		"res://assets/chara/general/climax.png", "expr: default image path convention")
