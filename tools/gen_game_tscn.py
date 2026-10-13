#!/usr/bin/env python3
"""Генератор scenes/game.tscn: раскладывает весь UI слот-машины узлами сцены.

ВНИМАНИЕ: перезаписывает scenes/game.tscn целиком. Запускайте только если
не редактировали сцену руками в редакторе (или хотите сбросить правки):
    python3 tools/gen_game_tscn.py
Макет зеркалит константы scripts/slot_machine.gd и scripts/reel.gd.
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
VSIZE = (1000, 700)
CELL = 146.0
GAP = 10.0
GRID_PAD = 14.0
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
# Текстуры ячеек барабанов в превью редактора (buffer + 3 видимых), по колонкам.
REEL_PREVIEW = [
    ["star", "wild", "cherry", "lemon"],
    ["cherry", "wild", "bell", "orange"],
    ["chestbonus", "lemon", "cherry", "orange"],
    ["plum", "watermelon", "plum", "horseshoe"],
    ["orange", "star", "lemon", "cherry"],
]

OUT = []
REG = {}  # имя узла -> последний созданный полный путь (порядок обхода DFS)


def hx(h: str, a: float = 1.0) -> str:
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return f"Color({r:g}, {g:g}, {b:g}, {a:g})"


def tex_uid(key: str) -> str:
    path = os.path.join(ROOT, "img", "slot_machine", key + ".png.import")
    m = re.search(r'uid="(uid://[^"]+)"', open(path).read())
    return m.group(1)


def prop_name(k: str) -> str:
    for g in ("constants", "font_sizes", "colors", "styles"):
        pre = f"theme_override_{g}_"
        if k.startswith(pre):
            return f"theme_override_{g}/" + k[len(pre):]
    return k


def node(name, ntype, parent, uniq=False, **props):
    # В .tscn parent — полный путь от корня; резолвим по реестру создания.
    if parent == ".":
        path = name
        parent_attr = "."
    else:
        base = REG[parent]
        path = base + "/" + name
        parent_attr = base
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


def btn(name, parent, text, size, styles="btn", fs=22, **kw):
    props = {"text": '"' + text + '"',
             "custom_minimum_size": f"Vector2({size[0]}, {size[1]})",
             "theme_override_font_sizes_font_size": fs}
    if styles == "btn":
        props["theme_override_styles_normal"] = 'SubResource("sb_btn_n")'
        props["theme_override_styles_hover"] = 'SubResource("sb_btn_h")'
        props["theme_override_styles_pressed"] = 'SubResource("sb_btn_p")'
    else:
        props["theme_override_styles_normal"] = 'SubResource("sb_gold_n")'
        props["theme_override_styles_hover"] = 'SubResource("sb_gold_h")'
        props["theme_override_styles_pressed"] = 'SubResource("sb_gold_p")'
        props["theme_override_styles_disabled"] = 'SubResource("sb_gold_d")'
        props["theme_override_colors_font_color"] = hx("2a1a08")
        props["theme_override_colors_font_disabled_color"] = hx("2a1a08")
    props.update(kw)
    node(name, "Button", parent, **props)


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


# ------------------------------------------------------------------ ресурсы
ext = ['[ext_resource type="Script" path="res://scripts/slot_machine.gd" '
       'id="scr"]',
       '[ext_resource type="Script" path="res://scripts/reel.gd" '
       'id="scr_reel"]']
for key in KEYS:
    ext.append(f'[ext_resource type="Texture2D" uid="{tex_uid(key)}" '
               f'path="res://img/slot_machine/{key}.png" id="tex_{key}"]')

stylebox("sb_grid", "221730", "d8b45e", 4, 14)
stylebox("sb_popup", "241a31", "d8b45e", 2, 14)
stylebox("sb_gold_n", "e8c06a", "8a6a20", 3, 12)
stylebox("sb_gold_h", "ffd98a", "8a6a20", 3, 12)
stylebox("sb_gold_p", "c79b45", "8a6a20", 3, 12)
stylebox("sb_gold_d", "5a5164", "3c3545", 0, 12)
stylebox("sb_btn_n", "3a2c4d", "7a6399", 2, 10)
stylebox("sb_btn_h", "4a3a61", "9a80bd", 2, 10)
stylebox("sb_btn_p", "2c2139", "7a6399", 2, 10)

# ------------------------------------------------------------------ узлы
OUT.append('\n[node name="game" type="Control" unique_id=1200433587]')
OUT.append("anchor_right = 1.0")
OUT.append("anchor_bottom = 1.0")
OUT.append("grow_horizontal = 2")
OUT.append("grow_vertical = 2")
OUT.append('script = ExtResource("scr")')

node("bg", "ColorRect", ".", color=hx("150e1d"),
     anchor_right=1.0, anchor_bottom=1.0, grow_horizontal=2, grow_vertical=2)
node("machine", "Control", ".", size=f"Vector2({VSIZE[0]}, {VSIZE[1]})")

label("title", "machine", "ЗОЛОТЫЕ БАРАБАНЫ 3×5", 36, "ffd794",
      position="Vector2(0, 2)", size=f"Vector2({VSIZE[0]}, 48)",
      horizontal_alignment=1)

hbox("top_bar", "machine", 12, position="Vector2(30, 56)",
     size=f"Vector2({VSIZE[0] - 60}, 46)")
label("balance_label", "top_bar", "Баланс: 0", 26, "ffe9b8")
spacer("spacer1", "top_bar")
label("win_label", "top_bar", "", 26, "8dffa0", horizontal_alignment=1)
spacer("spacer2", "top_bar")
label("fs_label", "top_bar", "", 26, "7ef3ff", horizontal_alignment=2,
      visible="false")

grid_w = COLS * CELL + (COLS - 1) * GAP
grid_h = ROWS * CELL + (ROWS - 1) * GAP
panel_w, panel_h = grid_w + GRID_PAD * 2, grid_h + GRID_PAD * 2
panel_x = (VSIZE[0] - panel_w) * 0.5
node("grid_panel", "Panel", "machine",
     position=f"Vector2({panel_x:g}, 110)",
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
             stretch_mode=0, mouse_filter=2)

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

hbox("bottom_bar", "machine", 10, position="Vector2(20, 614)",
     size=f"Vector2({VSIZE[0] - 40}, 72)")
btn("bet_minus", "bottom_bar", "−", (52, 56))
label("bet_label", "bottom_bar", "Ставка/линия: 1", 24, "ffe9b8",
      vertical_alignment=1)
btn("bet_plus", "bottom_bar", "+", (52, 56))
label("total_label", "bottom_bar", "Всего: 9", 24, "c9b6e2",
      vertical_alignment=1)
spacer("spacer3", "bottom_bar")
btn("spin_btn", "bottom_bar", "СПИН", (210, 68), styles="gold", fs=30)
spacer("spacer4", "bottom_bar")
btn("paytable_btn", "bottom_bar", "ТАБЛИЦА", (150, 56))
btn("bonus_btn", "bottom_bar", "+1000 МОНЕТ", (190, 56), visible="false")

# ------------------------------------------------------- попап таблицы выплат
node("paytable_popup", "Control", "machine", visible="false",
     anchor_right=1.0, anchor_bottom=1.0)
node("dim", "ColorRect", "paytable_popup", color=hx("000000", 0.78),
     anchor_right=1.0, anchor_bottom=1.0)
node("popup_panel", "Panel", "paytable_popup", position="Vector2(70, 40)",
     size=f"Vector2({VSIZE[0] - 140}, {VSIZE[1] - 80})",
     theme_override_styles_panel='SubResource("sb_popup")')
node("scroll", "ScrollContainer", "popup_panel",
     anchor_right=1.0, anchor_bottom=1.0,
     offset_left=16, offset_top=12, offset_right=-16, offset_bottom=-12)
node("vbox", "VBoxContainer", "scroll", size_flags_horizontal=3,
     theme_override_constants_separation=8)

hbox("head", "vbox", 0)
label("head_title", "head", "ТАБЛИЦА ВЫПЛАТ", 30, "ffd794")
spacer("spacer5", "head")
btn("close_btn", "head", "ЗАКРЫТЬ", (180, 50))

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
