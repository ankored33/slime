extends SceneTree

## Headless unit tests for GameRules and ExpressionRules.
## Run: godot --headless --path godot -s res://tests/run_tests.gd

const GameRules = preload("res://scripts/game_rules.gd")
const ExpressionRules = preload("res://scripts/expression_rules.gd")
const BrushScript = preload("res://scripts/brush.gd")
const NumberFormat = preload("res://scripts/number_format.gd")

var _failures := 0
var _passes := 0

func _init() -> void:
	_test_level_for_finish_total()
	_test_finish_threshold()
	_test_polish_bonus()
	_test_pain_resist()
	_test_retention_ratio()
	_test_chain_finishes()
	_test_number_format()
	_test_brush_unlocks()
	_test_banked_finish()
	_test_push_out_from_rect()
	_test_expression_pick()
	_test_rub_multiplier()
	_test_brush_action()
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
	for level: int in [7, 100, 500, 1000]:
		var need := GameRules.required_finish_total(level)
		_check_eq(GameRules.level_for_finish_total(need), level,
			"level: required total reaches Lv%d" % level)
		_check_eq(GameRules.level_for_finish_total(need - 1), level - 1,
			"level: one short of Lv%d stays below" % level)
	_check(GameRules.required_finish_total(GameRules.MAX_LEVEL) < 9007199254740992,
		"level: Lv1000 total stays JSON-safe")
	_check_eq(GameRules.level_for_finish_total(GameRules.required_finish_total(1000) * 10),
		GameRules.MAX_LEVEL, "level: capped at MAX_LEVEL")
	_check_eq(GameRules.level_for_finish_total(-5), 1, "level: negative finish clamps to Lv1")
	_check_eq(GameRules.level_for_finish_total(0, 5), 5, "level: saved level wins when higher")
	_check_eq(GameRules.level_for_finish_total(0, 99999), GameRules.MAX_LEVEL, "level: saved level capped")
	_check_eq(GameRules.level_for_finish_total(0, -3), 1, "level: bad saved level clamps to Lv1")

func _test_finish_threshold() -> void:
	_check_near(GameRules.finish_threshold(1), 1700.0, "threshold: Lv1 is near the ceiling")
	_check_near(GameRules.finish_threshold(5), 1340.0, "threshold: Lv5")
	_check_near(GameRules.finish_threshold(10), 900.0, "threshold: Lv10 floors at 900")
	_check_near(GameRules.finish_threshold(100), 900.0, "threshold: floored at 900")

func _test_polish_bonus() -> void:
	_check_near(GameRules.polish_bonus(1), 0.6, "polish_bonus: Lv1 is dull")
	_check_near(GameRules.polish_bonus(5), 1.2, "polish_bonus: Lv5")
	_check_near(GameRules.polish_bonus(10), 1.95, "polish_bonus: Lv10 roughly 2x")
	_check_near(GameRules.polish_bonus(1000), 3.0, "polish_bonus: capped in the late game")
	_check_near(GameRules.polish_bonus(0), 0.6, "polish_bonus: Lv0 clamps to baseline")

func _test_pain_resist() -> void:
	_check_near(GameRules.pain_resist(1), 1.0, "pain_resist: Lv1 baseline")
	_check_near(GameRules.pain_resist(5), 0.8, "pain_resist: Lv5")
	_check_near(GameRules.pain_resist(10), 0.55, "pain_resist: Lv10")
	_check_near(GameRules.pain_resist(21), 0.0, "pain_resist: fully immune from Lv21")
	_check_near(GameRules.pain_resist(1000), 0.0, "pain_resist: stays immune")

func _test_retention_ratio() -> void:
	_check_near(GameRules.retention_ratio(1), 0.0, "retention: Lv1 keeps nothing")
	_check_near(GameRules.retention_ratio(4), 0.35, "retention: Lv4")
	_check_near(GameRules.retention_ratio(6), 0.784, "retention: Lv6 targets 1 finish/sec")
	_check_near(GameRules.chain_rate_target(1000), GameRules.FINAL_CHAIN_RATE,
		"retention: Lv1000 targets the final chain rate")
	_check_near(GameRules.retention_ratio(1000),
		1.0 - 600.0 / (900.0 * GameRules.FINAL_CHAIN_RATE),
		"retention: Lv1000 derived from final rate")
	_check(GameRules.retention_ratio(1000) < 1.0, "retention: never reaches 1")

