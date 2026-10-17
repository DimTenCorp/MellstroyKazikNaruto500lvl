#!/usr/bin/env python3
"""Генератор scenes/game.tscn: раскладывает весь UI слот-машины узлами сцены.

ВНИМАНИЕ: перезаписывает scenes/game.tscn целиком. Запускайте только если
не редактировали сцену руками в редакторе (или хотите сбросить правки):
    python3 tools/gen_game_tscn.py
Макет зеркалит константы scripts/slot_machine.gd и scripts/reel.gd.
Кнопки интерфейса и бейджи выигрышей вырезаются атласами из спрайтшитов
(img/buttons_spr, img/win) — только русские версии.
"""
import importlib.util
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = importlib.util.spec_from_file_location(
    "sim", os.path.join(ROOT, "tools", "rtp_sim.py"))
SIM = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SIM)

# ------------------------------------------------------------------ константы
VSIZE = (1280, 720)
CELL = 160.0   ## ячейка символа: крупнее, спрайт влезает целиком
GAP = 8.0
GRID_PAD = 12.0
GRID_X = 185.58  ## позиция сетки перенесена заказчиком (e598c15)
GRID_Y = 78.375
INSET = 4.0
ROWS, COLS = 3, 5

KEYS = ["cherry", "lemon", "orange", "plum", "watermelon", "star", "horseshoe",
        "moneysack", "bell", "1bar", "2bar", "3bar", "777", "wild", "chestbonus"]
PAY_ORDER_KEYS = ["777", "3bar", "2bar", "1bar", "bell", "moneysack",
                  "horseshoe", "star", "watermelon", "plum", "orange",
                  "lemon", "cherry", "wild"]
NAMES_RU = {
    "cherry": "Вишня", "lemon": "Лимон", "orange": "Апельсин", "plum": "Слива",
    "watermelon": "Арбуз", "star": "Звезда", "horseshoe": "Подкова",
    "moneysack": "Мешок денег", "bell": "Колокол", "1bar": "BAR",
    "2bar": "BAR BAR", "3bar": "BAR BAR BAR", "777": "777", "wild": "WILD",
    "chestbonus": "BONUS",
}
LINE_HEX = ["ffd794", "5b8cff", "6ee06e", "ff6b6b", "c77bff",
            "4dd7ff", "ffa24d", "ff7bd5", "b8ff6b"]
REEL_PREVIEW = [
    ["star", "wild", "cherry", "lemon"],
    ["cherry", "wild", "bell", "orange"],
    ["chestbonus", "lemon", "cherry", "orange"],
    ["plum", "watermelon", "plum", "horseshoe"],
    ["orange", "star", "lemon", "cherry"],
]

# Прямоугольники кнопок в img/buttons_spr/buttons_sprites.png (RU).
BTN_REGIONS = {
    "spin": (12, 8, 270, 293),        # ПУСК
    "auto": (338, 8, 319, 293),       # АВТОИГРА
    "max": (716, 8, 266, 293),        # МАКС. СТАВКА
    "bet": (1062, 8, 265, 293),       # СТАВКА
    "denom": (1385, 8, 319, 293),     # НОМИНАЛ МОНЕТЫ
    "speed": (19, 330, 265, 283),     # УСКОРЕНИЕ
    "paytable": (369, 330, 256, 283), # ТАБЛИЦА ВЫПЛАТ
    "collect": (712, 330, 266, 283),  # ЗАБРАТЬ
    "sound": (1069, 330, 266, 283),   # ЗВУК
}

BETS_LIST = [1, 2, 5, 10, 25, 50]

OUT = []
REG = {}  # имя узла -> последний созданный полный путь (порядок обхода DFS)


def hx(h: str, a: float = 1.0) -> str:
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return f"Color({r:g}, {g:g}, {b:g}, {a:g})"


def res_uid(path: str) -> str:
    m = re.search(r'uid="(uid://[^"]+)"', open(os.path.join(ROOT, path) + ".import").read())
    return m.group(1)


def prop_name(k: str) -> str:
    for g in ("constants", "font_sizes", "colors", "styles"):
        pre = f"theme_override_{g}_"
        if k.startswith(pre):
            return f"theme_override_{g}/" + k[len(pre):]
    return k


