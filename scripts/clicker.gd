extends Control
## Сцена кликера «Бабло»: монета даёт монеты за клики, кнопка play —
## награду за рекламу через Playgama Bridge (autoload Bridge, метод
## show_rewarded()): работает на Yandex Games, Poki, CrazyGames и др.
## Баланс общий со слот-машиной (user://slot_save.cfg).
## Весь UI лежит узлами в scenes/clicker.tscn.

const VSIZE := Vector2(1280, 720)
const AD_REWARD := 500
const CLICK_BASE := 5        ## базовый заработок за клик без улучшений

## Очередь улучшений (порядок = порядок появления в витрине).
## click/auto — прибавка к статом за один уровень, max — потолок уровней,
## cost/mult — цена первого уровня и рост цены за уровень.
const UPGRADES := [
	{"name": "Смазка контактов", "icon": 0, "click": 2, "auto": 0,
	 "max": 5, "cost": 50, "mult": 1.6},
	{"name": "Механический переключатель", "icon": 1, "click": 5, "auto": 0,
	 "max": 5, "cost": 120, "mult": 1.6},
	{"name": "Турбо-скрипт", "icon": 2, "click": 0, "auto": 5,
	 "max": 5, "cost": 150, "mult": 1.6},
	{"name": "Макрос на клик", "icon": 3, "click": 10, "auto": 0,
	 "max": 5, "cost": 300, "mult": 1.7},
	{"name": "Обход антикликера", "icon": 4, "click": 25, "auto": 0,
	 "max": 3, "cost": 800, "mult": 1.8},
	{"name": "Разгон процессора", "icon": 5, "click": 0, "auto": 15,
	 "max": 5, "cost": 600, "mult": 1.7},
	{"name": "Усилитель импульса", "icon": 6, "click": 15, "auto": 5,
	 "max": 5, "cost": 900, "mult": 1.7},
	{"name": "Инъекция кода", "icon": 7, "click": 0, "auto": 40,
	 "max": 5, "cost": 2000, "mult": 1.8},
	{"name": "Взлом реестра", "icon": 8, "click": 50, "auto": 0,
	 "max": 3, "cost": 3500, "mult": 1.8},
	{"name": "Теневой сервер", "icon": 9, "click": 0, "auto": 100,
	 "max": 3, "cost": 8000, "mult": 1.9},
	{"name": "Драйвер подмены", "icon": 10, "click": 40, "auto": 40,
	 "max": 3, "cost": 12000, "mult": 1.9},
	{"name": "Нейросетевой кликер", "icon": 11, "click": 150, "auto": 50,
	 "max": 2, "cost": 30000, "mult": 2.0},
	{"name": "Квантовый контроллер", "icon": 12, "click": 200, "auto": 200,
	 "max": 1, "cost": 100000, "mult": 2.0},
]

## Регионы иконок в img/upgrades/upgrades.png (1344x717, сетка 5x3).
const UPGRADE_REGIONS := [
	Rect2(4, 2, 213, 211), Rect2(283, 2, 214, 211), Rect2(562, 2, 214, 211),
	Rect2(841, 2, 214, 211), Rect2(1121, 2, 213, 211),
	Rect2(4, 255, 213, 212), Rect2(283, 255, 214, 212), Rect2(562, 255, 214, 212),
	Rect2(841, 255, 214, 212), Rect2(1121, 255, 213, 212),
	Rect2(4, 499, 213, 211), Rect2(283, 499, 214, 211), Rect2(562, 499, 214, 211),
]     ## монет за досмотренную рекламу
const SAVE_PATH := "user://slot_save.cfg"

## Визуальный размер кнопок: в сцене спрайты лежат в родном размере региона
## (TextureButton не даёт Size меньше текстуры), масштаб ставим здесь.
const DEBUG := true  ## отладочные логи в консоль (print)

var balance := 1000
var upg_levels: Array[int] = []   ## уровни улучшений (индекс = номер в UPGRADES)
var _icons: Array[AtlasTexture] = []
var _auto_acc := 0.0         ## накопитель секунд для авто-заработка
var _cfg := ConfigFile.new()
var _watching := false
var _banner_tw: Tween

