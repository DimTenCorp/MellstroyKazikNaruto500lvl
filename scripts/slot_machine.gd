extends Control
## Главная сцена: слот-машина 3x5 (3 строки, 5 барабанов) для Яндекс.Игр.
## Правила: 9 линий выплат слева направо, WILD-замена, скаттер BONUS даёт
## выплату и фриспины. Баланс хранится в user://, игра без реальных денег.
##
## ВЕСЬ UI лежит узлами в scenes/game.tscn (редактируется в редакторе):
## фон back1, кнопки вырезаны атласами из img/buttons_spr (RU), бейджи
## больших выигрышей — из img/wins_spr (RU). Динамика (подсветка линий,
## попап выигрыша) создаётся/управляется кодом.

const VSIZE := Vector2(1000, 700)  ## виртуальный размер макета машины
const CELL := 146.0                ## размер ячейки символа
const GAP := 10.0                  ## зазор между ячейками
const BETS := [1, 2, 5, 10, 25, 50]
const START_BALANCE := 1000
const BONUS_TOPUP := 1000
const SAVE_PATH := "user://slot_save.cfg"

# Порядок символов в таблице выплат (id из SlotData.Symbol) и их ключи в сцене.
const PAY_ORDER: Array[int] = [12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 13]
const SYMBOL_KEYS: Array[String] = [
	"cherry", "lemon", "orange", "plum", "watermelon", "star", "horseshoe",
	"moneysack", "bell", "1bar", "2bar", "3bar", "777", "wild", "chestbonus",
]

