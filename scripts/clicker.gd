extends Control
## Сцена кликера «Бабло»: монета даёт монеты за клики, кнопка play —
## награду за рекламу через Playgama Bridge (autoload Bridge, метод
## show_rewarded()): работает на Yandex Games, Poki, CrazyGames и др.
## Баланс общий со слот-машиной (user://slot_save.cfg).
## Весь UI лежит узлами в scenes/clicker.tscn.

const VSIZE := Vector2(1280, 720)
const AD_REWARD := 500
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
	return CLICK_BASE + Upgrades.click_add(upg_levels)


func auto_gain() -> int:
	return Upgrades.auto_per_sec(upg_levels)


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


func _upg_effect_text(u: Dictionary) -> String:
	var parts: Array[String] = []
	if int(u.click) > 0:
		parts.append(L10n.t("eff_click") % u.click)
	if int(u.auto) > 0:
		parts.append(L10n.t("eff_auto") % u.auto)
	return " ".join(parts)


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


func _apply_lang() -> void:
	var at := coin_btn.texture_normal as AtlasTexture
	if at != null:
		at.region = COIN_REGIONS[L10n.lang]
	back_btn.text = L10n.t("back")
	play_caption.text = L10n.t("ad_caption") % AD_REWARD
	_refresh_shop()
	_update()


func _dbg(msg: String) -> void:
	if DEBUG:
		print("[clicker] " + msg)


func _ready() -> void:
	_load()
	coin_btn.pressed.connect(_on_coin)
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
		btn.pressed.connect(_on_upg.bind(i))
	_refresh_shop()
	var lg := String(_cfg.get_value("save", "lang", L10n.lang))
	if lg in L10n.LANGS:
		L10n.lang = lg
	_apply_lang()
	_dbg("сцена готова, баланс=%d, язык=%s" % [balance, L10n.lang])
	for btn in _find_buttons(self):
		_bind_press_anim(btn)
	play_caption.text = L10n.t("ad_caption") % AD_REWARD
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
		for k in Upgrades.UPGRADES.size():
			upg_levels.append(int(arr[k]) if k < arr.size() else 0)
	if upg_levels.size() != Upgrades.UPGRADES.size():
		upg_levels.clear()
		for k in Upgrades.UPGRADES.size():
			upg_levels.append(0)


## Пишем баланс в общий сейв, остальные ключи (ставка, скорость,
## громкости) сохраняем как есть.
func _save() -> void:
	_cfg.set_value("save", "balance", balance)
	_cfg.set_value("save", "upg_levels", upg_levels)
	_cfg.save(SAVE_PATH)


func _update() -> void:
	hud_balance.text = _fmt(balance)
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
		balance += AD_REWARD
		_dbg("награда начислена: +%d, баланс=%d" % [AD_REWARD, balance])
		_save()
		_update()
		_banner(L10n.t("ad_win") % _fmt(AD_REWARD), Color("#8dffa0"))
		_float("+%d" % AD_REWARD,
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
