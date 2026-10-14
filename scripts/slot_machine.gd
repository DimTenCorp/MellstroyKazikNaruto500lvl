extends Control
## Главная сцена: слот-машина 3x5 (3 строки, 5 барабанов) для Яндекс.Игр.
## Правила: 9 линий выплат слева направо, WILD-замена, скаттер BONUS даёт
## выплату и фриспины. Баланс хранится в user://, игра без реальных денег.
##
## ВЕСЬ UI лежит узлами в scenes/game.tscn: фон back1, кнопки-спрайты из
## img/buttons_spr (RU), бейджи выигрышей из img/win (RU), меню ставок,
## автоигры и звука. Динамика (подсветка линий, попап выигрыша) — кодом.

const VSIZE := Vector2(1280, 720)  ## виртуальный размер макета машины
const CELL := 160.0                ## размер ячейки символа (как в генераторе)
const GAP := 8.0                   ## зазор между ячейками
const BETS := [1, 2, 5, 10, 25, 50]
const AUTO_OPTIONS := [10, 25, 50, 100, -1]  ## -1 = без лимита
const SPEEDS := [1.0, 2.0, 5.0]
const START_BALANCE := 0  ## первый заход: баланс 0 (долг по сюжету)
const SAVE_PATH := "user://slot_save.cfg"

# Порядок символов в таблице выплат (id из SlotData.Symbol) и их ключи в сцене.
const PAY_ORDER: Array[int] = [12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 13]
const SYMBOL_KEYS: Array[String] = [
	"cherry", "lemon", "orange", "plum", "watermelon", "star", "horseshoe",
	"moneysack", "bell", "1bar", "2bar", "3bar", "777", "wild", "chestbonus",
]

## Бейджи img/win/wins_spritessheet.png (RU):
## 0 ВЫИГРЫШ, 1 БОЛЬШОЙ, 2 МЕГА, 3 ЭПИЧЕСКИЙ, 4 СУПЕР, 5 БОНУС,
## 6 ДЖЕКПОТ, 7 ФРИСПИН, 8 ВЫИГРЫШ В БОНУСНОЙ ИГРЕ.
const WIN_REGIONS: Array[Rect2] = [
	Rect2(9, 23, 394, 221),
	Rect2(462, 8, 393, 218),
	Rect2(929, 11, 373, 230),
	Rect2(24, 244, 365, 245),
	Rect2(466, 266, 386, 191),
	Rect2(949, 298, 331, 123),
	Rect2(6, 489, 401, 232),
	Rect2(471, 523, 372, 179),
	Rect2(921, 512, 392, 174),
]
## Пороги большого выигрыша в полных ставках: [множитель, бейдж].
const WIN_TIERS: Array[Array] = [
	[150, 6],  # ДЖЕКПОТ
	[80, 3],   # ЭПИЧЕСКИЙ ВЫИГРЫШ
	[40, 2],   # МЕГА ВЫИГРЫШ
	[20, 4],   # СУПЕР ВЫИГРЫШ
	[10, 1],   # БОЛЬШОЙ ВЫИГРЫШ
]

## Визуальный размер кнопок (кликовая область совпадает с картинкой):
## в сцене кнопки лежат в родном размере спрайта, т.к. TextureButton
## не позволяет Size меньше текстуры.
const DEBUG := true  ## отладочные логи в консоль (print)

var rng := RandomNumberGenerator.new()
var textures: Array[Texture2D] = []
var reels: Array[SlotReel] = []

var balance := START_BALANCE
var bet_line := 1  ## ставка на линию: любое число от 1 до баланса
var speed_idx := 0
var vol_sfx := 80
var vol_music := 80
var _fs_left := 0
var _spinning := false
var autospin := false
var _auto_left := 0  ## 0 = не активна, -1 = без лимита

var _fx_nodes: Array[Node] = []
var _win_tween: Tween
var _banner_tw: Tween
var _glow_tw: Tween
var _reset_armed := false
var upg_levels: Array[int] = []  ## уровни улучшений кликера (для авто-бабла)
var _auto_acc := 0.0
var _popup_tw: Tween
var _wins_tex: Texture2D