## Бейджи img/wins_spr/wins_spritessheet.png (RU):
## 0 ВЫИГРЫШ, 1 БОЛЬШОЙ, 2 МЕГА, 3 ЭПИЧЕСКИЙ, 4 СУПЕР, 5 БОНУС,
## 6 ДЖЕКПОТ, 7 ФРИСПИН, 8 ВЫИГРЫШ В БОНУСНОЙ ИГРЕ.
const WIN_REGIONS: Array[Rect2] = [
	Rect2(9, 23, 394, 212),
	Rect2(462, 8, 393, 218),
	Rect2(929, 11, 373, 224),
	Rect2(24, 235, 365, 224),
	Rect2(466, 266, 386, 191),
	Rect2(949, 235, 331, 186),
	Rect2(6, 483, 401, 238),
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

var rng := RandomNumberGenerator.new()
var textures: Array[Texture2D] = []
var reels: Array[SlotReel] = []

var balance := START_BALANCE
var bet_idx := 0
var _fs_left := 0
var _spinning := false
var autospin := false
var fast := false
var muted := false

var _fx_nodes: Array[Node] = []
var _win_tween: Tween
var _banner_tw: Tween
var _popup_tw: Tween
var _wins_tex: Texture2D

@onready var machine: Control = $machine
@onready var balance_label: Label = $machine/top_bar/balance_label
@onready var win_label: Label = $machine/top_bar/win_label
@onready var fs_label: Label = $machine/top_bar/fs_label
@onready var bet_label: Label = $machine/bottom_bar/bet_label
@onready var total_label: Label = $machine/bottom_bar/total_label
@onready var msg_label: Label = $machine/grid_panel/msg_label
@onready var spin_btn: TextureButton = $machine/bottom_bar/spin_btn
@onready var bet_btn: TextureButton = $machine/bottom_bar/bet_btn
@onready var denom_btn: TextureButton = $machine/bottom_bar/denom_btn
@onready var max_btn: TextureButton = $machine/bottom_bar/max_btn
@onready var auto_btn: TextureButton = $machine/bottom_bar/auto_btn
@onready var speed_btn: TextureButton = $machine/bottom_bar/speed_btn
@onready var sound_btn: TextureButton = $machine/bottom_bar/sound_btn
@onready var paytable_btn: TextureButton = $machine/bottom_bar/paytable_btn
@onready var collect_btn: TextureButton = $machine/collect_btn
@onready var bonus_btn: Button = $machine/bottom_bar/bonus_btn
@onready var fx_layer: Control = $machine/grid_panel/fx_layer
@onready var lines_overlay: Node2D = $machine/grid_panel/lines_overlay
@onready var win_popup: Control = $machine/win_popup
@onready var win_badge: TextureRect = $machine/win_popup/win_badge
@onready var win_popup_label: Label = $machine/win_popup/win_popup_label
@onready var paytable_popup: Control = $machine/paytable_popup
@onready var popup_dim: ColorRect = $machine/paytable_popup/dim
@onready var close_btn: Button = $machine/paytable_popup/popup_panel/scroll/vbox/head/close_btn


func _ready() -> void:
	rng.randomize()
	textures.resize(SlotData.SYMBOL_COUNT)
	for sym in SlotData.SYMBOL_COUNT:
		textures[sym] = load(SlotData.TEXTURES[sym])
	_wins_tex = load("res://img/wins_spr/wins_spritessheet.png")

	for c in SlotData.COLS:
		var reel: SlotReel = get_node("machine/grid_panel/Reel%d" % c)
		reel.configure(textures, rng)
		reel.set_symbols([
			SlotData.random_symbol(rng),
			SlotData.random_symbol(rng),
			SlotData.random_symbol(rng),
		])
		reels.append(reel)

	spin_btn.pressed.connect(_on_spin_pressed)
	bet_btn.pressed.connect(func() -> void: _change_bet(1))
	denom_btn.pressed.connect(func() -> void: _change_bet(-1))
	max_btn.pressed.connect(func() -> void:
		if not _spinning:
			bet_idx = BETS.size() - 1
			_update_labels()
	)
	auto_btn.pressed.connect(_on_auto_pressed)
	speed_btn.pressed.connect(_on_speed_pressed)
	sound_btn.pressed.connect(_on_sound_pressed)
	collect_btn.pressed.connect(_on_collect_pressed)
	bonus_btn.pressed.connect(_on_bonus_pressed)
	paytable_btn.pressed.connect(func() -> void: paytable_popup.show())
	close_btn.pressed.connect(func() -> void: paytable_popup.hide())
	popup_dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			paytable_popup.hide()
	)

	_load_save()
	_apply_toggles()
	_refresh_paytable()
	_update_labels()
	_layout()
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var vs := get_viewport_rect().size
	if vs.x <= 0 or vs.y <= 0:
		return
	var s := minf(vs.x / VSIZE.x, vs.y / VSIZE.y)
	machine.scale = Vector2(s, s)
	machine.position = (vs - VSIZE * s) * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if paytable_popup != null and paytable_popup.visible \
			and event.is_action_pressed("ui_cancel"):
		paytable_popup.hide()
		get_viewport().set_input_as_handled()


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


# ------------------------------------------------------------------- хелперы UI

func _update_labels() -> void:
	balance_label.text = "Баланс: %s" % _fmt(balance)
	bet_label.text = "Ставка/линия: %d" % BETS[bet_idx]
	total_label.text = "Всего: %s" % _fmt(total_bet())
	bonus_btn.visible = not _spinning and balance < total_bet()
	if _fs_left > 0:
		fs_label.show()
		fs_label.text = "ФРИСПИНЫ: %d" % _fs_left
	else:
		fs_label.hide()


func _apply_toggles() -> void:
	auto_btn.modulate = Color(1.35, 1.35, 1.35) if autospin else Color(1, 1, 1)
	speed_btn.modulate = Color(1.35, 1.35, 1.35) if fast else Color(1, 1, 1)
	sound_btn.modulate = Color(0.45, 0.45, 0.45) if muted else Color(1, 1, 1)
	for r in reels:
		r.speed_scale = 2.0 if fast else 1.0


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
	return int(BETS[bet_idx]) * SlotData.PAYLINES.size()