@onready var machine: Control = $machine
@onready var hud_balance: Label = $machine/hud_balance
@onready var coin_btn: TextureButton = $machine/coin_btn
@onready var click_hint: Label = $machine/click_hint
@onready var play_btn: TextureButton = $machine/play_btn
@onready var play_caption: Label = $machine/play_caption
@onready var back_btn: Button = $machine/back_btn
@onready var msg_label: Label = $machine/msg_label
var upg_btns: Array = []   ## кнопки-иконки строк списка улучшений
var upg_infos: Array = []  ## подписи строк списка улучшений
@onready var auto_stat: Label = $machine/auto_stat
@onready var click_stat: Label = $machine/click_stat
@onready var float_layer: Control = $machine/float_layer


func click_gain() -> int:
	var v := CLICK_BASE
	for i in UPGRADES.size():
		v += int(UPGRADES[i].click) * upg_levels[i]
	return v


func auto_gain() -> int:
	var v := 0
	for i in UPGRADES.size():
		v += int(UPGRADES[i].auto) * upg_levels[i]
	return v


func _upg_cost(i: int) -> int:
	var u: Dictionary = UPGRADES[i]
	return int(round(float(u.cost) * pow(float(u.mult), upg_levels[i]) / 10.0)) * 10


## Список показывает все улучшения сверху вниз; прокачанные до упора
## строки помечаются МАКС и их кнопка гаснет.
func _refresh_shop() -> void:
	for i in UPGRADES.size():
		var u: Dictionary = UPGRADES[i]
		upg_btns[i].texture_normal = _icons[int(u.icon)]
		upg_btns[i].disabled = upg_levels[i] >= int(u.max)
		if upg_levels[i] >= int(u.max):
			upg_infos[i].text = "%s\n%s | ур.%d/%d | МАКС" % [
					u.name, _upg_effect_text(u), upg_levels[i], u.max]
		else:
			upg_infos[i].text = "%s\n%s | ур.%d/%d | цена %d" % [
					u.name, _upg_effect_text(u), upg_levels[i], u.max, _upg_cost(i)]


func _upg_effect_text(u: Dictionary) -> String:
	var parts: Array[String] = []
	if int(u.click) > 0:
		parts.append("+%d/клик" % u.click)
	if int(u.auto) > 0:
		parts.append("+%d/с" % u.auto)
	return " ".join(parts)


func _on_upg(i: int) -> void:
	var u: Dictionary = UPGRADES[i]
	if upg_levels[i] >= int(u.max):
		return
	var c := _upg_cost(i)
	if balance < c:
		_dbg("улучшение %s: не хватает бабла (нужно %d, есть %d)" % [u.name, c, balance])
		_banner("НЕ ХВАТАЕТ БАБЛА: НУЖНО %d" % c, Color("#ff7b7b"))
		return
	balance -= c
	upg_levels[i] += 1
	_dbg("улучшение %s: ур.%d/%d, след. цена %d (клик %d, авто %d)" % [
			u.name, upg_levels[i], u.max, _upg_cost(i), click_gain(), auto_gain()])
	if upg_levels[i] >= int(u.max):
		_dbg("улучшение %s прокачано полностью" % u.name)
	_save()
	_refresh_shop()
	_update()
	_float(_upg_effect_text(u),
			upg_btns[i].global_position + upg_btns[i].size * 0.5, Color("#8dffa0"))


func _process(delta: float) -> void:
	var g := auto_gain()
	if g <= 0:
		return
	_auto_acc += delta
	var add := 0
	while _auto_acc >= 1.0:
		_auto_acc -= 1.0
		add += g
	if add > 0:
		balance += add
		_update()


func _dbg(msg: String) -> void:
	if DEBUG:
		print("[clicker] " + msg)


func _ready() -> void:
	_load()
	_dbg("сцена готова, баланс=%d" % balance)
	coin_btn.pressed.connect(_on_coin)
	play_btn.pressed.connect(_on_play)
	back_btn.pressed.connect(_on_back)
	var sheet: Texture2D = load("res://img/upgrades/upgrades.png")
	for r in UPGRADE_REGIONS:
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = r
		_icons.append(at)
	for i in UPGRADES.size():
		var btn: TextureButton = get_node(
				"machine/upg_scroll/upg_vbox/upg%d_row/upg%d_btn" % [i, i])
		var info: Label = get_node(
				"machine/upg_scroll/upg_vbox/upg%d_row/upg%d_info" % [i, i])
		upg_btns.append(btn)
		upg_infos.append(info)
		btn.pressed.connect(_on_upg.bind(i))
	_refresh_shop()
	for btn in _find_buttons(self):
		_bind_press_anim(btn)
	play_caption.text = "РЕКЛАМА: +%d" % AD_REWARD
	_update()
	_layout()
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var vs := get_viewport_rect().size
	if vs.x <= 0 or vs.y <= 0:
		return
	var s := minf(vs.x / VSIZE.x, vs.y / VSIZE.y)
	machine.scale = Vector2(s, s)
	machine.position = (vs - VSIZE * s) * 0.5


