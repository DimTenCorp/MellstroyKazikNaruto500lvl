extends Control
## Сцена кликера «Бабло»: монета даёт монеты за клики, кнопка play —
## награду за рекламу через Playgama Bridge (autoload Bridge, метод
## show_rewarded()): работает на Yandex Games, Poki, CrazyGames и др.
## Баланс общий со слот-машиной (user://slot_save.cfg).
## Весь UI лежит узлами в scenes/clicker.tscn.

const VSIZE := Vector2(1280, 720)
const CLICK_BASE := 5        ## базовый заработок за клик без улучшений

	 ## монет за досмотренную рекламу
const SAVE_PATH := "user://slot_save.cfg"

## Визуальный размер кнопок: в сцене спрайты лежат в родном размере региона
## (TextureButton не даёт Size меньше текстуры), масштаб ставим здесь.
const DEBUG := true  ## отладочные логи в консоль (print)

## Монета кликера нарисована с надписью: БАБЛО / CASH / PARA — второй ряд
## листа img/buttons_clicker.png, регион меняем по языку.
const COIN_REGIONS := {
	"ru": Rect2(20, 323, 278, 287),
	"en": Rect2(366, 325, 289, 287),
	"tr": Rect2(719, 326, 285, 287),
}

const BALANCE_MAX := 9223372036854775807  ## максимум int64: потолок больше невозможно поднять, переполнение исключено
var _balance_v := 1000
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
var upg_levels: Array[int] = []   ## уровни улучшений (индекс = номер в UPGRADES)
var _icons: Array[AtlasTexture] = []
var _auto_acc := 0.0         ## накопитель секунд для авто-заработка
var _cfg := ConfigFile.new()
var _watching := false
var _rebirths := 0      ## перерождения: заработок x2^N
var _debt_stage := -1  ## оплаченная ступень долга
var _rebirth_arm := false
var _boost_until := 0     ## unix-время конца временного x2 кликов
var _row_down := {}          ## старт нажатия в строке улучшения (драг-порог)
var _def_rects := {}
var _def_anchors := {}
var _def_offsets := {}
var _def_fonts := {}

const MANAGED := ["hud_icon", "hud_balance", "coin_btn", "click_hint", "rebirth_btn",
		"ad2x_btn", "debt_popup/debt_panel", "debt_popup/debt_label",
		"debt_popup/debt_btn", "debt_popup/debt_later",
		"auto_stat", "click_stat", "play_btn", "play_caption", "back_btn",
		"msg_label", "upg_scroll"]
## В портрете логическая ширина = 1280 (масштаб по ширине), поэтому
## размеры и шрифты крупнее десктопных примерно в 2.5 раза.
const PORTRAIT_FS := {"hud_balance": 64, "click_hint": 48, "auto_stat": 44,
		"click_stat": 44, "play_caption": 40, "msg_label": 52}
const UPG_INFO_FS := 40        ## шрифт строк улучшений в портрете
const UPG_ICON_MIN := 140.0    ## иконки улучшений в портрете
var _banner_tw: Tween

@onready var machine: Control = $machine
@onready var hud_balance: Label = $machine/hud_balance
@onready var coin_btn: TextureButton = $machine/coin_btn
@onready var rebirth_btn: TextureButton = $machine/rebirth_btn
@onready var ad2x_btn: Button = $machine/ad2x_btn
@onready var debt_popup: Control = $machine/debt_popup
@onready var debt_label: Label = $machine/debt_popup/debt_label
@onready var debt_btn: Button = $machine/debt_popup/debt_btn
@onready var debt_later: Button = $machine/debt_popup/debt_later
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


func _earn_mult() -> int:
	var m := 1
	for i in _rebirths:
		m *= 2
	return m


func _debt_target() -> int:
	var t := 10000000   ## базовый долг слотов, x3 за перерождение
	for i in _rebirths:
		t *= 3
	return t


func _boost_left() -> int:
	return maxi(0, _boost_until - int(Time.get_unix_time_from_system()))


