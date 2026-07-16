class_name GameAudio
extends Node

## 音システムの土台。素材ファイルが無い間は何も鳴らさず黙って動く。
## 素材の置き場所（OGG推奨。置くだけで鳴り出す）:
##   BGM:   res://assets/audio/bgm/<id>.ogg
##     title（タイトル画面） / select（キャラ選択・リザルト） /
##     opening_<キャラid>（キャラ別OP） / game_a〜game_c（磨き画面・ランダム）
##   SE:    res://assets/audio/se/<id>.ogg       （climax / despair / heartbeat / ui_click /
##                                                 brush_soft / brush_mid / brush_strong / brush_pain）
##   ボイス: res://assets/audio/voice/<キャラid>/<表情id>.ogg
## main.tscn に1ノード置くことで static 経由（GameAudio.play_se(...) 等）で
## どこからでも呼べる。ノードが無い環境（単体テスト等）では全呼び出しが no-op。

static var _instance: GameAudio

const SETTINGS_PATH := "user://audio_settings.json"
const SE_POOL_SIZE := 8
## 表情替わりのたびにボイスが連射されないための最小間隔（秒）。
const VOICE_MIN_INTERVAL := 0.8

# BGM素材は音圧が高いので既定を下げておく（GameAudio.set_volume で変更可）。
var _volumes := {"bgm": 0.4, "se": 1.0, "voice": 1.0}
var _stream_cache: Dictionary = {}
var _bgm_player: AudioStreamPlayer
var _bgm_id := ""
var _se_players: Array[AudioStreamPlayer] = []
var _se_next := 0
var _loop_channels: Dictionary = {}
var _voice_player: AudioStreamPlayer
var _voice_cooldown := 0.0

func _ready() -> void:
	_instance = self
	_load_settings()
	_bgm_player = _make_player("bgm")
	for i in range(SE_POOL_SIZE):
		_se_players.append(_make_player("se"))
	_voice_player = _make_player("voice")

func _exit_tree() -> void:
	if _instance == self:
		_instance = null

func _process(delta: float) -> void:
	_voice_cooldown = maxf(0.0, _voice_cooldown - delta)

# --- どこからでも呼べる入口。ノード不在時は何もしない ---

static func play_bgm(id: String) -> void:
	if _instance != null:
		_instance._play_bgm(id)

static func stop_bgm() -> void:
	if _instance != null:
		_instance._stop_bgm()

static func play_se(id: String) -> void:
	if _instance != null:
		_instance._play_se(id)

## ループSEのチャンネル更新。同じidなら継続、""で停止、別idなら切り替え。
## 毎フレーム呼んでも安全（冪等）。
static func update_loop(channel: String, id: String) -> void:
	if _instance != null:
		_instance._update_loop(channel, id)

static func play_voice(chara_id: String, expression_id: String) -> void:
	if _instance != null:
		_instance._play_voice(chara_id, expression_id)

static func set_volume(category: String, linear: float) -> void:
	if _instance != null:
		_instance._set_volume(category, linear)

static func get_volume(category: String) -> float:
	if _instance == null:
		return 1.0
	return float(_instance._volumes.get(category, 1.0))

# --- 実装 ---

func _make_player(category: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.set_meta("category", category)
	player.volume_db = linear_to_db(maxf(float(_volumes[category]), 0.0001))
	add_child(player)
	return player

func _play_bgm(id: String) -> void:
	if id == _bgm_id and _bgm_player.playing:
		return
	_bgm_id = id
	var stream := _load_stream("res://assets/audio/bgm/%s" % id, true)
	if stream == null:
		_bgm_player.stop()
		return
	_bgm_player.stream = stream
	_bgm_player.play()

func _stop_bgm() -> void:
	_bgm_id = ""
	_bgm_player.stop()

func _play_se(id: String) -> void:
	var stream := _load_stream("res://assets/audio/se/%s" % id, false)
	if stream == null:
		return
	var player := _se_players[_se_next]
	_se_next = (_se_next + 1) % SE_POOL_SIZE
	player.stream = stream
	player.play()

func _update_loop(channel: String, id: String) -> void:
	var entry: Dictionary = _loop_channels.get(channel, {})
	if entry.is_empty():
		entry = {"player": _make_player("se"), "id": ""}
		_loop_channels[channel] = entry
	if str(entry["id"]) == id:
		return
	entry["id"] = id
	var player: AudioStreamPlayer = entry["player"]
	if id == "":
		player.stop()
		return
	var stream := _load_stream("res://assets/audio/se/%s" % id, true)
	if stream == null:
		player.stop()
		return
	player.stream = stream
	player.play()

func _play_voice(chara_id: String, expression_id: String) -> void:
	if _voice_cooldown > 0.0:
		return
	var stream := _load_stream(
		"res://assets/audio/voice/%s/%s" % [chara_id, expression_id], false)
	if stream == null:
		return
	_voice_cooldown = VOICE_MIN_INTERVAL
	_voice_player.stream = stream
	_voice_player.play()

func _set_volume(category: String, linear: float) -> void:
	_volumes[category] = clampf(linear, 0.0, 1.0)
	for child in get_children():
		if child is AudioStreamPlayer and str(child.get_meta("category", "")) == category:
			child.volume_db = linear_to_db(maxf(float(_volumes[category]), 0.0001))
	_save_settings()

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		for category in _volumes.keys():
			if data.has(category):
				_volumes[category] = clampf(float(data[category]), 0.0, 1.0)

func _save_settings() -> void:
	var file := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("音量設定を保存できませんでした: %s" % SETTINGS_PATH)
		return
	file.store_string(JSON.stringify(_volumes))

## 拡張子なしのベースパスを受け取り ogg/wav/mp3 の順で探す。
## 見つからないパスは null をキャッシュして以後の存在チェックを省く。
func _load_stream(base_path: String, looped: bool) -> AudioStream:
	if _stream_cache.has(base_path):
		return _stream_cache[base_path]
	var stream: AudioStream = null
	for ext in ["ogg", "wav", "mp3"]:
		var path := "%s.%s" % [base_path, ext]
		if not ResourceLoader.exists(path):
			continue
		var res := load(path)
		if res is AudioStream:
			stream = res
			if looped:
				_apply_loop(stream)
			break
	_stream_cache[base_path] = stream
	return stream

func _apply_loop(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis or stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
