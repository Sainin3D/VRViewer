class_name EnvKit
extends RefCounted

var _mats: Dictionary = {}
var _tex: Dictionary = {}


func box(parent: Node3D, node_name: String, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	return mi


func cylinder(parent: Node3D, node_name: String, radius: float, height: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	return mi


func plane(parent: Node3D, node_name: String, size: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	var mesh := PlaneMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.set_surface_override_material(0, mat)
	parent.add_child(mi)
	return mi


func emissive(color: Color, energy := 2.4) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	return mat


func triplanar(key: String, a: Color, b: Color, seed: int, freq := 0.045, roughness := 0.85, metallic := 0.0, scale := 0.55) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _noise_tex(key, a, b, seed, freq)
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.roughness = roughness
	mat.metallic = metallic
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_triplanar_sharpness = 4.0
	mat.uv1_scale = Vector3(scale, scale, scale)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	_mats[key] = mat
	return mat


func omni(parent: Node3D, light_id: String, pos: Vector3, color: Color, energy: float, range_m: float, flicker := false) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = light_id
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = range_m
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	light.light_indirect_energy = 1.0
	light.add_to_group("env_light")
	light.set_meta("light_id", light_id)
	light.set_meta("base_energy", energy)
	light.set_meta("flicker", flicker)
	parent.add_child(light)
	return light


func spot(parent: Node3D, light_id: String, pos: Vector3, look_at_pos: Vector3, color: Color, energy: float, range_m: float, angle := 35.0) -> SpotLight3D:
	var light := SpotLight3D.new()
	light.name = light_id
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.spot_range = range_m
	light.spot_angle = angle
	light.shadow_enabled = false
	light.add_to_group("env_light")
	light.set_meta("light_id", light_id)
	light.set_meta("base_energy", energy)
	light.set_meta("flicker", false)
	parent.add_child(light)
	light.look_at(look_at_pos, Vector3.UP)
	return light


func sun(parent: Node3D, light_id: String, rot_deg: Vector3, color: Color, energy: float, cast_shadow := true) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.name = light_id
	light.rotation_degrees = rot_deg
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = cast_shadow
	light.add_to_group("env_light")
	light.set_meta("light_id", light_id)
	light.set_meta("base_energy", energy)
	parent.add_child(light)
	return light


func torch(parent: Node3D, light_id: String, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = light_id
	root.position = pos
	parent.add_child(root)
	var iron := triplanar("iron", Color(0.18, 0.16, 0.15), Color(0.08, 0.08, 0.09), 9, 0.2, 0.45, 0.65, 1.8)
	cylinder(root, "Bracket", 0.025, 0.28, Vector3(0, 0.05, 0.08), iron, Vector3(90, 0, 0))
	cylinder(root, "Handle", 0.03, 0.18, Vector3(0, -0.02, 0), iron)
	var flame := MeshInstance3D.new()
	flame.name = "Flame"
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.16
	flame.mesh = sphere
	flame.position = Vector3(0, 0.12, 0)
	flame.set_surface_override_material(0, emissive(Color(1.0, 0.55, 0.18), 3.2))
	root.add_child(flame)
	omni(root, light_id, Vector3(0, 0.14, 0), Color(1.0, 0.62, 0.28), 2.1, 7.5, true)
	return root


func pendant(parent: Node3D, light_id: String, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = light_id
	root.position = pos
	parent.add_child(root)
	var chrome := triplanar("chrome", Color(0.72, 0.74, 0.76), Color(0.35, 0.36, 0.38), 3, 0.3, 0.22, 0.85, 2.2)
	cylinder(root, "Stem", 0.012, 0.45, Vector3(0, 0.22, 0), chrome)
	cylinder(root, "Shade", 0.16, 0.08, Vector3(0, -0.02, 0), chrome)
	var bulb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.1
	bulb.mesh = sphere
	bulb.position = Vector3(0, -0.06, 0)
	bulb.set_surface_override_material(0, emissive(Color(1.0, 0.92, 0.78), 2.0))
	root.add_child(bulb)
	omni(root, light_id, Vector3(0, -0.08, 0), Color(1.0, 0.93, 0.82), 1.6, 8.0)
	return root


func floor_lamp(parent: Node3D, light_id: String, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = light_id
	root.position = pos
	parent.add_child(root)
	var black := triplanar("lamp_black", Color(0.12, 0.12, 0.13), Color(0.05, 0.05, 0.06), 4, 0.25, 0.4, 0.3, 2.0)
	cylinder(root, "Pole", 0.02, 1.55, Vector3(0, 0.78, 0), black)
	cylinder(root, "Base", 0.16, 0.04, Vector3(0, 0.02, 0), black)
	cylinder(root, "Shade", 0.18, 0.22, Vector3(0, 1.48, 0), black)
	omni(root, light_id, Vector3(0, 1.42, 0), Color(1.0, 0.9, 0.72), 1.8, 7.0)
	return root


func campfire(parent: Node3D, light_id: String, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = light_id
	root.position = pos
	parent.add_child(root)
	var wood := triplanar("char_wood", Color(0.22, 0.14, 0.08), Color(0.08, 0.05, 0.03), 11, 0.12, 0.9, 0.0, 1.4)
	for i in 4:
		var ang := i * 45.0
		box(root, "Log%s" % i, Vector3(0.55, 0.08, 0.1), Vector3(0, 0.05, 0), wood, Vector3(0, ang, 12))
	var glow := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.16
	sphere.height = 0.28
	glow.mesh = sphere
	glow.position = Vector3(0, 0.18, 0)
	glow.set_surface_override_material(0, emissive(Color(1.0, 0.45, 0.12), 4.0))
	root.add_child(glow)
	omni(root, light_id, Vector3(0, 0.3, 0), Color(1.0, 0.5, 0.18), 2.8, 9.0, true)
	return root


func _noise_tex(key: String, a: Color, b: Color, seed: int, freq: float) -> ImageTexture:
	if _tex.has(key):
		return _tex[key]
	var noise := FastNoiseLite.new()
	noise.seed = seed
	noise.frequency = freq
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			var n := clampf((noise.get_noise_2d(x, y) + 1.0) * 0.5, 0.0, 1.0)
			img.set_pixel(x, y, a.lerp(b, n))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex[key] = tex
	return tex
