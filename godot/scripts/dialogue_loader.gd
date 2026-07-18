class_name DialogueLoader
extends RefCounted

## セリフCSV（res://data/dialogue/<キャラid>.csv）を読み込む。
## 列: expression_id, line。同じ表情idの行を複数書くと候補が増える
## （その表情に入るたびランダムに1つ選ぶ。選ぶ側は game_screen.gd）。
## 1行目はヘッダとして無条件でスキップする。
## ファイル欠落・不正行は必須コンテンツの欠落なので push_error/push_warning で知らせる
## （黙って空データにはしない）。

const DIALOGUE_DIR := "res://data/dialogue"

static func load_dialogue(character_id: String) -> Dictionary:
	var path := "%s/%s.csv" % [DIALOGUE_DIR, character_id]
	var result: Dictionary = {}
	if not FileAccess.file_exists(path):
		push_error("DialogueLoader: file not found: %s" % path)
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DialogueLoader: failed to open %s (error %d)" % [path, FileAccess.get_open_error()])
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
		if row.size() < 2:
			push_warning("DialogueLoader: %s:%d has too few columns, skipped" % [path, line_number])
			continue
		var expression_id := row[0].strip_edges()
		var line := row[1]
		if expression_id == "" or line.strip_edges() == "":
			push_warning("DialogueLoader: %s:%d has an empty expression_id or line, skipped" % [path, line_number])
			continue
		if not ExpressionRules.ALL_IDS.has(expression_id):
			push_warning("DialogueLoader: %s:%d has unknown expression_id '%s', skipped" % [path, line_number, expression_id])
			continue
		if not result.has(expression_id):
			result[expression_id] = []
		result[expression_id].append(line)
	return result