@onready var machine: Control = $machine
@onready var balance_label: Label = $machine/balance_label
@onready var win_label: Label = $machine/win_label
@onready var freespin_label: Label = $machine/freespin_label
@onready var bet_label: Label = $machine/bottom_bar/bet_label
@onready var fullbet_label: Label = $machine/bottom_bar/fullbet_label
@onready var auto_label: Label = $machine/bottom_bar/auto_label
@onready var msg_label: Label = $machine/grid_panel/msg_label
@onready var spin_btn: TextureButton = $machine/bottom_bar/spin_btn
@onready var bet_btn: TextureButton = $machine/bottom_bar/bet_btn
@onready var max_btn: TextureButton = $machine/bottom_bar/max_btn
@onready var auto_btn: TextureButton = $machine/bottom_bar/auto_btn
@onready var speed_btn: TextureButton = $machine/bottom_bar/speed_btn
@onready var sound_btn: TextureButton = $machine/bottom_bar/sound_btn
@onready var paytable_btn: TextureButton = $machine/bottom_bar/paytable_btn
@onready var intro_popup: Control = $machine/intro_popup
@onready var intro_btn: Button = $machine/intro_popup/intro_btn
@onready var intro_label: Label = $machine/intro_popup/intro_label
@onready var clicker_glow: Panel = $machine/bottom_bar/clicker_glow
@onready var reset_btn: Button = $machine/reset_btn
@onready var clicker_btn: TextureButton = $machine/bottom_bar/clicker_btn
@onready var fx_layer: Control = $machine/grid_panel/fx_layer
@onready var lines_overlay: Node2D = $machine/grid_panel/lines_overlay
@onready var win_popup: Control = $machine/win_popup
@onready var win_badge: TextureRect = $machine/win_popup/win_badge
@onready var win_popup_label: Label = $machine/win_popup/win_popup_label
@onready var paytable_popup: Control = $machine/paytable_popup
@onready var bet_menu: Control = $machine/bet_menu
@onready var bet_total_label: Label = $machine/bet_menu/panel/vbox/bet_total
@onready var bet_input: LineEdit = $machine/bet_menu/panel/vbox/bet_row/bet_input
@onready var bet_apply: Button = $machine/bet_menu/panel/vbox/bet_row/bet_apply
@onready var auto_menu: Control = $machine/auto_menu
@onready var sound_menu: Control = $machine/sound_menu
@onready var sfx_slider: HSlider = $machine/sound_menu/panel/vbox/row_sfx/sfx_slider
@onready var music_slider: HSlider = $machine/sound_menu/panel/vbox/row_music/music_slider
@onready var sfx_val: Label = $machine/sound_menu/panel/vbox/row_sfx/sfx_val
@onready var music_val: Label = $machine/sound_menu/panel/vbox/row_music/music_val


func _ready() -> void:
	rng.randomize()
	textures.resize(SlotData.SYMBOL_COUNT)
	for sym in SlotData.SYMBOL_COUNT:
		textures[sym] = load(SlotData.TEXTURES[sym])
	_wins_tex = load("res://img/win/wins_spritessheet.png")

	for c in SlotData.COLS:
		var reel: SlotReel = get_node("machine/grid_panel/Reel%d" % c)
		reel.configure(textures, rng)
		reel.set_symbols([
			SlotData.random_symbol(rng),
			SlotData.random_symbol(rng),
			SlotData.random_symbol(rng),
		])
		reels.append(reel)

	# Аудио-шины заводим сразу: звуки и музыка появятся позже, громкости готовы.
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
			AudioServer.set_bus_send(AudioServer.get_bus_index(bus_name), "Master")

	spin_btn.pressed.connect(_on_spin_pressed)
	bet_btn.pressed.connect(func() -> void: _open_bet_menu())
	max_btn.pressed.connect(_on_max_bet)
	auto_btn.pressed.connect(_on_auto_pressed)
	speed_btn.pressed.connect(_on_speed_pressed)
	sound_btn.pressed.connect(func() -> void: _open_menu(sound_menu))
	intro_btn.pressed.connect(_on_intro_ok)
	reset_btn.pressed.connect(_on_reset_pressed)
	clicker_btn.pressed.connect(_on_clicker_pressed)
	paytable_btn.pressed.connect(func() -> void: _open_menu(paytable_popup))

	_connect_menu($machine/paytable_popup,
			"popup_panel/scroll/vbox/head/close_btn")
	_connect_menu(bet_menu)
	_connect_menu(auto_menu)
	_connect_menu(sound_menu)
	for i in BETS.size():
		var opt: Button = get_node("machine/bet_menu/panel/vbox/grid/bet_opt%d" % i)
		opt.pressed.connect(func() -> void:
			_set_bet(int(BETS[i]))
			_close_menus()
		)
	bet_apply.pressed.connect(_on_bet_apply)
	bet_input.text_submitted.connect(func(_t: String) -> void: _on_bet_apply())
	for i in AUTO_OPTIONS.size():
		var opt: Button = get_node("machine/auto_menu/panel/vbox/grid/auto_opt%d" % i)
		opt.pressed.connect(func() -> void: _start_autospin(int(AUTO_OPTIONS[i])))
	get_node("machine/auto_menu/panel/vbox/grid/auto_cancel").pressed.connect(
		func() -> void: _close_menus())

	sfx_slider.value_changed.connect(func(v: float) -> void:
		vol_sfx = int(v)
		sfx_val.text = str(vol_sfx)
		_apply_volumes()
		_save()
	)
	music_slider.value_changed.connect(func(v: float) -> void:
		vol_music = int(v)
		music_val.text = str(vol_music)
		_apply_volumes()
		_save()
	)

	for btn in _find_buttons(self):
		_bind_press_anim(btn)
	_load_save()
	sfx_slider.value = vol_sfx
	music_slider.value = vol_music
	sfx_val.text = str(vol_sfx)
	music_val.text = str(vol_music)
	_apply_volumes()
	_apply_toggles()
	_refresh_paytable()
	_update_labels()
	_setup_intro()
	_layout()
	get_viewport().size_changed.connect(_layout)


