class_name SlotData
extends RefCounted
## Чистая математика слота: символы, веса барабанов, линии и расчёт выигрыша.
## Не содержит узлов — логику можно тестировать отдельно от сцены.
##
## ВАЖНО: константы ниже продублированы в tools/rtp_sim.py (симулятор RTP).
## При изменении баланса обновляйте оба файла. Целевой RTP ~94.7%.

const ROWS := 3  ## высота сетки (видимых строк на барабан)
const COLS := 5  ## ширина сетки (количество барабанов)

enum Symbol {
	CHERRY,
	LEMON,
	ORANGE,
	PLUM,
	WATERMELON,
	STAR,
	HORSESHOE,
	MONEYBAG,
	BELL,
	BAR1,
	BAR2,
	BAR3,
	SEVEN,
	WILD,
	BONUS,
}

const SYMBOL_COUNT := 15

const TEXTURES := {
	Symbol.CHERRY: "res://img/slot_machine/cherry.png",
	Symbol.LEMON: "res://img/slot_machine/lemon.png",
	Symbol.ORANGE: "res://img/slot_machine/orange.png",
	Symbol.PLUM: "res://img/slot_machine/plum.png",
	Symbol.WATERMELON: "res://img/slot_machine/watermelon.png",
	Symbol.STAR: "res://img/slot_machine/star.png",
	Symbol.HORSESHOE: "res://img/slot_machine/horseshoe.png",
	Symbol.MONEYBAG: "res://img/slot_machine/moneysack.png",
	Symbol.BELL: "res://img/slot_machine/bell.png",
	Symbol.BAR1: "res://img/slot_machine/1bar.png",
	Symbol.BAR2: "res://img/slot_machine/2bar.png",
	Symbol.BAR3: "res://img/slot_machine/3bar.png",
	Symbol.SEVEN: "res://img/slot_machine/777.png",
	Symbol.WILD: "res://img/slot_machine/wild.png",
	Symbol.BONUS: "res://img/slot_machine/chestbonus.png",
}

const NAMES := {
	Symbol.CHERRY: "Вишня",
	Symbol.LEMON: "Лимон",
	Symbol.ORANGE: "Апельсин",
	Symbol.PLUM: "Слива",
	Symbol.WATERMELON: "Арбуз",
	Symbol.STAR: "Звезда",
	Symbol.HORSESHOE: "Подкова",
	Symbol.MONEYBAG: "Мешок денег",
	Symbol.BELL: "Колокол",
	Symbol.BAR1: "BAR",
	Symbol.BAR2: "BAR BAR",
	Symbol.BAR3: "BAR BAR BAR",
	Symbol.SEVEN: "777",
	Symbol.WILD: "WILD",
	Symbol.BONUS: "BONUS",
}

## Вероятностные веса символов на каждой ячейке барабана (индекс = Symbol).
## Чем ценнее символ, тем реже он выпадает. WILD и BONUS — редкие.
const WEIGHTS: Array[int] = [
	34,  # CHERRY
	32,  # LEMON
	30,  # ORANGE
	26,  # PLUM
	24,  # WATERMELON
	20,  # STAR
	17,  # HORSESHOE
	14,  # MONEYBAG
	12,  # BELL
	10,  # BAR1
	8,   # BAR2
	6,   # BAR3
	5,   # SEVEN
	11,  # WILD
	6,   # BONUS
]

## Выплаты в единицах СТАВКИ НА ЛИНИЮ за 2/3/4/5 символов подряд слева
## (0 = не платится). Пара платится только у трёх дешёвых фруктов.
## WILD заменяет любой символ, кроме BONUS. Линия из одних WILD платит по таблице WILD.
const PAYTABLE: Array[Array] = [
	[2, 10, 25, 100],     # CHERRY
	[2, 10, 25, 100],     # LEMON
	[2, 12, 30, 120],     # ORANGE
	[0, 15, 40, 150],     # PLUM
	[0, 20, 60, 200],     # WATERMELON
	[0, 25, 80, 300],     # STAR
	[0, 30, 100, 400],    # HORSESHOE
	[0, 40, 150, 600],    # MONEYBAG
	[0, 50, 200, 800],    # BELL
	[0, 75, 300, 1200],   # BAR1
	[0, 100, 400, 1600],  # BAR2
	[0, 150, 600, 2500],  # BAR3
	[0, 250, 1000, 5000], # SEVEN
	[0, 500, 2000, 10000],# WILD
	[0, 0, 0, 0],         # BONUS (платится как скаттер, см. SCATTER_PAYS)
]

