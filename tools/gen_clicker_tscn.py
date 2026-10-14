#!/usr/bin/env python3
"""Генератор scenes/clicker.tscn: сцена кликера «Бабло».

Перезаписывает scenes/clicker.tscn целиком:
    python3 tools/gen_clicker_tscn.py
Весь UI — узлы сцены. Спрайты вырезаются атласами из
img/buttons_clicker.png (монета «БАБЛО», кнопка play, мешок денег)
и img/money_icon.png (иконка баланса).
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VSIZE = (1280, 720)

# Регионы img/buttons_clicker.png (x, y, w, h) — посчитаны по альфе листа.
CLICKER_REGIONS = {
    "money": (25, 28, 288, 273),   # стопка купюр
    "play": (375, 25, 280, 276),   # кнопка play (реклама)
    "bag": (726, 17, 274, 284),    # мешок денег
    "coin": (20, 323, 278, 287),   # монета «БАБЛО»
}

OUT = []
REG = {}


def hx(h: str, a: float = 1.0) -> str:
    r, g, b = (int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    return f"Color({r:g}, {g:g}, {b:g}, {a:g})"


def res_uid(path: str) -> str:
    m = re.search(r'uid="(uid://[^"]+)"',
                  open(os.path.join(ROOT, path) + ".import").read())
    return m.group(1)


def prop_name(k: str) -> str:
    for g in ("constants", "font_sizes", "colors", "styles"):
        pre = f"theme_override_{g}_"
        if k.startswith(pre):
            return f"theme_override_{g}/" + k[len(pre):]
    return k


def node(name, ntype, parent, **props):
    if parent == ".":
        path, parent_attr = name, "."
    else:
        base = REG[parent]
        path, parent_attr = base + "/" + name, base
    REG[name] = path
    OUT.append(f'\n[node name="{name}" type="{ntype}" '
               f'parent="{parent_attr}"]')
    for k, v in props.items():
        OUT.append(f"{prop_name(k)} = {v}")


def label(name, parent, text, fs, color, **kw):
    props = {"text": '"' + text + '"',
             "theme_override_font_sizes_font_size": fs,
             "theme_override_colors_font_color": hx(color)}
    props.update(kw)
    node(name, "Label", parent, **props)


def stylebox(sid, bg, border=None, width=0, radius=10):
    OUT.append(f'\n[sub_resource type="StyleBoxFlat" id="{sid}"]')
    OUT.append(f"bg_color = {hx(bg)}")
    if width:
        for side in ("left", "top", "right", "bottom"):
            OUT.append(f"border_width_{side} = {width}")
        OUT.append(f"border_color = {hx(border)}")
    for c in ("top_left", "top_right", "bottom_left", "bottom_right"):
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
ext = ['[ext_resource type="Script" path="res://scripts/clicker.gd" '
       'id="scr"]',
       f'[ext_resource type="Texture2D" uid="{res_uid("img/upgrades/upgrades.png")}" '
       'path="res://img/upgrades/upgrades.png" id="tex_upgrades"]',
       f'[ext_resource type="Texture2D" uid="{res_uid("img/background/back2.jpg")}" '
       'path="res://img/background/back2.jpg" id="tex_back2"]',
       f'[ext_resource type="Texture2D" uid="{res_uid("img/buttons_clicker.png")}" '
       'path="res://img/buttons_clicker.png" id="tex_clicker"]',
       f'[ext_resource type="Texture2D" uid="{res_uid("img/money_icon.png")}" '
       'path="res://img/money_icon.png" id="tex_money"]']

stylebox("sb_btn_n", "3a2c4d", "7a6399", 2, 10)
for key in ("coin", "play", "bag"):
    atlassub("at_" + key, "tex_clicker", CLICKER_REGIONS[key])

# ------------------------------------------------------------------ узлы
OUT.append('\n[node name="clicker" type="Control"]')
OUT.append("anchor_right = 1.0")
OUT.append("anchor_bottom = 1.0")
OUT.append("grow_horizontal = 2")
OUT.append("grow_vertical = 2")
OUT.append('script = ExtResource("scr")')

node("bg", "TextureRect", ".", texture='ExtResource("tex_back2")',
     anchor_right=1.0, anchor_bottom=1.0, grow_horizontal=2, grow_vertical=2,
     stretch_mode=6, mouse_filter=2)
node("bg_dim", "ColorRect", ".", color=hx("140a20", 0.55),
     anchor_right=1.0, anchor_bottom=1.0, grow_horizontal=2, grow_vertical=2,
     mouse_filter=2)
node("machine", "Control", ".", size=f"Vector2({VSIZE[0]}, {VSIZE[1]})")

# верх: иконка денег + баланс
node("hud_icon", "TextureRect", "machine",
     texture='ExtResource("tex_money")',
     position="Vector2(30, 14)", size="Vector2(66, 61)",
     expand_mode=1, stretch_mode=5, mouse_filter=2)
label("hud_balance", "machine", "0", 28, "ffe9b8",
      position="Vector2(104, 24)", size="Vector2(320, 38)",
      theme_override_constants_outline_size=8,
      theme_override_colors_font_outline_color=hx("402008"))

# монета-кликер (в сцене родной размер региона, визуальный ставит скрипт)
tbtn("coin_btn", "machine", "at_coin", (480, 165), (320, 330))
label("click_hint", "machine", "+5 за клик", 22, "9d8fb8",
      position="Vector2(480, 508)", size="Vector2(320, 30)",
      horizontal_alignment=1)

# play = реклама с наградой
tbtn("play_btn", "machine", "at_play", (1060, 462), (200, 197))
label("play_caption", "machine", "РЕКЛАМА: +500", 20, "8dffa0",
      position="Vector2(1000, 674)", size="Vector2(270, 28)",
      horizontal_alignment=1)

# прокручиваемый список всех улучшений (строки — узлы сцены)
node("upg_scroll", "ScrollContainer", "machine",
     position="Vector2(900, 20)", size="Vector2(372, 420)")
node("upg_vbox", "VBoxContainer", "upg_scroll",
     size_flags_horizontal=3,
     theme_override_constants_separation=6)
node("upg0_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg0_btn", "TextureButton", "upg0_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg0_info", "upg0_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)
node("upg1_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg1_btn", "TextureButton", "upg1_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg1_info", "upg1_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)
node("upg2_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg2_btn", "TextureButton", "upg2_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg2_info", "upg2_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)
node("upg3_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg3_btn", "TextureButton", "upg3_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg3_info", "upg3_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)
node("upg4_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg4_btn", "TextureButton", "upg4_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg4_info", "upg4_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)
node("upg5_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg5_btn", "TextureButton", "upg5_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg5_info", "upg5_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)
node("upg6_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg6_btn", "TextureButton", "upg6_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg6_info", "upg6_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)
node("upg7_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg7_btn", "TextureButton", "upg7_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg7_info", "upg7_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)
node("upg8_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg8_btn", "TextureButton", "upg8_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg8_info", "upg8_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)
node("upg9_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg9_btn", "TextureButton", "upg9_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg9_info", "upg9_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)
node("upg10_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg10_btn", "TextureButton", "upg10_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg10_info", "upg10_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)
node("upg11_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg11_btn", "TextureButton", "upg11_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg11_info", "upg11_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)
node("upg12_row", "HBoxContainer", "upg_vbox",
     theme_override_constants_separation=6)
node("upg12_btn", "TextureButton", "upg12_row",
     ignore_texture_size="true", stretch_mode=5,
     custom_minimum_size="Vector2(56, 56)")
label("upg12_info", "upg12_row", "", 13, "9d8fb8",
      size_flags_horizontal=3, vertical_alignment=1)

# строки статуса заработка слева под балансом (разметка заказчика)
label("auto_stat", "machine", "авт. бабло: 0/с", 20, "ffe9b8",
      position="Vector2(30, 91)", size="Vector2(300, 24)",
      theme_override_constants_outline_size=6,
      theme_override_colors_font_outline_color=hx("402008"))
label("click_stat", "machine", "бабло за клик: 5", 20, "ffe9b8",
      position="Vector2(26, 127)", size="Vector2(300, 24)",
      theme_override_constants_outline_size=6,
      theme_override_colors_font_outline_color=hx("402008"))

# возврат к слот-машине
node("back_btn", "Button", "machine", text='"← К СЛОТАМ"',
     position="Vector2(30, 640)", size="Vector2(230, 56)",
     theme_override_font_sizes_font_size=20,
     theme_override_styles_normal='SubResource("sb_btn_n")',
     theme_override_styles_hover='SubResource("sb_btn_n")',
     theme_override_styles_pressed='SubResource("sb_btn_n")')

# баннер и слой всплывающих «+N»
label("msg_label", "machine", "", 40, "ffffff", horizontal_alignment=1,
      position="Vector2(0, 86)", size=f"Vector2({VSIZE[0]}, 60)",
      theme_override_constants_outline_size=10,
      theme_override_colors_font_outline_color=hx("3a1d6e"), visible="false")
node("float_layer", "Control", "machine",
     position="Vector2(0, 0)", size=f"Vector2({VSIZE[0]}, {VSIZE[1]})",
     mouse_filter=2)

# ------------------------------------------------------------------ сборка
body = "\n".join(OUT)
n_sub = body.count("\n[sub_resource ")
n_ext = len(ext)
header = (f"[gd_scene load_steps={n_ext + n_sub + 1} format=3 "
          f'uid="uid://cpkkdr77qsj4v"]\n\n' + "\n".join(ext) + "\n")
with open(os.path.join(ROOT, "scenes", "clicker.tscn"), "w") as f:
    f.write(header + body + "\n")
print("nodes:", body.count("\n[node "), "| sub_resources:", n_sub,
      "| ext_resources:", n_ext)
