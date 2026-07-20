class_name ResultScreen
extends RefCounted

## リザルト画面の描画・タイプライター演出。main.gd から Node 参照を受け取って動かす。

const GameAudio = preload("res://scripts/game_audio.gd")

## リザルト本文のタイプライター演出の速度（1秒あたりの文字数）。
const TYPE_CHARS_PER_SEC := 25.0
## タイプ演出後にキャラ画像をフェードインする長さ。
const IMAGE_FADE_DURATION := 0.3
## リザルト画面に入ってからタイプ演出が始まるまでの間。
const TYPE_START_DELAY := 1.0

var _screen: Control
var _date_label: Label
var _body: RichTextLabel
var _chara_image: TextureRect
var _return_button: Button
var _type_tween: Tween

func setup(
	screen: Control,
	date_label: Label,
	body: RichTextLabel,
	chara_image: TextureRect,
	return_button: Button
) -> void:
	_screen = screen
	_date_label = date_label
	_body = body
	_chara_image = chara_image
	_return_button = return_button
	_body.gui_input.connect(_on_body_gui_input)

func render(chara: Dictionary, last_result: Dictionary) -> void:
	_update_chara_image(str(chara["result"]))
	var today := Time.get_date_dict_from_system()
	_date_label.text = "帝国暦%d年%d月%d日" % [int(today["year"]), int(today["month"]), int(today["day"])]
	var level_after := int(chara["level"])
	var level_before := int(last_result.get("level_before", level_after))
	var level_line := "矯正進度: %d / 100" % level_after
	if level_after > level_before:
		GameAudio.play_se("levelup")
		level_line = "矯正進度: %d → [b][bgcolor=#ffd75e][color=#3a1208] %d [/color][/bgcolor][/b] / 100　[bgcolor=#ffd75e][color=#3a1208][b] LEVEL UP! +%d [/b][/color][/bgcolor]" % [
			level_before, level_after, level_after - level_before]
	var failed := bool(last_result.get("failed_by_pain", false))
	var status_line := "痛みが限界に達した。今日の成果は半減となった。\n" if failed else ""
	var tool_lines := _format_finish_by_tool(last_result.get("finish_count_by_tool", {}))
	_body.text = (
		"[b]%s[/b]\n"
		+ "%s\n"
		+ "%s\n"
		+ "本日の絶頂回数: %s\n"
		+ "%s"
		+ "累計絶頂回数: %s\n"
		+ "苦痛超過による矯正中断回数: %d"
	) % [
		str(last_result.get("species_name", "？？？")),
		level_line,
		status_line,
		NumberFormat.group(int(last_result.get("day_finish_count", 0))),
		tool_lines,
		NumberFormat.group(int(chara["finish_total"])),
		int(chara["pain_fail_total"])
	]
	_start_typing()

## リザルト画面の登場演出。日付→本文の順に1文字ずつタイプし、終わったら
## キャラ画像を短くフェードインして、最後に戻るボタンを出す。クリックで全表示に飛ばせる。
func _start_typing() -> void:
	if _type_tween:
		_type_tween.kill()
	_return_button.visible = false
	_chara_image.modulate.a = 0.0
	if DisplayServer.get_name() == "headless":
		complete_typing()
		return
	_date_label.visible_characters = 0
	_body.visible_characters = 0
	var date_total := _date_label.get_total_character_count()
	var body_total := _body.get_total_character_count()
	_type_tween = _date_label.create_tween()
	_type_tween.tween_interval(TYPE_START_DELAY)
	_type_tween.tween_property(
		_date_label, "visible_characters", date_total, date_total / TYPE_CHARS_PER_SEC)
	_type_tween.tween_property(
		_body, "visible_characters", body_total, body_total / TYPE_CHARS_PER_SEC)
	_type_tween.tween_property(
		_chara_image, "modulate:a", 1.0, IMAGE_FADE_DURATION)
	_type_tween.tween_callback(func() -> void: _return_button.visible = true)

func is_typing() -> bool:
	return _screen.visible and _type_tween != null and _type_tween.is_running()

func complete_typing() -> void:
	if _type_tween:
		_type_tween.kill()
	_date_label.visible_characters = -1
	_body.visible_characters = -1
	_chara_image.modulate.a = 1.0
	_return_button.visible = true

func _on_body_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and is_typing():
		complete_typing()
		_body.get_viewport().set_input_as_handled()

## { ツール表示名: FINISH数 } を件数の多い順に "- 指: 12\n" 形式へ整形する。空なら空文字。
func _format_finish_by_tool(by_tool: Dictionary) -> String:
	if by_tool.is_empty():
		return ""
	var tool_names := by_tool.keys()
	tool_names.sort_custom(func(a, b): return int(by_tool[a]) > int(by_tool[b]))
	var lines := "内訳:\n"
	for tool_name in tool_names:
		lines += "- %s: %s\n" % [tool_name, NumberFormat.group(int(by_tool[tool_name]))]
	return lines + "\n"

## キャラ定義の result 画像があればリザルト画面右に表示する。無ければ隠す。
func _update_chara_image(path: String) -> void:
	if ResourceLoader.exists(path):
		var texture := load(path)
		if texture is Texture2D:
			_chara_image.texture = texture
			_chara_image.visible = true
			return
	_chara_image.visible = false
