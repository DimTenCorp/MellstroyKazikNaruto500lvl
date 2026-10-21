class_name Sfx
extends RefCounted
## Звуковое сопровождение: файлы из res://audio/. Шины SFX/Music создаются
## один раз, громкость берётся из сейва (vol_sfx/vol_music, слайдеры меню).
## Не autoload: вызывается статически из обеих сцен.
## Все потоки — preload-константы: так они гарантированно попадают
## в веб-экспорт (.pck), в отличие от load() по строке пути.

const ST_MUSIC := preload("res://audio/kazik-mellstroy.mp3")  ## фоновая музыка
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
	if has_vols():
		vol_sfx = cur_sfx      ## живые значения важнее старых из сейва
		vol_music = cur_music
	else:
		cur_sfx = vol_sfx
		cur_music = vol_music
	for b in ["SFX", "Music"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
			AudioServer.set_bus_send(
					AudioServer.get_bus_index(b), "Master")
	set_volumes(vol_sfx, vol_music)


static func set_volumes(vol_sfx: float, vol_music: float) -> void:
	cur_sfx = vol_sfx
	cur_music = vol_music
	for pair in [["SFX", vol_sfx], ["Music", vol_music]]:
		var idx := AudioServer.get_bus_index(str(pair[0]))
		if idx == -1:
			continue
		var v: float = pair[1]
		AudioServer.set_bus_mute(idx, v <= 0.0)
		if v > 0.0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(v / 100.0))


## Одноразовый плеер на узле сцены; сам удаляется после окончания.
## Временная диагностика веба: печатает состояние потока и шины.
static var _unlocked := false
static var _spin_pl: AudioStreamPlayer = null
## Оперативные громкости: живут поверх сейва, чтобы переходы между
## сценами не могли их потерять (сцена читает их раньше/вместо сейва).
static var cur_sfx := -1.0
static var cur_music := -1.0

## Фоновая музыка: один плеер на корне дерева сцен — переживает смены
## сцен без перезапуска. Шина Music, зациклен, громкость от vol_music.
static var _music_pl: AudioStreamPlayer = null

static func ensure_music() -> void:
	if _music_pl != null and is_instance_valid(_music_pl):
		return
	if AudioServer.get_bus_index("Music") == -1:
		ensure_buses(80, 80)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var st := ST_MUSIC.duplicate() as AudioStreamMP3
	st.loop = true
	_music_pl = AudioStreamPlayer.new()
	_music_pl.name = "MusicPlayer"
	_music_pl.stream = st
	_music_pl.bus = "Music"
	tree.root.add_child(_music_pl)
	_music_pl.play()
	_music_try = 0
	print("[sfx] фоновая музыка запущена: %s" % st.resource_path)
	## отложенная самопроверка: если старт не удался (веб-блокировка и т.п.) — повторить
	tree.create_timer(0.7).timeout.connect(func() -> void:
		if _music_pl != null and is_instance_valid(_music_pl) and not _music_pl.playing:
			print("[sfx] музыка не играла через 0.7 c — повторяю play()")
			_music_pl.play()
	)


## Вызывается из _process обеих сцен: держит музыку живой (рестарт, если
## поток остановился или плеер погиб при смене сцены).
static var _music_try := 0

static func tick_music() -> void:
	if _music_pl == null or not is_instance_valid(_music_pl):
		ensure_music()
		return
	if not _music_pl.playing:
		_music_try += 1
		if _music_try % 60 == 1:   ## не чаще раза в секунду
			_music_pl.play()


static func has_vols() -> bool:
	return cur_sfx >= 0.0


## Веб: дёргаем разблокировку AudioContext из шаблона экспорта
## (снаппет ставится в index.html до старта движка).
static func _unlock_web() -> void:
	if _unlocked or not OS.has_feature("web"):
		return
	_unlocked = true
	if JavaScriptBridge.has_method("eval"):
		JavaScriptBridge.eval("window.__unlockAudio && window.__unlockAudio()")


static func _one_shot(node: Node, st: AudioStream,
		bus: String = "SFX", vol_db: float = 0.0) -> AudioStreamPlayer:
	_unlock_web()
	if node == null or st == null:
		return null
	if not node.is_inside_tree():
		return null
	var pl := AudioStreamPlayer.new()
	pl.stream = st
	pl.bus = bus
	pl.volume_db = vol_db
	node.add_child(pl)
	pl.finished.connect(func() -> void:
		if is_instance_valid(pl):
			pl.queue_free())
	pl.play()
	return pl


## what: click | win | buy.
static func play(node: Node, what: String) -> void:
	play_on_bus(node, what, "SFX")


## То же, но на заданную шину (для A/B-теста SFX против Master).
static func play_on_bus(node: Node, what: String, bus: String) -> void:
	match what:
		"click":
			_one_shot(node, ST_CLICK, bus)
		"win":
			_one_shot(node, ST_WIN, bus)
		"buy":
			_one_shot(node, ST_BUY, bus)


## Звук прокрута зависит от скорости: x1 — вариации prokrut1/3/4,
## x2 — prokrut3, x5 — prokrut2.
static func play_spin(node: Node, speed: float) -> void:
	## prokrut*.ogg записаны тише остальных (~-23 dB) — компенсируем +20 dB.
	stop_spin(0.5)   ## прежний прокрут уходит мягко, если спин restart
	match int(speed):
		2:
			_spin_pl = _one_shot(node, ST_SPIN_X2, "SFX", 20.0)
		5:
			_spin_pl = _one_shot(node, ST_SPIN_X5, "SFX", 20.0)
		_:
			_spin_pl = _one_shot(node,
					ST_SPIN_X1[randi() % ST_SPIN_X1.size()], "SFX", 20.0)


## Погасить звук прокрута, если барабаны встали раньше, чем кончился
## файл. Трогает ТОЛЬКО x2 (prokrut3 длиннее спина): x1 и x5 доигрывают
## сами. Фейд длинный и плавный (SINE/EASE_IN), без рваного обрыва.
static func stop_spin(fade: float = 0.9) -> void:
	var pl := _spin_pl
	_spin_pl = null
	if pl == null or not is_instance_valid(pl) or not pl.playing:
		return
	if pl.stream != ST_SPIN_X2:
		return
	var tw := pl.create_tween()
	tw.tween_property(pl, "volume_db", -60.0, fade)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if is_instance_valid(pl):
			pl.stop()
			pl.queue_free())
