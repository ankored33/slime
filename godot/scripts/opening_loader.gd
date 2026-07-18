class_name OpeningLoader
extends RefCounted

## オープニングの各ページを res://data/opening/<キャラid>.csv から読み込む。
## 列: style, portrait, text。行の並び順がページの並び順になる。
## style は "split"（左に立ち絵・右にテキスト）| "blackout"（暗転＋中央テキスト）。
## "curtain" は日次導入演出専用の別ページ形式（main.gd が confirm_text 付きで直接組み立てる）で、
## このCSV経由では読み込まない。
## portrait は split のときだけ使う、キャラ定義のキー名（portrait / portrait_after_opening）。
## text はセル内に改行を含められる（Excel/スプレッドシートで通常のセル内改行として編集可）。
## 1行目はヘッダとして無条件でスキップする。
## ファイル欠落・不正行は必須コンテンツの欠落なので push_error/push_warning で知らせる
## （黙って空データにはしない）。

const OPENING_DIR := "res://data/opening"
const KNOWN_STYLES := ["split", "blackout"]

static func load_pages(character_id: String) -> Array[Dictionary]:
	var path := "%s/%s.csv" % [OPENING_DIR, character_id]
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		push_error("OpeningLoader: file not found: %s" % path)
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("OpeningLoader: failed to open %s (error %d)" % [path, FileAccess.get_open_error()])
		return result
	var first_row := true
	var line_number := 0
	while not file.eof_reached():
		var row := file.get_csv_line()
		line_number += 1
		if first_row:
			first_row = false
			continue
		if CsvLoaderUtil.is_trailing_blank_row(row):
			continue
		if row.size() < 3:
			push_warning("OpeningLoader: %s:%d has too few columns, skipped" % [path, line_number])
			continue
		var style := row[0].strip_edges()
		var portrait := row[1].strip_edges()
		var text := row[2]
		if style == "" or text.strip_edges() == "":
			push_warning("OpeningLoader: %s:%d has an empty style or text, skipped" % [path, line_number])
			continue
		if not KNOWN_STYLES.has(style):
			push_warning("OpeningLoader: %s:%d has unknown style '%s', skipped" % [path, line_number, style])
			continue
		var page := {"style": style, "text": text}
		if portrait != "":
			page["portrait"] = portrait
		result.append(page)
	return result
