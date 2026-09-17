class_name EnvironmentStage
extends Node3D

signal changed

const ENV_IDS := ["studio", "dungeon", "battlefield", "condo", "passthrough", "splat"]
const ENV_LABELS := ["Studio", "Dungeon", "Foggy battlefield", "Penthouse condo", "Passthrough", "Gaussian splat"]

var current_id := "studio"
var condition_index := 0
var dimmer := 1.0
var contrast := 1.15
var surround := 0.28

var _kit := EnvKit.new()
var _world_env: WorldEnvironment
var _gizmo: Node3D
var _hint: Node3D
var _roots: Dictionary = {}
var _flicker_t := 0.0
var _model_fill: Node3D
var _splat: SplatRuntime


func setup(gizmo: Node3D, hint: Node3D) -> void:
	_gizmo = gizmo
	_hint = hint
	_world_env = WorldEnvironment.new()
	_world_env.name = "WorldEnvironment"
	add_child(_world_env)
	_roots["studio"] = _build_studio()
	_roots["dungeon"] = _build_dungeon()
	_roots["battlefield"] = _build_battlefield()
	_roots["condo"] = _build_condo()
	_roots["passthrough"] = _build_passthrough()
	_roots["splat"] = _build_splat()
	_build_model_fill()
	apply("studio", 0, 1.0)


func environment_count() -> int:
	return ENV_IDS.size()


func condition_labels() -> PackedStringArray:
	match current_id:
		"studio":
			return PackedStringArray(["Gallery", "Overhead", "Rim", "Work lamp"])
		"dungeon":
			return PackedStringArray(["Torches", "Embers", "Moon crack", "Blackout"])
		"battlefield":
			return PackedStringArray(["Overcast", "Dusk", "Night fire", "Whiteout"])
		"condo":
			return PackedStringArray(["Daylight", "Golden hour", "Evening lamps", "Night"])
		"passthrough":
			return PackedStringArray(["Room estimate", "Neutral", "Warm interior", "Cool daylight"])
		"splat":
			return PackedStringArray(["Captured", "Matched lights", "Bright models", "Dim"])
		_:
			return PackedStringArray(["Default"])


func apply(env_id: String, condition: int, energy_scale: float) -> void:
	if not ENV_IDS.has(env_id):
		env_id = "studio"
	current_id = env_id
	condition_index = clampi(condition, 0, condition_labels().size() - 1)
	dimmer = clampf(energy_scale, 0.05, 2.5)
	for id in _roots:
		var node := _roots[id] as Node3D
		var on: bool = str(id) == current_id
		node.visible = on
		node.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if _gizmo:
		_gizmo.visible = current_id == "studio"
	if _hint:
		_hint.visible = current_id == "studio"
	if _model_fill:
		_model_fill.visible = current_id != "splat"
		_model_fill.process_mode = Node.PROCESS_MODE_INHERIT if current_id != "splat" else Node.PROCESS_MODE_DISABLED
	if _splat:
		_splat.apply_relight_mode("matched" if current_id == "splat" and condition_index == 1 else "captured")
	_apply_environment()
	_apply_lights()
	_apply_surround()
	changed.emit()


func set_environment(index: int) -> void:
	var id: String = ENV_IDS[clampi(index, 0, ENV_IDS.size() - 1)]
	apply(id, 0, dimmer)


func set_condition(index: int) -> void:
	apply(current_id, index, dimmer)


func set_dimmer(value: float) -> void:
	apply(current_id, condition_index, value)


func set_contrast(value: float) -> void:
	contrast = clampf(value, 0.6, 2.2)
	_apply_environment()
	changed.emit()


func set_surround(value: float) -> void:
	surround = clampf(value, 0.05, 1.0)
	_apply_environment()
	_apply_lights()
	_apply_surround()
	changed.emit()


func is_passthrough() -> bool:
	return current_id == "passthrough"


func is_splat() -> bool:
	return current_id == "splat"


