class_name CharacterDefs

## キャラ定義データ（ロジックなし）。テキストの推敲・座標調整はこのファイルだけ触ればよい。
##
## - left / right は磨きターゲット2点の配置。
##   座標は 800x800 素材の画面換算: screen_x = 280 + src_x*0.9, screen_y = src_y*0.9
##   （640x720 枠・cover 表示・左右40pxクロップ前提。素材を差し替えたら要再計測）
##   image_native_size: true なら乳首画像を等倍表示し、当たり判定半径も画像サイズから取る
##   （radius 指定は無視される）。
##   breast: 胸レイヤー画像（立ち絵と同一キャンバスの透過PNG）。指定すると立ち絵の上に
##   重なり、乳首ターゲットの動きに応じて根元を固定したまま伸び縮みする（breast_layer.gd）。
##   breast_root: 伸縮の固定点（付け根）。breast 画像の素材ピクセル座標（800x800基準、
##   src_x/src_y そのまま。screen換算はしない）で指定する。身体に近い側・下端が目安。
##   breast を指定して breast_root を書き忘れるとレイヤーは追加されない。
## - expressions は表情id → 画像パス。空のままなら既定パス
##   res://assets/chara/<id>/<表情id>.png を探す（無ければ表情名ラベルで代替表示）。
##   表情id一覧: idle_a〜idle_d（ブラシ無し）, touch_a〜touch_d（ブラシ当て）,
##   climax（絶頂）, despair（絶望）, exhausted（憔悴）。詳細は expression_rules.gd。
## - dialogue は表情id → セリフ候補の配列（画面下部のセリフパネルに「」付きで表示）。
##   その表情に入るたびランダムに1つ選ぶ。expressions と同じ表情idキーを使う。
##   未設定・空配列の表情ではパネルを空欄にする。
##   実体はコードに書かず `godot/data/dialogue/<キャラid>.csv` に置く
##   （列: expression_id, line。同じ表情idを複数行書くと候補が増える）。
##   Excel/スプレッドシートで直接編集できる。読み込みは dialogue_loader.gd。
## - opening_pages: style = "split"（左に立ち絵・右にテキスト）| "blackout"（暗転＋中央テキスト）。
##   split の portrait にはキャラ定義のキー名（portrait / portrait_after_opening）を書く。
##   表示は「。」および既存の改行ごとに1行としてフェードインする（opening_screen.gd）。
##   実体はコードに書かず `godot/data/opening/<キャラid>.csv` に置く
##   （列: style, portrait, text。行の並び順がページの並び順。textはセル内改行可）。
##   Excel/スプレッドシートで直接編集できる。読み込みは opening_loader.gd。
## - profile はオープニング未読時、profile_after_opening は既読時に選択画面へ出る
##   （after 側が空文字なら profile を使い回す）。
## - name_after_opening / epithet_after_opening: オープニング既読後の表示名と肩書き
##   （虜囚番号・虜囚区分）。既読後は全画面で本名・二つ名の代わりにこれが出る。
## - result: リザルト画面と、磨き開始前の左右分割演出で共用するキャラ画像。
## - level / finish_total / pain_fail_total / opening_seen は初期値。実際の値はセーブが上書きする。

## 表示名の解決だけここに置く（どの画面も同じ規則で名前を出すため）。
static func display_name(chara: Dictionary) -> String:
	return _resolve_after_opening(chara, "name", "name_after_opening")

static func display_epithet(chara: Dictionary) -> String:
	return _resolve_after_opening(chara, "epithet", "epithet_after_opening")

static func _resolve_after_opening(chara: Dictionary, base_key: String, after_key: String) -> String:
	if bool(chara.get("opening_seen", false)):
		var after := str(chara.get(after_key, ""))
		if after != "":
			return after
	return str(chara.get(base_key, ""))

static func create() -> Array[Dictionary]:
	return [
		{
			"id": "general",
			"name": "アリスティア",
			"epithet": "《眩耀たる漆黒》",
			"name_after_opening": "虜囚番号N10564",
			"epithet_after_opening": "帝国の一般虜囚",
			"portrait": "res://assets/chara/general/portrait.png",
			"portrait_after_opening": "res://assets/chara/general/portrait_after_opening.png",
			"result": "res://assets/chara/general/result.png",
			"game_background": "res://assets/chara/general/game_background.png",
			"expressions": {},
			"dialogue": DialogueLoader.load_dialogue("general"),
			"profile": "ネブラレア王国将軍／同国軍総司令官\n\n能力評価：\n膂力　S\n技巧　SS\n魔力　S\n策略　B\n戦略　A",
			"profile_after_opening": "種族：人間\n性別：女\n年齢：21\n捕縛日：帝国暦2025年8月\n収監場所：帝国矯罰院",
			"color": Color(1.0, 0.71, 0.78, 0.92),
			"left": {
				"position": Vector2(413.2, 503.1),
				"radius": 40.0,
				"image": ""
			},
			"right": {
				"position": Vector2(679.6, 350.1),
				"radius": 40.0,
				"image": ""
			},
			"level": 1,
			"finish_total": 0,
			"pain_fail_total": 0,
			"opening_seen": false,
			"opening_pages": OpeningLoader.load_pages("general")
		},
		{
			"id": "admiral",
			"name": "チチカ・エルマ",
			"epithet": "《緋色の方程式》",
			"name_after_opening": "虜囚番号C39312",
			"epithet_after_opening": "帝国の一般虜囚",
			"portrait": "res://assets/chara/admiral/portrait.png",
			"portrait_after_opening": "res://assets/chara/admiral/portrait_after_opening.png",
			"result": "res://assets/chara/admiral/result.png",
			"game_background": "res://assets/chara/admiral/game_background.png",
			"expressions": {},
			"dialogue": DialogueLoader.load_dialogue("admiral"),
			"profile": "ザコチック条約機構 軍事委員会議長\n\n能力評価：\n膂力　C\n技巧　C\n魔力　B\n策略　S\n戦略　SSS",
			"profile_after_opening": "種族：ハイエルフ\n性別：女\n年齢：455\n捕縛日：帝国暦2025年8月\n収監場所：帝国矯罰院",
			"color": Color(0.47, 0.9, 0.78, 0.92),
			"left": {
				"position": Vector2(372.7, 390.2),
				"radius": 40.0,
				"image": "res://assets/chara/admiral/nipple_left.png",
				"image_native_size": true,
				"breast": "res://assets/chara/admiral/breast_left.png",
				"breast_root": Vector2(461.0, 765.0)
			},
			"right": {
				"position": Vector2(921.7, 285.3),
				"radius": 40.0,
				"image": ""
			},
			"level": 1,
			"finish_total": 0,
			"pain_fail_total": 0,
			"opening_seen": false,
			"opening_pages": OpeningLoader.load_pages("admiral")
		}
	]