def node(name, ntype, parent, uniq=False, **props):
    if parent == ".":
        path, parent_attr = name, "."
    else:
        base = REG[parent]
        path, parent_attr = base + "/" + name, base
    REG[name] = path
    u = " unique_name_in_owner=true" if uniq else ""
    OUT.append(f'\n[node name="{name}" type="{ntype}" '
               f'parent="{parent_attr}"{u}]')
    for k, v in props.items():
        OUT.append(f"{prop_name(k)} = {v}")


def label(name, parent, text, fs, color, **kw):
    props = {"text": '"' + text + '"',
             "theme_override_font_sizes_font_size": fs,
             "theme_override_colors_font_color": hx(color)}
    props.update(kw)
    node(name, "Label", parent, **props)


def spacer(name, parent):
    node(name, "Control", parent, size_flags_horizontal=3)


def hbox(name, parent, sep=10, **kw):
    props = {"theme_override_constants_separation": sep}
    props.update(kw)
    node(name, "HBoxContainer", parent, **props)


def stylebox(sid, bg, border=None, width=0, radius=10):
    OUT.append(f'\n[sub_resource type="StyleBoxFlat" id="{sid}"]')
    OUT.append(f"bg_color = {hx(bg)}")
    if width:
        for side in ("left", "top", "right", "bottom"):
            OUT.append(f"border_width_{side} = {width}")
        OUT.append(f"border_color = {hx(border)}")
    for c in ("top_left", "top_right", "bottom_right", "bottom_left"):
        OUT.append(f"corner_radius_{c} = {radius}")


def atlassub(sid, ext_id, rect):
    OUT.append(f'\n[sub_resource type="AtlasTexture" id="{sid}"]')
    OUT.append(f'atlas = ExtResource("{ext_id}")')
    OUT.append(f"region = Rect2({rect[0]}, {rect[1]}, {rect[2]}, {rect[3]})")


def tbtn(name, parent, sid, pos, size):
    node(name, "TextureButton", parent,
         texture_normal=f'SubResource("{sid}")',
         ignore_texture_size="true",  # можно уменьшать в редакторе
         stretch_mode=5,
         position=f"Vector2({pos[0]}, {pos[1]})",
         size=f"Vector2({size[0]}, {size[1]})")


# ------------------------------------------------------------------ ресурсы
ext = ['[ext_resource type="Script" path="res://scripts/slot_machine.gd" '
       'id="scr"]',
       '[ext_resource type="Script" path="res://scripts/reel.gd" '
       'id="scr_reel"]',
       f'[ext_resource type="Texture2D" uid="{res_uid("img/background/back1.jpg")}" '
       'path="res://img/background/back1.jpg" id="tex_back1"]',
       f'[ext_resource type="Texture2D" uid="{res_uid("img/background/back2.jpg")}" '
       'path="res://img/background/back2.jpg" id="tex_back2"]',
       f'[ext_resource type="Texture2D" uid="{res_uid("img/money_icon.png")}" '
       'path="res://img/money_icon.png" id="tex_money"]',
       f'[ext_resource type="Texture2D" uid="{res_uid("img/buttons_clicker.png")}" '
       'path="res://img/buttons_clicker.png" id="tex_clicker"]',
       f'[ext_resource type="Texture2D" uid="{res_uid("img/buttons_spr/buttons_sprites.png")}" '
       'path="res://img/buttons/buttons_sprites.png" id="tex_buttons"]'.replace(
           "img/buttons/buttons_sprites.png", "img/buttons_spr/buttons_sprites.png"),
       ]
for key in KEYS:
    ext.append(f'[ext_resource type="Texture2D" uid="{res_uid("img/slot_machine/" + key + ".png")}" '
               f'path="res://img/slot_machine/{key}.png" id="tex_{key}"]')

stylebox("sb_grid", "221730", "d8b45e", 4, 14)
stylebox("sb_popup", "241a31", "d8b45e", 2, 14)
stylebox("sb_btn_n", "3a2c4d", "7a6399", 2, 10)
stylebox("sb_btn_h", "4a3a63", "9d86c4", 2, 10)
stylebox("sb_btn_p", "2a1f3a", "5d4a80", 2, 10)
stylebox("sb_glow", "ffd79400", "ffd794", 6, 20)  # светящаяся рамка-указатель
for key in BTN_REGIONS:
    if key in ("collect", "denom"):
        continue  # кнопки ЗАБРАТЬ/НОМИНАЛ удалены заказчиком
    atlassub("at_" + key, "tex_buttons", BTN_REGIONS[key])