func has_splat() -> bool:
	return _splat != null and _splat.has_splat()


func splat_path() -> String:
	return _splat.path if _splat else ""


func splat_status() -> String:
	return _splat.status if _splat else ""


func load_splat(path: String) -> Dictionary:
	if _splat == null:
		return {"ok": false, "message": "Splat environment is not ready."}
	var result := _splat.load_splat(path)
	if not result.get("ok", false):
		changed.emit()
		return result
	if current_id != "splat":
		apply("splat", 0, dimmer)
	else:
		_splat.apply_relight_mode("matched" if condition_index == 1 else "captured")
		_apply_environment()
		_apply_lights()
		_apply_surround()
		changed.emit()
	return result


func _process(delta: float) -> void:
	_flicker_t += delta
	if _splat:
		_splat.poll_bake()
	if current_id == "passthrough":
		_tick_room_estimate()
	var root: Node3D = _roots.get(current_id)
	if root == null or not root.visible:
		return
	for light in root.find_children("*", "Light3D", true, false):
		if not (light as Light3D).get_meta("flicker", false):
			continue
		var base := float((light as Light3D).get_meta("base_energy", (light as Light3D).light_energy))
		var id_hash := float(light.get_instance_id() % 17)
		var n := 0.82 + 0.18 * sin(_flicker_t * (7.3 + id_hash * 0.13) + id_hash)
		n *= 0.92 + 0.08 * sin(_flicker_t * (19.0 + id_hash))
		(light as Light3D).light_energy = base * n * dimmer


func _apply_lights() -> void:
	var table := _light_table()
	var root: Node3D = _roots[current_id]
	for light in root.find_children("*", "Light3D", true, false):
		var id := str((light as Light3D).get_meta("light_id", light.name))
		var energy := float(table.get(id, 0.0))
		(light as Light3D).set_meta("base_energy", energy)
		if not (light as Light3D).get_meta("flicker", false):
			(light as Light3D).light_energy = energy * dimmer
		(light as Light3D).visible = energy > 0.001


func _light_table() -> Dictionary:
	match current_id:
		"studio":
			match condition_index:
				0:
					return {"key": 1.15, "fill": 0.35, "rim": 0.0, "lamp": 0.0}
				1:
					return {"key": 0.25, "fill": 0.15, "rim": 0.0, "lamp": 0.0, "overhead": 1.6}
				2:
					return {"key": 0.15, "fill": 0.08, "rim": 2.2, "lamp": 0.0}
				_:
					return {"key": 0.05, "fill": 0.04, "rim": 0.0, "lamp": 2.4}
		"dungeon":
			match condition_index:
				0:
					return {"torch_n": 2.2, "torch_e": 2.0, "torch_s": 2.1, "torch_w": 2.0, "crack": 0.0}
				1:
					return {"torch_n": 0.55, "torch_e": 0.4, "torch_s": 0.7, "torch_w": 0.35, "crack": 0.08}
				2:
					return {"torch_n": 0.0, "torch_e": 0.0, "torch_s": 0.0, "torch_w": 0.0, "crack": 1.8}
				_:
					return {"torch_n": 0.0, "torch_e": 0.0, "torch_s": 0.22, "torch_w": 0.0, "crack": 0.0}
		"battlefield":
			match condition_index:
				0:
					return {"sun": 0.85, "fire": 0.35}
				1:
					return {"sun": 1.4, "fire": 0.9}
				2:
					return {"sun": 0.12, "fire": 2.6}
				_:
					return {"sun": 1.8, "fire": 0.15}
		"condo":
			match condition_index:
				0:
					return {"window": 1.6, "pendant_a": 0.0, "pendant_b": 0.0, "floor_lamp": 0.0}
				1:
					return {"window": 1.1, "pendant_a": 0.45, "pendant_b": 0.4, "floor_lamp": 0.5}
				2:
					return {"window": 0.25, "pendant_a": 1.5, "pendant_b": 1.4, "floor_lamp": 1.7}
				_:
					return {"window": 0.06, "pendant_a": 1.2, "pendant_b": 1.1, "floor_lamp": 1.9}
		"passthrough":
			match condition_index:
				0:
					return {"room_key": 1.6, "room_fill": 0.55}
				1:
					return {"room_key": 1.5, "room_fill": 0.6}
				2:
					return {"room_key": 1.3, "room_fill": 0.75}
				_:
					return {"room_key": 1.7, "room_fill": 0.5}
		"splat":
			var boost := 1.0
			if _splat:
				boost = clampf(float(_splat.estimate.get("energy", 1.15)) / 1.15, 0.55, 1.7)
			match condition_index:
				0:
					return {"splat_key": 1.15 * boost, "splat_fill": 0.42, "splat_rim": 0.2}
				1:
					return {"splat_key": 1.35 * boost, "splat_fill": 0.5, "splat_rim": 0.28}
				2:
					return {"splat_key": 1.7 * boost, "splat_fill": 1.05, "splat_rim": 0.55}
				_:
					return {"splat_key": 0.55 * boost, "splat_fill": 0.22, "splat_rim": 0.12}
	return {}


