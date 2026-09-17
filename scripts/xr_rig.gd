class_name XRRig
extends XROrigin3D

signal xr_started
signal xr_stopped
signal status_changed(text: String)

@export var move_speed := 2.2
@export var snap_degrees := 45.0
@export var grab_ray_length := 8.0
const GRAB_REACH := 0.28

var assembly: ModelAssembly
var xr_interface: XRInterface
var xr_active := false

var _left: XRController3D
var _right: XRController3D
var _camera: XRCamera3D
var _left_laser: MeshInstance3D
var _right_laser: MeshInstance3D
var board: VrBoard
var passthrough_on := false

var _grip_left := false
var _grip_right := false
var _trigger_left := false
var _trigger_right := false
var _one_hand: XRController3D
var _grab_offset := Transform3D.IDENTITY
var _grab_part: Node3D
var _part_offset := Transform3D.IDENTITY
var _two_hand := false
var _th_dist := 1.0
var _th_scale := 1.0
var _th_mid := Vector3.ZERO
var _th_xf := Transform3D.IDENTITY
var _th_left := Vector3.ZERO
var _th_right := Vector3.ZERO
var _did_snap := false
var _did_raise := false


func _ready() -> void:
	_build()
	visible = false
	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface:
		xr_interface.pose_recentered.connect(_on_recentered)


func is_openxr_ready() -> bool:
	return xr_interface != null and xr_interface.is_initialized()


func headset_camera() -> XRCamera3D:
	return _camera


func start_session() -> bool:
	if xr_interface == null:
		xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface == null:
		status_changed.emit("OpenXR interface not found. Enable XR in project settings.")
		return false
	if not xr_interface.is_initialized():
		if not xr_interface.initialize():
			status_changed.emit("OpenXR is not running. Start SteamVR with the headset on, then relaunch the app and click Enter VR.")
			return false
	var vp := get_tree().root
	vp.use_xr = true
	vp.physics_object_picking = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if RenderingServer.get_rendering_device() != null:
		vp.vrs_mode = Viewport.VRS_XR
	xr_active = true
	visible = true
	if _camera:
		_camera.make_current()
	Engine.physics_ticks_per_second = 90
	if not XRServer.tracker_added.is_connected(_on_tracker_added):
		XRServer.tracker_added.connect(_on_tracker_added)
	_sync_controllers()
	_ensure_render_models()
	if board:
		board.visible = true
		board.place_in_front_of(_camera)
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if board and _camera and xr_active:
				board.place_in_front_of(_camera)
		)
	status_changed.emit("VR: A shows or hides the board. Trigger clicks the board or grabs the model.")
	xr_started.emit()
	return true


func stop_session() -> void:
	set_passthrough(false)
	if get_viewport().use_xr:
		get_viewport().use_xr = false
	xr_active = false
	visible = false
	if _camera:
		_camera.current = false
	if get_tree().root.use_xr:
		get_tree().root.use_xr = false
	if xr_interface and xr_interface.is_initialized() and xr_interface.has_method("uninitialize"):
		xr_interface.uninitialize()
	_reset_grabs()
	status_changed.emit("VR session ended.")
	xr_stopped.emit()


func set_passthrough(enabled: bool) -> Dictionary:
	if not enabled:
		if passthrough_on:
			XrPassthrough.disable(xr_interface, get_tree().root)
			passthrough_on = false
		return {"ok": true, "message": "Passthrough off."}
	if xr_interface == null or not xr_interface.is_initialized():
		return {
			"ok": false,
			"message": "Passthrough needs an active VR session. Start SteamVR, Enter VR, then choose Passthrough."
		}
	var result: Dictionary = XrPassthrough.enable(xr_interface, get_tree().root)
	passthrough_on = bool(result.get("ok", false))
	return result


func _build() -> void:
	_camera = XRCamera3D.new()
	_camera.name = "XRCamera3D"
	_camera.position = Vector3(0, 1.7, 0)
	_camera.near = 0.01
	_camera.far = 4000.0
	add_child(_camera)

	_left = _make_controller("LeftHand", "left_hand", Vector3(-0.25, 1.0, -0.3))
	_right = _make_controller("RightHand", "right_hand", Vector3(0.25, 1.0, -0.3))
	_left_laser = _left.get_node("Laser") as MeshInstance3D
	_right_laser = _right.get_node("Laser") as MeshInstance3D
	board = VrBoard.new()
	board.name = "VrBoard"
	add_child(board)


