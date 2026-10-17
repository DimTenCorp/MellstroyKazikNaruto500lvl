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
const DEBT := 10000000    ## сюжетный долг: 10 000 000 денег
const DEBUG_SUMS := [1000, 10000, 100000, 1000000, 10000000]
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

const BALANCE_MAX := 2147483647  ## потолок: выше не растёт (защита от переполнения)
var _balance_v := START_BALANCE
var _cap_notified := false       ## баннер о достижении потолка показан
## Баланс с защитой: отрицательное значение невозможно установить —
## любая попытка пишется в лог и зажимается в 0 (счетчик не уйдёт в минус).
var balance: int:
	get:
		return _balance_v
	set(v):
		if v < 0:
			## вместо сброса: баланс остаётся при прежнем значении
			print("[balance] ОТРИЦАТЕЛЬНОЕ значение %d отклонено, остаётся %d"
					% [v, _balance_v])
		elif v > BALANCE_MAX:
			## потолок: дальше баланс не растёт, переполнение невозможно
			if _balance_v < BALANCE_MAX:
				print("[balance] достигнут потолок %d, рост остановлен" % BALANCE_MAX)
			_balance_v = BALANCE_MAX
		else:
			_balance_v = v
var bet_line := 1  ## ставка на линию: любое число от 1 до баланса
var speed_idx := 0
var vol_sfx := 80
var vol_music := 80
var rebirths := 0        ## число перерождений: заработок x2^N
var debt_stage := -1     ## оплаченная ступень долга (-1 = ещё нет)
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
var _lang_icons := {}
var _pop_scale := 1.0          ## масштаб попапа выигрыша в портрете
var _cell_w := CELL            ## текущая метрика ячейки (портрет меняет)
var _gap_w := GAP
var _def_rects := {}
var _def_anchors := {}
var _def_offsets := {}           ## дефолтные rect'ы узлов для возврата из портрета
var _def_fonts := {}

## Узлы, которые переставляются в портретном режиме (пути от machine).
const MANAGED := [
	"balance_icon", "balance_label", "win_label", "freespin_label",
	"bottom_bar/bet_label", "bottom_bar/auto_label", "bottom_bar/fullbet_label",
	"grid_panel", "grid_panel/Reel0", "grid_panel/Reel1", "grid_panel/Reel2",
	"grid_panel/Reel3", "grid_panel/Reel4", "grid_panel/msg_label",
	"bottom_bar/bet_btn", "bottom_bar/max_btn", "bottom_bar/auto_btn",
	"bottom_bar/speed_btn", "bottom_bar/spin_btn", "bottom_bar/paytable_btn",
	"bottom_bar/sound_btn", "bottom_bar/lang_btn", "bottom_bar/clicker_btn",
	"bottom_bar/clicker_glow", "debug_btn", "reset_btn", "win_popup",
	"bet_menu/panel", "auto_menu/panel", "sound_menu/panel", "debug_menu/panel",
	"paytable_popup/popup_panel",
	"intro_popup/intro_panel", "intro_popup/intro_label", "intro_popup/intro_btn",
	"debt_popup/debt_panel", "debt_popup/debt_label", "debt_popup/debt_btn",
	"debt_popup/debt_later", "rebirth_btn", "debt_plaque",
]
## В портрете логическая ширина остаётся 1280 (canvas_items масштабирует
## по ширине), поэтому размеры/шрифты крупнее десктопных в ~2.5 раза.
const PORTRAIT_FS := {
	"balance_label": 64, "win_label": 56, "freespin_label": 44,
	"bottom_bar/auto_label": 44, "bottom_bar/fullbet_label": 52,
	"bottom_bar/bet_label": 46, "grid_panel/msg_label": 64,
}
var _auto_acc := 0.0
var _popup_tw: Tween
## Переведённые листы бейджей выигрыша.
const WIN_SHEETS := {
	"ru": "res://img/win/wins_spritessheet.png",
	"en": "res://img/win/wins_spritessheet_EN.png",
	"tr": "res://img/win/wins_spritessheet_TR.png",
}