func _apply_environment() -> void:
	var env := Environment.new()
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.ssao_enabled = false
	env.glow_enabled = false
	env.ambient_light_sky_contribution = 0.0
	env.adjustment_enabled = true
	env.adjustment_contrast = contrast
	env.adjustment_brightness = 1.0
	env.adjustment_saturation = 1.0
	match current_id:
		"studio":
			env.background_mode = Environment.BG_SKY
			env.sky = _sky(Color(0.22, 0.26, 0.32), Color(0.42, 0.44, 0.46), Color(0.12, 0.12, 0.13))
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.82, 0.84, 0.88)
			env.ambient_light_energy = [1.6, 1.35, 1.2, 1.1][condition_index]
			env.fog_enabled = false
		"dungeon":
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.04, 0.03, 0.025)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.55, 0.42, 0.32) if condition_index < 2 else Color(0.35, 0.40, 0.55)
			env.ambient_light_energy = [1.1, 0.95, 1.0, 0.85][condition_index]
			env.fog_enabled = true
			env.fog_light_color = Color(0.18, 0.12, 0.08)
			env.fog_density = [0.004, 0.006, 0.005, 0.008][condition_index]
			env.fog_sky_affect = 1.0
		"battlefield":
			env.background_mode = Environment.BG_SKY
			env.sky = _sky(
				[Color(0.48, 0.50, 0.46), Color(0.58, 0.38, 0.22), Color(0.14, 0.16, 0.22), Color(0.66, 0.68, 0.70)][condition_index],
				[Color(0.55, 0.55, 0.50), Color(0.75, 0.48, 0.28), Color(0.22, 0.24, 0.30), Color(0.74, 0.76, 0.78)][condition_index],
				Color(0.22, 0.20, 0.16)
			)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = Color(0.75, 0.72, 0.65)
			env.ambient_light_energy = [1.35, 1.2, 1.0, 1.4][condition_index]
			env.fog_enabled = true
			env.fog_light_color = [Color(0.55, 0.56, 0.50), Color(0.62, 0.38, 0.22), Color(0.16, 0.18, 0.22), Color(0.72, 0.74, 0.76)][condition_index]
			env.fog_density = [0.008, 0.01, 0.012, 0.018][condition_index]
			env.fog_aerial_perspective = 0.5
			env.fog_sky_affect = 0.7
			env.fog_sun_scatter = 0.25 if condition_index == 1 else 0.05
		"condo":
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.10, 0.11, 0.13)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = [Color(0.88, 0.90, 0.95), Color(0.95, 0.82, 0.62), Color(0.85, 0.72, 0.55), Color(0.55, 0.52, 0.62)][condition_index]
			env.ambient_light_energy = [1.45, 1.25, 1.15, 1.0][condition_index]
			env.fog_enabled = false
		"passthrough":
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.0, 0.0, 0.0, 0.0)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = [
				Color(0.85, 0.86, 0.88),
				Color(0.88, 0.90, 0.92),
				Color(1.0, 0.84, 0.62),
				Color(0.78, 0.86, 1.0)
			][condition_index]
			env.ambient_light_energy = [1.0, 0.95, 0.9, 1.05][condition_index]
			env.fog_enabled = false
		"splat":
			var amb := Color(0.62, 0.64, 0.68)
			var amb_e: float = [0.95, 0.85, 1.15, 0.55][condition_index]
			if _splat:
				var estimated: Variant = _splat.estimate.get("ambient", amb)
				if estimated is Color:
					amb = estimated
			env.background_mode = Environment.BG_COLOR
			env.background_color = Color(0.015, 0.016, 0.02)
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = amb
			env.ambient_light_energy = amb_e
			env.fog_enabled = false
	env.ambient_light_energy *= surround
	_world_env.environment = env


