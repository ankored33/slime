class_name DialogueLoader
extends RefCounted

## セリフCSV（res://data/dialogue/<キャラid>.csv）を読み込む。
## 列: expression_id, line。同じ表情idの行を複数書くと候補が増える
## （その表情に入るたびランダムに1つ選ぶ。選ぶ側は game_screen.gd）。
## 1行目はヘッダとして無条件でスキップする。ファイルが無ければ空辞書を返す。

const DIALOGUE_DIR := "res://data/dialogue"

static func load_dialogue(character_id: String) -> Dictionary:
	var path := "%s/%s.csv" % [DIALOGUE_DIR, character_id]
	var result: Dictionary = {}
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
		if row.size() < 2:
			continue
		var expression_id := row[0].strip_edges()
		var line := row[1]
		if expression_id == "" or line.strip_edges() == "":
			continue
		if not result.has(expression_id):
			result[expression_id] = []
		result[expression_id].append(line)
	return result
