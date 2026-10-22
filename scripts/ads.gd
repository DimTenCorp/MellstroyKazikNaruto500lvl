class_name Ads
extends RefCounted
## Стики-баннер платформы (Playgama Bridge): запрашиваем один раз за запуск.
## Веб-обёртка (index.html) переносит баннер в правую колонку и держит
## игровую область слева, чтобы баннер не закрывал игру.
static var _done := false


static func ensure_banner() -> void:
	if _done:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var br := tree.root.get_node_or_null("Bridge")
	if br == null or br.advertisement == null:
		return
	if not bool(br.advertisement.is_banner_supported):
		_done = true   ## платформа без баннеров — повторять бессмысленно
		return
	br.advertisement.show_banner()
	_done = true
	print("[ads] запрошен стики-баннер платформы")
