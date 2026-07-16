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

## 設計方針

**コードとデータを最初から分離する。** 「コードを読まない人が編集したくなるもの」
（セリフ・プロフィール等のテキスト、座標、バランス数値、アセットパス、対応表）は
main.gd 等のロジックに直書きせず、最初から専用のデータファイルに置く。

- キャラ関連のデータ → `godot/scripts/characters.gd`（`CharacterDefs`）
- ゲームバランス定数 → `godot/scripts/game_rules.gd`
- 素材の対応・出典 → `docs/`（例: `bgm_credits.md`）
- 新しい種類のデータが増えるときは、main.gd に足す前に置き場を決める

## ポリシー
当ゲームに登場する人物はすべて架空の成人である。
