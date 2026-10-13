extends Control
## Главная сцена: слот-машина 3x5 (3 строки, 5 барабанов) для Яндекс.Игр.
## Правила: 9 линий выплат слева направо, WILD-замена, скаттер BONUS даёт
## выплату и фриспины. Баланс хранится в user://, игра без реальных денег.

const VSIZE := Vector2(1000, 700)  ## виртуальный размер макета машины
const CELL := 146.0                ## размер ячейки символа
const GAP := 10.0                  ## зазор между ячейками
const GRID_PAD := 14.0             ## отступ внутри рамки барабанов
const BETS := [1, 2, 5, 10, 25, 50]
const START_BALANCE := 1000
const BONUS_TOPUP := 1000
const SAVE_PATH := "user://slot_save.cfg"

# Порядок символов в таблице выплат (id из SlotData.Symbol), от дорогих к дешёвым.
const PAY_ORDER: Array[int] = [12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 13]

var rng := RandomNumberGenerator.new()
var textures: Array[Texture2D] = []
var reels: Array[SlotReel] = []

var balance := START_BALANCE
var bet_idx := 0
var _fs_left := 0
var _spinning := false

var machine: Control
var bg: ColorRect
var balance_label: Label
var win_label: Label
var fs_label: Label
var bet_label: Label
var total_label: Label
var msg_label: Label
var spin_btn: Button
var bet_minus: Button
var bet_plus: Button
var bonus_btn: Button
var paytable_btn: Button
var grid_panel: Panel
var fx_layer: Control
var lines_overlay: Node2D
var paytable_popup: Control
var _fx_nodes: Array[Node] = []
var _win_tween: Tween
var _banner_tw: Tween


func _ready() -> void:
	rng.randomize()
	textures.resize(SlotData.SYMBOL_COUNT)
	for sym in SlotData.SYMBOL_COUNT:
		textures[sym] = load(SlotData.TEXTURES[sym])
	_build_ui()
	_load_save()
	_update_labels()
	_layout()
	get_viewport().size_changed.connect(_layout)


func _unhandled_input(event: InputEvent) -> void:
	if paytable_popup != null and paytable_popup.visible \
			and event.is_action_pressed("ui_cancel"):
		paytable_popup.hide()
		get_viewport().set_input_as_handled()


func _layout() -> void:
	var vs := get_viewport_rect().size
	if vs.x <= 0 or vs.y <= 0:
		return
	var s := minf(vs.x / VSIZE.x, vs.y / VSIZE.y)
	machine.scale = Vector2(s, s)
	machine.position = (vs - VSIZE * s) * 0.5


# ---------------------------------------------------------------- построение UI