## Регионы бейджей EN/TR-листов (порядок 3×3 как у RU).
const WIN_REGIONS_LANG := {
	"ru": WIN_REGIONS,
	"en": [
		Rect2(10, 24, 412, 216), Rect2(459, 9, 436, 228), Rect2(903, 11, 461, 229),
		Rect2(25, 240, 382, 240), Rect2(488, 278, 405, 201), Rect2(995, 250, 345, 190),
		Rect2(6, 505, 420, 250), Rect2(493, 547, 390, 188), Rect2(965, 536, 410, 182),
	],
	"tr": [
		Rect2(10, 24, 412, 216), Rect2(459, 9, 436, 227), Rect2(903, 11, 461, 229),
		Rect2(26, 240, 381, 240), Rect2(488, 279, 405, 200), Rect2(995, 250, 345, 190),
		Rect2(6, 505, 420, 251), Rect2(494, 547, 388, 188), Rect2(965, 536, 410, 182),
	],
}

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
@onready var debug_btn: Button = $machine/debug_btn
@onready var lang_btn: TextureButton = $machine/bottom_bar/lang_btn
@onready var debt_popup: Control = $machine/debt_popup
@onready var debt_btn: Button = $machine/debt_popup/debt_btn
@onready var debt_later: Button = $machine/debt_popup/debt_later
@onready var rebirth_btn: Button = $machine/rebirth_btn
@onready var debt_plaque: Label = $machine/debt_plaque
@onready var debt_label: Label = $machine/debt_popup/debt_label
@onready var debug_menu: Control = $machine/debug_menu
@onready var dbg_input: LineEdit = $machine/debug_menu/panel/vbox/dbg_row/dbg_input
@onready var dbg_apply: Button = $machine/debug_menu/panel/vbox/dbg_row/dbg_apply
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
	debt_btn.pressed.connect(_on_debt_rebirth)
	debt_later.pressed.connect(_on_debt_later)
	rebirth_btn.pressed.connect(_on_rebirth_btn)
	debug_btn.pressed.connect(func() -> void: _open_menu(debug_menu))
	_setup_lang()
	_apply_lang()
	_connect_menu(debug_menu)
	# страховка: закрытие меню выдачи даже если список _close_menus устареет
	debug_menu.get_node("panel/vbox/head/close_btn").pressed.connect(
			func() -> void: debug_menu.hide())
	debug_menu.get_node("dim").gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			debug_menu.hide())
	# меню выдачи — верхним слоем, чтобы ничего не перехватывало клики
	debug_menu.get_parent().move_child(debug_menu, -1)
	for i in DEBUG_SUMS.size():
		var opt: Button = get_node("machine/debug_menu/panel/vbox/grid/dbg_opt%d" % i)
		opt.pressed.connect(func() -> void:
			_give_money(int(DEBUG_SUMS[i]))
			_close_menus()
		)
	dbg_apply.pressed.connect(_on_dbg_apply)
	dbg_input.text_submitted.connect(func(_t: String) -> void: _on_dbg_apply())
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
		Sfx.set_volumes(vol_sfx, vol_music)
		_apply_volumes()
		_save()   ## настройки звука живут в сейве сразу, переживая смены сцен
	)
	music_slider.value_changed.connect(func(v: float) -> void:
		vol_music = int(v)
		music_val.text = str(vol_music)
		Sfx.set_volumes(vol_sfx, vol_music)
		_apply_volumes()
		_save()
	)

	for btn in _find_buttons(self):
		_bind_press_anim(btn)
		btn.pressed.connect(func() -> void: Sfx.play(self, "click"))
	_load_save()
	if Sfx.has_vols():   ## живые громкости переживают любую смену сцены
		vol_sfx = int(Sfx.cur_sfx)
		vol_music = int(Sfx.cur_music)
	print("[sfx-cfg] слот старт: vol_sfx=%d vol_music=%d" % [vol_sfx, vol_music])
	sfx_slider.value = vol_sfx
	music_slider.value = vol_music
	Sfx.ensure_buses(vol_sfx, vol_music)
	sfx_val.text = str(vol_sfx)
	music_val.text = str(vol_music)
	_apply_volumes()
	_apply_toggles()
	_update_rebirth_btn()
	_refresh_paytable()
	_update_labels()
	_setup_intro()
	for p in ["win_label", "balance_label", "freespin_label",
			"bottom_bar/auto_label", "bottom_bar/bet_label",
			"bottom_bar/fullbet_label", "grid_panel/msg_label",
			"balance_icon", "bottom_bar/clicker_glow"]:
		machine.get_node(p).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capture_defaults()
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
	debt_label.size = Vector2(640, 200)
	debt_label.position = Vector2(320, 220)
	debt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	debt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	debt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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
		_dbg("первый заход: баланс обнулён, показано интро о долге 10 000 000")
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
		reset_btn.text = L10n.t("reset_confirm")
		_dbg("сброс: первое нажатие, жду подтверждение 3 c")
		await get_tree().create_timer(3.0).timeout
		_reset_armed = false
		if is_instance_valid(reset_btn):
			reset_btn.text = L10n.t("reset_btn")
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