func _make_controller(node_name: String, tracker: String, preview: Vector3) -> XRController3D:
	var c := XRController3D.new()
	c.name = node_name
	c.tracker = tracker
	c.pose = &"default"
	c.position = preview
	add_child(c)
	c.button_pressed.connect(_on_controller_button.bind(c))

	var body := MeshInstance3D.new()
	body.name = "FallbackMesh"
	var box := BoxMesh.new()
	box.size = Vector3(0.09, 0.09, 0.18)
	body.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.45, 0.08)
	body.set_surface_override_material(0, mat)
	c.add_child(body)
	var tip := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.035
	ball.height = 0.07
	tip.mesh = ball
	tip.position = Vector3(0, 0, -0.11)
	tip.set_surface_override_material(0, mat)
	c.add_child(tip)

	var laser := MeshInstance3D.new()
	laser.name = "Laser"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.003
	cyl.bottom_radius = 0.003
	cyl.height = 2.4
	laser.mesh = cyl
	laser.rotation_degrees.x = -90
	laser.position.z = -1.2
	var laser_mat := StandardMaterial3D.new()
	laser_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	laser_mat.albedo_color = Color(0.45, 0.75, 1.0, 0.45)
	laser_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	laser.set_surface_override_material(0, laser_mat)
	c.add_child(laser)
	return c


func _process(delta: float) -> void:
	if not xr_active:
		return
	_sync_controllers()
	var tl := _is_trigger(_left)
	var tr := _is_trigger(_right)
	var ui_l := false
	var ui_r := false
	if board and board.visible:
		ui_l = board.poll(_left, tl)
		ui_r = board.poll(_right, tr)
		_update_laser(_left, _left_laser, ui_l)
		_update_laser(_right, _right_laser, ui_r)
	else:
		_set_laser_idle(_left_laser)
		_set_laser_idle(_right_laser)
	var want_l := tl and not ui_l
	var want_r := tr and not ui_r
	var start_l := want_l and not _grip_left
	var start_r := want_r and not _grip_right
	var end_l := not want_l and _grip_left
	var end_r := not want_r and _grip_right
	_grip_left = want_l
	_grip_right = want_r
	_trigger_left = tl
	_trigger_right = tr
	if start_l or start_r:
		if _grip_left and _grip_right:
			if _in_grab_reach(_left) and _in_grab_reach(_right):
				_begin_two_hand()
			elif start_l:
				_on_grip_start(_left, false)
			elif start_r:
				_on_grip_start(_right, false)
		else:
			if start_l:
				_on_grip_start(_left, false)
			if start_r:
				_on_grip_start(_right, false)
	if end_l:
		_on_grip_end(_left)
	if end_r:
		_on_grip_end(_right)
	_update_raise()
	_update_grab()
	if not _two_hand and not ui_l and not ui_r:
		_locomotion(delta)



func _update_laser(controller: XRController3D, laser: MeshInstance3D, on_ui: bool) -> void:
	if laser == null or controller == null:
		return
	var dist := 2.4
	if on_ui and board:
		var d := board.last_hit_distance(controller.global_position)
		if d > 0.05:
			dist = clampf(d, 0.2, 4.0)
	var cyl := laser.mesh as CylinderMesh
	if cyl:
		cyl.height = dist
	laser.position.z = -dist * 0.5
	var mat := laser.get_surface_override_material(0) as StandardMaterial3D
	if mat:
		if on_ui:
			mat.albedo_color = Color(1.0, 0.9, 0.35, 0.85)
		else:
			mat.albedo_color = Color(0.45, 0.75, 1.0, 0.35)
	laser.visible = true


func _set_laser_idle(laser: MeshInstance3D) -> void:
	if laser == null:
		return
	var cyl := laser.mesh as CylinderMesh
	if cyl:
		cyl.height = 2.4
	laser.position.z = -1.2
	var mat := laser.get_surface_override_material(0) as StandardMaterial3D
	if mat:
		mat.albedo_color = Color(0.45, 0.75, 1.0, 0.35)


func _on_grip_start(controller: XRController3D, with_trigger: bool) -> void:
	if board and board.is_pointing(controller.global_position, -controller.global_transform.basis.z):
		return
	if assembly == null:
		return
	var part := assembly.nearest_part(controller.global_position, GRAB_REACH)
	if part == null:
		return
	_haptic(controller)
	if _grip_left and _grip_right:
		var other := _right if controller == _left else _left
		var other_part := assembly.nearest_part(other.global_position, GRAB_REACH)
		if other_part == part or other_part != null:
			_grab_part = part
			_begin_two_hand()
			return
	_one_hand = controller
	_grab_part = part
	_part_offset = controller.global_transform.affine_inverse() * part.global_transform


func _on_grip_end(controller: XRController3D) -> void:
	if _two_hand:
		_two_hand = false
		var other := _right if controller == _left else _left
		if _is_trigger(other) and _grab_part and is_instance_valid(_grab_part):
			_one_hand = other
			_part_offset = other.global_transform.affine_inverse() * _grab_part.global_transform
		else:
			_reset_grabs()
		return
	if _one_hand == controller:
		_one_hand = null
		_grab_part = null


