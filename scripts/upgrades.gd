class_name Upgrades
extends RefCounted
## Общая таблица улучшений кликера: используется и кликером (витрина, покупка),
## и слот-машиной (авто-бабло капает в обеих сценах).

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
const REGIONS := [
	Rect2(4, 2, 213, 211), Rect2(283, 2, 214, 211), Rect2(562, 2, 214, 211),
	Rect2(841, 2, 214, 211), Rect2(1121, 2, 213, 211),
	Rect2(4, 255, 213, 212), Rect2(283, 255, 214, 212), Rect2(562, 255, 214, 212),
	Rect2(841, 255, 214, 212), Rect2(1121, 255, 213, 212),
	Rect2(4, 499, 213, 211), Rect2(283, 499, 214, 211), Rect2(562, 499, 214, 211),
]

static func click_add(levels: Array) -> int:
	var v := 0
	for i in UPGRADES.size():
		v += int(UPGRADES[i].click) * int(levels[i])
	return v


static func auto_per_sec(levels: Array) -> int:
	var v := 0
	for i in UPGRADES.size():
		v += int(UPGRADES[i].auto) * int(levels[i])
	return v


static func cost(i: int, lvl: int) -> int:
	var u: Dictionary = UPGRADES[i]
	return int(round(float(u.cost) * pow(float(u.mult), lvl) / 10.0)) * 10