func click_gain() -> int:
	var g := (CLICK_BASE + Upgrades.click_add(upg_levels)) * _earn_mult()
	if _boost_left() > 0:
		g *= 2   ## временное улучшение за рекламу: клики x2
	return g


func auto_gain() -> int:
	return Upgrades.auto_per_sec(upg_levels) * _earn_mult()


func _upg_cost(i: int) -> int:
	return Upgrades.cost(i, upg_levels[i])


## Список показывает все улучшения сверху вниз; прокачанные до упора
## строки помечаются МАКС и их кнопка гаснет.
func _refresh_shop() -> void:
	if upg_btns.is_empty():
		return  # список ещё не построен
	for i in Upgrades.UPGRADES.size():
		var u: Dictionary = Upgrades.UPGRADES[i]
		upg_btns[i].texture_normal = _icons[int(u.icon)]
		upg_btns[i].disabled = upg_levels[i] >= int(u.max)
		if upg_levels[i] >= int(u.max):
			upg_infos[i].text = L10n.t("upg_max") % [
					L10n.t("upg%d" % i), _upg_effect_text(u), upg_levels[i], u.max]
		else:
			upg_infos[i].text = L10n.t("upg_line") % [
					L10n.t("upg%d" % i), _upg_effect_text(u), upg_levels[i], u.max,
					_upg_cost(i)]


## Эффект улучшения с учётом множителя перерождений: цифры в описании
## показывают фактическую прибавку, а не базовую.
func _upg_effect_text(u: Dictionary) -> String:
	var m := _earn_mult()
	var parts: Array[String] = []
	if int(u.click) > 0:
		parts.append(L10n.t("eff_click") % (int(u.click) * m))
	if int(u.auto) > 0:
		parts.append(L10n.t("eff_auto") % (int(u.auto) * m))
	if m > 1:
		parts.append(L10n.t("eff_mult") % m)
	return " ".join(parts)


## Нажатие на строку улучшения: палец/курсор не уехал (порог 40) — покупка;
## уехал (драг) — значит листали список, покупку не считаем.
func _on_row_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_row_down[i] = ev.position
		elif _row_down.has(i):
			var st: Vector2 = _row_down[i]
			_row_down.erase(i)
			if ev.position.distance_to(st) < 40.0:
				_on_upg(i)


func _on_upg(i: int) -> void:
	var u: Dictionary = Upgrades.UPGRADES[i]
	if upg_levels[i] >= int(u.max):
		return
	var c := _upg_cost(i)
	if balance < c:
		_dbg("улучшение %s: не хватает бабла (нужно %d, есть %d)" % [u.name, c, balance])
		_banner(L10n.t("need_money") % c, Color("#ff7b7b"))
		return
	balance -= c
	Sfx.play(self, "buy")
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
	_update_ad2x()
	_check_debt()
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


func _apply_lang() -> void:
	var at := coin_btn.texture_normal as AtlasTexture
	if at != null:
		at.region = COIN_REGIONS[L10n.lang]
	back_btn.text = L10n.t("back")
	play_caption.text = L10n.t("ad_caption") % _ad_reward()
	_refresh_shop()
	_update()


func _dbg(msg: String) -> void:
	if DEBUG:
		print("[clicker] " + msg)


