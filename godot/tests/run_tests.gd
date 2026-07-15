extends SceneTree

## Headless unit tests for GameRules.
## Run: godot --headless --path godot -s res://tests/run_tests.gd

const GameRules = preload("res://scripts/game_rules.gd")

var _failures := 0
var _passes := 0

func _init() -> void:
	_test_level_for_finish_total()
	_test_polish_bonus()
	_test_pain_resist()
	_test_retention_ratio()
	_test_banked_finish()
	_test_push_out_from_rect()
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
	_check_eq(GameRules.level_for_finish_total(2), 1, "level: 2 finish -> Lv1")
	_check_eq(GameRules.level_for_finish_total(3), 2, "level: 3 finish -> Lv2")
	_check_eq(GameRules.level_for_finish_total(20), 7, "level: 20 finish -> Lv7")
	_check_eq(GameRules.level_for_finish_total(999), GameRules.MAX_LEVEL, "level: capped at MAX_LEVEL")
	_check_eq(GameRules.level_for_finish_total(-5), 1, "level: negative finish clamps to Lv1")
	_check_eq(GameRules.level_for_finish_total(0, 5), 5, "level: saved level wins when higher")
	_check_eq(GameRules.level_for_finish_total(0, 99), GameRules.MAX_LEVEL, "level: saved level capped")
	_check_eq(GameRules.level_for_finish_total(0, -3), 1, "level: bad saved level clamps to Lv1")

func _test_polish_bonus() -> void:
	_check_near(GameRules.polish_bonus(1), 1.0, "polish_bonus: Lv1 baseline")
	_check_near(GameRules.polish_bonus(5), 1.32, "polish_bonus: Lv5")
	_check_near(GameRules.polish_bonus(0), 1.0, "polish_bonus: Lv0 clamps to baseline")

func _test_pain_resist() -> void:
	_check_near(GameRules.pain_resist(1), 1.0, "pain_resist: Lv1 baseline")
	_check_near(GameRules.pain_resist(5), 0.84, "pain_resist: Lv5")
	_check_near(GameRules.pain_resist(100), 0.45, "pain_resist: floored at 0.45")

func _test_retention_ratio() -> void:
	_check_near(GameRules.retention_ratio(1), 0.0, "retention: Lv1 keeps nothing")
	_check_near(GameRules.retention_ratio(4), 0.24, "retention: Lv4")
	_check_near(GameRules.retention_ratio(100), 0.6, "retention: capped at 0.6")

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