func _capture_defaults() -> void:
	for p in MANAGED:
		var n: Control = machine.get_node(p)
		_def_rects[p] = Rect2(n.position, n.size)
		_def_anchors[p] = Vector4(n.anchor_left, n.anchor_top,
				n.anchor_right, n.anchor_bottom)
		_def_offsets[p] = Vector4(n.offset_left, n.offset_top,
				n.offset_right, n.offset_bottom)
	for p in PORTRAIT_FS:
		var l: Label = machine.get_node(p)
		_def_fonts[p] = int(l.get_theme_font_size("font_size"))


## Ставим rect узлу: сначала гасим якоря, иначе size перезапишется.
func _set_r(p: String, x: float, y: float, w: float, h: float) -> void:
	var n: Control = machine.get_node(p)
	if n.anchor_left != n.anchor_right or n.anchor_top != n.anchor_bottom:
		n.anchor_left = 0.0
		n.anchor_top = 0.0
		n.anchor_right = 0.0
		n.anchor_bottom = 0.0
	n.position = Vector2(x, y)
	n.size = Vector2(w, h)


func _restore_defaults() -> void:
	for p in _def_rects:
		var n: Control = machine.get_node(p)
		var a: Vector4 = _def_anchors[p]
		n.anchor_left = a.x
		n.anchor_top = a.y
		n.anchor_right = a.z
		n.anchor_bottom = a.w
		var o: Vector4 = _def_offsets[p]
		n.offset_left = o.x
		n.offset_top = o.y
		n.offset_right = o.z
		n.offset_bottom = o.w
	for p in _def_fonts:
		var l: Label = machine.get_node(p)
		l.add_theme_font_size_override("font_size", _def_fonts[p])
	win_popup.scale = Vector2.ONE
	_pop_scale = 1.0
	for bp in ["debt_popup/debt_btn", "debt_popup/debt_later", "rebirth_btn"]:
		(machine.get_node(bp) as Button).remove_theme_font_size_override("font_size")
	debt_plaque.remove_theme_font_size_override("font_size")
	_cell_w = CELL
	_gap_w = GAP
	for c in SlotData.COLS:
		(machine.get_node("grid_panel/Reel%d" % c) as SlotReel).relayout()


