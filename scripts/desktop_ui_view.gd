class_name DesktopUiView
extends TextureRect

## Forwards mouse + keyboard into the UI SubViewport. Physical keys only reach
## this control when it has focus; we grab focus on click so LineEdits work.

var target: SubViewport


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _gui_input(event: InputEvent) -> void:
	if target == null:
		return
	if event is InputEventMouseButton and event.pressed:
		grab_focus()
	if event is InputEventMouse:
		var scaled := event.duplicate() as InputEventMouse
		var sz := size
		if sz.x < 1.0 or sz.y < 1.0:
			return
		var vp_size := Vector2(target.size)
		scaled.position = Vector2(
			event.position.x * vp_size.x / sz.x,
			event.position.y * vp_size.y / sz.y
		)
		scaled.global_position = scaled.position
		target.push_input(scaled, true)
		accept_event()
	else:
		# Keys / actions while the panel is focused.
		target.push_input(event, true)
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	# Catch keys even if a 3D control tried to take them, while the cursor is over us.
	if target == null:
		return
	if event is InputEventKey and (has_focus() or get_global_rect().has_point(get_viewport().get_mouse_position())):
		target.push_input(event, true)
		get_viewport().set_input_as_handled()