## Анимация нажатия: кнопка чуть сжимается и отпружинивает обратно.
func _bind_press_anim(btn: BaseButton) -> void:
	btn.pivot_offset = btn.size * 0.5  # сжатие при нажатии от центра
	var base: Vector2 = btn.scale
	btn.button_down.connect(func() -> void:
		var old: Tween = btn.get_meta("press_tw") if btn.has_meta("press_tw") else null
		if old != null and old.is_valid():
			old.kill()
		var tw := create_tween()
		tw.tween_property(btn, "scale", base * 0.9, 0.06)
		btn.set_meta("press_tw", tw)
	)
	btn.button_up.connect(func() -> void:
		var old: Tween = btn.get_meta("press_tw") if btn.has_meta("press_tw") else null
		if old != null and old.is_valid():
			old.kill()
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


## Рисует кнопки в задуманном размере: в сцене спрайт лежит в родном
## размере, здесь ставим масштаб от левого верхнего угла. Кликабельная
## область учитывает трансформ контроля, то есть совпадает с картинкой.
func _flag_get(key: String, def: Variant) -> Variant:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		return cfg.get_value("save", key, def)
	return def


func _flag_set(key: String, val: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("save", key, val)
	cfg.save(SAVE_PATH)


## Первый заход: сюжетный долг, баланс 0, подсветка кнопки кликера.
func _setup_intro() -> void:
	# страховка: редактор может сбросить autowrap/размер — ставим из кода
	intro_label.size = Vector2(620, 240)
	intro_label.position = Vector2(330, 200)
	intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if not bool(_flag_get("intro_seen", false)):
		balance = 0
		_save()
		_update_labels()
		intro_popup.visible = true
		_dbg("первый заход: баланс обнулён, показано интро о долге 100 000")
	if not bool(_flag_get("clicker_visited", false)):
		clicker_glow.visible = true
		clicker_glow.modulate = Color(1, 1, 1, 1)
		_glow_tw = create_tween().set_loops()
		_glow_tw.tween_property(clicker_glow, "modulate:a", 0.15, 0.7)
		_glow_tw.tween_property(clicker_glow, "modulate:a", 1.0, 0.7)
		_dbg("световое выделение кнопки кликера включено")


## Отладочный полный сброс: удаляет общий сейв (баланс, уровни кликера,
## флаги интро) и перезапускает сцену — игра снова «с первого захода».
## Защита от случайного нажатия: два нажатия подряд за 3 секунды.
func _on_reset_pressed() -> void:
	if not _reset_armed:
		_reset_armed = true
		reset_btn.text = "ТОЧНО? ЕЩЁ РАЗ"
		_dbg("сброс: первое нажатие, жду подтверждение 3 c")
		await get_tree().create_timer(3.0).timeout
		_reset_armed = false
		if is_instance_valid(reset_btn):
			reset_btn.text = "СБРОС (ОТЛАДКА)"
		return
	_reset_armed = false
	_dbg("ПОЛНЫЙ СБРОС ПРОГРЕССА: удаляю сейв %s" % SAVE_PATH)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	get_tree().reload_current_scene()


func _on_intro_ok() -> void:
	_flag_set("intro_seen", true)
	intro_popup.visible = false
	_dbg("интро закрыто игроком")


## Авто-бабло капает и в сцене слотов: улучшения куплены в кликере,
## а доход общий — иначе при возврате с кликера прибавка "засыпает".
func _process(delta: float) -> void:
	var g := Upgrades.auto_per_sec(upg_levels)
	if g <= 0:
		return
	_auto_acc += delta
	var add := 0
	while _auto_acc >= 1.0:
		_auto_acc -= 1.0
		add += g
	if add > 0:
		balance += add
		_update_labels()


func _dbg(msg: String) -> void:
	if DEBUG:
		print("[slot] " + msg)


func _layout() -> void:
	var vs := get_viewport_rect().size
	if vs.x <= 0 or vs.y <= 0:
		return
	var s := minf(vs.x / VSIZE.x, vs.y / VSIZE.y)
	machine.scale = Vector2(s, s)
	machine.position = (vs - VSIZE * s) * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		for m in [paytable_popup, bet_menu, auto_menu, sound_menu]:
			if m.visible:
				_close_menus()
				get_viewport().set_input_as_handled()
				return


## Поддерживает тексты выплат в таблице актуальными по данным SlotData.
func _refresh_paytable() -> void:
	var vbox: VBoxContainer = $machine/paytable_popup/popup_panel/scroll/vbox
	for sym in PAY_ORDER:
		var row := vbox.get_node_or_null("row_%s" % SYMBOL_KEYS[sym])
		if row == null:
			continue
		var pays: Array = SlotData.PAYTABLE[sym]
		var parts: Array[String] = []
		for k in range(1, 4):
			parts.append("×%d: %d" % [k + 1, int(pays[k])])
		var val: Label = row.get_node("val")
		val.text = "   ".join(parts)
		var p2 := row.get_node_or_null("p2")
		if p2 != null:
			p2.text = "×2: %d" % int(pays[0])
			p2.visible = int(pays[0]) > 0


# ------------------------------------------------------------------- меню

func _connect_menu(menu: Control,
		close_path: String = "panel/vbox/head/close_btn") -> void:
	menu.get_node("dim").gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_menus()
	)
	menu.get_node(close_path).pressed.connect(_close_menus)


func _open_menu(menu: Control) -> void:
	if _spinning and menu != paytable_popup:
		return  # настройки ставки/автоигры не меняются посреди спина
	_close_menus()
	menu.show()


func _open_bet_menu() -> void:
	if _spinning:
		return
	bet_total_label.text = "Полная ставка: %s" % _fmt(total_bet())
	_open_menu(bet_menu)
	bet_input.text = str(total_bet())


func _close_menus() -> void:
	paytable_popup.hide()
	bet_menu.hide()
	auto_menu.hide()
	sound_menu.hide()


# ------------------------------------------------------------------- хелперы UI

func _update_labels() -> void:
	balance_label.text = _fmt(balance)  # число рядом с иконкой мешка денег
	bet_label.text = "Ставка/линия: %d" % bet_line
	fullbet_label.text = "Полная ставка: %d" % total_bet()
	if _fs_left > 0:
		freespin_label.show()
		freespin_label.text = "ФРИСПИНЫ: %d" % _fs_left
	else:
		freespin_label.hide()
	if autospin:
		auto_label.show()
		auto_label.text = "АВТО: %s" % ("∞" if _auto_left < 0 else str(_auto_left))
	else:
		auto_label.hide()


func _apply_toggles() -> void:
	auto_btn.modulate = Color(1.35, 1.35, 1.35) if autospin else Color(1, 1, 1)
	speed_btn.modulate = Color(1.35, 1.35, 1.35) if speed_idx > 0 else Color(1, 1, 1)
	for r in reels:
		r.speed_scale = SPEEDS[speed_idx]


func _apply_volumes() -> void:
	for bus_name in ["SFX", "Music"]:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx == -1:
			continue
		var v := vol_sfx if bus_name == "SFX" else vol_music
		AudioServer.set_bus_mute(idx, v <= 0)
		if v > 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(v / 100.0))


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