func _build_ui() -> void:
	bg = ColorRect.new()
	bg.color = Color("#150e1d")
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	machine = Control.new()
	machine.size = VSIZE
	add_child(machine)

	var title := Label.new()
	title.text = "ЗОЛОТЫЕ БАРАБАНЫ 3×5"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 2)
	title.size = Vector2(VSIZE.x, 48)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color("#ffd794"))
	machine.add_child(title)

	var top := HBoxContainer.new()
	top.position = Vector2(30, 56)
	top.size = Vector2(VSIZE.x - 60, 46)
	top.add_theme_constant_override("separation", 12)
	machine.add_child(top)

	balance_label = _label("Баланс: 0", 26, Color("#ffe9b8"))
	top.add_child(balance_label)
	top.add_child(_spacer())
	win_label = _label("", 26, Color("#8dffa0"))
	win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(win_label)
	top.add_child(_spacer())
	fs_label = _label("", 26, Color("#7ef3ff"))
	fs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fs_label.hide()
	top.add_child(fs_label)

	# Рамка с барабанами.
	var grid_w := SlotData.COLS * CELL + (SlotData.COLS - 1) * GAP
	var grid_h := SlotData.ROWS * CELL + (SlotData.ROWS - 1) * GAP
	grid_panel = Panel.new()
	grid_panel.position = Vector2((VSIZE.x - grid_w - GRID_PAD * 2) * 0.5, 110)
	grid_panel.size = Vector2(grid_w + GRID_PAD * 2, grid_h + GRID_PAD * 2)
	var sb := _stylebox(Color("#221730"), Color("#d8b45e"), 14)
	sb.set_border_width_all(4)
	grid_panel.add_theme_stylebox_override("panel", sb)
	machine.add_child(grid_panel)

	for c in SlotData.COLS:
		var reel := SlotReel.new()
		var initial: Array[int] = []
		for i in (SlotData.ROWS + 1):
			initial.append(SlotData.random_symbol(rng))
		reel.setup(Vector2(CELL, CELL), textures, rng, initial)
		reel.position = Vector2(GRID_PAD + c * (CELL + GAP), GRID_PAD)
		grid_panel.add_child(reel)
		reels.append(reel)

	fx_layer = Control.new()
	fx_layer.position = Vector2(GRID_PAD, GRID_PAD)
	fx_layer.size = Vector2(grid_w, grid_h)
	fx_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_panel.add_child(fx_layer)

	lines_overlay = Node2D.new()
	lines_overlay.position = Vector2(GRID_PAD, GRID_PAD)
	grid_panel.add_child(lines_overlay)

	msg_label = _label("", 42, Color("#ffffff"))
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.position = Vector2(0, grid_panel.size.y * 0.5 - 30)
	msg_label.size = Vector2(grid_panel.size.x, 60)
	msg_label.add_theme_constant_override("outline_size", 10)
	msg_label.add_theme_color_override("font_outline_color", Color("#3a1d6e"))
	msg_label.hide()
	grid_panel.add_child(msg_label)

	# Нижняя панель управления.
	var bottom := HBoxContainer.new()
	bottom.position = Vector2(20, 614)
	bottom.size = Vector2(VSIZE.x - 40, 72)
	bottom.add_theme_constant_override("separation", 10)
	machine.add_child(bottom)

	bet_minus = _button("−", Vector2(52, 56))
	bet_minus.pressed.connect(func() -> void: _change_bet(-1))
	bottom.add_child(bet_minus)
	bet_label = _label("Ставка/линия: 1", 24, Color("#ffe9b8"))
	bet_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(bet_label)
	bet_plus = _button("+", Vector2(52, 56))
	bet_plus.pressed.connect(func() -> void: _change_bet(1))
	bottom.add_child(bet_plus)
	total_label = _label("Всего: 9", 24, Color("#c9b6e2"))
	total_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom.add_child(total_label)
	bottom.add_child(_spacer())

	spin_btn = _button("СПИН", Vector2(210, 68))
	var gold := _stylebox(Color("#e8c06a"), Color("#8a6a20"), 12)
	gold.set_border_width_all(3)
	var gold_hover := _stylebox(Color("#ffd98a"), Color("#8a6a20"), 12)
	gold_hover.set_border_width_all(3)
	var gold_press := _stylebox(Color("#c79b45"), Color("#8a6a20"), 12)
	gold_press.set_border_width_all(3)
	spin_btn.add_theme_stylebox_override("normal", gold)
	spin_btn.add_theme_stylebox_override("hover", gold_hover)
	spin_btn.add_theme_stylebox_override("pressed", gold_press)
	spin_btn.add_theme_stylebox_override("disabled", _stylebox(Color("#5a5164"), Color("#3c3545"), 12))
	spin_btn.add_theme_font_size_override("font_size", 30)
	spin_btn.add_theme_color_override("font_color", Color("#2a1a08"))
	spin_btn.add_theme_color_override("font_disabled_color", Color("#2a1a08"))
	spin_btn.pressed.connect(_on_spin_pressed)
	bottom.add_child(spin_btn)
	bottom.add_child(_spacer())

	paytable_btn = _button("ТАБЛИЦА", Vector2(150, 56))
	paytable_btn.pressed.connect(func() -> void: paytable_popup.show())
	bottom.add_child(paytable_btn)
	bonus_btn = _button("+%d МОНЕТ" % BONUS_TOPUP, Vector2(190, 56))
	bonus_btn.pressed.connect(_on_bonus_pressed)
	bonus_btn.hide()
	bottom.add_child(bonus_btn)

	_build_paytable_popup()