func _ready() -> void:
	_load()
	var vs := float(_cfg.get_value("save", "vol_sfx", 80))
	var vm := float(_cfg.get_value("save", "vol_music", 80))
	if Sfx.has_vols():
		vs = Sfx.cur_sfx
		vm = Sfx.cur_music
	print("[sfx-cfg] кликер старт: vol_sfx=%d vol_music=%d" % [int(vs), int(vm)])
	Sfx.ensure_buses(vs, vm)
	coin_btn.pressed.connect(_on_coin)
	coin_btn.pressed.connect(func() -> void: Sfx.play(self, "win"))
	rebirth_btn.pressed.connect(_on_rebirth_press)
	ad2x_btn.pressed.connect(_on_ad2x)
	debt_btn.pressed.connect(_on_debt_rebirth)
	debt_later.pressed.connect(_on_debt_later)
	debt_btn.pressed.connect(func() -> void: Sfx.play(self, "click"))
	debt_later.pressed.connect(func() -> void: Sfx.play(self, "click"))
	debt_label.text = L10n.t("debt_text")
	debt_btn.text = L10n.t("rebirth_now")
	debt_later.text = L10n.t("rebirth_later")
	ad2x_btn.pressed.connect(func() -> void: Sfx.play(self, "click"))
	_update_ad2x()
	_apply_rebirth_tex()
	_update_rebirth_btn()
	rebirth_btn.ignore_texture_size = true
	rebirth_btn.stretch_mode = TextureButton.STRETCH_SCALE
	rebirth_btn.custom_minimum_size = Vector2.ZERO
	play_btn.pressed.connect(func() -> void: Sfx.play(self, "click"))
	back_btn.pressed.connect(func() -> void: Sfx.play(self, "click"))
	play_btn.pressed.connect(_on_play)
	back_btn.pressed.connect(_on_back)
	var sheet: Texture2D = load("res://img/upgrades/upgrades.png")
	for r in Upgrades.REGIONS:
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = r
		_icons.append(at)
	for i in Upgrades.UPGRADES.size():
		var btn: TextureButton = get_node(
				"machine/upg_scroll/upg_vbox/upg%d_row/upg%d_btn" % [i, i])
		var info: Label = get_node(
				"machine/upg_scroll/upg_vbox/upg%d_row/upg%d_info" % [i, i])
		upg_btns.append(btn)
		upg_infos.append(info)
		# покупку ловит вся строка целиком; PASS пропускает событие дальше
		# в ScrollContainer, поэтому драгом по строке можно листать список
		btn.mouse_filter = Control.MOUSE_FILTER_PASS
		info.mouse_filter = Control.MOUSE_FILTER_PASS
		var row: Control = get_node(
				"machine/upg_scroll/upg_vbox/upg%d_row" % i)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.gui_input.connect(_on_row_input.bind(i))
	# цепочка пропагации драга: строка(PASS) -> vbox(PASS) -> ScrollContainer,
	# иначе контейнер со STOP съест событие и скролл не поедет
	machine.get_node("upg_scroll/upg_vbox").mouse_filter = \
			Control.MOUSE_FILTER_PASS
	_refresh_shop()
	var lg := String(_cfg.get_value("save", "lang", L10n.lang))
	if lg in L10n.LANGS:
		L10n.lang = lg
	_apply_lang()
	_dbg("сцена готова, баланс=%d, язык=%s" % [balance, L10n.lang])
	for btn in _find_buttons(self):
		_bind_press_anim(btn)
	play_caption.text = L10n.t("ad_caption") % _ad_reward()
	_update()
	for p in ["hud_balance", "click_hint", "auto_stat", "click_stat",
			"play_caption", "msg_label", "hud_icon", "float_layer"]:
		machine.get_node(p).mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capture_defaults()
	_layout()
	get_viewport().size_changed.connect(_layout)


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
	for i in Upgrades.UPGRADES.size():
		var l: Label = machine.get_node(
				"upg_scroll/upg_vbox/upg%d_row/upg%d_info" % [i, i])
		_def_fonts["upg%d" % i] = int(l.get_theme_font_size("font_size"))
		var b: TextureButton = machine.get_node(
				"upg_scroll/upg_vbox/upg%d_row/upg%d_btn" % [i, i])
		_def_rects["upgmin%d" % i] = b.custom_minimum_size


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
		if p.begins_with("upgmin"):
			continue
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
		if p.begins_with("upg"):
			var i := int(p.trim_prefix("upg"))
			var li: Label = machine.get_node(
					"upg_scroll/upg_vbox/upg%d_row/upg%d_info" % [i, i])
			li.add_theme_font_size_override("font_size", _def_fonts[p])
		else:
			var lo: Label = machine.get_node(p)
			lo.add_theme_font_size_override("font_size", _def_fonts[p])
	for i in Upgrades.UPGRADES.size():
		var b: TextureButton = machine.get_node(
				"upg_scroll/upg_vbox/upg%d_row/upg%d_btn" % [i, i])
		b.custom_minimum_size = _def_rects["upgmin%d" % i]