func total_bet() -> int:
	return bet_line * SlotData.PAYLINES.size()


## Ставка на линию (внутренняя мастер-величина, целая).
func _set_bet(v: int) -> void:
	var capped := clampi(v, 1, maxi(1, balance))
	if v > balance:
		_banner("СТАВКА НЕ БОЛЬШЕ БАЛАНСА: %s" % _fmt(balance), Color("#ff7b7b"))
	bet_line = capped
	bet_input.text = str(total_bet())
	_save()
	_update_labels()
	_dbg("ставка на линию: %d, полная %d" % [bet_line, total_bet()])


## Игрок вписывает ПОЛНУЮ ставку: округляем до кратной 9 линиям,
## не больше баланса.
func _set_bet_total(t: int) -> void:
	var capped := clampi(t, 1, maxi(1, balance))
	if t > balance:
		_banner("СТАВКА НЕ БОЛЬШЕ БАЛАНСА: %s" % _fmt(balance), Color("#ff7b7b"))
	var lines := SlotData.PAYLINES.size()
	var rounded := maxi(lines, int(round(float(capped) / float(lines))) * lines)
	if rounded != t:
		_banner("ПОЛНАЯ СТАВКА ОКРУГЛЕНА ДО %d (9 ЛИНИЙ)" % rounded, Color("#ffe9b8"))
	_set_bet(rounded / lines)