# мешок денег из листа кликера: кнопка перехода в кликер
atlassub("at_bag", "tex_clicker", (726, 17, 274, 284))

# ------------------------------------------------------------------ узлы
OUT.append('\n[node name="game" type="Control" unique_id=1200433587]')
OUT.append("anchor_right = 1.0")
OUT.append("anchor_bottom = 1.0")
OUT.append("grow_horizontal = 2")
OUT.append("grow_vertical = 2")
OUT.append('script = ExtResource("scr")')

node("bg", "TextureRect", ".", texture='ExtResource("tex_back1")',
     anchor_right=1.0, anchor_bottom=1.0, grow_horizontal=2, grow_vertical=2,
     stretch_mode=6, mouse_filter=2)
node("bg_dim", "ColorRect", ".", color=hx("140a20", 0.52),
     anchor_right=1.0, anchor_bottom=1.0, grow_horizontal=2, grow_vertical=2,
     mouse_filter=2)
node("machine", "Control", ".", size=f"Vector2({VSIZE[0]}, {VSIZE[1]})")
# Остаток фриспинов (узел добавлен заказчиком, перенесён под machine,
# чтобы масштабироваться вместе с макетом).
label("freespin_label", "machine", "", 22, "7ef3ff",
      position="Vector2(10, 140)", size="Vector2(160, 34)",
      theme_override_constants_outline_size=8,
      theme_override_colors_font_outline_color=hx("1d3a6e"),
      visible="false")
# Иконка денег и число баланса лежат ОТДЕЛЬНО от контейнеров,
# чтобы их можно было перетаскивать в редакторе.
node("balance_icon", "TextureRect", "machine",
     texture='ExtResource("tex_money")',
     position="Vector2(24, 34)", size="Vector2(64.14015, 59)",  # размер заказчика — НЕ МЕНЯТЬ
     expand_mode=1, stretch_mode=5, mouse_filter=2)
label("balance_label", "machine", "0", 26, "ffe9b8",
      position="Vector2(98, 44)", size="Vector2(240, 36)",
      vertical_alignment=1)

# Выигрыш пишется сверху над сеткой: поверх панели его плохо видно.
label("debt_plaque", "machine", "ДОЛГ: 10 000 000", 20, "ff7b7b",
      position="Vector2(1030, 18)", size="Vector2(240, 52)",
      horizontal_alignment=2,
      theme_override_constants_outline_size=6,
      theme_override_colors_font_outline_color=hx("31131a"))
label("win_label", "machine", "", 26, "8dffa0",
      position="Vector2(340, 6)", size="Vector2(600, 44)",
      horizontal_alignment=1,
      theme_override_constants_outline_size=8,
      theme_override_colors_font_outline_color=hx("1d4d1d"))
hbox("top_bar", "machine", 12, position="Vector2(30, 56)",
     size=f"Vector2({VSIZE[0] - 60}, 46)")
spacer("spacer1", "top_bar")
spacer("spacer2", "top_bar")

grid_w = COLS * CELL + (COLS - 1) * GAP
grid_h = ROWS * CELL + (ROWS - 1) * GAP
panel_w, panel_h = grid_w + GRID_PAD * 2, grid_h + GRID_PAD * 2
node("grid_panel", "Panel", "machine",
     position=f"Vector2({GRID_X:g}, {GRID_Y:g})",
     size=f"Vector2({panel_w:g}, {panel_h:g})",
     theme_override_styles_panel='SubResource("sb_grid")')

for c in range(COLS):
    node(f"Reel{c}", "Control", "grid_panel",
         position=f"Vector2({GRID_PAD + c * (CELL + GAP):g}, {GRID_PAD:g})",
         size=f"Vector2({CELL:g}, {CELL * ROWS:g})", clip_contents="true",
         script='ExtResource("scr_reel")')
    for i, key in enumerate(REEL_PREVIEW[c]):
        node(f"Cell{i}", "TextureRect", f"Reel{c}",
             texture=f'ExtResource("tex_{key}")',
             position=f"Vector2({INSET:g}, {i * CELL - CELL + INSET:g})",
             size=f"Vector2({CELL - INSET * 2:g}, {CELL - INSET * 2:g})",
             stretch_mode=0, expand_mode=0, mouse_filter=2)

