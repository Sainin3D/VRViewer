class_name XrPassthrough
extends RefCounted

static var _le_started := false

static func enable(xr: XRInterface, vp: Viewport) -> Dictionary:
	if xr == null:
		return {"ok": false, "mode": "", "message": "No XR interface."}
	var modes: Array = []
	if xr.has_method("get_supported_environment_blend_modes"):
		modes = xr.get_supported_environment_blend_modes()
	vp.transparent_bg = true
	var ext_ok := false
	if xr.has_method("start_passthrough"):
		ext_ok = bool(xr.start_passthrough())
	# Some SteamVR/Quest Link runtimes support blend but do not list it. Try alpha, then additive.
	if xr.has_method("set_environment_blend_mode"):
		if not xr.set_environment_blend_mode(XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND):
			xr.set_environment_blend_mode(XRInterface.XR_ENV_BLEND_MODE_ADDITIVE)
	else:
		xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	var current := int(xr.environment_blend_mode)
	var passthrough_on := ext_ok
	if xr.has_method("is_passthrough_enabled"):
		passthrough_on = passthrough_on or xr.is_passthrough_enabled()
	if current == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND or ext_ok:
		return {
			"ok": true,
			"mode": "alpha",
			"message": "Passthrough on. Virtual rooms hidden; models stay in the real world."
		}
	if current == XRInterface.XR_ENV_BLEND_MODE_ADDITIVE:
		return {
			"ok": true,
			"mode": "additive",
			"message": "Passthrough on (additive blend)."
		}
	var mode_names := PackedStringArray()
	for m in modes:
		mode_names.append(str(m))
	return {
		"ok": false,
		"mode": "",
		"message": "Runtime reported no passthrough (modes: %s). Index has no cameras. Quest needs Link passthrough or the SteamVR OpenXR passthrough layer." % ", ".join(mode_names)
	}


static func disable(xr: XRInterface, vp: Viewport) -> void:
	if xr == null:
		return
	if xr.has_method("is_passthrough_enabled") and xr.is_passthrough_enabled():
		if xr.has_method("stop_passthrough"):
			xr.stop_passthrough()
	if xr.has_method("set_environment_blend_mode"):
		xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_OPAQUE
	if vp:
		vp.transparent_bg = false


static func poll_light_estimate() -> Dictionary:
	# Core Godot XR has no light estimation. Android XR / vendors plugin may.
	if ClassDB.class_exists("OpenXRAndroidLightEstimationExtension"):
		var ext: Object = _android_estimator()
		if ext == null:
			return {"ok": false}
		if ext.has_method("is_light_estimation_supported") and not ext.is_light_estimation_supported():
			return {"ok": false}
		if ext.has_method("start_light_estimation") and not _le_started:
			ext.start_light_estimation()
			_le_started = true
		var ambient := Color(0.7, 0.7, 0.7)
		var energy := 0.5
		var dir := Vector3(-0.35, -0.85, -0.4).normalized()
		var light_col := Color(1, 0.98, 0.94)
		var light_e := 1.0
		if ext.get("ambient_light_color") != null:
			ambient = ext.get("ambient_light_color")
		if ext.get("ambient_light_intensity") != null:
			energy = float(ext.get("ambient_light_intensity"))
		if ext.get("main_light_direction") != null:
			dir = ext.get("main_light_direction")
		if ext.get("main_light_intensity") != null:
			light_e = float(ext.get("main_light_intensity"))
		if ext.get("main_light_color") != null:
			light_col = ext.get("main_light_color")
		return {
			"ok": true,
			"ambient": ambient,
			"ambient_energy": clampf(energy, 0.05, 2.5),
			"direction": dir,
			"light_color": light_col,
			"light_energy": clampf(light_e, 0.05, 4.0),
		}
	return {"ok": false}


static func _android_estimator() -> Object:
	if Engine.has_singleton("OpenXRAndroidLightEstimationExtension"):
		return Engine.get_singleton("OpenXRAndroidLightEstimationExtension")
	return null
