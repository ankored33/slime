class_name ToolActionRegistry
extends RefCounted

## Maps a held tool to its secondary-action request. Input handling only asks
## this registry for a request; adding a tool no longer requires another
## brush-id branch in GameScreenBrushes.

var _handlers: Dictionary = {}

func _init() -> void:
	register_action("candle", _wax_drop_request)
	register_action("teeth", _bite_request)
	register_action("finger", _pinch_request)
	register_action("clip", _pinch_request)
	register_action("tongue", _kiss_request)

func register_action(brush_id: String, handler: Callable) -> void:
	_handlers[brush_id] = handler

func request_for(brush: Brush) -> Dictionary:
	if brush == null:
		return {}
	var handler: Callable = _handlers.get(brush.brush_id, Callable())
	return handler.call(brush) if handler.is_valid() else {}

func _wax_drop_request(brush: Brush) -> Dictionary:
	return {"wax_origin": brush.position + Vector2(0.0, brush.hit_radius * 0.7)}

func _bite_request(_brush: Brush) -> Dictionary:
	return {"bite_requested": true}

func _pinch_request(_brush: Brush) -> Dictionary:
	return {"pinch_requested": true}

func _kiss_request(_brush: Brush) -> Dictionary:
	return {"kiss_requested": true}
