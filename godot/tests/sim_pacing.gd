extends SceneTree

## レベル別の体感ペース表を出す開発ツール（テストではない・合否なし）。
## 実行: godot --headless --path godot -s res://tests/sim_pacing.gd
##
## 想定プレイ: 回転ブラシ(磨き200/秒)を左に設置、右を指(160/秒×こすり1.0)で磨き続ける。
## 各サイドはGAUGE_MAXでキャップ。合計がしきい値を超えたぶんだけ連鎖会計。
## ※ Lv1〜5の実プレイはFINISHごとに5秒のフル演出停止が挟まる（表の秒数には含めない）。
## ※ 痛みによる中断は考慮しない（Lv20以下の実プレイはこれより遅くなる）。

const GameRules = preload("res://scripts/game_rules.gd")

func _init() -> void:
	print("Lv | しきい値 |    感度 | 実測レート/秒 | 1FINISHあたり")
	for level: int in [1, 2, 3, 4, 5, 6, 8, 10, 17, 18, 21, 50, 100, 300, 500, 1000]:
		var bonus := GameRules.polish_bonus(level)
		var threshold := GameRules.finish_threshold(level)
		var left := 0.0
		var right := 0.0
		var total := 0
		var dt := 1.0 / 60.0
		var seconds := 60.0
		for i in range(int(seconds / dt)):
			# 快感には上限がない（game_screen.gd の _apply_brush_effects と同じ想定）。
			left += 200.0 * bonus * dt
			right += 160.0 * bonus * dt
			var count := GameRules.finish_count(left + right, threshold)
			total += count
			if count > 0:
				left = 0.0
				right = 0.0
		var rate := float(total) / seconds
		var per_finish := "%.1f秒" % (1.0 / rate) if rate > 0.0 and rate < 2.0 else "-"
		print("%4d | %6.0f | %8.1f | %12.1f | %s" % [level, threshold, bonus, rate, per_finish])
	quit(0)