node("fx_layer", "Control", "grid_panel",
     position=f"Vector2({GRID_PAD:g}, {GRID_PAD:g})",
     size=f"Vector2({grid_w:g}, {grid_h:g})", mouse_filter=2)
node("lines_overlay", "Node2D", "grid_panel",
     position=f"Vector2({GRID_PAD:g}, {GRID_PAD:g})")
label("msg_label", "grid_panel", "", 42, "ffffff", horizontal_alignment=1,
      position=f"Vector2(0, {panel_h * 0.5 - 30:g})",
      size=f"Vector2({panel_w:g}, 60)",
      theme_override_constants_outline_size=10,
      theme_override_colors_font_outline_color=hx("3a1d6e"), visible="false")

# ---------------------------------------------------------- нижняя панель
node("bottom_bar", "Control", "machine",
     position="Vector2(0, 0)", size=f"Vector2({VSIZE[0]}, {VSIZE[1]})",
     mouse_filter=2)
# Раскладка кнопок перенесена из правки заказчика (91dc2e5): позиции те же,
# но размеры заданы через Size (без Scale), чтобы хитбокс совпадал со спрайтом.
tbtn("bet_btn", "bottom_bar", "at_bet", (8, 544), (150, 166))
tbtn("max_btn", "bottom_bar", "at_max", (168, 568), (129, 142))
label("bet_label", "bottom_bar", "Ставка/линия: 1", 20, "ffe9b8",
      position="Vector2(264, 48)", size="Vector2(220, 28)")
label("auto_label", "bottom_bar", "", 26, "7ef3ff",
      position="Vector2(32, 112)", size="Vector2(200, 40)",
      theme_override_constants_outline_size=8,
      theme_override_colors_font_outline_color=hx("1d3a6e"),
      visible="false")
tbtn("auto_btn", "bottom_bar", "at_auto", (800, 576), (163, 144))
tbtn("speed_btn", "bottom_bar", "at_speed", (968, 592), (113, 120))
tbtn("spin_btn", "bottom_bar", "at_spin", (1088, 520), (177, 192))
tbtn("paytable_btn", "bottom_bar", "at_paytable", (1152, 152), (115, 127))
node("lang_btn", "TextureButton", "bottom_bar",
     ignore_texture_size="true", stretch_mode=5,
     position="Vector2(13, 214)", size="Vector2(72, 76.6452)")
tbtn("sound_btn", "bottom_bar", "at_sound", (5, 123), (86, 91.95386))
node("clicker_glow", "Panel", "bottom_bar",
     position="Vector2(1140, 277)", size="Vector2(140, 140)",
     visible="false", mouse_filter=2,
     theme_override_styles_panel='SubResource("sb_glow")')
tbtn("clicker_btn", "bottom_bar", "at_bag", (1153, 283), (116, 120))

# ---------------------------------------------------------- попап выигрыша
node("win_popup", "Control", "machine", position="Vector2(364, 173)",
     size="Vector2(500, 330)", visible="false", mouse_filter=2)
node("win_badge", "TextureRect", "win_popup",
     position="Vector2(0, 0)", size="Vector2(500, 260)",
     stretch_mode=5, mouse_filter=2)
label("win_popup_label", "win_popup", "", 44, "ffe9b8",
      horizontal_alignment=1, position="Vector2(0, 252)",
      size="Vector2(500, 66)",
      theme_override_constants_outline_size=10,
      theme_override_colors_font_outline_color=hx("402008"))

# полная ставка (узел заказчика fullbet_label, 79b2277)
label("fullbet_label", "bottom_bar", "Полная ставка:", 22, "ffe9b8",
      position="Vector2(342, 602)", size="Vector2(290, 59)",
      theme_override_constants_outline_size=6,
      theme_override_colors_font_outline_color=hx("402008"))

# отладочная кнопка полного сброса прогресса
node("reset_btn", "Button", "machine", text='"СБРОС (ОТЛАДКА)"',
     position="Vector2(-29, 480)", size="Vector2(152, 36)",
     theme_override_font_sizes_font_size=14,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_h")',
     theme_override_styles_pressed='SubResource("sb_btn_p")')