func _begin_two_hand() -> void:
	if assembly == null:
		return
	if _grab_part == null or not is_instance_valid(_grab_part):
		_grab_part = assembly.nearest_part((_left.global_position + _right.global_position) * 0.5, GRAB_REACH * 2.0)
	if _grab_part == null:
		return
	_two_hand = true
	_one_hand = null
	_th_left = _left.global_position
	_th_right = _right.global_position
	_th_dist = maxf(_th_left.distance_to(_th_right), 0.01)
	_th_scale = _grab_part.global_transform.basis.get_scale().x
	_th_mid = (_th_left + _th_right) * 0.5
	_th_xf = _grab_part.global_transform


func _update_grab() -> void:
	if assembly == null:
		return
	if _two_hand and _grip_left and _grip_right:
		_apply_two_hand()
		return
	if _grab_part and is_instance_valid(_grab_part) and _one_hand:
		_grab_part.global_transform = _one_hand.global_transform * _part_offset


func _apply_two_hand() -> void:
	if _grab_part == null or not is_instance_valid(_grab_part):
		return
	var mid := (_left.global_position + _right.global_position) * 0.5
	var dist := _left.global_position.distance_to(_right.global_position)
	var factor := dist / _th_dist
	var new_scale := maxf(_th_scale * factor, 0.0001)
	var local := _th_xf.affine_inverse() * _th_mid
	var basis := _th_xf.basis.orthonormalized()
	var start_flat := _th_right - _th_left
	start_flat.y = 0.0
	var now_flat := _right.global_position - _left.global_position
	now_flat.y = 0.0
	if start_flat.length() > 0.02 and now_flat.length() > 0.02:
		basis = Basis(Quaternion(start_flat.normalized(), now_flat.normalized())) * basis
	var scaled: Basis = basis.scaled(Vector3.ONE * new_scale)
	_grab_part.global_transform = Transform3D(scaled, mid - scaled * local)


func _locomotion(delta: float) -> void:
	var move := _stick(_left)
	if move.length() > 0.15:
		var basis := _camera.global_transform.basis
		var forward := -basis.z
		forward.y = 0.0
		var right := basis.x
		right.y = 0.0
		if forward.length_squared() > 0.0001:
			forward = forward.normalized()
		if right.length_squared() > 0.0001:
			right = right.normalized()
		var dir := (right * move.x + forward * move.y)
		global_position += dir * move_speed * delta

	var turn := _stick(_right).x
	if absf(turn) > 0.7:
		if not _did_snap:
			rotate_y(deg_to_rad(-snap_degrees * signf(turn)))
			_did_snap = true
	elif absf(turn) < 0.35:
		_did_snap = false


func _pick(controller: XRController3D) -> Node3D:
	if assembly == null:
		return null
	var part := assembly.pick_part(controller.global_position, -controller.global_transform.basis.z)
	if part == null:
		return null
	var box := assembly.world_aabb()
	if _distance_to_aabb(controller.global_position, box) > GRAB_REACH:
		return null
	return part


func _in_grab_reach(controller: XRController3D) -> bool:
	if assembly == null or controller == null or assembly.parts.is_empty():
		return false
	return assembly.nearest_part(controller.global_position, GRAB_REACH) != null


func _distance_to_aabb(p: Vector3, box: AABB) -> float:
	var min_p := box.position
	var max_p := box.position + box.size
	var closest := Vector3(
		clampf(p.x, min_p.x, max_p.x),
		clampf(p.y, min_p.y, max_p.y),
		clampf(p.z, min_p.z, max_p.z)
	)
	return p.distance_to(closest)


func _ray_hits_assembly(controller: XRController3D) -> bool:
	return _in_grab_reach(controller)


func _is_grip(c: XRController3D) -> bool:
	if _axis(c, ["grip", "squeeze", "squeeze_value"]) > 0.55:
		return true
	return _pressed(c, ["grip_click", "squeeze", "squeeze_click"])


func _is_trigger(c: XRController3D) -> bool:
	if _axis(c, ["trigger", "trigger_value"]) > 0.65:
		return true
	return _pressed(c, ["trigger_click", "select_button", "select"])


func _stick(c: XRController3D) -> Vector2:
	var v := _vec2(c, ["primary", "thumbstick", "trackpad"])
	return v


func _axis(c: XRController3D, names: PackedStringArray) -> float:
	if c == null:
		return 0.0
	for n in names:
		var v := c.get_float(n)
		if absf(v) > 0.01:
			return v
	return _tracker_float(c, names)


func _pressed(c: XRController3D, names: PackedStringArray) -> bool:
	if c == null:
		return false
	for n in names:
		if c.is_button_pressed(n):
			return true
	return _tracker_float(c, names) > 0.5


