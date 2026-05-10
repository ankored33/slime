# Slime Polish - 仕様書（現行）

このドキュメントは、現在のコードベースで有効な仕様をまとめたものです。

## 1. 概要
- タイトル: Slime Polish
- 技術: HTML5 Canvas + JavaScript（フレームワークなし）
- 現在の運用モード: エディタ主導のレイアウト構築モード
- 解像度: 1280x720 固定

## 2. 現在の画面状態
- 実行時はメインループ（`game`）画面のみを描画する
- 旧タイトル/オプション/選択/結果画面の機能コードは残存するが、通常フローでは表示しない
- スライム・ブラシ・HUD・Finish演出は描画停止中（機能コードは保持）

参照: `js/main.js`, `js/screens.js`, `js/render.js`

## 3. レイアウトエディタ

### 3.1 起動と構成
- `F2` でレイアウトエディタを開閉
- レイアウトエディタとは別に、画面上部に「画面管理バー」を常時表示
- レイアウトは `localStorage` に保存

参照: `js/layout.js`, `styles.css`

### 3.2 画面管理バー（エディタ外）
- 画面一覧の選択
- 画面の追加（新規画面名入力 + `Add Screen`）
- 追加した画面ごとに独立した要素配列を保持

保存データ:
- `editor.screens`: 画面名配列
- `editor.selectedScreen`: 現在の編集対象画面
- `elements[screenName]`: 画面ごとの要素配列

参照: `js/layout.js` (`renderScreenManager`, `addScreen`, `getActiveScreenName`)

### 3.3 要素タイプ
単一ドロップダウンで以下を選択:
- `text`
- `panel`
- `button`
- `object`
- `gauge`

参照: `js/layout.js` (`TYPE_OPTIONS`)

### 3.4 共通要素プロパティ
- `name`
- `z`（表示順）
- `x`, `y`, `w`, `h`（画面ピクセル基準）
- `imagePath`
- `fit` (`contain` / `cover` / `stretch`)
- `anchor` (`topleft` / `center`)

補足:
- `imageFile` でローカル画像選択可能（`data:` URLとして `imagePath` に保存）

### 3.5 タイプ別プロパティ
- `text`: `text`, `size`, `align`, `verticalAlign` (`top` / `middle` / `bottom`), `fontFamily`, `weight`, `color`
- `button`: `text`
- `gauge`: `value`, `max`, `fillColor`, `bgColor`, `showPercent`
- `object`: `hitEnabled` (true / false), `role` (`none` / `slime` / `wall`), `hitShape` (`rect` / `circle`)

### 3.6 編集操作
- `Add` / `Remove` / `Reset`
- キャンバス上ドラッグ移動
- 選択中要素はハイライト表示
- ハイライト枠の辺・角ドラッグでリサイズ
  - 辺: 1軸
  - 角: 2軸

参照: `js/layout.js` (`handlePointerDown`, `handlePointerMove`, `getEditorCursor`), `js/render.js`

### 3.7 レイヤー（表示順）
- 描画は `z` 昇順（大きい値ほど手前）
- クリック/選択判定は `z` 降順（手前を優先）

参照: `js/render.js` (`drawLayoutElements`), `js/layout.js` (`findElementAt`)

### 3.8 Undo / Redo
- ボタン: `Undo`, `Redo`
- ショートカット:
  - `Ctrl+Z` / `Cmd+Z`: Undo
  - `Ctrl+Y` / `Cmd+Shift+Z`: Redo
- 履歴上限: 120ステップ
- 対象操作:
  - 要素追加/削除
  - プロパティ編集
  - 画面追加
  - 編集対象画面切替
  - ドラッグ移動 / リサイズ（1操作単位）

参照: `js/layout.js` (`history`, `runWithHistory`, `undoLayout`, `redoLayout`)

## 4. 描画仕様（要素）

### 4.1 共通
- `elements[selectedScreen]` を描画
- 画像設定時は `fit` に従って描画

### 4.2 タイプ別の素描画
- `panel`: 角丸パネル
- `button`: ボタン風描画
- `object`: 画像未設定時は点線枠
- `text`: テキスト描画
- `gauge`: 背景バー + 充填バー + 枠 + 任意ラベル + 任意%表示

参照: `js/render.js` (`drawLayoutElements`)

## 5. 入力仕様
- マウス/ポインタ:
  - エディタ表示中は要素選択・移動・リサイズ
- キーボード:
  - `F2`: エディタ開閉
  - `Ctrl/Cmd + Z`, `Ctrl + Y`, `Cmd + Shift + Z`: Undo/Redo

参照: `js/main.js`, `js/layout.js`

## 6. データ保存
- 進捗保存キー: `slime_polish_progress_v1`
- レイアウト保存キー: `slime_layout_editor_v2:<resolutionId>`
  - 現在は解像度固定運用のため実質1系統

参照: `js/storage.js`, `js/constants.js`, `js/layout.js`

## 7. 設定（config.js）
- `game.width = 1280`
- `game.height = 720`
- `game.fixedScale = true`
- `art.fonts[]` にフォント定義を追加可能
  - 形式: `{ family, path, weight?, style? }`
  - `path` は `./assets/fonts/` 配下のみ有効（それ以外は無視）
- スライム定義・ブラシ設定・ズーム設定は保持

参照: `config.js`, `js/constants.js`

## 8. 保持している未使用/将来向けコード
- 旧画面群（title/options/select/result）の描画・遷移コード
- スライム磨きロジック（進捗/痛み/Finish/演出）
- 音声再生関連

これらは「今は表示に使っていない」状態で保持されている。

## 9. 現在の開発方針
- まずエディタで画面レイアウトを構築
- 次に要素IDベースで機能を紐付ける
  - 例: 「このボタンにこの処理」「このゲージにこの値ソース」
- UI機能とゲームロジックを段階的に再接続する
