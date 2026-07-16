# Slime Polish - 実装仕様（現行 / Godot 版）

このドキュメントは、現在のコードベース（Godot 移植版）で有効な実装仕様をまとめたものです。
ゲームデザイン仕様は `game_spec_v0_2.md`、画面仕様は `screen_spec_v0_1.md` を参照してください。

> 旧 HTML5 Canvas + JavaScript 版（`web_legacy`）とそのレイアウトエディタは削除済みです。
> 本ドキュメントの旧版（レイアウトエディタ仕様）は Git 履歴を参照してください。

## 1. 概要
- タイトル: Slime Polish
- 技術: Godot 4.6 / GDScript（外部アドオン依存なし）
- プロジェクトルート: `godot/`
- 解像度: 1280x720（stretch mode: `canvas_items`）

## 2. 画面フロー

`main.gd` が3画面の表示切替を管理する（シーン遷移ではなく可視切替）。

1. スライム選択画面（`_show_select_screen`）
2. 磨き画面（`game_screen.tscn` / `_show_game_screen`）
3. リザルト画面（`_show_result_screen`）→ 選択画面に戻る

参照: `godot/scripts/main.gd`, `godot/scenes/main.tscn`

## 3. ゲームルール定数・計算式

純粋なゲームルール計算は `GameRules`（`godot/scripts/game_rules.gd`）に集約されている。
ノード非依存の static 関数のみで構成され、単体テスト対象。

| 項目 | 値 / 式 |
|---|---|
| レベル上限 `MAX_LEVEL` | 8 |
| レベル計算 | `1 + finish_total / 3`（LEVEL_STEP=3、セーブ値と高い方を採用、1〜8にクランプ） |
| polish 上昇補正 | `1.0 + (level-1) * 0.08` |
| pain 耐性 | `max(0.45, 1.0 - (level-1) * 0.04)` |
| FINISH 後 polish 保持率 | `min(0.6, (level-1) * 0.08)`（Lv1 は全ロス） |
| pain 上限 | 100.0（到達で強制終了） |
| 失敗ペナルティ | 当日 FINISH 数を半減（切り捨て） |
| FINISH しきい値 | 160.0（`game_screen.gd` の `finish_threshold`、2匹の polish 合計） |

## 4. 磨き画面（ゲームプレイ）

参照: `godot/scripts/game_screen.gd`, `godot/scenes/game_screen.tscn`

- スライム2匹（left/right）それぞれが `polish` / `pain` ゲージ（0〜100）を持つ。
- ブラシ（`brush.gd`）:
  - ドラッグで移動（`follow_speed` による lerp 追従、プレイフィールド内にクランプ）
  - 個別 ON/OFF トグル
  - 特殊技（一時ブースト）を手動発動
  - ブラシ同士の重なりは押し出しで解決（`_resolve_brush_overlaps`）
  - 壁ゾーン(`wall_zone.gd`)からの押し出し（`GameRules.push_out_from_rect`）
- FINISH: 2匹の polish 合計が `finish_threshold` を超えると発生。
  当日 FINISH 数を加算し、polish は保持率分だけ残して減少。pain は継続。
- 1日の終了:
  - End Day ボタンで任意終了（成果は全額持ち帰り）
  - どちらかの pain が 100% で強制失敗終了（成果半減）
- 終了時に `day_finished` シグナルで結果 Dictionary を `main.gd` へ通知。

## 5. スライム種と成長

参照: `godot/scripts/main.gd`（`_species_list`）, `godot/scripts/slime_target.gd`

- 種は3種（mint / peach / azure）。種ごとに色・左右それぞれの配置座標・当たり判定半径・画像パスを持つ。
- 成長は種単位で管理: `level`, `finish_total`, `pain_fail_total`。
- 現状、種データは `main.gd` にハードコード（将来リソース化の候補）。

## 6. データ保存

- 保存先: `user://slime_save_v1.json`
- 形式: `{"version": 1, "species": [{"id", "level", "finish_total", "pain_fail_total"}]}`
- ロード時はセーブされたレベルと `finish_total` からの導出レベルの高い方を採用。
- 不正な形式のセーブは警告を出して無視する。

参照: `godot/scripts/main.gd`（`_save_progress`, `_load_progress`）

## 7. UI 部品

- `named_gauge.tscn` / `named_gauge.gd`: `gauge_id`（例: `polish-L`, `pain-R`）で識別されるゲージ。
  `named_gauges` グループ経由で `game_screen.gd` が収集する。
- 同様に `brushes`, `wall_zones`, `slime_targets` グループで各ノードを収集する。

## 8. テスト

- ランナー: `godot/tests/run_tests.gd`（`SceneTree` 継承のヘッドレススクリプト）
- 実行方法:
  ```
  cd godot
  godot --headless -s res://tests/run_tests.gd
  ```
- 対象: `GameRules` の全計算式（レベル、補正、保持率、ペナルティ、矩形押し出し）
- 失敗があると終了コード 1 を返す。

## 9. 未実装 / 今後

- アート・音声アセットの本移植（現状はプレースホルダ描画）
- FINISH 演出の本実装（5秒の土台のみ）
- 音の差分（`表情差分と音.xlsx` の音側。表情差分は `expression_rules.gd` + `game_screen.gd` で実装済み。
  画像は `res://assets/chara/<キャラid>/<表情id>.png` を置くと自動で差し替わる）
- 種データのリソース化（`.tres`）
- ゲームバランスの本調整（現行値は暫定）
