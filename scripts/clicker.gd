extends Control
## Сцена кликера «Бабло»: монета даёт монеты за клики, кнопка play —
## награду за рекламу через Playgama Bridge (autoload Bridge, метод
## show_rewarded()): работает на Yandex Games, Poki, CrazyGames и др.
## Баланс общий со слот-машиной (user://slot_save.cfg).
## Весь UI лежит узлами в scenes/clicker.tscn.

const VSIZE := Vector2(1280, 720)
const CLICK_VALUE := 5     ## монет за клик по монете
const AD_REWARD := 500     ## монет за досмотренную рекламу
const SAVE_PATH := "user://slot_save.cfg"

## Визуальный размер кнопок: в сцене спрайты лежат в родном размере региона
## (TextureButton не даёт Size меньше текстуры), масштаб ставим здесь.
const VISUAL := {
	"coin_btn": Vector2(320, 330),
	"play_btn": Vector2(200, 197),
}

const DEBUG := true  ## отладочные логи в консоль (print)

var balance := 1000
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
@onready var float_layer: Control = $machine/float_layer


func _dbg(msg: String) -> void:
	if DEBUG:
		print("[clicker] " + msg)


func _ready() -> void:
	_load()
	_dbg("сцена готова, баланс=%d" % balance)
	for key in VISUAL:
		var btn: TextureButton = get_node("machine/" + key)
		btn.pivot_offset = Vector2.ZERO
		btn.scale = VISUAL[key] / btn.size
	coin_btn.pressed.connect(_on_coin)
	play_btn.pressed.connect(_on_play)
	back_btn.pressed.connect(_on_back)
	for btn in _find_buttons(self):
		_bind_press_anim(btn)
	click_hint.text = "+%d за клик" % CLICK_VALUE
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


## Пишем баланс в общий сейв, остальные ключи (ставка, скорость,
## громкости) сохраняем как есть.
func _save() -> void:
	_cfg.set_value("save", "balance", balance)
	_cfg.save(SAVE_PATH)


func _update() -> void:
	hud_balance.text = _fmt(balance)


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
	balance += CLICK_VALUE
	_dbg("клик по монете: +%d, баланс=%d" % [CLICK_VALUE, balance])
	_save()
	_update()
	_float("+%d" % CLICK_VALUE, coin_btn.position + VISUAL["coin_btn"] * 0.5,
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
				play_btn.position + VISUAL["play_btn"] * 0.5, Color("#8dffa0"))
	else:
		_banner("РЕКЛАМА НЕ ДОСМОТРЕНА — НЕТ НАГРАДЫ", Color("#ff7b7b"))
	_watching = false
	play_btn.disabled = false


## Показ рекламы с наградой через Playgama Bridge (autoload Bridge):
## сигнал rewarded_state_changed даёт REWARDED (награда) и CLOSED/FAILED
## (конец показа). В редакторе аддон крутит мок-состояния — награда приходит
## сразу, в вебе рекламу показывает SDK площадки (Yandex, Poki, CrazyGames…).
func _watch_rewarded_ad() -> bool:
	var br := get_node_or_null("/root/Bridge")
	if br == null or br.advertisement == null:
		_dbg("ОШИБКА: autoload Bridge не найден")
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