## Портретная раскладка (9:16): все размеры через u = ширина/1280, низ
## якорится к низу экрана — не зависит от конвенции масштаба canvas_items.
func _layout_portrait(W: float, H: float) -> void:
	var u := W / 1280.0
	var m := 24.0 * u
	var g := 16.0 * u
	var gw := W - 2 * m
	var cell := (gw - 4 * g) / 5.0
	var gh := 3 * cell + 2 * g
	_set_r("balance_icon", m, m, 150 * u, 138 * u)
	_set_r("balance_label", m + 160 * u, m + 10 * u, W - 434 * u - m, 90 * u)
	_set_r("debt_plaque", W - 260 * u, 34 * u, 236 * u, 90 * u)
	debt_plaque.add_theme_font_size_override("font_size", int(34 * u))
	_set_r("win_label", m, 168 * u, W - 260 * u, 80 * u)
	_set_r("freespin_label", m, 252 * u, (W - 2 * m) * 0.5, 60 * u)
	_set_r("bottom_bar/auto_label", m + (W - 2 * m) * 0.5, 252 * u,
			(W - 2 * m) * 0.5, 60 * u)
	_set_r("grid_panel", m, 320 * u, gw, gh)
	for c in SlotData.COLS:
		var rl: SlotReel = machine.get_node("grid_panel/Reel%d" % c)
		rl.position = Vector2(c * (cell + g), 0)
		rl.size = Vector2(cell, gh)
		rl.relayout()
	_set_r("grid_panel/msg_label", 0, gh * 0.5 - 60 * u, gw, 120 * u)
	_set_r("bottom_bar/fullbet_label", m, 328 * u + gh, W - 2 * m, 70 * u)
	_set_r("bottom_bar/bet_label", m, 402 * u + gh, W - 2 * m, 60 * u)
	# редкие кнопки — колонки по бокам нижней зоны
	_set_r("bottom_bar/paytable_btn", m, H - 720 * u, 200 * u, 200 * u)
	_set_r("bottom_bar/sound_btn", m, H - 510 * u, 200 * u, 200 * u)
	_set_r("bottom_bar/lang_btn", W - 224 * u, H - 720 * u, 200 * u, 200 * u)
	_set_r("bottom_bar/clicker_btn", W - 224 * u, H - 510 * u, 200 * u, 200 * u)
	_set_r("bottom_bar/clicker_glow", W - 232 * u, H - 518 * u, 216 * u, 216 * u)
	# частые — центр низа: ставка/макс/авто, турбо, ПУСК во всю ширину
	var cx := m + 216 * u
	var cw := W - 2 * m - 432 * u
	var w3 := (cw - 2 * g) / 3.0
	_set_r("bottom_bar/bet_btn", cx, H - 720 * u, w3, 210 * u)
	_set_r("bottom_bar/max_btn", cx + w3 + g, H - 720 * u, w3, 210 * u)
	_set_r("bottom_bar/auto_btn", cx + 2 * (w3 + g), H - 720 * u, w3, 210 * u)
	_set_r("bottom_bar/speed_btn", cx, H - 500 * u, cw, 190 * u)
	_set_r("bottom_bar/spin_btn", m, H - 290 * u, W - 2 * m, 270 * u)
	_set_r("debug_btn", W - 220 * u, 168 * u, 200 * u, 50 * u)
	_set_r("reset_btn", W - 220 * u, 224 * u, 200 * u, 50 * u)
	for mp in ["bet_menu/panel", "auto_menu/panel", "sound_menu/panel",
			"debug_menu/panel"]:
		var ph := minf((_def_rects[mp] as Rect2).size.y * u, H - 80 * u)
		var pw := minf(900.0 * u, W - 48 * u)
		_set_r(mp, (W - pw) * 0.5, (H - ph) * 0.5, pw, ph)
	_set_r("paytable_popup/popup_panel", 24 * u, 120 * u, W - 48 * u,
			H - 240 * u)
	var ps := minf(1.0, (W - 48 * u) / 500.0)
	_pop_scale = ps
	win_popup.scale = Vector2(ps, ps)
	win_popup.position = Vector2((W - 500 * ps) * 0.5, H * 0.3)
	_set_r("intro_popup/intro_panel", 40 * u, 400 * u, W - 80 * u, 900 * u)
	_set_r("intro_popup/intro_label", 70 * u, 480 * u, W - 140 * u, 560 * u)
	_set_r("intro_popup/intro_btn", (W - 560 * u) * 0.5, 1060 * u, 560 * u,
			120 * u)
	_set_r("debt_popup/debt_panel", 40 * u, 450 * u, W - 80 * u, 850 * u)
	_set_r("debt_popup/debt_label", 70 * u, 520 * u, W - 140 * u, 480 * u)
	var w2 := (W - 140 * u - 20 * u) / 2.0
	_set_r("debt_popup/debt_btn", 70 * u, 1030 * u, w2, 120 * u)
	_set_r("debt_popup/debt_later", 70 * u + w2 + 20 * u, 1030 * u, w2, 120 * u)
	_set_r("rebirth_btn", m, H - 930 * u, 200 * u, 200 * u)
	(rebirth_btn as Button).add_theme_font_size_override(
			"font_size", int(28 * u))
	debt_btn.add_theme_font_size_override("font_size", int(30 * u))
	debt_later.add_theme_font_size_override("font_size", int(30 * u))
	_cell_w = cell
	_gap_w = g
	for p in PORTRAIT_FS:
		var l: Label = machine.get_node(p)
		l.add_theme_font_size_override("font_size",
				int(PORTRAIT_FS[p] * u))


func _layout() -> void:
	var vs := get_viewport_rect().size
	var off := Vector2.ZERO
	if OS.has_feature("mobile") or OS.has_feature("android") \
			or OS.has_feature("ios"):
		var sa := DisplayServer.get_display_safe_area()
		if sa.size.x > 0 and sa.size.y > 0:
			off = sa.position
			vs = sa.size
	if vs.x <= 0 or vs.y <= 0:
		return
	if vs.x < vs.y:  # портрет (9:16): своя раскладка вместо уменьшения всей
		machine.scale = Vector2.ONE
		machine.position = off
		_dbg("портрет: логический вьюпорт %s" % vs)
		_layout_portrait(vs.x, vs.y)
		return
	_restore_defaults()
	var s := minf(vs.x / VSIZE.x, vs.y / VSIZE.y)
	machine.scale = Vector2(s, s)
	machine.position = off + (vs - VSIZE * s) * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		for m in [paytable_popup, bet_menu, auto_menu, sound_menu, debug_menu]:
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
	bet_total_label.text = L10n.t("full_bet_menu") % _fmt(total_bet())
	_open_menu(bet_menu)
	bet_input.text = str(total_bet())