func _apply_surround() -> void:
	if current_id == "splat":
		# Splat lights are the only lights on the models; don't fold them
		# by the surround dimmer the authored rooms use.
		return
	var root: Node3D = _roots.get(current_id)
	if root == null:
		return
	for light in root.find_children("*", "Light3D", true, false):
		var id := str((light as Light3D).get_meta("light_id", ""))
		if id.begins_with("fill") or id == "model_key":
			continue
		var base := float((light as Light3D).get_meta("base_energy", (light as Light3D).light_energy))
		(light as Light3D).light_energy = base * dimmer * surround


func _sky(top: Color, horizon: Color, ground: Color) -> Sky:
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = top
	mat.sky_horizon_color = horizon
	mat.ground_bottom_color = ground
	mat.ground_horizon_color = horizon.darkened(0.25)
	mat.sun_angle_max = 22.0
	sky.sky_material = mat
	return sky


func _root(id: String) -> Node3D:
	var n := Node3D.new()
	n.name = id.capitalize()
	add_child(n)
	return n


func _build_splat() -> Node3D:
	_splat = SplatRuntime.new()
	_splat.name = "Splat"
	add_child(_splat)
	_splat.setup(_kit)
	_splat.status_changed.connect(func(_t): changed.emit())
	return _splat


func _build_model_fill() -> void:
	var fill := Node3D.new()
	fill.name = "ModelFill"
	_model_fill = fill
	add_child(fill)
	var key := _kit.sun(fill, "model_key", Vector3(-40, 35, 0), Color(1.0, 0.98, 0.94), 1.8, false)
	key.position = Vector3(0, 2.5, 2.0)
	var a := _kit.omni(fill, "fill_a", Vector3(1.6, 1.7, 0.8), Color(1.0, 0.98, 0.95), 1.6, 12.0)
	var b := _kit.omni(fill, "fill_b", Vector3(-1.5, 1.4, -1.0), Color(0.90, 0.93, 1.0), 1.4, 12.0)
	var c := _kit.omni(fill, "fill_c", Vector3(0.0, 2.2, -1.8), Color(1.0, 1.0, 1.0), 1.2, 12.0)


func _build_passthrough() -> Node3D:
	var root := _root("passthrough")
	var catcher := MeshInstance3D.new()
	catcher.name = "ShadowCatcher"
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	catcher.mesh = plane
	var mat := ShaderMaterial.new()
	var sh := load("res://assets/shadow_catcher.gdshader")
	if sh:
		mat.shader = sh
	catcher.set_surface_override_material(0, mat)
	root.add_child(catcher)
	var key := _kit.sun(root, "room_key", Vector3(-48, 35, 0), Color(1.0, 0.97, 0.92), 1.0, true)
	key.position = Vector3(0.0, 2.4, 0.0)
	_kit.omni(root, "room_fill", Vector3(0.2, 1.7, 0.5), Color(0.82, 0.86, 1.0), 0.22, 10.0)
	return root


