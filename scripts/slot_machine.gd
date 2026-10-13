extends Control
## Главная сцена: слот-машина 3x5 (3 строки, 5 барабанов) для Яндекс.Игр.
## Правила: 9 линий выплат слева направо, WILD-замена, скаттер BONUS даёт
## выплату и фриспины. Баланс хранится в user://, игра без реальных денег.
##
## ВЕСЬ UI лежит узлами в scenes/game.tscn (редактируется в редакторе).
## Скрипт содержит только логику и ссылки на узлы. Динамические узлы
## (подсветка линий, линии выплат) создаются в fx_layer / lines_overlay.

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

var rng := RandomNumberGenerator.new()
var textures: Array[Texture2D] = []
var reels: Array[SlotReel] = []

var balance := START_BALANCE
var bet_idx := 0
var _fs_left := 0
var _spinning := false

var _fx_nodes: Array[Node] = []
var _win_tween: Tween
var _banner_tw: Tween

@onready var machine: Control = $machine
@onready var balance_label: Label = $machine/top_bar/balance_label
@onready var win_label: Label = $machine/top_bar/win_label
@onready var fs_label: Label = $machine/top_bar/fs_label
@onready var bet_label: Label = $machine/bottom_bar/bet_label
@onready var total_label: Label = $machine/bottom_bar/total_label
@onready var msg_label: Label = $machine/grid_panel/msg_label
@onready var spin_btn: Button = $machine/bottom_bar/spin_btn
@onready var bet_minus: Button = $machine/bottom_bar/bet_minus
@onready var bet_plus: Button = $machine/bottom_bar/bet_plus
@onready var bonus_btn: Button = $machine/bottom_bar/bonus_btn
@onready var paytable_btn: Button = $machine/bottom_bar/paytable_btn
@onready var fx_layer: Control = $machine/grid_panel/fx_layer
@onready var lines_overlay: Node2D = $machine/grid_panel/lines_overlay
@onready var paytable_popup: Control = $machine/paytable_popup
@onready var popup_dim: ColorRect = $machine/paytable_popup/dim
@onready var close_btn: Button = %close_btn


func _ready() -> void:
	rng.randomize()
	textures.resize(SlotData.SYMBOL_COUNT)
	for sym in SlotData.SYMBOL_COUNT:
		textures[sym] = load(SlotData.TEXTURES[sym])

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
	bet_minus.pressed.connect(func() -> void: _change_bet(-1))
	bet_plus.pressed.connect(func() -> void: _change_bet(1))
	bonus_btn.pressed.connect(_on_bonus_pressed)
	paytable_btn.pressed.connect(func() -> void: paytable_popup.show())
	close_btn.pressed.connect(func() -> void: paytable_popup.hide())
	popup_dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			paytable_popup.hide()
	)

	_load_save()
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
	var vbox: VBoxContainer = %vbox
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
	bet_minus.disabled = _spinning or bet_idx <= 0
	bet_plus.disabled = _spinning or bet_idx >= BETS.size() - 1
	if _fs_left > 0:
		fs_label.show()
		fs_label.text = "ФРИСПИНЫ: %d" % _fs_left
	else:
		fs_label.hide()


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


# ------------------------------------------------------------------- сейв

func _load_save() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		balance = int(cfg.get_value("save", "balance", START_BALANCE))
		bet_idx = clampi(int(cfg.get_value("save", "bet", 0)), 0, BETS.size() - 1)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("save", "balance", balance)
	cfg.set_value("save", "bet", bet_idx)
	cfg.save(SAVE_PATH)


# ------------------------------------------------------------------- спины

func _on_spin_pressed() -> void:
	if _spinning or _fs_left > 0:
		return
	if balance < total_bet():
		_banner("НЕДОСТАТОЧНО МОНЕТ!", Color("#ff7b7b"))
		_update_labels()
		return
	_spinning = true
	win_label.text = ""
	balance -= total_bet()
	_save()
	_update_labels()
	spin_btn.disabled = true
	_yk_call("gameplay_start")

	await _spin(false)
	if _fs_left > 0:
		await get_tree().create_timer(1.5).timeout
		while _fs_left > 0:
			_fs_left -= 1
			_update_labels()
			await _spin(true)
			if _fs_left > 0:
				await get_tree().create_timer(0.7).timeout
		_banner("ФРИСПИНЫ ЗАВЕРШЕНЫ", Color("#7ef3ff"))
		await get_tree().create_timer(1.2).timeout
	_spinning = false
	spin_btn.disabled = false
	_update_labels()
	_yk_call("gameplay_stop")


## Один оборот барабанов с оценкой результата. is_free = фриспин.
func _spin(is_free: bool) -> void:
	_clear_fx()
	var grid := SlotData.make_grid(rng)
	for reel in reels:
		reel.start_spin()
	for c in reels.size():
		var delay := 0.85 + c * 0.3 + rng.randf() * 0.15
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
	if res.free_spins > 0:
		if is_free:
			_fs_left += res.free_spins
			_banner("РЕТРИГГЕР! +%d ФРИСПИНОВ" % res.free_spins, Color("#7ef3ff"))
		else:
			_fs_left = res.free_spins
			_banner("СУНДУКИ! %d ФРИСПИНОВ" % res.free_spins, Color("#7ef3ff"))
	_update_labels()


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