func _close_menus() -> void:
	paytable_popup.hide()
	bet_menu.hide()
	auto_menu.hide()
	sound_menu.hide()


# ------------------------------------------------------------------- хелперы UI

## Переведённые листы арт-кнопок: меняем атлас у AtlasTexture кнопок.
const BTN_SHEETS := {
	"ru": "res://img/buttons_spr/buttons_sprites.png",
	"en": "res://img/buttons/buttons_sprites_EN.png",
	"tr": "res://img/buttons/buttons_sprites_TR.png",
}

const LANG_REGIONS := {
	"ru": Rect2(8, 10, 285, 305),
	"en": Rect2(330, 10, 300, 305),
	"tr": Rect2(676, 10, 293, 305),
}


## Язык: из сейва; при первом заходе в вебе — авто через Playgama Bridge.
func _setup_lang() -> void:
	var sheet: Texture2D = load("res://img/buttons/buttons_lang.png")
	for code in LANG_REGIONS:
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = LANG_REGIONS[code]
		_lang_icons[code] = at
	var saved := String(_flag_get("lang", ""))
	if saved == "":
		saved = _detect_lang()
		_flag_set("lang", saved)
	L10n.lang = saved if saved in L10n.LANGS else "ru"
	_dbg("язык: %s" % L10n.lang)
	lang_btn.texture_normal = _lang_icons[L10n.lang]
	lang_btn.pressed.connect(_on_lang_pressed)


func _detect_lang() -> String:
	if not OS.has_feature("web"):
		return "ru"  # в редакторе мок-платформа, авто только в вебе
	var br := get_node_or_null("/root/Bridge")
	if br == null:
		var s: GDScript = load("res://addons/playgama_bridge/bridge.gd")
		if s != null:
			br = s.new()
			br.name = "Bridge"
			get_tree().root.add_child(br)
	if br != null and br.platform != null:
		var code := str(br.platform.language).to_lower()
		for l in L10n.LANGS:
			if code.begins_with(l):
				return l
	return "ru"


func _on_lang_pressed() -> void:
	var i := L10n.LANGS.find(L10n.lang)
	L10n.lang = L10n.LANGS[(i + 1) % L10n.LANGS.size()]
	_flag_set("lang", L10n.lang)
	lang_btn.texture_normal = _lang_icons[L10n.lang]
	_apply_lang()
	_update_labels()
	_banner(L10n.t("lang_banner"), Color("#ffe9b8"))
	_dbg("язык переключён: %s" % L10n.lang)