# отладочная кнопка и меню выдачи денег
node("debug_btn", "Button", "machine", text='"ДЕНЬГИ (ОТЛАДКА)"',
     position="Vector2(-29, 522)", size="Vector2(163, 36)",
     theme_override_font_sizes_font_size=14,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_h")',
     theme_override_styles_pressed='SubResource("sb_btn_p")')
node("debug_menu", "Control", "machine", visible="false",
     anchor_right=1.0, anchor_bottom=1.0)
node("dim", "ColorRect", "debug_menu", color=hx("000000", 0.7),
     anchor_right=1.0, anchor_bottom=1.0)
node("panel", "Panel", "debug_menu", position="Vector2(470, 150)",
     size="Vector2(340, 420)",
     theme_override_styles_panel='SubResource("sb_popup")')
node("vbox", "VBoxContainer", "panel",
     anchor_right=1.0, anchor_bottom=1.0,
     offset_left=16, offset_top=12, offset_right=-16, offset_bottom=-12,
     theme_override_constants_separation=12)
hbox("head", "vbox", 0)
label("head_title", "head", "ВЫДАЧА ДЕНЕГ", 22, "ffd794")
spacer("spacer_dbg", "head")
node("close_btn", "Button", "head", text='"ЗАКРЫТЬ"',
     custom_minimum_size="Vector2(120, 40)",
     theme_override_font_sizes_font_size=16,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_n")',
     theme_override_styles_pressed='SubResource("sb_btn_n")')
node("grid", "GridContainer", "vbox", columns=2,
     theme_override_constants_h_separation=10,
     theme_override_constants_v_separation=10)
for i, b in enumerate([1000, 10000, 100000, 1000000, 10000000]):
    node(f"dbg_opt{i}", "Button", "grid", text='"+%s"' % format(b, " ").replace(" ", " "),
         custom_minimum_size="Vector2(140, 56)",
         theme_override_font_sizes_font_size=20,
         theme_override_styles_normal='SubResource("sb_btn_n")',
         theme_override_styles_hover='SubResource("sb_btn_h")',
         theme_override_styles_pressed='SubResource("sb_btn_p")')
hbox("dbg_row", "vbox", 10)
node("dbg_input", "LineEdit", "dbg_row",
     size_flags_horizontal=3,
     custom_minimum_size="Vector2(0, 46)",
     placeholder_text='"СВОЯ СУММА"',
     theme_override_font_sizes_font_size=20)
node("dbg_apply", "Button", "dbg_row", text='"ВЫДАТЬ"',
     custom_minimum_size="Vector2(120, 46)",
     theme_override_font_sizes_font_size=18,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_h")',
     theme_override_styles_pressed='SubResource("sb_btn_p")')

# интро при первом заходе: долг 10 000 000
node("intro_popup", "Control", "machine", visible="false")
node("intro_panel", "Panel", "intro_popup",
     position="Vector2(300, 170)", size="Vector2(680, 360)",
     theme_override_styles_panel='SubResource("sb_popup")')
label("intro_label", "intro_popup",
      "Ты набрал много кредитов и проиграл всё в казино, теперь тебе нужно "
      "собрать 10 000 000 денег, чтобы расплатится с долгами", 24, "ffe9b8",
      position="Vector2(330, 200)", size="Vector2(620, 240)",
      autowrap_mode=3, horizontal_alignment=1, vertical_alignment=1,
      theme_override_constants_outline_size=8,
      theme_override_colors_font_outline_color=hx("241a31"))
# попап расплаты с долгами: показывается при балансе >= 10 000 000
node("debt_popup", "Control", "machine", visible="false")
node("debt_panel", "Panel", "debt_popup",
     position="Vector2(290, 190)", size="Vector2(700, 340)",
     theme_override_styles_panel='SubResource("sb_popup")')
label("debt_label", "debt_popup",
      "Вы успешно расплатились со своими долгами и теперь вам доступно "
      "перерождение, долг увеличится в втрое, а любой заработок вдвое", 24, "8dffa0",
      position="Vector2(320, 220)", size="Vector2(640, 200)",
      autowrap_mode=3, horizontal_alignment=1, vertical_alignment=1,
      theme_override_constants_outline_size=8,
      theme_override_colors_font_outline_color=hx("1d4d1d"))