func _build_paytable_popup() -> void:
	paytable_popup = Control.new()
	paytable_popup.set_anchors_preset(PRESET_FULL_RECT)
	paytable_popup.hide()
	machine.add_child(paytable_popup)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_LEFT:
			paytable_popup.hide()
	)
	paytable_popup.add_child(dim)

	var panel := Panel.new()
	panel.position = Vector2(70, 40)
	panel.size = Vector2(VSIZE.x - 140, VSIZE.y - 80)
	panel.add_theme_stylebox_override("panel", _stylebox(Color("#241a31"), Color("#d8b45e"), 14))
	paytable_popup.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.offset_left = 16
	scroll.offset_top = 12
	scroll.offset_right = -16
	scroll.offset_bottom = -12
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	var head := HBoxContainer.new()
	vbox.add_child(head)
	var h := _label("ТАБЛИЦА ВЫПЛАТ", 30, Color("#ffd794"))
	head.add_child(h)
	head.add_child(_spacer())
	var close := _button("ЗАКРЫТЬ", Vector2(180, 50))
	close.pressed.connect(func() -> void: paytable_popup.hide())
	head.add_child(close)

	var rules := _label(
		"Линии платят слева направо, начиная с первого барабана. Выплата = "
		+ "ставка на линию × коэффициент. WILD заменяет любой символ, кроме "
		+ "BONUS. Пара платится только у вишни, лимона и апельсина.\n"
		+ "BONUS (скаттер): 3/4/5 сундуков в любом месте поля = 2/10/50 полных "
		+ "ставок и 10/15/20 фриспинов. Во время фриспинов ставка не списывается.",
		20, Color("#d9c9ef"))
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(rules)

	for sym in PAY_ORDER:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		vbox.add_child(row)
		var icon := TextureRect.new()
		icon.texture = textures[sym]
		icon.custom_minimum_size = Vector2(54, 54)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var name_l := _label(String(SlotData.NAMES[sym]), 22, Color("#ffffff"))
		name_l.custom_minimum_size = Vector2(170, 0)
		name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_l)
		var pays: Array = SlotData.PAYTABLE[sym]
		var parts: Array[String] = []
		for k in range(1, 4):
			parts.append("×%d: %d" % [k + 1, int(pays[k])])
		var vals := _label("   ".join(parts), 22, Color("#8dffa0"))
		vals.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(vals)
		if int(pays[0]) > 0:
			var p2 := _label("×2: %d" % int(pays[0]), 22, Color("#9d8fb8"))
			p2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(p2)

	var scatter := HBoxContainer.new()
	scatter.add_theme_constant_override("separation", 14)
	vbox.add_child(scatter)
	var chest := TextureRect.new()
	chest.texture = textures[SlotData.Symbol.BONUS]
	chest.custom_minimum_size = Vector2(54, 54)
	chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	scatter.add_child(chest)
	var sc_text := _label(
		"BONUS (скаттер): 3 → 2× ставки + 10 фриспинов, 4 → 10× + 15, 5 → 50× + 20",
		22, Color("#7ef3ff"))
	sc_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	scatter.add_child(sc_text)

	vbox.add_child(_label("ЛИНИИ ВЫПЛАТ (9):", 26, Color("#ffd794")))
	var lines_grid := GridContainer.new()
	lines_grid.columns = 3
	lines_grid.add_theme_constant_override("h_separation", 30)
	lines_grid.add_theme_constant_override("v_separation", 14)
	vbox.add_child(lines_grid)
	for li in SlotData.PAYLINES.size():
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 10)
		lines_grid.add_child(cell)
		var num := _label("Л%d" % (li + 1), 20, SlotData.LINE_COLORS[li])
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(num)
		cell.add_child(_line_diagram(li))


func _line_diagram(line_idx: int) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(94, 58)
	box.size = Vector2(94, 58)
	var path: Array = SlotData.PAYLINES[line_idx]
	for c in SlotData.COLS:
		for r in SlotData.ROWS:
			var dot := ColorRect.new()
			dot.size = Vector2(12, 12)
			dot.position = Vector2(c * 19.0 + 2, r * 21.0 + 4)
			if int(path[c]) == r:
				dot.color = SlotData.LINE_COLORS[line_idx]
			else:
				dot.color = Color("#3c3347")
			box.add_child(dot)
	return box


# ------------------------------------------------------------------- хелперы UI

func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return s


func _stylebox(bg_color: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	return sb


func _button(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	var normal := _stylebox(Color("#3a2c4d"), Color("#7a6399"), 10)
	normal.set_border_width_all(2)
	var hover := _stylebox(Color("#4a3a61"), Color("#9a80bd"), 10)
	hover.set_border_width_all(2)
	var pressed := _stylebox(Color("#2c2139"), Color("#7a6399"), 10)
	pressed.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_font_size_override("font_size", 22)
	return b


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