func _vec2(c: XRController3D, names: PackedStringArray) -> Vector2:
	if c == null:
		return Vector2.ZERO
	for n in names:
		var v := c.get_vector2(n)
		if v != Vector2.ZERO:
			return v
	var t := _tracker_of(c)
	if t:
		for n in names:
			var inp: Variant = t.get_input(n)
			if typeof(inp) == TYPE_VECTOR2 and inp != Vector2.ZERO:
				return inp
	return Vector2.ZERO


func _tracker_float(c: XRController3D, names: PackedStringArray) -> float:
	var t := _tracker_of(c)
	if t == null:
		return 0.0
	for n in names:
		var inp: Variant = t.get_input(n)
		if typeof(inp) == TYPE_FLOAT and absf(float(inp)) > 0.01:
			return float(inp)
		if typeof(inp) == TYPE_BOOL and inp:
			return 1.0
	return 0.0


func _tracker_of(c: XRController3D) -> XRPositionalTracker:
	if c == null or str(c.tracker) == "":
		return null
	var t := XRServer.get_tracker(c.tracker)
	if t is XRPositionalTracker:
		return t
	return null


func _haptic(c: XRController3D) -> void:
	c.trigger_haptic_pulse("haptic", 0.0, 0.6, 0.08, 0.0)


func raise_board() -> void:
	if board == null or _camera == null:
		return
	board.toggle(_camera)
	_haptic(_left)
	_haptic(_right)


func _update_raise() -> void:
	var want := _is_raise(_left) or _is_raise(_right)
	if want and not _did_raise:
		_did_raise = true
		raise_board()
	elif not want:
		_did_raise = false


func _is_raise(c: XRController3D) -> bool:
	if c == null:
		return false
	return c.is_button_pressed("ax_button") or c.is_button_pressed("menu_button")


func _on_controller_button(button: String, _controller: XRController3D) -> void:
	if button == "ax_button" or button == "menu_button" or button == "by_button":
		raise_board()


func _on_recentered() -> void:
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	raise_board()


func _on_tracker_added(_tracker_name: StringName, _type: int) -> void:
	_sync_controllers()


func _sync_controllers() -> void:
	var left_name := &""
	var right_name := &""
	var extras: Array[StringName] = []
	var all: Dictionary = XRServer.get_trackers(XRServer.TRACKER_ANY)
	for id in all:
		var tracker: XRTracker = all[id]
		if tracker == null:
			continue
		var ns := str(tracker.name).to_lower()
		if ns.contains("head") or ns.contains("hand_tracker") or ns.contains("body") or ns.contains("face"):
			continue
		if tracker is XRPositionalTracker:
			pass
		elif tracker.get_class() != "XRControllerTracker":
			continue
		var n := StringName(str(tracker.name))
		var hand := 0
		if tracker is XRPositionalTracker:
			hand = int((tracker as XRPositionalTracker).hand)
		if hand == 1 or ns.contains("left"):
			left_name = n
		elif hand == 2 or ns.contains("right"):
			right_name = n
		else:
			extras.append(n)
	if left_name == &"" and extras.size() > 0:
		left_name = extras[0]
	if right_name == &"" and extras.size() > 1:
		right_name = extras[1]
	if left_name != &"":
		_left.tracker = left_name
	else:
		_try_tracker(_left, [&"left_hand", &"/user/hand/left"])
	if right_name != &"":
		_right.tracker = right_name
	else:
		_try_tracker(_right, [&"right_hand", &"/user/hand/right"])
	_bind_best_pose(_left)
	_bind_best_pose(_right)


func _try_tracker(c: XRController3D, names: Array[StringName]) -> void:
	for n in names:
		if XRServer.get_tracker(n) != null:
			c.tracker = n
			return


func _bind_best_pose(c: XRController3D) -> void:
	var t := _tracker_of(c)
	if t == null:
		c.pose = &"default"
		return
	var pose_names: Array[StringName] = [&"aim_pose", &"aim", &"default", &"grip_pose", &"grip", &"default_pose", &"palm_pose"]
	for pose_name in pose_names:
		if t.has_pose(pose_name):
			var pose: XRPose = t.get_pose(pose_name)
			if pose != null and pose.has_tracking_data:
				c.pose = pose_name
				c.transform = pose.transform
				return
	c.pose = &"default"


func _ensure_render_models() -> void:
	if has_node("RenderModels"):
		return
	if not ClassDB.class_exists("OpenXRRenderModelManager"):
		return
	if xr_interface == null or not xr_interface.is_initialized():
		return
	var models: Node = ClassDB.instantiate("OpenXRRenderModelManager")
	models.name = "RenderModels"
	add_child(models)


func _reset_grabs() -> void:
	_two_hand = false
	_one_hand = null
	_grab_part = null
	_grip_left = false
	_grip_right = false