node("debt_btn", "Button", "debt_popup", text='"ПЕРЕРОДИТЬСЯ"',
     position="Vector2(320, 440)", size="Vector2(320, 52)",
     theme_override_font_sizes_font_size=20,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_h")',
     theme_override_styles_pressed='SubResource("sb_btn_p")')

node("debt_later", "Button", "debt_popup", text='"ПОЗЖЕ"',
     position="Vector2(660, 440)", size="Vector2(300, 52)",
     theme_override_font_sizes_font_size=20,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_h")',
     theme_override_styles_pressed='SubResource("sb_btn_p")')
node("rebirth_btn", "TextureButton", "machine", visible="false",
     ignore_texture_size="true",
     position="Vector2(1153, 407)", size="Vector2(116, 133)")

node("intro_btn", "Button", "intro_popup", text='"ПОНЯТНО, ПОГНАЛИ"',
     position="Vector2(520, 455)", size="Vector2(240, 52)",
     theme_override_font_sizes_font_size=20,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_h")',
     theme_override_styles_pressed='SubResource("sb_btn_p")')

# ---------------------------------------------------------- меню ставок
node("bet_menu", "Control", "machine", visible="false",
     anchor_right=1.0, anchor_bottom=1.0)
node("dim", "ColorRect", "bet_menu", color=hx("000000", 0.7),
     anchor_right=1.0, anchor_bottom=1.0)
node("panel", "Panel", "bet_menu", position="Vector2(470, 170)",
     size="Vector2(340, 360)",
     theme_override_styles_panel='SubResource("sb_popup")')
node("vbox", "VBoxContainer", "panel",
     anchor_right=1.0, anchor_bottom=1.0,
     offset_left=16, offset_top=12, offset_right=-16, offset_bottom=-12,
     theme_override_constants_separation=12)
hbox("head", "vbox", 0)
label("head_title", "head", "ПОЛНАЯ СТАВКА", 26, "ffd794")
spacer("spacer_bet", "head")
node("close_btn", "Button", "head", text='"ЗАКРЫТЬ"',
     custom_minimum_size="Vector2(140, 42)",
     theme_override_font_sizes_font_size=18,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_n")',
     theme_override_styles_pressed='SubResource("sb_btn_n")')
node("grid", "GridContainer", "vbox", columns=3,
     theme_override_constants_h_separation=10,
     theme_override_constants_v_separation=10)
for i, b in enumerate(BETS_LIST):
    node(f"bet_opt{i}", "Button", "grid", text=f'"{b * 9}"',  # пресеты полными ставками
         custom_minimum_size="Vector2(96, 56)",
         theme_override_font_sizes_font_size=24,
         theme_override_styles_normal='SubResource("sb_btn_n")',
         theme_override_styles_hover='SubResource("sb_btn_h")',
         theme_override_styles_pressed='SubResource("sb_btn_p")')
hbox("bet_row", "vbox", 10)
node("bet_input", "LineEdit", "bet_row",
     size_flags_horizontal=3,
     custom_minimum_size="Vector2(0, 46)",
     placeholder_text='"ПОЛНАЯ СТАВКА (ЧИСЛО)"',
     theme_override_font_sizes_font_size=20)
node("bet_apply", "Button", "bet_row", text='"ПРИМЕНЯТЬ"',
     custom_minimum_size="Vector2(150, 46)",
     theme_override_font_sizes_font_size=18,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_h")',
     theme_override_styles_pressed='SubResource("sb_btn_p")')
label("bet_total", "vbox", "Полная ставка: 9", 20, "c9b6e2",
      horizontal_alignment=1)

# ---------------------------------------------------------- меню автоигры
node("auto_menu", "Control", "machine", visible="false",
     anchor_right=1.0, anchor_bottom=1.0)
node("dim", "ColorRect", "auto_menu", color=hx("000000", 0.7),
     anchor_right=1.0, anchor_bottom=1.0)
node("panel", "Panel", "auto_menu", position="Vector2(470, 190)",
     size="Vector2(340, 320)",
     theme_override_styles_panel='SubResource("sb_popup")')
node("vbox", "VBoxContainer", "panel",
     anchor_right=1.0, anchor_bottom=1.0,
     offset_left=16, offset_top=12, offset_right=-16, offset_bottom=-12,
     theme_override_constants_separation=12)
