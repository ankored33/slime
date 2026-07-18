class_name OpeningLoader
extends RefCounted

## オープニングの各ページを res://data/opening/<キャラid>.csv から読み込む。
## 列: style, portrait, text。行の並び順がページの並び順になる。
## style は "split"（左に立ち絵・右にテキスト）| "blackout"（暗転＋中央テキスト）。
## portrait は split のときだけ使う、キャラ定義のキー名（portrait / portrait_after_opening）。
## text はセル内に改行を含められる（Excel/スプレッドシートで通常のセル内改行として編集可）。
## 1行目はヘッダとして無条件でスキップする。ファイルが無ければ空配列を返す。

const OPENING_DIR := "res://data/opening"

static func load_pages(character_id: String) -> Array[Dictionary]:
	var path := "%s/%s.csv" % [OPENING_DIR, character_id]
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var first_row := true
	while not file.eof_reached():
		var row := file.get_csv_line()
		if first_row:
			first_row = false
			continue
		if row.size() < 3:
			continue
		var style := row[0].strip_edges()
		var portrait := row[1].strip_edges()
		var text := row[2]
		if style == "" or text.strip_edges() == "":
			continue
		var page := {"style": style, "text": text}
		if portrait != "":
			page["portrait"] = portrait
		result.append(page)
	return result