func _test_chain_finishes() -> void:
	var below: Dictionary = GameRules.chain_finishes(500.0, 900.0, 0.63)
	_check_eq(int(below["count"]), 0, "chain: below threshold yields nothing")
	_check_near(float(below["factor"]), 1.0, "chain: below threshold keeps polish")

	var no_retention: Dictionary = GameRules.chain_finishes(1700.0, 1700.0, 0.0)
	_check_eq(int(no_retention["count"]), 1, "chain: zero retention is a single finish")
	_check_near(float(no_retention["factor"]), 0.0, "chain: zero retention drains polish")

	var single: Dictionary = GameRules.chain_finishes(1000.0, 900.0, 0.63)
	_check_eq(int(single["count"]), 1, "chain: one crossing is one finish")
	_check_near(float(single["factor"]), 0.63, "chain: single finish keeps retention ratio")

	var multi: Dictionary = GameRules.chain_finishes(1000.0, 900.0, 0.95)
	_check_eq(int(multi["count"]), 3, "chain: high retention chains within one frame")
	_check_near(float(multi["factor"]), pow(0.95, 3), "chain: factor is retention^count")

	# 終盤想定: 1フレームの供給超過で千回超のFINISHが立つ。
	var endgame_r := GameRules.retention_ratio(1000)
	var endgame: Dictionary = GameRules.chain_finishes(906.5, 900.0, endgame_r)
	var count := int(endgame["count"])
	var remaining: float = 906.5 * float(endgame["factor"])
	_check(count > 1000, "chain: endgame frame yields 1000+ finishes (got %d)" % count)
	_check(remaining < 900.0, "chain: remaining polish drops below threshold")
	_check(remaining / endgame_r >= 900.0, "chain: count is minimal (one less would still cross)")

func _test_number_format() -> void:
	_check_eq(NumberFormat.group(0), "0", "format: zero")
	_check_eq(NumberFormat.group(999), "999", "format: no separator under 1000")
	_check_eq(NumberFormat.group(1234567), "1,234,567", "format: comma grouping")
	_check_eq(NumberFormat.group(-9876), "-9,876", "format: negative grouping")
	_check_eq(NumberFormat.ja_unit(0.4), "0.4", "format: sub-10 rate keeps a decimal")
	_check_eq(NumberFormat.ja_unit(5.0), "5", "format: whole rate drops .0")
	_check_eq(NumberFormat.ja_unit(42.0), "42", "format: two digits plain")
	_check_eq(NumberFormat.ja_unit(9999.0), "9999", "format: below 1万 stays plain")
	_check_eq(NumberFormat.ja_unit(100000.0), "10万", "format: 10万 flat")
	_check_eq(NumberFormat.ja_unit(123456.0), "12.3万", "format: 万 with decimal")
	_check_eq(NumberFormat.ja_unit(320000000.0), "3.2億", "format: 億")
	_check_eq(NumberFormat.ja_unit(1500000000000.0), "1.5兆", "format: 兆")

func _test_brush_unlocks() -> void:
	for brush_id: String in GameRules.BRUSH_UNLOCK_LEVELS:
		_check_eq(GameRules.brush_unlock_level(brush_id), 1,
			"unlock: %s temporarily set to Lv1" % brush_id)
		_check(GameRules.is_brush_unlocked(brush_id, 1),
			"unlock: %s available at Lv1" % brush_id)
	_check(not GameRules.is_brush_unlocked("candle", 0),
		"unlock: level gate still rejects levels below requirement")
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

	# 接触ループSEの対応
	_check_eq(ExpressionRules.touch_loop_se(ExpressionRules.TOUCH_A), "brush_pain", "se: 痛い -> brush_pain")
	_check_eq(ExpressionRules.touch_loop_se(ExpressionRules.TOUCH_D), "brush_strong", "se: 大快感 -> brush_strong")
	_check_eq(ExpressionRules.touch_loop_se(ExpressionRules.IDLE_A), "", "se: 非接触表情はループ無し")
	_check_eq(ExpressionRules.touch_loop_se(ExpressionRules.CLIMAX), "", "se: 絶頂中はループ無し")

func _test_rub_multiplier() -> void:
	_check_near(GameRules.rub_multiplier(0.0), 0.0, "rub: parked brush has no effect")
	_check_near(GameRules.rub_multiplier(-50.0), 0.0, "rub: negative speed has no effect")
	_check_near(GameRules.rub_multiplier(GameRules.RUB_START_SPEED), 0.0, "rub: tiny movement stays below threshold")
	_check_near(GameRules.rub_multiplier(300.0), 1.0, "rub: brisk stroke reaches full effect")
	_check_near(GameRules.rub_multiplier(500.0), GameRules.RUB_MAX_MULTIPLIER, "rub: fast stroke hits cap")
	_check_near(GameRules.rub_multiplier(9999.0), GameRules.RUB_MAX_MULTIPLIER, "rub: capped at max")

func _test_brush_action() -> void:
	var brush = BrushScript.new()
	brush._rub_speed = 0.0
	_check_near(brush.get_action_multiplier(), 0.0, "brush: regular brush parked has no effect")
	brush._rub_speed = 300.0
	_check_near(brush.get_action_multiplier(), 1.0, "brush: regular brush works while rubbing")
	brush.is_rotating = true
	brush.is_active = false
	_check_near(brush.get_action_multiplier(), 0.0, "brush: rotating brush off has no effect")
	brush.is_active = true
	_check_near(brush.get_action_multiplier(), 1.0, "brush: rotating brush on works while parked")
	brush.is_rotating = false
	brush.brush_id = "candle"
	brush._rub_speed = 500.0
	_check_near(brush.get_action_multiplier(), 0.0, "brush: candle has no rubbing effect")
	brush.brush_id = "teeth"
	_check_near(brush.get_action_multiplier(), 0.0, "brush: teeth have no rubbing effect")
	brush.free()