func _tick_room_estimate() -> void:
	if condition_index != 0:
		return
	var est: Dictionary = XrPassthrough.poll_light_estimate()
	if not bool(est.get("ok", false)):
		return
	var env := _world_env.environment
	if env:
		env.ambient_light_color = est.get("ambient", Color(0.7, 0.7, 0.7))
		env.ambient_light_energy = float(est.get("ambient_energy", 0.45)) * dimmer
	var root: Node3D = _roots.get("passthrough")
	if root == null:
		return
	for light in root.find_children("*", "Light3D", true, false):
		var id := str((light as Light3D).get_meta("light_id", light.name))
		if id == "room_key" and light is DirectionalLight3D:
			var dir: Vector3 = est.get("direction", Vector3.DOWN)
			if dir.length_squared() > 0.001:
				dir = dir.normalized()
				var up := Vector3.UP
				if absf(dir.dot(up)) > 0.95:
					up = Vector3.FORWARD
				(light as Node3D).look_at((light as Node3D).global_position + dir, up)
			(light as Light3D).light_color = est.get("light_color", Color.WHITE)
			(light as Light3D).light_energy = float(est.get("light_energy", 1.0)) * dimmer
		elif id == "room_fill":
			(light as Light3D).light_color = est.get("ambient", Color(0.8, 0.8, 0.85))
			(light as Light3D).light_energy = float(est.get("ambient_energy", 0.25)) * 0.5 * dimmer


func _build_studio() -> Node3D:
	var root := _root("studio")
	var grid_mat := ShaderMaterial.new()
	var shader := load("res://assets/grid.gdshader")
	if shader:
		grid_mat.shader = shader
	_kit.plane(root, "Floor", Vector2(48, 48), Vector3.ZERO, grid_mat)
	_kit.sun(root, "key", Vector3(-48, 35, 0), Color(1, 0.98, 0.94), 1.6, false)
	_kit.omni(root, "fill", Vector3(-2.5, 2.2, 1.5), Color(0.75, 0.82, 1.0), 0.35, 12.0)
	_kit.sun(root, "rim", Vector3(-20, -150, 0), Color(0.75, 0.85, 1.0), 0.0, false)
	_kit.sun(root, "overhead", Vector3(-88, 0, 0), Color(1, 1, 1), 0.0, false)
	_kit.omni(root, "lamp", Vector3(1.6, 1.4, -0.2), Color(1.0, 0.88, 0.65), 0.0, 6.0)
	return root