func _on_bet_apply() -> void:
	var s := bet_input.text.replace(" ", "").replace("\t", "")
	if not s.is_valid_int():
		_banner("ВПИШИ ЧИСЛО: НАПРИМЕР 90", Color("#ff7b7b"))
		return
	_set_bet_total(int(s))


func _on_max_bet() -> void:
	if _spinning:
		return
	_set_bet(int(BETS[BETS.size() - 1]))
	_banner("МАКС. СТАВКА: %s" % _fmt(total_bet()), Color("#ffe9b8"))


func _on_clicker_pressed() -> void:
	if _spinning:
		_dbg("клик по мешку во время спина — игнор")
		return
	_dbg("переход в сцену кликера, баланс=%d" % balance)
	if not bool(_flag_get("clicker_visited", false)):
		_flag_set("clicker_visited", true)
		clicker_glow.visible = false
		if _glow_tw != null:
			_glow_tw.kill()
		_dbg("световое выделение снято: игрок впервые ушёл в кликер")
	_save()
	get_tree().change_scene_to_file("res://scenes/clicker.tscn")


func _on_auto_pressed() -> void:
	if autospin:
		_stop_autospin("АВТОИГРА ОСТАНОВЛЕНА")
		return
	if _spinning:
		return
	_open_menu(auto_menu)


func _start_autospin(count: int) -> void:
	_close_menus()
	autospin = true
	_auto_left = count
	_apply_toggles()
	_update_labels()
	if not _spinning:
		_run_session()


func _stop_autospin(text: String) -> void:
	autospin = false
	_auto_left = 0
	_apply_toggles()
	_update_labels()
	_banner(text, Color("#7ef3ff"))


func _on_speed_pressed() -> void:
	speed_idx = (speed_idx + 1) % SPEEDS.size()
	_dbg("скорость -> x%d" % int(SPEEDS[speed_idx]))
	_save()
	_apply_toggles()
	_banner("СКОРОСТЬ ×%d" % int(SPEEDS[speed_idx]), Color("#ffd794"))


