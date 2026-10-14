extends Node
## Playgama Bridge (https://github.com/playgama/browser-games-bridge) —
## единый мост к SDK площадок (Yandex Games, Poki, CrazyGames, VK и др.).
## В веб-сборке подключает web/bridge.js (лежит рядом с index.html),
## в редакторе работает мок: реклама считается досмотренной.
##
## Использование:
##   var res: Dictionary = await Bridge.show_rewarded()   # {success, rewarded}
##   Bridge.gameplay_start() / Bridge.gameplay_stop()
##   Bridge.platform_id()  # "yandex", "poki", ... или "editor"

const BRIDGE_JS := "bridge.js"
const READY_TIMEOUT := 6.0
const AD_TIMEOUT := 90.0

var _bridge_ready := false


func _ready() -> void:
	if is_web():
		_load_bridge()


func is_web() -> bool:
	return OS.has_feature("web")


## Инжектит bridge.js в страницу и ждёт появления window.bridge.
func _load_bridge() -> void:
	JavaScriptBridge.evaluate("""
		(function () {
			if (window.bridge || window.playgamaBridge) { window.__bridge_ready = true; return; }
			window.__bridge_ready = false;
			var s = document.createElement('script');
			s.src = '%s';
			s.onload = function () { window.__bridge_ready = true; };
			s.onerror = function () { window.__bridge_ready = false; };
			document.head.appendChild(s);
		})();
	""" % BRIDGE_JS)
	var waited := 0.0
	while waited < READY_TIMEOUT:
		if _eval_bool("window.__bridge_ready === true && !!(window.bridge || window.playgamaBridge)"):
			_bridge_ready = true
			return
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	push_warning("Playgama Bridge: не удалось загрузить %s" % BRIDGE_JS)


func is_ready() -> bool:
	return _bridge_ready


func platform_id() -> String:
	if not is_web():
		return "editor"
	if not _bridge_ready:
		return "unknown"
	return str(JavaScriptBridge.evaluate("String((window.bridge || window.playgamaBridge).platformId)"))


## Пауза игровой логики площадки во время рекламы/меню (не обязательна
## на всех платформах, но рекомендуется).
func gameplay_start() -> void:
	if is_web() and _bridge_ready:
		JavaScriptBridge.evaluate("(window.bridge || window.playgamaBridge).gameplay.start()")


func gameplay_stop() -> void:
	if is_web() and _bridge_ready:
		JavaScriptBridge.evaluate("(window.bridge || window.playgamaBridge).gameplay.stop()")


## Показ рекламы с наградой. Возвращает Dictionary:
## { "success": bool, "rewarded": bool, "mock": bool, "error": String }
func show_rewarded() -> Dictionary:
	if not is_web():
		# Мок для редактора: имитируем досмотр, чтобы тестировать награды.
		await get_tree().create_timer(1.0).timeout
		return {"success": true, "rewarded": true, "mock": true, "error": ""}
	if not _bridge_ready:
		return {"success": false, "rewarded": false, "mock": false,
				"error": "bridge not ready"}
	JavaScriptBridge.evaluate("""
		window.__rw = { reward: false, closed: false, failed: false };
		(window.bridge || window.playgamaBridge).advertisement.showRewarded({
			onRewarded: function () { window.__rw.reward = true; },
			onClose: function () { window.__rw.closed = true; },
			onClosed: function () { window.__rw.closed = true; },
			onFailed: function () { window.__rw.failed = true; }
		});
	""")
	var waited := 0.0
	while waited < AD_TIMEOUT:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
		if _eval_bool("window.__rw && (window.__rw.closed || window.__rw.failed)"):
			break
	var rewarded := _eval_bool("window.__rw && window.__rw.reward")
	var failed := _eval_bool("window.__rw && window.__rw.failed")
	return {"success": not failed, "rewarded": rewarded, "mock": false,
			"error": "ad failed" if failed else ""}


## Межстраничная реклама (например, между сессиями) — без награды.
func show_interstitial() -> void:
	if is_web() and _bridge_ready:
		JavaScriptBridge.evaluate(
			"(window.bridge || window.playgamaBridge).advertisement.showInterstitial()")


func _eval_bool(code: String) -> bool:
	return str(JavaScriptBridge.evaluate(code)) == "true"