func _build_dungeon() -> Node3D:
	var root := _root("dungeon")
	var stone := _kit.triplanar("dungeon_stone", Color(0.28, 0.24, 0.20), Color(0.12, 0.11, 0.10), 17, 0.035, 0.92, 0.04, 0.42)
	var floor := _kit.triplanar("dungeon_floor", Color(0.22, 0.18, 0.14), Color(0.08, 0.07, 0.06), 21, 0.04, 0.95, 0.02, 0.38)
	var moss := _kit.triplanar("dungeon_moss", Color(0.16, 0.18, 0.10), Color(0.07, 0.08, 0.05), 8, 0.05, 0.98, 0.0, 0.5)
	_kit.box(root, "Floor", Vector3(14, 0.2, 14), Vector3(0, -0.1, 0), floor)
	_kit.box(root, "Ceiling", Vector3(14, 0.35, 14), Vector3(0, 4.25, 0), stone)
	# Walls with a south doorway.
	_kit.box(root, "WallN", Vector3(14, 4.4, 0.45), Vector3(0, 2.1, -6.9), stone)
	_kit.box(root, "WallE", Vector3(0.45, 4.4, 14), Vector3(6.9, 2.1, 0), stone)
	_kit.box(root, "WallW", Vector3(0.45, 4.4, 14), Vector3(-6.9, 2.1, 0), stone)
	_kit.box(root, "WallS_L", Vector3(5.4, 4.4, 0.45), Vector3(-4.3, 2.1, 6.9), stone)
	_kit.box(root, "WallS_R", Vector3(5.4, 4.4, 0.45), Vector3(4.3, 2.1, 6.9), stone)
	_kit.box(root, "Lintel", Vector3(3.4, 0.7, 0.5), Vector3(0, 3.7, 6.9), stone)
	for p in [Vector3(-3.6, 1.7, -3.6), Vector3(3.6, 1.7, -3.6), Vector3(-3.6, 1.7, 3.6), Vector3(3.6, 1.7, 3.6)]:
		_kit.box(root, "Pillar", Vector3(0.5, 3.4, 0.5), p, stone)
	_kit.box(root, "Altar", Vector3(1.6, 0.45, 0.7), Vector3(0, 0.22, -4.6), stone)
	_kit.box(root, "RubbleA", Vector3(0.9, 0.4, 0.7), Vector3(-5.4, 0.2, -5.2), moss, Vector3(0, 22, 0))
	_kit.box(root, "RubbleB", Vector3(0.7, 0.28, 1.1), Vector3(5.6, 0.14, 4.8), moss, Vector3(0, -30, 0))
	_kit.torch(root, "torch_n", Vector3(0, 2.15, -6.55))
	_kit.torch(root, "torch_e", Vector3(6.55, 2.05, 1.4))
	_kit.torch(root, "torch_s", Vector3(-2.2, 2.1, 6.55))
	_kit.torch(root, "torch_w", Vector3(-6.55, 2.2, -1.1))
	var crack := _kit.box(root, "CrackGlow", Vector3(2.4, 0.04, 0.12), Vector3(1.4, 4.05, -1.2), _kit.emissive(Color(0.45, 0.62, 1.0), 2.4), Vector3(0, 18, 0))
	crack.visible = true
	_kit.spot(root, "crack", Vector3(1.4, 4.0, -1.2), Vector3(0.2, 0.0, -1.0), Color(0.55, 0.7, 1.0), 0.0, 9.0, 28.0)
	return root


func _build_battlefield() -> Node3D:
	var root := _root("battlefield")
	var mud := _kit.triplanar("mud", Color(0.28, 0.24, 0.16), Color(0.12, 0.11, 0.08), 33, 0.03, 0.95, 0.0, 0.22)
	var dirt := _kit.triplanar("dirt", Color(0.32, 0.26, 0.16), Color(0.18, 0.14, 0.09), 14, 0.025, 0.92, 0.0, 0.28)
	var timber := _kit.triplanar("timber", Color(0.30, 0.18, 0.10), Color(0.12, 0.08, 0.05), 19, 0.08, 0.88, 0.0, 0.9)
	_kit.plane(root, "Ground", Vector2(48, 48), Vector3.ZERO, mud)
	_kit.box(root, "MoundA", Vector3(3.2, 0.55, 2.4), Vector3(-7.5, 0.15, -6.5), dirt, Vector3(0, 18, 6))
	_kit.box(root, "MoundB", Vector3(2.6, 0.4, 3.5), Vector3(8.5, 0.1, 5.5), dirt, Vector3(0, -24, 4))
	_kit.box(root, "RuinA", Vector3(0.4, 1.8, 3.2), Vector3(-6.2, 0.9, 4.8), dirt, Vector3(0, 12, 8))
	_kit.box(root, "RuinB", Vector3(2.8, 1.2, 0.38), Vector3(-5.4, 0.6, 6.2), dirt, Vector3(0, 18, -6))
	_kit.box(root, "RuinC", Vector3(0.35, 2.2, 2.4), Vector3(7.4, 1.1, -5.8), dirt, Vector3(0, -8, 5))
	for i in 6:
		var x := -4.0 + i * 1.15
		_kit.cylinder(root, "Stake", 0.05, 1.4, Vector3(x, 0.55, 7.2), timber, Vector3(8, 0, i * 3.0 - 8.0))
	_kit.campfire(root, "fire", Vector3(5.4, 0.0, 4.8))
	_kit.sun(root, "sun", Vector3(-50, 40, 0), Color(0.85, 0.86, 0.78), 0.85)
	return root