# ------------------------------------------------------------------- сейв

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		balance = int(cfg.get_value("save", "balance", START_BALANCE))
		var old_idx := clampi(int(cfg.get_value("save", "bet", 0)), 0, BETS.size() - 1)
		bet_line = maxi(1, int(cfg.get_value("save", "bet_line", int(BETS[old_idx]))))
		var arr: Array = cfg.get_value("save", "upg_levels", [])
		upg_levels.clear()
		for k in Upgrades.UPGRADES.size():
			upg_levels.append(int(arr[k]) if k < arr.size() else 0)
		speed_idx = clampi(int(cfg.get_value("save", "speed", 0)), 0, SPEEDS.size() - 1)
		vol_sfx = clampi(int(cfg.get_value("save", "vol_sfx", 80)), 0, 100)
		vol_music = clampi(int(cfg.get_value("save", "vol_music", 80)), 0, 100)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # сохраняем чужие ключи (уровни кликера, флаги)
	cfg.set_value("save", "balance", balance)
	cfg.set_value("save", "bet_line", bet_line)
	cfg.set_value("save", "speed", speed_idx)
	cfg.set_value("save", "vol_sfx", vol_sfx)
	cfg.set_value("save", "vol_music", vol_music)
	cfg.save(SAVE_PATH)


# ------------------------------------------------------------------- спины

func _on_spin_pressed() -> void:
	if _spinning:
		return
	if autospin:  # ПУСК во время автоигры останавливает серию
		_stop_autospin("АВТОИГРА ОСТАНОВЛЕНА")
		return
	_run_session()


## Серия спинов: спин + цепочка фриспинов; в автоигре повторяется,
## пока не кончится лимит, баланс или игрок не остановил серию.
func _run_session() -> void:
	if _spinning:
		return
	_dbg("сессия спинов начата (autospin=%s, ставка=%d)" % [autospin, total_bet()])
	_spinning = true
	_update_labels()
	while true:
		await _spin(false)
		if _fs_left > 0:
			await get_tree().create_timer(1.2).timeout
			while _fs_left > 0:
				_fs_left -= 1
				_update_labels()
				await _spin(true)
				if _fs_left > 0:
					await get_tree().create_timer(0.5 if SPEEDS[speed_idx] > 1.0 else 0.9).timeout
			_banner("ФРИСПИНЫ ЗАВЕРШЕНЫ", Color("#7ef3ff"))
			await get_tree().create_timer(0.8).timeout
		if not autospin:
			break
		if _auto_left > 0:
			_auto_left -= 1
			_update_labels()
			if _auto_left == 0:
				_stop_autospin("АВТОИГРА ЗАВЕРШЕНА")
				break
		if balance < total_bet():
			_stop_autospin("НЕДОСТАТОЧНО МОНЕТ!")
			break
		await get_tree().create_timer(0.3 if SPEEDS[speed_idx] > 1.0 else 0.6).timeout
	_spinning = false
	_dbg("сессия спинов завершена, баланс=%d" % balance)
	_update_labels()


## Один оборот барабанов с оценкой результата. is_free = фриспин.
func _spin(is_free: bool) -> void:
	_clear_fx()
	if not is_free:
		if balance < total_bet():
			_banner("НЕДОСТАТОЧНО МОНЕТ!", Color("#ff7b7b"))
			_update_labels()
			return
		balance -= total_bet()
		_save()
		_update_labels()
	win_label.text = ""

	var grid := SlotData.make_grid(rng)
	for reel in reels:
		reel.start_spin()
	var sf: float = SPEEDS[speed_idx]
	for c in reels.size():
		var delay: float = (0.85 + c * 0.3 + rng.randf() * 0.15) / sf
		get_tree().create_timer(delay).timeout.connect(
			func() -> void: reels[c].stop_at(grid[c]))
	for reel in reels:
		await reel.stopped

	var res := SlotData.evaluate(grid, bet_line)
	var won: int = res.total
	_dbg("спин: выигрыш=%d, линий=%d, скаттер=%d, фриспины=%d" % [
			won, res.line_wins.size(), res.scatter, res.free_spins])
	if won > 0:
		balance += won
		_save()
		_show_win_fx(res)
		_count_up(won)
	_update_labels()

	# Всплывающие уведомления: скаттер -> большой выигрыш.
	if res.scatter >= 3:
		await _popup(5, "+%d ФРИСПИНОВ" % res.free_spins)
	if won > 0:
		var ratio := float(won) / float(total_bet())
		var tier := -1
		for t in WIN_TIERS:
			if ratio >= float(t[0]):
				tier = int(t[1])
				break
		if tier >= 0:
			if is_free and tier != 6:
				tier = 8  # выигрыш в бонусной игре (фриспины)
			await _popup(tier, "ВЫИГРЫШ: %s" % _fmt(won))
	if is_free and res.free_spins > 0:
		await _popup(7, "+%d ФРИСПИНОВ" % res.free_spins)
	if res.free_spins > 0:
		if is_free:
			_fs_left += res.free_spins
		else:
			_fs_left = res.free_spins
		_update_labels()