hbox("head", "vbox", 0)
label("head_title", "head", "АВТОИГРА", 26, "ffd794")
spacer("spacer_auto", "head")
node("close_btn", "Button", "head", text='"ЗАКРЫТЬ"',
     custom_minimum_size="Vector2(140, 42)",
     theme_override_font_sizes_font_size=18,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_n")',
     theme_override_styles_pressed='SubResource("sb_btn_n")')
node("grid", "GridContainer", "vbox", columns=3,
     theme_override_constants_h_separation=10,
     theme_override_constants_v_separation=10)
for i, t in enumerate(["10", "25", "50", "100", "∞"]):
    node(f"auto_opt{i}", "Button", "grid", text=f'"{t}"',
         custom_minimum_size="Vector2(96, 56)",
         theme_override_font_sizes_font_size=24,
         theme_override_styles_normal='SubResource("sb_btn_n")',
         theme_override_styles_hover='SubResource("sb_btn_h")',
         theme_override_styles_pressed='SubResource("sb_btn_p")')
node("auto_cancel", "Button", "grid", text='"ОТМЕНА"',
     custom_minimum_size="Vector2(96, 56)",
     theme_override_font_sizes_font_size=20,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_h")',
     theme_override_styles_pressed='SubResource("sb_btn_p")')
label("auto_hint", "vbox",
      "ПУСК во время автоигры останавливает серию", 18, "9d8fb8",
      horizontal_alignment=1)

# ---------------------------------------------------------- меню звука
node("sound_menu", "Control", "machine", visible="false",
     anchor_right=1.0, anchor_bottom=1.0)
node("dim", "ColorRect", "sound_menu", color=hx("000000", 0.7),
     anchor_right=1.0, anchor_bottom=1.0)
node("panel", "Panel", "sound_menu", position="Vector2(430, 220)",
     size="Vector2(420, 260)",
     theme_override_styles_panel='SubResource("sb_popup")')
node("vbox", "VBoxContainer", "panel",
     anchor_right=1.0, anchor_bottom=1.0,
     offset_left=16, offset_top=12, offset_right=-16, offset_bottom=-12,
     theme_override_constants_separation=14)
hbox("head", "vbox", 0)
label("head_title", "head", "ЗВУК", 26, "ffd794")
spacer("spacer_sound", "head")
node("close_btn", "Button", "head", text='"ЗАКРЫТЬ"',
     custom_minimum_size="Vector2(140, 42)",
     theme_override_font_sizes_font_size=18,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_n")',
     theme_override_styles_pressed='SubResource("sb_btn_n")')
for row_id, row_name in (("sfx", "ЭФФЕКТЫ"), ("music", "МУЗЫКА")):
    hbox(f"row_{row_id}", "vbox", 12)
    label(f"{row_id}_name", f"row_{row_id}", row_name,
          20, "ffffff", custom_minimum_size="Vector2(110, 0)",
          vertical_alignment=1)
    node(f"{row_id}_slider", "HSlider", f"row_{row_id}",
         min_value=0, max_value=100, value=80,
         custom_minimum_size="Vector2(190, 36)",
         size_flags_vertical=8)
    label(f"{row_id}_val", f"row_{row_id}", "80", 20,
          "8dffa0", custom_minimum_size="Vector2(44, 0)",
          horizontal_alignment=2, vertical_alignment=1)

# ------------------------------------------------------- попап таблицы выплат
node("paytable_popup", "Control", "machine", visible="false",
     anchor_right=1.0, anchor_bottom=1.0)
node("dim", "ColorRect", "paytable_popup", color=hx("000000", 0.78),
     anchor_right=1.0, anchor_bottom=1.0)
node("popup_panel", "Panel", "paytable_popup", position="Vector2(70, 40)",
     size=f"Vector2({VSIZE[0] - 140}, {VSIZE[1] - 80})",
     theme_override_styles_panel='SubResource("sb_popup")')
node("panel_bg", "TextureRect", "popup_panel",
     texture='ExtResource("tex_back2")',
     anchor_right=1.0, anchor_bottom=1.0, stretch_mode=6, mouse_filter=2)
node("panel_dim", "ColorRect", "popup_panel", color=hx("12081c", 0.86),
     anchor_right=1.0, anchor_bottom=1.0, mouse_filter=2)
node("scroll", "ScrollContainer", "popup_panel",
     anchor_right=1.0, anchor_bottom=1.0,
     offset_left=16, offset_top=12, offset_right=-16, offset_bottom=-12)