## Все статические надписи сцены — по текущему языку.
func _apply_lang() -> void:
	var m := $machine
	m.get_node("bet_menu/panel/vbox/head/head_title").text = L10n.t("m_bet")
	m.get_node("auto_menu/panel/vbox/head/head_title").text = L10n.t("m_auto")
	m.get_node("sound_menu/panel/vbox/head/head_title").text = L10n.t("m_sound")
	m.get_node("debug_menu/panel/vbox/head/head_title").text = L10n.t("m_debug")
	var pt := "paytable_popup/popup_panel/scroll/vbox/"
	m.get_node(pt + "head/head_title").text = L10n.t("m_pay")
	m.get_node(pt + "head/close_btn").text = L10n.t("close")
	m.get_node(pt + "rules").text = L10n.t("rules")
	m.get_node(pt + "row_bonus/name").text = L10n.t("scatter_name")
	m.get_node(pt + "row_bonus/val").text = L10n.t("bonus_val")
	m.get_node(pt + "lines_title").text = L10n.t("lines_title")
	for key in ["cherry", "lemon", "orange", "plum", "watermelon", "star",
			"horseshoe", "moneysack", "bell"]:
		m.get_node(pt + "row_%s/name" % key).text = L10n.t("sym_" + key)
	for menu in ["bet_menu", "auto_menu", "sound_menu", "debug_menu"]:
		m.get_node("%s/panel/vbox/head/close_btn" % menu).text = L10n.t("close")
	m.get_node("bet_menu/panel/vbox/bet_row/bet_apply").text = L10n.t("apply")
	m.get_node("bet_menu/panel/vbox/bet_row/bet_input").placeholder_text = L10n.t("ph_bet")
	m.get_node("bet_menu/panel/vbox/bet_total").text = \
			L10n.t("full_bet_menu") % _fmt(total_bet())
	m.get_node("auto_menu/panel/vbox/grid/auto_cancel").text = L10n.t("cancel")
	m.get_node("auto_menu/panel/vbox/auto_hint").text = L10n.t("auto_hint")
	m.get_node("sound_menu/panel/vbox/row_sfx/sfx_name").text = L10n.t("sfx")
	m.get_node("sound_menu/panel/vbox/row_music/music_name").text = L10n.t("music")
	m.get_node("debug_menu/panel/vbox/dbg_row/dbg_apply").text = L10n.t("give")
	m.get_node("debug_menu/panel/vbox/dbg_row/dbg_input").placeholder_text = L10n.t("ph_sum")
	intro_label.text = L10n.t("intro_text")
	intro_btn.text = L10n.t("intro_btn")
	debt_label.text = L10n.t("debt_text")
	debt_btn.text = L10n.t("rebirth_now")
	debt_later.text = L10n.t("rebirth_later")
	rebirth_btn.text = L10n.t("rebirth_btn")
	reset_btn.text = L10n.t("reset_btn")
	debug_btn.text = L10n.t("debug_btn")
	var sheet: Texture2D = load(BTN_SHEETS[L10n.lang])
	for b in [spin_btn, auto_btn, max_btn, bet_btn, speed_btn, paytable_btn,
			sound_btn]:
		var at := b.texture_normal as AtlasTexture
		if at != null:
			at.atlas = sheet
	_wins_tex = load(WIN_SHEETS[L10n.lang])


## Отладочная выдача денег: пресеты или своё число в меню.
	_update_labels()   ## плашка долга и числа тоже переводятся


func _give_money(v: int) -> void:
	if v <= 0:
		return
	balance += v
	_save()
	_update_labels()
	_banner(L10n.t("give_done") % _fmt(v), Color("#8dffa0"))
	_dbg("отладочная выдача: +%d, баланс=%d" % [v, balance])


func _on_dbg_apply() -> void:
	var s := dbg_input.text.replace(" ", "").replace("\t", "")
	if not s.is_valid_int():
		_banner(L10n.t("enter_num_sum"), Color("#ff7b7b"))
		return
	_give_money(int(s))


## Накопил достаточно — показываем попап расплаты (один раз до согласия).
## Долг текущей ступени: 10 млн, x3 за каждое перерождение.
func debt_target() -> int:
	var t := DEBT
	for i in rebirths:
		t *= 3
	return t


## Множитель любого заработка: x2 за каждое перерождение.
func earn_mult() -> int:
	var m := 1
	for i in rebirths:
		m *= 2
	return m


## Баланс дотянул до долга ступени: долг списывается сразу, попап
## предлагает перерождение.
func _check_debt() -> void:
	if debt_stage >= rebirths:
		return
	var target := debt_target()
	if balance < target or debt_popup.visible:
		return
	balance -= target
	debt_stage = rebirths
	_save()
	_update_labels()
	_banner(L10n.t("debt_paid") % _fmt(target), Color("#8dffa0"))
	Sfx.play(self, "win")
	debt_label.text = L10n.t("debt_text")
	debt_popup.visible = true
	_dbg("баланс дотянул до долга %d: списано, показан попап перерождения" % target)


func _on_debt_rebirth() -> void:
	debt_popup.visible = false
	_do_rebirth()


func _on_debt_later() -> void:
	debt_popup.visible = false
	_update_rebirth_btn()
	_dbg("перерождение отложено: кнопка осталась в интерфейсе")


func _on_rebirth_btn() -> void:
	debt_label.text = L10n.t("debt_text")
	debt_popup.visible = true


func _update_rebirth_btn() -> void:
	rebirth_btn.visible = debt_stage == rebirths


## Перерождение: сброс баланса и улучшений, множитель заработка x2,
## следующий долг x3.
func _do_rebirth() -> void:
	rebirths += 1
	balance = 0
	for i in upg_levels.size():
		upg_levels[i] = 0
	_flag_set("boost2x_until", 0)   ## временный x2 кликов сгорает
	_save()
	_update_rebirth_btn()
	_update_labels()
	_banner(L10n.t("rebirth_done") % [rebirths, earn_mult(), _fmt(debt_target())],
			Color("#ffe9b8"))
	Sfx.play(self, "win")
	_dbg("перерождение #%d: множитель x%d, следующий долг %d"
			% [rebirths, earn_mult(), debt_target()])