## Всплывающее уведомление с бейджем из wins_spritessheet.png.
func _popup(badge_idx: int, text: String) -> void:
	_dbg("попап бейджа %d: %s" % [badge_idx, text])
	if _popup_tw != null and _popup_tw.is_valid():
		_popup_tw.kill()
	var at := AtlasTexture.new()
	at.atlas = _wins_tex
	at.region = WIN_REGIONS[badge_idx]
	win_badge.texture = at
	win_popup_label.text = text
	win_popup.show()
	win_popup.pivot_offset = win_popup.size * 0.5
	win_popup.scale = Vector2(0.5, 0.5)
	win_popup.modulate = Color(1, 1, 1, 0)
	_popup_tw = create_tween()
	_popup_tw.set_parallel(true)
	_popup_tw.tween_property(win_popup, "scale", Vector2(1, 1), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popup_tw.tween_property(win_popup, "modulate", Color(1, 1, 1, 1), 0.25)
	_popup_tw.chain().tween_interval(0.45 if SPEEDS[speed_idx] > 1.0 else 1.1)
	_popup_tw.set_parallel(false)
	_popup_tw.chain().tween_property(win_popup, "modulate", Color(1, 1, 1, 0), 0.35)
	_popup_tw.chain().tween_callback(win_popup.hide)
	await _popup_tw.finished


func _cell_center(col: int, row: int) -> Vector2:
	return Vector2(col * (CELL + GAP) + CELL * 0.5, row * (CELL + GAP) + CELL * 0.5)


func _show_win_fx(res: Dictionary) -> void:
	for w in res.line_wins:
		var color: Color = SlotData.LINE_COLORS[int(w.line)]
		var pts: PackedVector2Array = PackedVector2Array()
		for cellv in w.cells:
			pts.append(_cell_center(cellv.x, cellv.y))
			var hl := ColorRect.new()
			hl.size = Vector2(CELL, CELL)
			hl.position = Vector2(cellv.x * (CELL + GAP), cellv.y * (CELL + GAP))
			hl.color = Color(color.r, color.g, color.b, 0.32)
			fx_layer.add_child(hl)
			_fx_nodes.append(hl)
		var glow := Line2D.new()
		glow.points = pts
		glow.width = 18.0
		glow.default_color = Color(color.r, color.g, color.b, 0.30)
		lines_overlay.add_child(glow)
		_fx_nodes.append(glow)
		var line := Line2D.new()
		line.points = pts
		line.width = 7.0
		line.default_color = color
		lines_overlay.add_child(line)
		_fx_nodes.append(line)
	for cellv in _scatter_cells(res):
		var hl := ColorRect.new()
		hl.size = Vector2(CELL, CELL)
		hl.position = Vector2(cellv.x * (CELL + GAP), cellv.y * (CELL + GAP))
		hl.color = Color(1.0, 0.85, 0.3, 0.4)
		fx_layer.add_child(hl)
		_fx_nodes.append(hl)
	if _fx_nodes.is_empty():
		return
	var tw := create_tween()
	tw.set_loops(4)
	tw.tween_property(fx_layer, "modulate", Color(1, 1, 1, 0.35), 0.45)
	tw.tween_property(fx_layer, "modulate", Color(1, 1, 1, 1.0), 0.45)


func _scatter_cells(res: Dictionary) -> Array:
	var out: Array = []
	if int(res.scatter) < 3:
		return out
	for c in SlotData.COLS:
		for r in SlotData.ROWS:
			if reels[c].symbols[r] == SlotData.Symbol.BONUS:
				out.append(Vector2i(c, r))
	return out


func _clear_fx() -> void:
	for n in _fx_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_fx_nodes.clear()
	fx_layer.modulate = Color(1, 1, 1, 1)
	win_label.text = ""


func _count_up(amount: int) -> void:
	if _win_tween != null and _win_tween.is_valid():
		_win_tween.kill()
	_win_tween = create_tween()
	var set_win := func(v: float) -> void:
		win_label.text = "Выигрыш: %s" % _fmt(int(round(v)))
	_win_tween.tween_method(set_win, 0.0, float(amount), 0.7)


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
