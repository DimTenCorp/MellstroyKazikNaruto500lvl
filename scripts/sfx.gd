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
		print("[sfx] ПОТОК NULL, звук пропущен")
		return null
	if not node.is_inside_tree():
		print("[sfx] узел вне дерева, звук пропущен")
		return null
	var idx := AudioServer.get_bus_index("SFX")
	print("[sfx] play: stream=%s len=%.2f cборка_web=%s bus_idx=%d mute=%s db=%.1f"
			% [st.resource_path, st.get_length(), OS.has_feature("web"),
			idx, AudioServer.is_bus_mute(idx) if idx != -1 else true,
			AudioServer.get_bus_volume_db(idx) if idx != -1 else -80.0])
	var pl := AudioStreamPlayer.new()
	pl.stream = st
	pl.bus = bus
	pl.volume_db = vol_db
	node.add_child(pl)
	pl.finished.connect(func() -> void:
		if is_instance_valid(pl):
			pl.queue_free())
	pl.play()
	print("[sfx] playing=%s bus=%s vol_db=%.0f" % [pl.playing, bus, vol_db])
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
