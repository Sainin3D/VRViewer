class_name VrBoard
extends Node3D

## Landscape dashboard for the VR SubViewport (1920x1480).
const BOARD_SIZE := Vector2(2.45, 1.89)
const PLACE_DISTANCE := 1.95
const UI_LAYER := 20

var viewport: SubViewport
var _quad: MeshInstance3D
var _body: StaticBody3D
var _cursor: MeshInstance3D
var _pointer_was_down: Dictionary = {}
var _last_hit_pixel := Vector2.ZERO
var _last_hit_world := Vector3.ZERO
var _has_hit := false


func _ready() -> void:
	_quad = MeshInstance3D.new()
	_quad.name = "PanelQuad"
	var mesh := QuadMesh.new()
	mesh.size = BOARD_SIZE
	_quad.mesh = mesh
	# Face the user (-Z). Collision stays a child so UV space matches the mesh.
	_quad.rotation_degrees.y = 180.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_quad.set_surface_override_material(0, mat)
	add_child(_quad)

	_body = StaticBody3D.new()
	_body.name = "PanelBody"
	_body.collision_layer = 0
	_body.set_collision_layer_value(UI_LAYER, true)
	_body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Thin volume in front of the quad (local +Z after the 180 yaw faces the user as -Z world).
	box.size = Vector3(BOARD_SIZE.x, BOARD_SIZE.y, 0.05)
	col.shape = box
	col.position = Vector3(0.0, 0.0, 0.02)
	_body.add_child(col)
	_quad.add_child(_body)

	_cursor = MeshInstance3D.new()
	_cursor.name = "PointerDot"
	var ball := SphereMesh.new()
	ball.radius = 0.012
	ball.height = 0.024
	_cursor.mesh = ball
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(1.0, 0.85, 0.25, 0.95)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cursor.set_surface_override_material(0, cmat)
	_cursor.visible = false
	add_child(_cursor)

	visible = false
	position = Vector3(0.0, 1.45, -PLACE_DISTANCE)


func use_viewport(vp: SubViewport) -> void:
	viewport = vp
	var mat := _quad.get_surface_override_material(0) as StandardMaterial3D
	if mat:
		mat.albedo_texture = vp.get_texture()


func place_in_front_of(cam: Node3D) -> void:
	var forward := -cam.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	global_position = cam.global_position + forward * PLACE_DISTANCE
	global_position.y = cam.global_position.y - 0.28  # taller board: center lower so top stays in view
	look_at(cam.global_position, Vector3.UP)
	# Keep board upright: kill roll after look_at.
	rotation.z = 0.0


func toggle(cam: Node3D) -> void:
	if visible:
		visible = false
		_cursor.visible = false
		return
	visible = true
	place_in_front_of(cam)


func is_pointing(from: Vector3, dir: Vector3) -> bool:
	return visible and _intersect(from, dir).hit


func last_hit_distance(from: Vector3) -> float:
	if not _has_hit:
		return -1.0
	return from.distance_to(_last_hit_world)


func poll(controller: XRController3D, trigger_down: bool) -> bool:
	if not visible or viewport == null:
		_cursor.visible = false
		_has_hit = false
		return false
	var from := controller.global_position
	var dir := -controller.global_transform.basis.z
	var hit := _intersect(from, dir)
	if not hit.hit:
		if _pointer_was_down.get(controller, false):
			_push_button(_last_hit_pixel, false)
		_pointer_was_down[controller] = false
		_cursor.visible = false
		_has_hit = false
		return false
	_has_hit = true
	_last_hit_pixel = hit.pixel
	_last_hit_world = hit.world
	_cursor.visible = true
	_cursor.global_position = hit.world
	_push_motion(hit.pixel)
	_scroll_hovered(controller, hit.pixel)
	var was: bool = _pointer_was_down.get(controller, false)
	if trigger_down and not was:
		_push_button(hit.pixel, true)
	elif not trigger_down and was:
		_push_button(hit.pixel, false)
	_pointer_was_down[controller] = trigger_down
	return true


func _intersect(from: Vector3, dir: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	if space == null:
		return {"hit": false, "pixel": Vector2.ZERO, "world": Vector3.ZERO}
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 8.0)
	q.collision_mask = 1 << (UI_LAYER - 1)
	q.collide_with_areas = false
	var res := space.intersect_ray(q)
	if res.is_empty():
		return {"hit": false, "pixel": Vector2.ZERO, "world": Vector3.ZERO}
	# Body is parented under the rotated quad — local XY matches the QuadMesh.
	var local: Vector3 = _quad.to_local(res.position)
	var uv := Vector2(
		(local.x / BOARD_SIZE.x) + 0.5,
		1.0 - ((local.y / BOARD_SIZE.y) + 0.5)
	)
	uv.x = clampf(uv.x, 0.0, 1.0)
	uv.y = clampf(uv.y, 0.0, 1.0)
	var pixel := Vector2(uv.x * float(viewport.size.x), uv.y * float(viewport.size.y))
	return {"hit": true, "pixel": pixel, "world": res.position}


func _scroll_hovered(controller: XRController3D, pixel: Vector2) -> void:
	var dy := 0.0
	var stick := controller.get_vector2("primary")
	var pad := controller.get_vector2("trackpad")
	if absf(stick.y) > 0.18:
		dy += stick.y
	if absf(pad.y) > 0.18:
		dy += pad.y
	if is_zero_approx(dy):
		return
	# Mouse wheel is the most reliable scroll for Tree / ScrollContainer / lists.
	_push_wheel(pixel, dy)
	var hovered := viewport.gui_get_hovered_control()
	var tree := _find_ancestor(hovered, "Tree") as Tree
	if tree and tree.has_method("get_scroll"):
		var cur: Vector2 = tree.get_scroll()
		tree.set("scroll_vertical", cur.y - dy * 48.0)
	var list := _find_ancestor(hovered, "ItemList") as ItemList
	if list:
		var bar := list.get_v_scroll_bar()
		if bar:
			bar.value -= dy * 40.0
	var scroll := _find_ancestor(hovered, "ScrollContainer") as ScrollContainer
	if scroll == null:
		scroll = _find_scroll(viewport)
	if scroll:
		scroll.scroll_vertical -= int(dy * 36.0)


func _find_ancestor(node: Node, type_name: String) -> Node:
	var n := node
	while n:
		if n.get_class() == type_name:
			return n
		n = n.get_parent()
	return null


func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node as ScrollContainer
	for child in node.get_children():
		var found := _find_scroll(child)
		if found:
			return found
	return null


func _push_motion(pixel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pixel
	ev.global_position = pixel
	viewport.push_input(ev, true)


func _push_button(pixel: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pixel
	ev.global_position = pixel
	viewport.push_input(ev, true)


func _push_wheel(pixel: Vector2, dy: float) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_WHEEL_UP if dy > 0.0 else MOUSE_BUTTON_WHEEL_DOWN
	ev.pressed = true
	ev.factor = clampf(absf(dy), 0.2, 3.0)
	ev.position = pixel
	ev.global_position = pixel
	viewport.push_input(ev, true)
	var ev_up := ev.duplicate() as InputEventMouseButton
	ev_up.pressed = false
	viewport.push_input(ev_up, true)