## Портрет 9:16: монета по центру, реклама/выход по бокам, улучшения внизу
## во всю ширину; размеры через u = ширина/1280 (независимо от масштаба).
	ad2x_btn.remove_theme_font_size_override("font_size")
	debt_label.remove_theme_font_size_override("font_size")
	debt_btn.remove_theme_font_size_override("font_size")
	debt_later.remove_theme_font_size_override("font_size")


func _layout_portrait(W: float, H: float) -> void:
	var u := W / 1280.0
	var m := 24.0 * u
	_set_r("hud_icon", m, m, 150 * u, 138 * u)
	_set_r("hud_balance", m + 160 * u, m + 10 * u, W - 184 * u - m, 90 * u)
	_set_r("coin_btn", (W - 700 * u) * 0.5, 300 * u, 700 * u, 722 * u)
	_set_r("click_hint", (W - 700 * u) * 0.5, 1030 * u, 700 * u, 64 * u)
	_set_r("auto_stat", m, 1100 * u, (W - 2 * m) * 0.5, 60 * u)
	_set_r("click_stat", m + (W - 2 * m) * 0.5, 1100 * u,
			(W - 2 * m) * 0.5, 60 * u)
	_set_r("play_btn", m, 480 * u, 230 * u, 225 * u)
	_set_r("play_caption", m, 712 * u, 320 * u, 56 * u)
	_set_r("back_btn", W - 380 * u, 480 * u, 356 * u, 130 * u)
	_set_r("rebirth_btn", m, 780 * u, 190 * u, 218 * u)
	_set_r("ad2x_btn", W - 250 * u, 630 * u, 226 * u, 90 * u)
	_set_r("debt_popup/debt_panel", 40 * u, 450 * u, W - 80 * u, 850 * u)
	_set_r("debt_popup/debt_label", 70 * u, 520 * u, W - 140 * u, 480 * u)
	var w2 := (W - 140 * u - 20 * u) / 2.0
	_set_r("debt_popup/debt_btn", 70 * u, 1030 * u, w2, 120 * u)
	_set_r("debt_popup/debt_later", 70 * u + w2 + 20 * u, 1030 * u, w2, 120 * u)
	debt_label.add_theme_font_size_override("font_size", int(34 * u))
	debt_btn.add_theme_font_size_override("font_size", int(30 * u))
	debt_later.add_theme_font_size_override("font_size", int(30 * u))
	ad2x_btn.add_theme_font_size_override("font_size", int(30 * u))
	var sh := 1016.0 * u
	_set_r("msg_label", 0, H - sh - 90 * u, W, 80 * u)
	_set_r("upg_scroll", 0, H - sh, W, sh)
	for p in PORTRAIT_FS:
		var l: Label = machine.get_node(p)
		l.add_theme_font_size_override("font_size",
				int(PORTRAIT_FS[p] * u))
	for i in Upgrades.UPGRADES.size():
		var l: Label = machine.get_node(
				"upg_scroll/upg_vbox/upg%d_row/upg%d_info" % [i, i])
		l.add_theme_font_size_override("font_size", int(UPG_INFO_FS * u))
		var b: TextureButton = machine.get_node(
				"upg_scroll/upg_vbox/upg%d_row/upg%d_btn" % [i, i])
		b.custom_minimum_size = Vector2(UPG_ICON_MIN * u, UPG_ICON_MIN * u)


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
	if vs.x < vs.y:  # портрет (9:16): своя раскладка
		machine.scale = Vector2.ONE
		machine.position = off
		_dbg("портрет: логический вьюпорт %s" % vs)
		_layout_portrait(vs.x, vs.y)
		return
	_restore_defaults()
	var s := minf(vs.x / VSIZE.x, vs.y / VSIZE.y)
	machine.scale = Vector2(s, s)
	machine.position = off + (vs - VSIZE * s) * 0.5
	# страховка: монета и подсказка всегда целиком в кадре, даже если
	# в редакторе их утащат за экран
	var cp := coin_btn.position
	cp.x = clampf(cp.x, 0.0, VSIZE.x - coin_btn.size.x)
	cp.y = clampf(cp.y, 0.0, VSIZE.y - coin_btn.size.y)
	coin_btn.position = cp
	var hp := click_hint.position
	hp.x = clampf(hp.x, 0.0, VSIZE.x - click_hint.size.x)
	hp.y = clampf(hp.y, 0.0, VSIZE.y - click_hint.size.y)
	click_hint.position = hp