func _update_labels() -> void:
	balance_label.text = _fmt(balance)
	if debt_stage < rebirths:
		debt_plaque.text = L10n.t("debt_plaque") % _fmt(debt_target())
	else:
		debt_plaque.text = L10n.t("debt_plaque_paid")  # число рядом с иконкой мешка денег
	bet_label.text = L10n.t("bet_line") % bet_line
	fullbet_label.text = L10n.t("full_bet") % total_bet()
	_check_debt()
	if _fs_left > 0:
		freespin_label.show()
		freespin_label.text = L10n.t("freespins") % _fs_left
	else:
		freespin_label.hide()
	if autospin:
		auto_label.show()
		auto_label.text = L10n.t("auto_banner") % ("∞" if _auto_left < 0 else str(_auto_left))
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
		_banner(L10n.t("bet_cap") % _fmt(balance), Color("#ff7b7b"))
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
		_banner(L10n.t("bet_cap") % _fmt(balance), Color("#ff7b7b"))
	var lines := SlotData.PAYLINES.size()
	var rounded := maxi(lines, int(round(float(capped) / float(lines))) * lines)
	if rounded != t:
		_banner(L10n.t("bet_round") % rounded, Color("#ffe9b8"))
	_set_bet(int(rounded / float(lines)))


func _on_bet_apply() -> void:
	var s := bet_input.text.replace(" ", "").replace("\t", "")
	if not s.is_valid_int():
		_banner(L10n.t("enter_num_bet"), Color("#ff7b7b"))
		return
	_set_bet_total(int(s))


## MAX = олл-ин: вся балансовая сумма, округлённая вниз до кратной
## числу линий (9), чтобы полная ставка не превысила баланс.
@warning_ignore("integer_division")
func _on_max_bet() -> void:
	if _spinning:
		return
	var lines := SlotData.PAYLINES.size()
	var t := balance - balance % lines
	if t < lines:
		_banner(L10n.t("need_money") % lines, Color("#ff7b7b"))
		return
	_set_bet(t / lines)
	_banner(L10n.t("max_bet") % _fmt(total_bet()), Color("#ffe9b8"))


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
		_stop_autospin(L10n.t("auto_stop"))
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
	_banner(L10n.t("speed") % int(SPEEDS[speed_idx]), Color("#ffd794"))


# ------------------------------------------------------------------- сейв

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		balance = maxi(0, int(cfg.get_value("save", "balance", START_BALANCE)))
		var old_idx := clampi(int(cfg.get_value("save", "bet", 0)), 0, BETS.size() - 1)
		bet_line = maxi(1, int(cfg.get_value("save", "bet_line", int(BETS[old_idx]))))
		var arr: Array = cfg.get_value("save", "upg_levels", [])
		upg_levels.clear()
		for k in Upgrades.UPGRADES.size():
			upg_levels.append(int(arr[k]) if k < arr.size() else 0)
		speed_idx = clampi(int(cfg.get_value("save", "speed", 0)), 0, SPEEDS.size() - 1)
		vol_sfx = clampi(int(cfg.get_value("save", "vol_sfx", 80)), 0, 100)
		vol_music = clampi(int(cfg.get_value("save", "vol_music", 80)), 0, 100)
		rebirths = clampi(int(cfg.get_value("save", "rebirths", 0)), 0, 99)
		debt_stage = int(cfg.get_value("save", "debt_stage", -1))
	if debt_stage < 0 and bool(cfg.get_value("save", "debt_paid", false)):
		debt_stage = 0   ## старые сейвы: долг уже был оплачен один раз
		print("[sfx-cfg] слот читает сейв %s: vol_sfx=%d vol_music=%d"
				% [SAVE_PATH, vol_sfx, vol_music])
	if upg_levels.size() != Upgrades.UPGRADES.size():
		upg_levels.clear()
		for k in Upgrades.UPGRADES.size():
			upg_levels.append(0)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # сохраняем чужие ключи (уровни кликера, флаги)
	cfg.set_value("save", "balance", balance)
	cfg.set_value("save", "bet_line", bet_line)
	cfg.set_value("save", "upg_levels", upg_levels)
	cfg.set_value("save", "speed", speed_idx)
	cfg.set_value("save", "vol_sfx", vol_sfx)
	cfg.set_value("save", "vol_music", vol_music)
	cfg.set_value("save", "rebirths", rebirths)
	cfg.set_value("save", "debt_stage", debt_stage)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		print("[sfx-cfg] ОШИБКА записи сейва %s: %d" % [SAVE_PATH, err])


