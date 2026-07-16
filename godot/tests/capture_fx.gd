extends SceneTree

## 手動確認用: FINISH演出・失敗演出を発火させてスクリーンショットを保存する。
## 描画できる環境（WSLg等）で実行:
##   godot --path godot -s res://tests/capture_fx.gd -- <保存先ディレクトリ>
## ヘッドレスでは描画できないため CI では使わない。

var _started := false

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false

func _out_dir() -> String:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		return args[0]
	return "user://fx_shots"

func _run() -> void:
	var dir := _out_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var main_scene: PackedScene = load("res://scenes/main.tscn")
	var main: Control = main_scene.instantiate()
	root.add_child(main)
	await process_frame
	main._characters[0]["opening_seen"] = true
	main._on_character_start_pressed(0)
	var game: Control = main.get_node("GameScreen")
	await process_frame

	# FINISH演出: 合計polishを閾値超えにして発火させる
	game._slime_state["left"]["polish"] = 100.0
	game._slime_state["right"]["polish"] = 100.0
	await create_timer(0.35).timeout
	_capture(dir, "fx_finish_flash.png")
	await create_timer(1.3).timeout
	_capture(dir, "fx_finish_afterglow.png")
	await create_timer(4.0).timeout
	_capture(dir, "fx_exhausted.png")

	# 失敗演出: 痛みを限界にして暗転を確認
	game._slime_state["left"]["pain"] = 100.0
	await create_timer(0.7).timeout
	_capture(dir, "fx_fail.png")
	quit(0)

func _capture(dir: String, file_name: String) -> void:
	var image := root.get_texture().get_image()
	var path := dir.path_join(file_name)
	var err := image.save_png(path)
	print("captured %s (%s)" % [path, error_string(err)])
