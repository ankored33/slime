class_name ExpressionRules
extends RefCounted

## 表情差分の選択ロジック（docs/表情差分と音.xlsx 準拠）。
## Node/シーン非依存で単体テスト可能に保つ。

# ブラシ無し（快感ゲージ比率で段階変化）
const IDLE_A := "idle_a"        # 怒り・軽蔑
const IDLE_B := "idle_b"        # 恥じらい・耐え
const IDLE_C := "idle_c"        # 大快感耐え
const IDLE_D := "idle_d"        # 媚び

# ブラシ当て中（快感ゲージ比率で段階変化、痛み優勢なら a）
const TOUCH_A := "touch_a"      # 痛い（痛み上昇値 > 快感上昇値）
const TOUCH_B := "touch_b"      # 恥じらい・耐え
const TOUCH_C := "touch_c"      # 快感
const TOUCH_D := "touch_d"      # 大快感

const CLIMAX := "climax"        # 絶頂（FINISH演出中）
const DESPAIR := "despair"      # 絶望（痛み限界）
const EXHAUSTED := "exhausted"  # 憔悴（FINISH後）

const DISPLAY_NAMES := {
	IDLE_A: "怒り・軽蔑",
	IDLE_B: "恥じらい・耐え",
	IDLE_C: "大快感耐え",
	IDLE_D: "媚び",
	TOUCH_A: "痛い",
	TOUCH_B: "恥じらい・耐え（当て）",
	TOUCH_C: "快感",
	TOUCH_D: "大快感",
	CLIMAX: "絶頂",
	DESPAIR: "絶望",
	EXHAUSTED: "憔悴"
}

const ALL_IDS: Array[String] = [
	IDLE_A, IDLE_B, IDLE_C, IDLE_D,
	TOUCH_A, TOUCH_B, TOUCH_C, TOUCH_D,
	CLIMAX, DESPAIR, EXHAUSTED
]

# 快感ゲージ比率（合計快感 / FINISH閾値）の段階境界
const TOUCH_MID := 0.35    # b→c
const TOUCH_HIGH := 0.75   # c→d
const IDLE_LOW := 0.15     # a→b
const IDLE_MID := 0.5      # b→c
const IDLE_HIGH := 0.9     # c→d（絶頂寸前で媚び）

## state:
##   touching: bool        アクティブなブラシがスライムに接触中か
##   polish_ratio: float   合計快感 / FINISH閾値
##   polish_rate: float    現在の快感上昇量/秒（補正込み）
##   pain_rate: float      現在の痛み上昇量/秒（補正込み）
##   climax: bool          FINISH演出中
##   despair: bool         痛み限界演出中
##   exhausted: bool       FINISH後の余韻中
static func pick(state: Dictionary) -> String:
	if bool(state.get("despair", false)):
		return DESPAIR
	if bool(state.get("climax", false)):
		return CLIMAX
	var ratio := float(state.get("polish_ratio", 0.0))
	if bool(state.get("touching", false)):
		if float(state.get("pain_rate", 0.0)) > float(state.get("polish_rate", 0.0)):
			return TOUCH_A
		if ratio < TOUCH_MID:
			return TOUCH_B
		if ratio < TOUCH_HIGH:
			return TOUCH_C
		return TOUCH_D
	if bool(state.get("exhausted", false)):
		return EXHAUSTED
	if ratio < IDLE_LOW:
		return IDLE_A
	if ratio < IDLE_MID:
		return IDLE_B
	if ratio < IDLE_HIGH:
		return IDLE_C
	return IDLE_D

static func display_name(expression_id: String) -> String:
	return str(DISPLAY_NAMES.get(expression_id, expression_id))

## ブラシ接触中に流すループSEのid（assets/audio/se/<id>.ogg）。非接触表情は ""。
const TOUCH_LOOP_SE := {
	TOUCH_A: "brush_pain",
	TOUCH_B: "brush_soft",
	TOUCH_C: "brush_mid",
	TOUCH_D: "brush_strong"
}

static func touch_loop_se(expression_id: String) -> String:
	return str(TOUCH_LOOP_SE.get(expression_id, ""))

## 素材の既定パス。expressions 辞書に指定が無いときはこの場所を探す。
static func default_image_path(chara_id: String, expression_id: String) -> String:
	return "res://assets/chara/%s/%s.png" % [chara_id, expression_id]