# ------------------------------------------------------------------- спины

func _on_spin_pressed() -> void:
	if _spinning:
		return
	if autospin:  # ПУСК во время автоигры останавливает серию
		_stop_autospin(L10n.t("auto_stop"))
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
			_banner(L10n.t("fs_done"), Color("#7ef3ff"))
			await get_tree().create_timer(0.8).timeout
		if not autospin:
			break
		if _auto_left > 0:
			_auto_left -= 1
			_update_labels()
			if _auto_left == 0:
				_stop_autospin(L10n.t("auto_done"))
				break
		if balance < total_bet():
			_stop_autospin(L10n.t("no_coins"))
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
			_banner(L10n.t("no_coins"), Color("#ff7b7b"))
			_update_labels()
			return
		balance -= total_bet()
		_save()
		_update_labels()
	win_label.text = ""

	var grid := SlotData.make_grid(rng)
	for reel in reels:
		reel.start_spin()
	Sfx.play_spin(self, SPEEDS[speed_idx])
	var sf: float = SPEEDS[speed_idx]
	for c in reels.size():
		var delay: float = (0.85 + c * 0.3 + rng.randf() * 0.15) / sf
		get_tree().create_timer(delay).timeout.connect(
			func() -> void: reels[c].stop_at(grid[c]))
	for reel in reels:
		await reel.stopped
	Sfx.stop_spin()

	var res := SlotData.evaluate(grid, bet_line)
	var won: int = res.total * earn_mult()
	_dbg("спин: выигрыш=%d, линий=%d, скаттер=%d, фриспины=%d" % [
			won, res.line_wins.size(), res.scatter, res.free_spins])
	if won > 0:
		balance += won
		_save()
		Sfx.play(self, "win")
		_show_win_fx(res)
		_count_up(won)
	_update_labels()

	# Всплывающие уведомления: скаттер -> большой выигрыш.
	if res.scatter >= 3:
		await _popup(5, L10n.t("fs_add") % res.free_spins)
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
			await _popup(tier, L10n.t("win_total") % _fmt(won))
	if is_free and res.free_spins > 0:
		await _popup(7, L10n.t("fs_add") % res.free_spins)
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
	at.region = WIN_REGIONS_LANG[L10n.lang][badge_idx]
	win_badge.texture = at
	win_popup_label.text = text
	win_popup.show()
	win_popup.pivot_offset = win_popup.size * 0.5
	win_popup.scale = Vector2(0.5, 0.5) * _pop_scale
	win_popup.modulate = Color(1, 1, 1, 0)
	_popup_tw = create_tween()
	_popup_tw.set_parallel(true)
	_popup_tw.tween_property(win_popup, "scale", Vector2.ONE * _pop_scale, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_popup_tw.tween_property(win_popup, "modulate", Color(1, 1, 1, 1), 0.25)
	_popup_tw.chain().tween_interval(0.45 if SPEEDS[speed_idx] > 1.0 else 1.1)
	_popup_tw.set_parallel(false)
	_popup_tw.chain().tween_property(win_popup, "modulate", Color(1, 1, 1, 0), 0.35)
	_popup_tw.chain().tween_callback(win_popup.hide)
	await _popup_tw.finished


func _cell_center(col: int, row: int) -> Vector2:
	return Vector2(col * (_cell_w + _gap_w) + _cell_w * 0.5, row * (_cell_w + _gap_w) + _cell_w * 0.5)


func _show_win_fx(res: Dictionary) -> void:
	for w in res.line_wins:
		var color: Color = SlotData.LINE_COLORS[int(w.line)]
		var pts: PackedVector2Array = PackedVector2Array()
		for cellv in w.cells:
			pts.append(_cell_center(cellv.x, cellv.y))
			var hl := ColorRect.new()
			hl.size = Vector2(_cell_w, _cell_w)
			hl.position = Vector2(cellv.x * (_cell_w + _gap_w), cellv.y * (_cell_w + _gap_w))
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
		hl.size = Vector2(_cell_w, _cell_w)
		hl.position = Vector2(cellv.x * (_cell_w + _gap_w), cellv.y * (_cell_w + _gap_w))
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
		win_label.text = L10n.t("win_total_low") % _fmt(int(round(v)))
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
