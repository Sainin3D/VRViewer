class_name OrbitCamera
extends Camera3D

@export var target := Vector3(0, 0.5, 0)
@export var distance := 3.2
@export var yaw_deg := 35.0
@export var pitch_deg := 28.0
@export var min_distance := 0.05
@export var max_distance := 250.0
@export var orbit_sens := 0.35
@export var pan_sens := 0.0018

var _orbiting := false
var _panning := false
var _look_flying := false
var _enabled := true


func _ready() -> void:
	near = 0.01
	far = 4000.0
	current = true
	_apply()


func set_enabled(value: bool) -> void:
	_enabled = value
	current = value
	if value:
		_apply()


func frame_aabb(aabb: AABB, padding := 2.2) -> void:
	if aabb.size == Vector3.ZERO:
		return
	target = aabb.get_center()
	var radius := aabb.size.length() * 0.5
	distance = clampf(radius * padding, 0.15, max_distance)
	# Desktop starts above the floor looking down at the model (negative pitch sits under the plane).
	if pitch_deg < 10.0:
		pitch_deg = 28.0
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if not _enabled or not current:
		return
	if _over_ui():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = clampf(distance * 0.85, min_distance, max_distance)
			_apply()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = clampf(distance * 1.18, min_distance, max_distance)
			_apply()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = mb.pressed and not mb.shift_pressed
			_panning = mb.pressed and mb.shift_pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.alt_pressed:
			_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_look_flying = mb.pressed
			if mb.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _orbiting:
			yaw_deg -= mm.relative.x * orbit_sens
			pitch_deg = clampf(pitch_deg - mm.relative.y * orbit_sens, -89.0, 89.0)
			_apply()
		elif _panning:
			var right := global_transform.basis.x
			var up := global_transform.basis.y
			var pan_scale := distance * pan_sens
			target -= right * mm.relative.x * pan_scale
			target += up * mm.relative.y * pan_scale
			_apply()
		elif _look_flying:
			yaw_deg -= mm.relative.x * orbit_sens
			pitch_deg = clampf(pitch_deg - mm.relative.y * orbit_sens, -89.0, 89.0)
			_apply()
	elif event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_F:
			# Parent handles framing; still consume if we want.
			pass


func _process(delta: float) -> void:
	if not _enabled or not current:
		return
	if not _look_flying:
		return
	var wish := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		wish -= global_transform.basis.z
	if Input.is_physical_key_pressed(KEY_S):
		wish += global_transform.basis.z
	if Input.is_physical_key_pressed(KEY_A):
		wish -= global_transform.basis.x
	if Input.is_physical_key_pressed(KEY_D):
		wish += global_transform.basis.x
	if Input.is_physical_key_pressed(KEY_E):
		wish += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		wish -= Vector3.UP
	if wish != Vector3.ZERO:
		var speed := 4.5 * distance
		if Input.is_physical_key_pressed(KEY_SHIFT):
			speed *= 3.0
		var delta_move := wish.normalized() * speed * delta
		target += delta_move
		_apply()


func _apply() -> void:
	var yaw := deg_to_rad(yaw_deg)
	var pitch := deg_to_rad(pitch_deg)
	var offset := Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	) * distance
	global_position = target + offset
	look_at(target, Vector3.UP)


func _over_ui() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null