func _build_condo() -> Node3D:
	var root := _root("condo")
	var wood := _kit.triplanar("oak", Color(0.42, 0.28, 0.16), Color(0.22, 0.14, 0.08), 6, 0.06, 0.55, 0.0, 0.7)
	var plaster := _kit.triplanar("plaster", Color(0.86, 0.84, 0.80), Color(0.72, 0.70, 0.66), 2, 0.02, 0.78, 0.0, 0.35)
	var marble := _kit.triplanar("marble", Color(0.78, 0.76, 0.74), Color(0.55, 0.54, 0.52), 12, 0.09, 0.28, 0.08, 0.8)
	var dark := _kit.triplanar("condo_dark", Color(0.14, 0.13, 0.12), Color(0.06, 0.06, 0.06), 5, 0.08, 0.4, 0.2, 1.2)
	_kit.box(root, "Floor", Vector3(12, 0.16, 9), Vector3(0, -0.08, 0.2), wood)
	_kit.box(root, "Rug", Vector3(2.6, 0.03, 2.2), Vector3(0, 0.02, -1.3), dark)
	_kit.box(root, "Ceiling", Vector3(12, 0.18, 9), Vector3(0, 3.22, 0.2), plaster)
	_kit.box(root, "WallW", Vector3(0.2, 3.3, 9), Vector3(-6.0, 1.6, 0.2), plaster)
	_kit.box(root, "WallE", Vector3(0.2, 3.3, 9), Vector3(6.0, 1.6, 0.2), plaster)
	_kit.box(root, "WallN", Vector3(12, 3.3, 0.2), Vector3(0, 1.6, -4.3), plaster)
	# Window wall: frame + glowing glass looking over a city.
	_kit.box(root, "Sill", Vector3(12, 0.18, 0.28), Vector3(0, 0.55, 4.55), marble)
	_kit.box(root, "WinFrameL", Vector3(0.16, 2.4, 0.16), Vector3(-4.6, 1.8, 4.58), dark)
	_kit.box(root, "WinFrameR", Vector3(0.16, 2.4, 0.16), Vector3(4.6, 1.8, 4.58), dark)
	_kit.box(root, "WinFrameM", Vector3(0.12, 2.4, 0.12), Vector3(0, 1.8, 4.58), dark)
	var glass := _kit.box(root, "Glass", Vector3(11.4, 2.35, 0.06), Vector3(0, 1.8, 4.62), _kit.emissive(Color(0.35, 0.45, 0.7), 1.1))
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_kit.box(root, "Counter", Vector3(2.4, 0.9, 0.7), Vector3(-4.6, 0.45, -3.6), marble)
	_kit.box(root, "Cabinets", Vector3(2.4, 0.7, 0.5), Vector3(-4.6, 2.55, -3.7), dark)
	_kit.box(root, "Sofa", Vector3(2.4, 0.55, 0.85), Vector3(4.2, 0.28, -2.6), dark)
	_kit.box(root, "SofaBack", Vector3(2.4, 0.7, 0.22), Vector3(4.2, 0.7, -2.95), dark)
	_kit.box(root, "Table", Vector3(1.1, 0.08, 0.55), Vector3(4.2, 0.42, -1.7), marble)
	_kit.pendant(root, "pendant_a", Vector3(-2.4, 2.55, 0.6))
	_kit.pendant(root, "pendant_b", Vector3(2.2, 2.55, 0.9))
	_kit.floor_lamp(root, "floor_lamp", Vector3(4.6, 0.0, 2.4))
	_kit.sun(root, "window", Vector3(-18, 180, 0), Color(0.75, 0.84, 1.0), 1.6)
	return root