func _change_bet(d: int) -> void:
	if _spinning:
		return
	bet_idx = clampi(bet_idx + d, 0, BETS.size() - 1)
	_update_labels()


func _on_bonus_pressed() -> void:
	if _spinning:
		return
	balance += BONUS_TOPUP
	_save()
	_update_labels()
	_banner("БОНУС +%s МОНЕТ" % _fmt(BONUS_TOPUP), Color("#8dffa0"))


func _on_auto_pressed() -> void:
	if autospin:
		autospin = false
		_apply_toggles()
		return
	autospin = true
	_apply_toggles()
	if not _spinning:
		_run_session()


func _on_speed_pressed() -> void:
	fast = not fast
	_save()
	_apply_toggles()


func _on_sound_pressed() -> void:
	muted = not muted
	_save()
	_apply_toggles()
	# Звуков пока нет: флаг пригодится, когда появятся (AudioStreamPlayer).


func _on_collect_pressed() -> void:
	if autospin:
		autospin = false
		_apply_toggles()
	if not _spinning:
		_banner("ЗАБРАНО: %s" % _fmt(balance), Color("#8dffa0"))


# ------------------------------------------------------------------- сейв

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		balance = int(cfg.get_value("save", "balance", START_BALANCE))
		bet_idx = clampi(int(cfg.get_value("save", "bet", 0)), 0, BETS.size() - 1)
		fast = bool(cfg.get_value("save", "fast", false))
		muted = bool(cfg.get_value("save", "muted", false))


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("save", "balance", balance)
	cfg.set_value("save", "bet", bet_idx)
	cfg.set_value("save", "fast", fast)
	cfg.set_value("save", "muted", muted)
	cfg.save(SAVE_PATH)


# ------------------------------------------------------------------- спины

func _on_spin_pressed() -> void:
	if _spinning:
		return
	if autospin:  # повторное нажатие ПУСК останавливает автоигру
		autospin = false
		_apply_toggles()
		return
	_run_session()


## Серия спинов: один обычный спин + цепочка фриспинов; в режиме автоигры
## повторяется, пока хватает баланса или игрок не выключил автоигру.
func _run_session() -> void:
	if _spinning:
		return
	_spinning = true
	_update_labels()
	_yk_call("gameplay_start")
	while true:
		await _spin(false)
		if _fs_left > 0:
			await get_tree().create_timer(1.2).timeout
			while _fs_left > 0:
				_fs_left -= 1
				_update_labels()
				await _spin(true)
				if _fs_left > 0:
					await get_tree().create_timer(0.5 if fast else 0.9).timeout
			_banner("ФРИСПИНЫ ЗАВЕРШЕНЫ", Color("#7ef3ff"))
			await get_tree().create_timer(0.8).timeout
		if not autospin:
			break
		if balance < total_bet():
			autospin = false
			_apply_toggles()
			_banner("НЕДОСТАТОЧНО МОНЕТ!", Color("#ff7b7b"))
			break
		await get_tree().create_timer(0.3 if fast else 0.6).timeout
	_spinning = false
	_update_labels()
	_yk_call("gameplay_stop")


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
	var sf := 2.0 if fast else 1.0
	for c in reels.size():
		var delay := (0.85 + c * 0.3 + rng.randf() * 0.15) / sf
		get_tree().create_timer(delay).timeout.connect(
			func() -> void: reels[c].stop_at(grid[c]))
	for reel in reels:
		await reel.stopped

	var res := SlotData.evaluate(grid, int(BETS[bet_idx]))
	var won: int = res.total
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
	_popup_tw.chain().tween_interval(0.45 if fast else 1.1)
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


# ------------------------------------------------------------------- Yandex SDK

func _yk_call(method: String) -> void:
	var yk := get_node_or_null("/root/YandexGames")
	if yk != null and yk.has_method(method):
		yk.call(method)