# ------------------------------------------------------------------- баланс

func _load() -> void:
	if _cfg.load(SAVE_PATH) == OK:
		balance = maxi(0, int(_cfg.get_value("save", "balance", balance)))
		_rebirths = clampi(int(_cfg.get_value("save", "rebirths", 0)), 0, 99)
		_boost_until = int(_cfg.get_value("save", "boost2x_until", 0))
		_debt_stage = int(_cfg.get_value("save", "debt_stage", -1))
		var arr: Array = _cfg.get_value("save", "upg_levels", [])
		upg_levels.clear()
		for k in Upgrades.UPGRADES.size():
			upg_levels.append(int(arr[k]) if k < arr.size() else 0)
	if upg_levels.size() != Upgrades.UPGRADES.size():
		upg_levels.clear()
		for k in Upgrades.UPGRADES.size():
			upg_levels.append(0)
	if _debt_stage < 0 and bool(_cfg.get_value("save", "debt_paid", false)):
		_debt_stage = 0


## Пишем баланс в общий сейв, остальные ключи (ставка, скорость,
## громкости) сохраняем как есть.
func _save() -> void:
	_cfg.set_value("save", "balance", balance)
	_cfg.set_value("save", "upg_levels", upg_levels)
	_cfg.set_value("save", "rebirths", _rebirths)
	_cfg.set_value("save", "boost2x_until", _boost_until)
	_cfg.set_value("save", "debt_stage", _debt_stage)
	_cfg.save(SAVE_PATH)


## Награда за рекламу: бабло за клик (с множителем перерождений) × 2.
func _ad_reward() -> int:
	return click_gain() * 2


const REBIRTH_REGIONS := {
	"ru": Rect2(0, 0, 558, 640),
	"en": Rect2(558, 0, 558, 640),
	"tr": Rect2(1116, 0, 558, 640),
}


## Спрайт кнопки перерождения: лист из трёх карточек RU/EN/TR.
func _apply_rebirth_tex() -> void:
	var at := AtlasTexture.new()
	at.atlas = load("res://img/buttons/rebirth.png")
	at.region = REBIRTH_REGIONS[L10n.lang]
	rebirth_btn.texture_normal = at


func _update_rebirth_btn() -> void:
	rebirth_btn.visible = _debt_stage == _rebirths


## Долг ступени дотянут: списание сразу + попап перерождения (как в слотах).
func _check_debt() -> void:
	if _debt_stage >= _rebirths:
		return
	var target := _debt_target()
	if balance < target or debt_popup.visible:
		return
	balance -= target
	_debt_stage = _rebirths
	_save()
	_update()
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


