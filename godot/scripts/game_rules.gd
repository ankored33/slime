class_name GameRules
extends RefCounted

## Pure gameplay formulas shared by main.gd and game_screen.gd.
## Keep this file free of Node/scene dependencies so it stays unit-testable.

const MAX_LEVEL := 8
const LEVEL_STEP := 3
const FAIL_PENALTY_RATIO := 0.5
const PAIN_LIMIT := 100.0

static func level_for_finish_total(finish_total: int, saved_level: int = 1) -> int:
	var derived := 1 + maxi(0, finish_total) / LEVEL_STEP
	return mini(MAX_LEVEL, maxi(1, maxi(saved_level, derived)))

static func polish_bonus(level: int) -> float:
	return 1.0 + float(maxi(0, level - 1)) * 0.08

static func pain_resist(level: int) -> float:
	return maxf(0.45, 1.0 - float(maxi(0, level - 1)) * 0.04)

static func retention_ratio(level: int) -> float:
	return minf(0.6, float(maxi(0, level - 1)) * 0.08)

static func banked_finish(day_finish_count: int, failed_by_pain: bool) -> int:
	if failed_by_pain:
		return int(floor(float(day_finish_count) * FAIL_PENALTY_RATIO))
	return day_finish_count

static func push_out_from_rect(center: Vector2, radius: float, rect: Rect2) -> Vector2:
	var nearest := Vector2(
		clampf(center.x, rect.position.x, rect.position.x + rect.size.x),
		clampf(center.y, rect.position.y, rect.position.y + rect.size.y)
	)
	var delta := center - nearest
	var distance := delta.length()
	if distance >= radius:
		return center
	if distance > 0.0001:
		return center + delta.normalized() * (radius - distance)

	# Exact overlap on rect edge or inside; escape through the shortest axis.
	var left_gap := absf(center.x - rect.position.x)
	var right_gap := absf((rect.position.x + rect.size.x) - center.x)
	var top_gap := absf(center.y - rect.position.y)
	var bottom_gap := absf((rect.position.y + rect.size.y) - center.y)
	var min_gap := minf(minf(left_gap, right_gap), minf(top_gap, bottom_gap))
	if min_gap == left_gap:
		return Vector2(rect.position.x - radius, center.y)
	if min_gap == right_gap:
		return Vector2(rect.position.x + rect.size.x + radius, center.y)
	if min_gap == top_gap:
		return Vector2(center.x, rect.position.y - radius)
	return Vector2(center.x, rect.position.y + rect.size.y + radius)
