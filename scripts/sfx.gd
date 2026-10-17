class_name Sfx
extends RefCounted
## Звуковое сопровождение: файлы из res://audio/. Шины SFX/Music создаются
## один раз, громкость берётся из сейва (vol_sfx/vol_music, слайдеры меню).
## Не autoload: вызывается статически из обеих сцен.
## Все потоки — preload-константы: так они гарантированно попадают
## в веб-экспорт (.pck), в отличие от load() по строке пути.

const ST_CLICK := preload("res://audio/pusk.ogg")       ## клик по кнопкам
const ST_WIN := preload("res://audio/get_bablo.ogg")     ## деньги получены
const ST_BUY := preload("res://audio/buy_upgrade.ogg")   ## покупка улучшения
const ST_SPIN_X2 := preload("res://audio/prokrut3.ogg")  ## прокрут x2
const ST_SPIN_X5 := preload("res://audio/prokrut2.ogg")  ## прокрут x5
## прокрут x1: случайная вариация
const ST_SPIN_X1 := [
	preload("res://audio/prokrut1.ogg"),
	preload("res://audio/prokrut3.ogg"),
	preload("res://audio/prokrut4.ogg"),
]


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


## Одноразовый плеер на узле сцены; сам удаляется после окончания.
static func _one_shot(node: Node, st: AudioStream) -> void:
	if node == null or st == null:
		return
	if not node.is_inside_tree():
		return
	var pl := AudioStreamPlayer.new()
	pl.stream = st
	pl.bus = "SFX"
	node.add_child(pl)
	pl.finished.connect(pl.queue_free)
	pl.play()


## what: click | win | buy.
static func play(node: Node, what: String) -> void:
	match what:
		"click":
			_one_shot(node, ST_CLICK)
		"win":
			_one_shot(node, ST_WIN)
		"buy":
			_one_shot(node, ST_BUY)


## Звук прокрута зависит от скорости: x1 — вариации prokrut1/3/4,
## x2 — prokrut3, x5 — prokrut2.
static func play_spin(node: Node, speed: float) -> void:
	match int(speed):
		2:
			_one_shot(node, ST_SPIN_X2)
		5:
			_one_shot(node, ST_SPIN_X5)
		_:
			_one_shot(node, ST_SPIN_X1[randi() % ST_SPIN_X1.size()])