## 9 линий выплат: для каждого барабана (0..4) — номер строки (0 = верх).
const PAYLINES: Array[Array] = [
	[1, 1, 1, 1, 1],  # центральная
	[0, 0, 0, 0, 0],  # верхняя
	[2, 2, 2, 2, 2],  # нижняя
	[0, 1, 2, 1, 0],  # V
	[2, 1, 0, 1, 2],  # ^
	[0, 0, 1, 2, 2],  # диагональ вниз
	[2, 2, 1, 0, 0],  # диагональ вверх
	[1, 0, 0, 1, 2],  # зигзаг Z
	[1, 2, 2, 1, 0],  # зигзаг S
]

const LINE_COLORS: Array[Color] = [
	Color("#ffd794ff"),  # золото
	Color("#5b8cffff"),  # синий
	Color("#6ee06eff"),  # зелёный
	Color("#ff6b6bff"),  # красный
	Color("#c77bffff"),  # фиолетовый
	Color("#4dd7ffff"),  # голубой
	Color("#ffa24dff"),  # оранжевый
	Color("#ff7bd5ff"),  # розовый
	Color("#b8ff6bff"),  # салатовый
]

## Скаттер (сундук BONUS): платит в единицах ПОЛНОЙ ставки от числа совпадений.
const SCATTER_PAYS := {3: 2, 4: 10, 5: 50}
## ...и выдаёт фриспины.
const SCATTER_SPINS := {3: 10, 4: 15, 5: 20}


static func random_symbol(rng: RandomNumberGenerator) -> int:
	var total := 0
	for w in WEIGHTS:
		total += w
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for i in SYMBOL_COUNT:
		acc += WEIGHTS[i]
		if roll < acc:
			return i
	return Symbol.CHERRY


## grid[col][row] -> id символа (Symbol).
static func make_grid(rng: RandomNumberGenerator) -> Array:
	var grid: Array[Array] = []
	for c in COLS:
		var column: Array[int] = []
		for r in ROWS:
			column.append(random_symbol(rng))
		grid.append(column)
	return grid


## Полная оценка спина.
## Возвращает: {total, line_wins:[{line, symbol, count, pay, cells:[Vector2i(col,row)]}],
##              scatter, scatter_pay, free_spins}
static func evaluate(grid: Array, line_bet: int) -> Dictionary:
	var total_bet := line_bet * PAYLINES.size()
	var line_wins: Array = []
	var total := 0

	for li in PAYLINES.size():
		var line: Array = PAYLINES[li]
		# Базовый символ линии: первый не-WILD слева (все WILD => линия из WILD).
		var base: int = Symbol.WILD
		for c in COLS:
			var s: int = grid[c][line[c]]
			if s != Symbol.WILD:
				base = s
				break
		if base == Symbol.BONUS:
			continue  # скаттер не участвует в линиях
		var count := 0
		for c in COLS:
			var s: int = grid[c][line[c]]
			if s == base or s == Symbol.WILD:
				count += 1
			else:
				break
		if count >= 2:
			var mult: int = PAYTABLE[base][count - 2]
			if mult > 0:
				var cells: Array = []
				for c in count:
					cells.append(Vector2i(c, line[c]))
				line_wins.append({
					"line": li,
					"symbol": base,
					"count": count,
					"pay": mult * line_bet,
					"cells": cells,
				})
				total += mult * line_bet

	var scatter := 0
	for c in COLS:
		for r in ROWS:
			if int(grid[c][r]) == Symbol.BONUS:
				scatter += 1
	var scatter_pay := 0
	var free_spins := 0
	if scatter >= 3:
		var k := mini(scatter, 5)
		scatter_pay = int(SCATTER_PAYS[k]) * total_bet
		free_spins = int(SCATTER_SPINS[k])
		total += scatter_pay

	return {
		"total": total,
		"line_wins": line_wins,
		"scatter": scatter,
		"scatter_pay": scatter_pay,
		"free_spins": free_spins,
	}