node("vbox", "VBoxContainer", "scroll", size_flags_horizontal=3,
     theme_override_constants_separation=8)

hbox("head", "vbox", 0)
label("head_title", "head", "ТАБЛИЦА ВЫПЛАТ", 30, "ffd794")
spacer("spacer5", "head")
node("close_btn", "Button", "head", text='"ЗАКРЫТЬ"',
     custom_minimum_size="Vector2(180, 50)",
     theme_override_font_sizes_font_size=22,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_n")',
     theme_override_styles_pressed='SubResource("sb_btn_n")')

rules = ("Линии платят слева направо, начиная с первого барабана. Выплата = "
         "ставка на линию × коэффициент. WILD заменяет любой символ, кроме "
         "BONUS. Пара платится только у вишни, лимона и апельсина.\\n"
         "BONUS (скаттер): 3/4/5 сундуков в любом месте поля = 2/10/50 полных "
         "ставок и 10/15/20 фриспинов. Во время фриспинов ставка не списывается.")
label("rules", "vbox", rules, 20, "d9c9ef", autowrap_mode=3,
      size_flags_horizontal=3)

for key in PAY_ORDER_KEYS:
    sym = KEYS.index(key)
    pays = SIM.PAYTABLE[sym]
    hbox(f"row_{key}", "vbox", 14)
    node("icon", "TextureRect", f"row_{key}",
         texture=f'ExtResource("tex_{key}")',
         custom_minimum_size="Vector2(54, 54)", stretch_mode=4)
    label("name", f"row_{key}", NAMES_RU[key], 22, "ffffff",
          custom_minimum_size="Vector2(170, 0)", vertical_alignment=1)
    vals = "   ".join(f"×{k + 1}: {int(pays[k])}" for k in range(1, 4))
    label("val", f"row_{key}", vals, 22, "8dffa0", vertical_alignment=1)
    if pays[0] > 0:
        label("p2", f"row_{key}", f"×2: {int(pays[0])}", 22, "9d8fb8",
              vertical_alignment=1)

hbox("row_bonus", "vbox", 14)
node("icon", "TextureRect", "row_bonus",
     texture='ExtResource("tex_chestbonus")',
     custom_minimum_size="Vector2(54, 54)", stretch_mode=4)
label("name", "row_bonus", "BONUS (скаттер)", 22, "ffffff",
      custom_minimum_size="Vector2(170, 0)", vertical_alignment=1)
label("val", "row_bonus",
      "3 → 2× ставки + 10 фриспинов, 4 → 10× + 15, 5 → 50× + 20",
      22, "7ef3ff", vertical_alignment=1)

label("lines_title", "vbox", "ЛИНИИ ВЫПЛАТ (9):", 26, "ffd794")
node("lines_grid", "GridContainer", "vbox", columns=3,
     theme_override_constants_h_separation=30,
     theme_override_constants_v_separation=14)

for li, path in enumerate(SIM.PAYLINES):
    hbox(f"line_cell{li}", "lines_grid", 10)
    label(f"line_num{li}", f"line_cell{li}", f"Л{li + 1}", 20, LINE_HEX[li],
          vertical_alignment=1)
    node(f"line_diag{li}", "Control", f"line_cell{li}",
         custom_minimum_size="Vector2(94, 58)", size="Vector2(94, 58)")
    for c in range(COLS):
        for r in range(ROWS):
            on = int(path[c]) == r
            node(f"dot_{c}_{r}", "ColorRect", f"line_diag{li}",
                 size="Vector2(12, 12)",
                 position=f"Vector2({c * 19.0 + 2:g}, {r * 21.0 + 4:g})",
                 color=hx(LINE_HEX[li] if on else "3c3347"))

# ------------------------------------------------------------------ сборка
body = "\n".join(OUT)
n_sub = body.count("\n[sub_resource ")
n_ext = len(ext)
header = (f"[gd_scene load_steps={n_ext + n_sub + 1} format=3 "
          f'uid="uid://jem4ybiqp44h"]\n\n' + "\n".join(ext) + "\n")
with open(os.path.join(ROOT, "scenes", "game.tscn"), "w") as f:
    f.write(header + body + "\n")
print("nodes:", body.count("\n[node "), "| sub_resources:", n_sub,
      "| ext_resources:", n_ext)
