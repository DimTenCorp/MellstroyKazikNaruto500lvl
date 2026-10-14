
const BridgeTypes := preload("res://addons/playgama_bridge/bridge_types.gd")
var type : get = _type_getter

func _type_getter():
	match OS.get_name():
		"Android":
			return BridgeTypes.DeviceType.MOBILE
		_:
			return BridgeTypes.DeviceType.DESKTOP
