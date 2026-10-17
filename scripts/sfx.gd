class_name Sfx
extends RefCounted
## Звуковое сопровождение: файлы из res://audio/. Шины SFX/Music создаются
## один раз, громкость берётся из сейва (vol_sfx/vol_music, слайдеры меню).
## Не autoload: вызывается статически из обеих сцен.

const PATH_CLICK := "res://audio/pusk.ogg"          ## клик по кнопкам
const PATH_STOP := "res://audio/prokrut2.ogg"        ## барабаны встали
const PATH_WIN := "res://audio/get_bablo.ogg"        ## деньги получены
const PATH_BUY := "res://audio/buy_upgrade.ogg"      ## покупка улучшения
const PATHS_SPIN := [                                ## прокрут (вариации)
	"res://audio/prokrut1.ogg",
	"res://audio/prokrut3.ogg",
	"res://audio/prokrut4.ogg",
]

static var _cache := {}


static func _stream(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


## Создать шины SFX/Music (идемпотентно) и применить громкость 0..100.
static func ensure_buses(vol_sfx: float, vol_music: float) -> void:
	for b in ["SFX", "Music"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
			AudioServer.set_bus_send(
					AudioServer.get_bus_index(b), "Master")
	set_volumes(vol_sfx, vol_music)


static func set_volumes(vol_sfx: float, vol_music: float) -> void:
	for pair in [["SFX", vol_sfx], ["Music", vol_music]]:
		var idx := AudioServer.get_bus_index(str(pair[0]))
		if idx == -1:
			continue
		var v: float = pair[1]
		AudioServer.set_bus_mute(idx, v <= 0.0)
		if v > 0.0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(v / 100.0))


## what: click | spin | stop | win | buy. Проигрывание одноразовым
## плеером на узле сцены; плеер сам удаляется после окончания.
static func play(node: Node, what: String) -> void:
	if node == null or not node.is_inside_tree():
		return
	var path: String
	match what:
		"click":
			path = PATH_CLICK
		"spin":
			path = PATHS_SPIN[randi() % PATHS_SPIN.size()]
		"stop":
			path = PATH_STOP
		"win":
			path = PATH_WIN
		"buy":
			path = PATH_BUY
		_:
			return
	var st := _stream(path)
	if st == null:
		return
	var pl := AudioStreamPlayer.new()
	pl.stream = st
	pl.bus = "SFX"
	node.add_child(pl)
	pl.finished.connect(pl.queue_free)
	pl.play()
