# Slime Polish

Godot 4.6 製の2Dゲーム（1280x720）。画面フロー: タイトル → キャラ選択 → オープニング（初回のみ） → 磨き画面 → リザルト。

## 構成

- `godot/` — Godot プロジェクト本体（`project.godot`、メインシーンは `scenes/main.tscn`）
  - `scripts/game_rules.gd` — 純粋なゲームルール計算（Node 非依存、ユニットテスト対象）
  - `scripts/game_screen.gd` — 磨き画面の進行・ゲージ・FINISH/失敗・表情
  - `scripts/game_screen_brushes.gd` — ブラシの入力・ドラッグ・アンロック・衝突補正
  - `godot/README.md` — シーン/スクリプトの詳細な説明
- `docs/` — 仕様書（`SPEC.md`、画面仕様、素材リスト）

## テスト

```
godot --headless -s res://tests/run_tests.gd       # ルールのユニットテスト
godot --headless -s res://tests/run_flow_tests.gd  # フローのテスト
```

失敗時は exit 1。ゲームロジックを変えたら実行すること。

## ポリシー
当ゲームに登場する人物はすべて架空の成人である。