# ------------------------------------------------------------------- баланс

func _load() -> void:
	if _cfg.load(SAVE_PATH) == OK:
		balance = int(_cfg.get_value("save", "balance", balance))
		var arr: Array = _cfg.get_value("save", "upg_levels", [])
		upg_levels.clear()
		for k in UPGRADES.size():
			upg_levels.append(int(arr[k]) if k < arr.size() else 0)
	if upg_levels.size() != UPGRADES.size():
		upg_levels.clear()
		for k in UPGRADES.size():
			upg_levels.append(0)


## Пишем баланс в общий сейв, остальные ключи (ставка, скорость,
## громкости) сохраняем как есть.
func _save() -> void:
	_cfg.set_value("save", "balance", balance)
	_cfg.set_value("save", "upg_levels", upg_levels)
	_cfg.save(SAVE_PATH)


func _update() -> void:
	hud_balance.text = _fmt(balance)
	click_hint.text = "+%d за клик" % click_gain()
	click_stat.text = "бабло за клик: %d" % click_gain()
	auto_stat.text = "авт. бабло: %d/с" % auto_gain()


func _fmt(v: int) -> String:
	var s := str(v)
	var out := ""
	var n := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		n += 1
		if n % 3 == 0 and i > 0 and s[i - 1] != "-":
			out = " " + out
	return out


func _bind_press_anim(btn: BaseButton) -> void:
	btn.pivot_offset = btn.size * 0.5  # сжатие при нажатии от центра
	var base: Vector2 = btn.scale
	btn.button_down.connect(func() -> void:
		var old_tw: Tween = btn.get_meta("press_tw") if btn.has_meta("press_tw") else null
		if old_tw != null and old_tw.is_valid():
			old_tw.kill()
		var tw := create_tween()
		tw.tween_property(btn, "scale", base * 0.9, 0.06)
		btn.set_meta("press_tw", tw)
	)
	btn.button_up.connect(func() -> void:
		var old_tw: Tween = btn.get_meta("press_tw") if btn.has_meta("press_tw") else null
		if old_tw != null and old_tw.is_valid():
			old_tw.kill()
		var tw := create_tween()
		tw.tween_property(btn, "scale", base, 0.16) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		btn.set_meta("press_tw", tw)
	)


func _find_buttons(root: Node) -> Array[BaseButton]:
	var out: Array[BaseButton] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is BaseButton:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


# ------------------------------------------------------------------- клики

func _on_coin() -> void:
	balance += click_gain()
	_dbg("клик по монете: +%d, баланс=%d" % [click_gain(), balance])
	_save()
	_update()
	_float("+%d" % click_gain(), coin_btn.position + coin_btn.size * 0.5,
			Color("#ffe9b8"))


func _float(text: String, at: Vector2, color: Color) -> void:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", 30)
	lab.add_theme_color_override("font_color", color)
	lab.add_theme_constant_override("outline_size", 8)
	lab.add_theme_color_override("font_outline_color", Color("#402008"))
	lab.position = at + Vector2(randf_range(-40, 20), -20)
	float_layer.add_child(lab)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lab, "position:y", lab.position.y - 90.0, 0.8)
	tw.tween_property(lab, "modulate", Color(1, 1, 1, 0), 0.8)
	tw.chain().tween_callback(lab.queue_free)


# ------------------------------------------------------------------- реклама

func _on_play() -> void:
	if _watching:
		_dbg("play нажат повторно — уже смотрим рекламу, игнор")
		return
	_dbg("play нажат: запрашиваем рекламу с наградой")
	_watching = true
	play_btn.disabled = true
	var rewarded := await _watch_rewarded_ad()
	_dbg("реклама завершена, rewarded=%s" % rewarded)
	if rewarded:
		balance += AD_REWARD
		_dbg("награда начислена: +%d, баланс=%d" % [AD_REWARD, balance])
		_save()
		_update()
		_banner("БАБЛО ЗА РЕКЛАМУ: +%s" % _fmt(AD_REWARD), Color("#8dffa0"))
		_float("+%d" % AD_REWARD,
				play_btn.position + play_btn.size * 0.5, Color("#8dffa0"))
	else:
		_banner("РЕКЛАМА НЕ ДОСМОТРЕНА — НЕТ НАГРАДЫ", Color("#ff7b7b"))
	_watching = false
	play_btn.disabled = false


