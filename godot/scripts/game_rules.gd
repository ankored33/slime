class_name GameRules
extends RefCounted

## Pure gameplay formulas shared by main.gd and game_screen.gd.
## Keep this file free of Node/scene dependencies so it stays unit-testable.

const MAX_LEVEL := 10
const FAIL_PENALTY_RATIO := 0.5
const PAIN_LIMIT := 100.0

## アクティブなブラシが触れていない部位の痛み自然回復量（毎秒）。
const PAIN_RECOVERY_PER_SEC := 2.0

## ろうそく固有アクション。右クリックで落としたろうが命中した時の一回分の刺激。
const WAX_POLISH_IMPACT := 12.0
const WAX_PAIN_IMPACT := 8.0
const WAX_DROP_SPEED := 90.0
const WAX_DROP_GRAVITY := 420.0
const WAX_DROP_RADIUS := 7.0
const WAX_DROP_LIFETIME := 3.0

## こすり判定: ブラシ移動速度(px/秒)による効果倍率。
## 微小な揺れは無視し、実際に動かしたときだけ効果が出る。
const RUB_START_SPEED := 20.0
const RUB_MAX_MULTIPLIER := 1.5

static func rub_multiplier(speed: float) -> float:
	if speed <= RUB_START_SPEED:
		return 0.0
	return clampf(0.25 + speed * 0.0025, 0.0, RUB_MAX_MULTIPLIER)

## Cumulative FINISH totals required to reach each level (index = level - 1).
## Gaps widen by one each level (2, 3, 4, ...) so progression stretches out:
## early levels come quickly, the road to Lv10 takes 54 FINISH in total.
const LEVEL_THRESHOLDS: Array[int] = [0, 2, 5, 9, 14, 20, 27, 35, 44, 54]

static func level_for_finish_total(finish_total: int, saved_level: int = 1) -> int:
	var derived := 1
	for index in range(LEVEL_THRESHOLDS.size()):
		if finish_total >= LEVEL_THRESHOLDS[index]:
			derived = index + 1
	return mini(MAX_LEVEL, maxi(1, maxi(saved_level, derived)))

## Combined polish needed for a FINISH. Starts near the 200-point ceiling
## (both targets almost maxed) and falls as sensitivity grows with level.
static func finish_threshold(level: int) -> float:
	return maxf(90.0, 170.0 - float(maxi(0, level - 1)) * 9.0)

## Sensitivity: polish gain multiplier. Dull at Lv1, roughly 2x by Lv10.
static func polish_bonus(level: int) -> float:
	return 0.6 + float(maxi(0, level - 1)) * 0.15

static func pain_resist(level: int) -> float:
	return maxf(0.5, 1.0 - float(maxi(0, level - 1)) * 0.05)

## Polish kept after a FINISH; high levels chain climaxes back to back.
static func retention_ratio(level: int) -> float:
	return minf(0.65, float(maxi(0, level - 1)) * 0.07)

## Character level required to use each brush. Unknown ids unlock at Lv1.
const BRUSH_UNLOCK_LEVELS := {
	"finger": 1,
	"tongue": 1,
	"feather": 1,
	"fude": 1,
	"teeth": 1,
	"toothbrush": 1,
	"rotary": 1,
	"candle": 1,
	"tawashi": 1
}

static func brush_unlock_level(brush_id: String) -> int:
	return int(BRUSH_UNLOCK_LEVELS.get(brush_id, 1))

static func is_brush_unlocked(brush_id: String, level: int) -> bool:
	return level >= brush_unlock_level(brush_id)

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