## Перерождение: сброс баланса, улучшений и буста x2; заработок x2, долг x3.
func _do_rebirth() -> void:
	_rebirth_arm = false
	_rebirths += 1
	balance = 0
	for i in upg_levels.size():
		upg_levels[i] = 0
	_boost_until = 0   ## временный x2 кликов сгорает при перерождении
	_save()
	debt_popup.visible = false
	_refresh_shop()
	_update()
	_update_rebirth_btn()
	_update_ad2x()
	rebirth_btn.modulate = Color(1, 1, 1)
	_banner(L10n.t("rebirth_done") % [_rebirths, _earn_mult(), _fmt(_debt_target())],
			Color("#ffe9b8"))
	Sfx.play(self, "win")


## Кнопка перерождения в кликере: первое нажатие взводит подтверждение
## на 3 с, второе — перерождает.
func _on_rebirth_press() -> void:
	if not _rebirth_arm:
		_rebirth_arm = true
		rebirth_btn.modulate = Color(1.0, 0.55, 0.55)
		_banner(L10n.t("rebirth_sure"), Color("#ffe9b8"))
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if _rebirth_arm:
				_rebirth_arm = false
				rebirth_btn.modulate = Color(1, 1, 1))
		return
	_do_rebirth()


## Кнопка временного x2: текст с остатком секунд, пока буст жив.
func _update_ad2x() -> void:
	var left := _boost_left()
	if left > 0:
		ad2x_btn.disabled = true
		ad2x_btn.text = L10n.t("ad2x_on") % left
	elif ad2x_btn.disabled or ad2x_btn.text != L10n.t("ad2x_btn"):
		ad2x_btn.disabled = _watching
		ad2x_btn.text = L10n.t("ad2x_btn")


## Временное улучшение за рекламу: rewarded-ролик -> 30 секунд x2 клики.
func _on_ad2x() -> void:
	if _watching or _boost_left() > 0:
		return
	_watching = true
	ad2x_btn.disabled = true
	_dbg("запуск рекламы за временный x2 кликов")
	var rewarded := await _watch_rewarded_ad()
	_watching = false
	_dbg("реклама за x2 завершена, rewarded=%s" % rewarded)
	if rewarded:
		_boost_until = int(Time.get_unix_time_from_system()) + 30
		_save()
		_banner(L10n.t("ad2x_started"), Color("#8dffa0"))
		Sfx.play(self, "win")
	else:
		_banner(L10n.t("ad_skip"), Color("#ff7b7b"))
	_update_ad2x()
	_update()


func _update() -> void:
	hud_balance.text = _fmt(balance)
	if balance >= BALANCE_MAX and not _cap_notified:
		_cap_notified = true
		_banner(L10n.t("balance_cap") % _fmt(BALANCE_MAX), Color("#ffd794"))
		Sfx.play(self, "win")
	elif balance < BALANCE_MAX:
		_cap_notified = false
	click_hint.text = L10n.t("per_click") % click_gain()
	click_stat.text = L10n.t("stat_click") % click_gain()
	auto_stat.text = L10n.t("stat_auto") % auto_gain()


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
		var reward := _ad_reward()
		balance += reward
		Sfx.play(self, "win")
		_dbg("награда начислена: +%d, баланс=%d" % [reward, balance])
		_save()
		_update()
		_banner(L10n.t("ad_win") % reward, Color("#8dffa0"))
		_float("+%d" % reward,
				play_btn.position + play_btn.size * 0.5, Color("#8dffa0"))
	else:
		_banner(L10n.t("ad_skip"), Color("#ff7b7b"))
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
		_banner(L10n.t("bridge_off"), Color("#ff7b7b"))
		return false
	_dbg("платформа: %s, rewarded supported=%s" % [
			_platform_name(br), br.advertisement.is_rewarded_supported])
	if not bool(br.advertisement.is_rewarded_supported):
		_banner(L10n.t("ad_unsup") % _platform_name(br),
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
	_banner(L10n.t("ad_watch") % _platform_name(br), Color("#ffd794"))
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
		_banner(L10n.t("ad_timeout"), Color("#ff7b7b"))
		return false
	if st["failed"]:
		_dbg("ОШИБКА: реклама завершилась с FAILED")
		_banner(L10n.t("ad_fail"), Color("#ff7b7b"))
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
