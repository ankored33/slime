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

`main.gd` が5画面の表示切替を管理する（シーン遷移ではなく可視切替）。

1. タイトル画面（`_show_title_screen`）
2. キャラ選択画面（`_show_select_screen`、全面ポートレイト2カード＋上部選択案内＋右下1/3幅プロフィールオーバーレイ。カードクリック後に確認して遷移）
3. キャラオープニング（`_show_opening_screen`、初回のみ・`opening_seen` で管理）
4. 磨き画面（`game_screen.tscn` / `_show_game_screen`）
5. リザルト画面（`_show_result_screen`）→ 選択画面に戻る

参照: `godot/scripts/main.gd`, `godot/scenes/main.tscn`

## 3. ゲームルール定数・計算式

純粋なゲームルール計算は `GameRules`（`godot/scripts/game_rules.gd`）に集約されている。
ノード非依存の static 関数のみで構成され、単体テスト対象。

| 項目 | 値 / 式 |
|---|---|
| レベル上限 `MAX_LEVEL` | 10 |
| レベル計算 | 累計FINISHの閾値表 `LEVEL_THRESHOLDS = [0, 2, 5, 9, 14, 20, 27, 35, 44, 54]`（セーブ値と高い方を採用、1〜10にクランプ） |
| polish 上昇補正 | `0.6 + (level-1) * 0.15`（Lv10 で約2倍） |
| pain 耐性 | `max(0.5, 1.0 - (level-1) * 0.05)` |
| FINISH 後 polish 保持率 | `min(0.65, (level-1) * 0.07)`（Lv1 は全ロス、高Lvは連続絶頂） |
| pain 上限 | 100.0（到達で強制終了） |
| 失敗ペナルティ | 当日 FINISH 数を半減（切り捨て） |
| FINISH しきい値 | `max(90, 170 - (level-1) * 9)`（磨きターゲット2点の polish 合計） |
| ブラシ解禁 | brush-a: Lv1 / brush-c: Lv2 / brush-b: Lv3 / brush-d: Lv5 / brush-e（回転）: Lv7 |

## 4. 磨き画面（ゲームプレイ）

参照: `godot/scripts/game_screen.gd`, `godot/scripts/game_screen_brushes.gd`,
`godot/scenes/game_screen.tscn`

- スライム2匹（left/right）それぞれが `polish` / `pain` ゲージ（0〜100）を持つ。
- ブラシ（`brush.gd`）:
  - クリックで保持/解除し、保持中はマウスへ追従（プレイフィールド内にクランプ）
  - 通常ブラシ4種はON/OFFなし。実際にこすったときだけ効果が出る
  - 回転ブラシだけ個別ON/OFFでき、ON中は静止したまま効果が出る
  - 特殊技（一時ブースト）を手動発動
  - ブラシ同士の重なりは押し出しで解決（`_resolve_brush_overlaps`）
  - 壁ゾーン(`wall_zone.gd`)からの押し出し（`GameRules.push_out_from_rect`）
  - 収集・入力・解禁UI・衝突補正は `game_screen_brushes.gd` が担当
- こすり判定: ブラシの移動速度（平滑化した px/秒）で効果に倍率が掛かる
  （`GameRules.rub_multiplier`、20px/秒以下は0倍、素早く磨いて最大1.5倍。快感・痛み・癒しに効く）。
  回転ブラシはON中、移動速度にかかわらず1.0倍。
- 痛みの回復:
  - アクティブなブラシが触れていない部位は毎秒 `PAIN_RECOVERY_PER_SEC`(2.0) 自然回復
  - 癒し系ブラシ（羽 = `pain_soothe_per_sec` > 0）は、こすっている間に痛みを減らす
    （こすり速度と特殊技の倍率が乗る）
- FINISH: 2匹の polish 合計が `finish_threshold` を超えると発生。
  当日 FINISH 数を加算し、polish は保持率分だけ残して減少。pain は継続。
- 1日の終了:
  - End Day ボタンで任意終了（成果は全額持ち帰り）
  - どちらかの pain が 100% で強制失敗終了（成果半減）
- 終了時に `day_finished` シグナルで結果 Dictionary を `main.gd` へ通知。

## 5. キャラクターと成長

参照: `godot/scripts/main.gd`（`_characters`）, `godot/scripts/slime_target.gd`

- キャラは2人: `general`（女将軍）/ `admiral`（エルフ提督）。
  ※旧Web版の「スライム3種（mint / peach / azure）」構成は廃止。実装するのはこの2人のみ。
- キャラごとに色・磨きターゲット2点（left / right）の配置座標・当たり判定半径・画像パス・
  表情画像辞書（`expressions`）・オープニングページ（`opening_pages`）を持つ。
- 成長はキャラ単位で管理: `level`, `finish_total`, `pain_fail_total`, `opening_seen`。
- 選択画面では `opening_seen` 後に `portrait_after_opening` へ切り替える。
- デバッグ用の状態リセットは対象キャラだけをLv1・各累計0・オープニング未視聴へ戻して保存する。
- 現状、キャラデータは `main.gd` にハードコード（将来リソース化の候補）。

## 6. データ保存

- 保存先: `user://slime_save_v2.json`
- 形式: `{"version": 2, "characters": [{"id", "level", "finish_total", "pain_fail_total", "opening_seen"}]}`
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

- アート・音声アセットの本移植（現状はプレースホルダ描画）。必要素材の一覧は `asset_list.md`
- FINISH 演出の本実装（5秒の土台のみ）
- 音素材（再生システムは `game_audio.gd` で実装済み。`assets/audio/` に OGG を置くと鳴り出す。
  BGM2曲・SE8種・任意ボイスの内訳は `asset_list.md` 参照）
- 表情差分は `expression_rules.gd` + `game_screen.gd` で実装済み。
  画像は `res://assets/chara/<キャラid>/<表情id>.png` を置くと自動で差し替わる
- 種データのリソース化（`.tres`）
- ゲームバランスの本調整（現行値は暫定）
