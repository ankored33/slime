# Slime Polish - 構造の地図

> **このドキュメントの役割は「どこに何があるか」だけ。**
> 数値・一覧・挙動の詳細はここに書かない。コードが唯一の真実であり、
> 詳細を書き残したくなったら該当コードのコメントに書く。
> この方針は CLAUDE.md の「ドキュメント方針」で固定されている。

## 概要

- Godot 4.6 / GDScript（外部アドオン依存なし）、1280x720
- プロジェクトルート: `godot/`、メインシーン: `scenes/main.tscn`

## 画面フロー

タイトル → キャラ選択 → キャラ別オープニング（初回のみ） → 磨き画面 → リザルト → 選択へ戻る。
タイトルからはオプション画面（音量設定）へも行ける。
`main.gd` が可視切替で管理し、画面間は黒フェードを挟む（ヘッドレス時は即時切替）。

## ファイルの担当

| ファイル | 担当 |
|---|---|
| `scripts/main.gd` | 画面フロー・フェード・セーブ/ロード・キャラ選択/OPの表示 |
| `scripts/characters.gd` | キャラ定義データ（テキスト・座標・パス）。推敲はここだけ |
| `scripts/game_rules.gd` | 純粋なルール計算・バランス定数（Node非依存・テスト対象） |
| `scripts/game_screen.gd` | 磨き画面の進行・ゲージ・FINISH/失敗演出・表情切替 |
| `scripts/game_screen_brushes.gd` | ブラシの収集・入力・保持/ドラッグ・解禁・衝突補正 |
| `scripts/brush.gd` | ブラシ1本の性能値・こすり判定・描画 |
| `scripts/slime_target.gd` | 磨きターゲット（当たり判定・押し込みバネ） |
| `scripts/expression_rules.gd` | 状態→表情id・接触ループSEの対応 |
| `scripts/game_audio.gd` | BGM/SE/ボイス再生（ファイルを置くだけで鳴る。冒頭コメント参照） |
| `scripts/named_gauge.gd` ほか | UI部品（`named_gauges` 等のグループ経由で収集） |
| `scripts/debug_panel.gd` | 開発用チートパネル（磨き画面でF1。デバッグビルドのみ生成） |

## セーブ

`user://slime_save_v2.json`。キャラ単位の `level` / `finish_total` / `pain_fail_total` /
`opening_seen` のみ保存。詳細は `main.gd` の `_save_progress` / `_load_progress`。
音量設定は別ファイル `user://audio_settings.json`（`game_audio.gd` が管理）。

## テスト

```
cd godot
godot --headless -s res://tests/run_tests.gd       # ルールのユニットテスト
godot --headless -s res://tests/run_flow_tests.gd  # 画面フローのテスト
```

失敗時 exit 1。ルールやフローを変えたら回す。

## 関連ドキュメント

- 素材の発注書（置き場所・サイズ・命名）: `asset_list.md`
- BGMの対応表とクレジット: `bgm_credits.md`

## 未実装 / 今後

- FINISH 演出の本実装（5秒の土台のみ）
- SE 8種・ボイスの調達
- 表情差分画像（受け口は実装済み）
- ろうそくの固有機能（垂らすスパイク型）
- ゲームバランスの本調整