## Показ рекламы с наградой через Playgama Bridge (autoload Bridge):
## сигнал rewarded_state_changed даёт REWARDED (награда) и CLOSED/FAILED
## (конец показа). В редакторе аддон крутит мок-состояния — награда приходит
## сразу, в вебе рекламу показывает SDK площадки (Yandex, Poki, CrazyGames…).
## Autoload Bridge из аддона Playgama. Если секция [autoload] потеряна
## (редактор иногда перезаписывает project.godot из памяти), поднимаем
## узел Bridge вручную из скрипта аддона — реклама работает всё равно.
func _get_bridge() -> Node:
	var br := get_node_or_null("/root/Bridge")
	if br != null:
		return br
	var script: GDScript = load("res://addons/playgama_bridge/bridge.gd")
	if script == null:
		return null
	br = script.new()
	br.name = "Bridge"
	get_tree().root.add_child(br)
	_dbg("autoload Bridge не найден — поднят fallback-узел из скрипта аддона")
	return br


func _watch_rewarded_ad() -> bool:
	var br := _get_bridge()
	if br == null or br.advertisement == null:
		_dbg("ОШИБКА: Bridge недоступен даже fallback-ом")
		_banner("BRIDGE НЕ ПОДКЛЮЧЁН", Color("#ff7b7b"))
		return false
	_dbg("платформа: %s, rewarded supported=%s" % [
			_platform_name(br), br.advertisement.is_rewarded_supported])
	if not bool(br.advertisement.is_rewarded_supported):
		_banner("НЕТ РЕКЛАМЫ НА ПЛАТФОРМЕ: %s" % _platform_name(br),
				Color("#ff7b7b"))
		return false
	var st := {"rewarded": false, "finished": false, "failed": false}
	var on_state := func(state) -> void:
		_dbg("состояние рекламы: %s" % state)
		if state == br.RewardedState.REWARDED:
			st["rewarded"] = true
		elif state == br.RewardedState.FAILED:
			st["failed"] = true
			st["finished"] = true
		elif state == br.RewardedState.CLOSED:
			st["finished"] = true
	br.advertisement.rewarded_state_changed.connect(on_state)
	_banner("СМОТРИМ РЕКЛАМУ... [%s]" % _platform_name(br), Color("#ffd794"))
	_dbg("вызов Bridge.advertisement.show_rewarded()")
	br.advertisement.show_rewarded()
	var t := 0.0
	while not st["finished"] and t < 90.0:
		await get_tree().create_timer(0.15).timeout
		t += 0.15
	if br.advertisement.rewarded_state_changed.is_connected(on_state):
		br.advertisement.rewarded_state_changed.disconnect(on_state)
	if not st["finished"]:
		_dbg("ОШИБКА: таймаут ожидания рекламы (90 c)")
		_banner("РЕКЛАМА НЕ ОТВЕТИЛА (ТАЙМАУТ)", Color("#ff7b7b"))
		return false
	if st["failed"]:
		_dbg("ОШИБКА: реклама завершилась с FAILED")
		_banner("ОШИБКА РЕКЛАМЫ — НЕТ НАГРАДЫ", Color("#ff7b7b"))
		return false
	return st["rewarded"]


func _platform_name(br: Node) -> String:
	if not OS.has_feature("web"):
		return "editor"
	if br.platform != null:
		return str(br.platform.id)
	return "web"


# ------------------------------------------------------------------- выход

func _on_back() -> void:
	_dbg("возврат к слот-машине, баланс=%d" % balance)
	_save()
	get_tree().change_scene_to_file("res://scenes/game.tscn")


# ------------------------------------------------------------------- баннер

func _banner(text: String, color: Color) -> void:
	if _banner_tw != null and _banner_tw.is_valid():
		_banner_tw.kill()
	_banner_tw = null
	msg_label.text = text
	msg_label.add_theme_color_override("font_color", color)
	msg_label.show()
	msg_label.pivot_offset = msg_label.size * 0.5
	msg_label.scale = Vector2(0.6, 0.6)
	msg_label.modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(msg_label, "scale", Vector2(1, 1), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(msg_label, "modulate", Color(1, 1, 1, 1), 0.25)
	tw.finished.connect(func() -> void:
		var t2 := create_tween()
		t2.tween_interval(1.4)
		t2.tween_property(msg_label, "modulate", Color(1, 1, 1, 0), 0.4)
		_banner_tw = t2
	)
