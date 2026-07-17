class_name GameRules
extends RefCounted

## Pure gameplay formulas shared by main.gd and game_screen.gd.
## Keep this file free of Node/scene dependencies so it stays unit-testable.

const MAX_LEVEL := 10
const FAIL_PENALTY_RATIO := 0.5

## 快感・痛みゲージの1本あたり満タン値。ゲージ系の数値はすべてこのスケールが基準。
## （内部は float だが、整数表示でも刻みが見えるよう 1000 スケールにしている）
const GAUGE_MAX := 1000.0

const PAIN_LIMIT := 1000.0
## 痛みゲージの表示・保持上限。PAIN_LIMIT より高く取ることで、ゲージ表示の
## 丸め込み（999.5以上は「1000」に見える）が失敗ラインと重ならないようにする。
const PAIN_CAP := 1100.0

## アクティブなブラシが触れていない部位の痛み自然回復量（毎秒）。
const PAIN_RECOVERY_PER_SEC := 20.0

## ろうそく固有アクション。右クリックで落としたろうが命中した時の一回分の刺激。
const WAX_POLISH_IMPACT := 120.0
const WAX_PAIN_IMPACT := 80.0
const WAX_DROP_SPEED := 90.0
const WAX_DROP_GRAVITY := 420.0
const WAX_DROP_RADIUS := 10.0
const WAX_DROP_LIFETIME := 3.0

## 歯を接触させて右クリックした時の一回分の痛みダメージ。
const BITE_PAIN_IMPACT := 240.0

## こすり判定: ブラシ移動速度(px/秒)による効果倍率。
## 微小な揺れは無視し、実際に動かしたときだけ効果が出る。
const RUB_START_SPEED := 20.0
const RUB_MAX_MULTIPLIER := 1.5

static func rub_multiplier(speed: float) -> float:
	if speed <= RUB_START_SPEED:
		return 0.0
	return clampf(0.25 + speed * 0.0025, 0.0, RUB_MAX_MULTIPLIER)

## Cumulative FINISH totals required to reach each level (index = level - 1).
## Lv6 あたりから連鎖（複数FINISH/秒）が始まり1日の獲得数が爆発するため、
## 後半のしきい値も指数的に伸ばして各レベル帯を数分ずつ観賞できるようにする。
const LEVEL_THRESHOLDS: Array[int] = [0, 2, 5, 9, 14, 20, 300, 10000, 300000, 10000000]

static func level_for_finish_total(finish_total: int, saved_level: int = 1) -> int:
	var derived := 1
	for index in range(LEVEL_THRESHOLDS.size()):
		if finish_total >= LEVEL_THRESHOLDS[index]:
			derived = index + 1
	return mini(MAX_LEVEL, maxi(1, maxi(saved_level, derived)))

## Combined polish needed for a FINISH. Starts near the 2000-point ceiling
## (both targets almost maxed) and falls as sensitivity grows with level.
static func finish_threshold(level: int) -> float:
	return maxf(900.0, 1700.0 - float(maxi(0, level - 1)) * 90.0)

## Sensitivity: polish gain multiplier. Dull at Lv1, roughly 2x by Lv10.
static func polish_bonus(level: int) -> float:
	return 0.6 + float(maxi(0, level - 1)) * 0.15

## 痛み倍率（低いほど耐久が高い）。レベルで身体の耐久が上がり、
## Lv10 で完全耐性＝ブラシを置きっぱなしにしても失敗しなくなる。
const PAIN_RESIST_BY_LEVEL: Array[float] = [
	1.0, 0.95, 0.9, 0.85, 0.8, 0.72, 0.6, 0.42, 0.2, 0.0
]

static func pain_resist(level: int) -> float:
	return PAIN_RESIST_BY_LEVEL[clampi(level, 1, MAX_LEVEL) - 1]

## FINISH後に残る快感の割合＝連鎖の燃費。終盤は1に肉薄させて連鎖を暴走させる。
## 回転ブラシ（磨き200/秒）放置時の目安ペース:
## Lv5 ~0.4回/秒, Lv6 ~1回/秒, Lv7 ~50回/秒, Lv8 ~500回/秒,
## Lv9 ~5000回/秒, Lv10 ~10万回/秒（最終目標値）。
const RETENTION_BY_LEVEL: Array[float] = [
	0.0, 0.1, 0.2, 0.35, 0.5, 0.8, 0.995, 0.99938, 0.999927, 0.9999967
]

static func retention_ratio(level: int) -> float:
	return RETENTION_BY_LEVEL[clampi(level, 1, MAX_LEVEL) - 1]

## 連鎖会計: 現在の合計快感がしきい値を超えている間に成立するFINISH回数と、
## 快感に掛ける保持係数（retention^count）を返す。終盤は1フレームで千回超に
## なるためループで数えず閉形式で求める（コストは回数によらず一定）。
static func chain_finishes(combined: float, threshold: float, retention: float) -> Dictionary:
	if threshold <= 0.0 or combined < threshold:
		return {"count": 0, "factor": 1.0}
	var ratio := clampf(retention, 0.0, 0.9999999)
	if ratio <= 0.0:
		return {"count": 1, "factor": 0.0}
	# combined * ratio^count < threshold を満たす最小の count。
	var count := int(floor(log(combined / threshold) / log(1.0 / ratio))) + 1
	return {"count": count, "factor": pow(ratio, count)}

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
