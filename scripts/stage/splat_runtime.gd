class_name SplatRuntime
extends Node3D

## Gaussian-splat environment: load a capture, stand the player on its floor
## in a low-density clearing, and light ordinary meshes so they belong in it.
##
## Lighting strategy (GDGS 3.3.0):
## - Raster backend (set in project.godot) so VR/multiview and hardware depth
##   occlusion work — models sit *in* the capture instead of compositing over it.
## - Keep captured radiance on the splats (relight off, or high unlit_level).
##   Splats store radiance, not albedo; aggressive relighting cannot remove the
##   baked capture light and just darkens the environment.
## - Sample SH DC colour to drive a directional key + fills on the *models*.
## - Bake a lighting proxy in the background so the splat casts real shadows
##   onto those meshes (`relight_cast_shadows`).

signal status_changed(text: String)

const SPLAT_NODE_PATH := "res://addons/gdgs/runtime/nodes/gaussian_splat_node.gd"
const LIGHTING_RESOURCE_PATH := "res://addons/gdgs/runtime/resources/gaussian_lighting_resource.gd"
const PIPELINE_PATH := "res://addons/gdgs/collision/pipeline/collision_pipeline.gd"
const BAKE_JOB_PATH := "res://addons/gdgs/lighting/bake/bake_job.gd"

const SH_C0 := 0.28209479177387814
const STRUCT_SIZE := 60
const CACHE_DIR := "user://splat_lighting"

const BAKE_SETTINGS := {
	"auto_voxel": true,
	"opacity_cutoff": 0.1,
	"compute_backend": "auto",
	"normal_smoothing": 1,
	"ao_radius": 3,
	"ao_strength": 1.0,
}

var path := ""
var status := "Browse a .ply / .splat / .sog splat and click Use selected splat."
var gaussian: Resource
var splat_node: Node3D
var is_room := true
var world_bounds := AABB()
var estimate := {
	"ambient": Color(0.72, 0.74, 0.78),
	"key_color": Color(1.0, 0.97, 0.92),
	"key_dir": Vector3(-0.35, -0.82, -0.25).normalized(),
	"energy": 1.15,
}

var _host: Node3D
var _ring: MeshInstance3D
var _catcher: MeshInstance3D
var _kit: EnvKit
var _bake_job: RefCounted
var _bake_task := -1
var _skip_bake := false


func setup(kit: EnvKit) -> void:
	_kit = kit
	_skip_bake = _is_smoke()
	_host = Node3D.new()
	_host.name = "SplatHost"
	add_child(_host)
	_ring = _make_play_ring()
	add_child(_ring)
	_catcher = _make_catcher()
	add_child(_catcher)
	_kit.sun(self, "splat_key", Vector3(-48, 35, 0), Color(1.0, 0.97, 0.92), 1.15, true)
	_kit.omni(self, "splat_fill", Vector3(1.4, 1.8, -0.6), Color(0.88, 0.90, 0.96), 0.45, 10.0)
	_kit.omni(self, "splat_rim", Vector3(-1.2, 1.6, 1.4), Color(0.95, 0.93, 0.88), 0.22, 9.0)


func has_splat() -> bool:
	return splat_node != null and gaussian != null


func clear_splat() -> void:
	_cancel_bake()
	gaussian = null
	path = ""
	if splat_node and is_instance_valid(splat_node):
		splat_node.queue_free()
	splat_node = null
	_catcher.visible = false
	status = "No splat loaded."
	status_changed.emit(status)


func load_splat(file_path: String) -> Dictionary:
	_cancel_bake()
	if splat_node and is_instance_valid(splat_node):
		splat_node.queue_free()
		splat_node = null
	gaussian = null
	path = file_path
	status = "Loading %s…" % file_path.get_file()
	status_changed.emit(status)
	var result := SplatLoader.load_path(file_path)
	if not result.get("ok", false):
		status = str(result.get("message", "Failed to load splat."))
		status_changed.emit(status)
		return result
	gaussian = result["resource"]
	if not ResourceLoader.exists(SPLAT_NODE_PATH, "Script"):
		status = "GaussianSplatNode script missing."
		status_changed.emit(status)
		return {"ok": false, "message": status}
	var script: GDScript = load(SPLAT_NODE_PATH)
	if script == null or not script.can_instantiate():
		status = "GaussianSplatNode failed to compile."
		status_changed.emit(status)
		return {"ok": false, "message": status}
	splat_node = script.new()
	splat_node.name = "GaussianSplat"
	splat_node.set("gaussian", gaussian)
	# Photoreal capture by default. Relighting is a condition, not the look.
	splat_node.set("relight_enabled", false)
	splat_node.set("relight_cast_shadows", true)
	splat_node.set("relight_unlit_level", 1.0)
	splat_node.set("relight_light_gain", 0.45)
	splat_node.set("relight_dc_only", true)
	splat_node.set("relight_ambient", Color(0.18, 0.18, 0.2))
	_host.transform = Transform3D.IDENTITY
	_host.add_child(splat_node)
	estimate = _estimate_lighting(gaussian)
	_place_in_capture()
	_apply_estimated_light_colors()
	var count := int(gaussian.get("point_count"))
	var size := world_bounds.size
	status = "%s · %s gaussians · %.1f × %.1f × %.1f m · play origin" % [
		file_path.get_file(),
		SplatLoader._format_int(count),
		size.x, size.y, size.z,
	]
	status_changed.emit(status)
	_start_bake()
	return {
		"ok": true,
		"message": status,
		"point_count": count,
		"aabb": world_bounds,
		"is_room": is_room,
	}


func apply_relight_mode(mode: String) -> void:
	if splat_node == null:
		return
	match mode:
		"matched":
			splat_node.set("relight_enabled", splat_node.get("lighting") != null)
			splat_node.set("relight_unlit_level", 0.82)
			splat_node.set("relight_light_gain", 0.55)
			splat_node.set("relight_dc_only", true)
		_:
			# Keep the capture. Adding lights on top of radiance looks wrong.
			splat_node.set("relight_enabled", false)
			splat_node.set("relight_unlit_level", 1.0)
			splat_node.set("relight_light_gain", 0.0)
			splat_node.set("relight_dc_only", false)


func poll_bake() -> void:
	if _bake_task < 0 or _bake_job == null:
		return
	var progress: Dictionary = _bake_job.get_status()
	status = "Baking shadow proxy: %s (%d%%)" % [
		str(progress.get("stage", "")),
		int(100.0 * float(progress.get("progress", 0.0))),
	]
	status_changed.emit(status)
	if not WorkerThreadPool.is_task_completed(_bake_task):
		return
	WorkerThreadPool.wait_for_task_completion(_bake_task)
	_bake_task = -1
	var result: Dictionary = _bake_job.get_result()
	_bake_job = null
	if not result.get("ok", false):
		status = "Splat loaded (shadow bake skipped: %s)." % str(result.get("error", "unknown"))
		status_changed.emit(status)
		return
	var lighting := _make_lighting_resource(result)
	if lighting == null:
		status = "Splat loaded (shadow bake produced no resource)."
		status_changed.emit(status)
		return
	var cache_path := _cache_path()
	if not cache_path.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
		ResourceSaver.save(lighting, cache_path)
	_assign_lighting(lighting)
	var size := world_bounds.size
	status = "%s · shadows ready · %.1f × %.1f × %.1f m" % [path.get_file(), size.x, size.y, size.z]
	status_changed.emit(status)


func _start_bake() -> void:
	if _skip_bake or gaussian == null:
		return
	var cache_path := _cache_path()
	if not cache_path.is_empty() and ResourceLoader.exists(cache_path):
		var cached: Resource = ResourceLoader.load(cache_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if cached != null and cached.has_method("matches_source") and bool(cached.call("matches_source", gaussian)):
			_assign_lighting(cached)
			return
	if not ResourceLoader.exists(PIPELINE_PATH, "Script") or not ResourceLoader.exists(BAKE_JOB_PATH, "Script"):
		return
	var pipeline: GDScript = load(PIPELINE_PATH)
	var snapshot: Dictionary = pipeline.create_snapshot(gaussian)
	if not snapshot.get("ok", false):
		status = "Splat loaded (could not snapshot for shadows)."
		status_changed.emit(status)
		return
	var job_script: GDScript = load(BAKE_JOB_PATH)
	_bake_job = job_script.new(snapshot["snapshot"], BAKE_SETTINGS.duplicate())
	_bake_task = WorkerThreadPool.add_task(_bake_job.run, false, "Bake splat lighting proxy")


func _assign_lighting(lighting: Resource) -> void:
	if splat_node == null:
		return
	splat_node.set("lighting", lighting)
	splat_node.set("relight_cast_shadows", true)


func _make_lighting_resource(result: Dictionary) -> Resource:
	if not ResourceLoader.exists(LIGHTING_RESOURCE_PATH, "Script"):
		return null
	var script: GDScript = load(LIGHTING_RESOURCE_PATH)
	if script == null:
		return null
	var lighting: Resource = script.new()
	lighting.source_point_count = int(gaussian.get("point_count"))
	lighting.source_aabb = gaussian.get("aabb")
	lighting.voxel_size = float(result.get("voxel_size", 0.0))
	lighting.splat_data = result.get("splat_data", PackedByteArray())
	var proxy: Dictionary = result.get("proxy", {})
	lighting.proxy_positions = proxy.get("positions", PackedVector3Array())
	lighting.proxy_normals = proxy.get("normals", PackedVector3Array())
	lighting.proxy_indices = proxy.get("indices", PackedInt32Array())
	lighting.bake_settings = result.get("settings", {})
	return lighting


func _place_in_capture() -> void:
	if splat_node == null or gaussian == null:
		return
	_host.transform = Transform3D.IDENTITY
	var xf := splat_node.global_transform
	var fit := _fit_play_origin(xf)
	var stand: Vector3 = fit.get("stand", Vector3.ZERO)
	var span: Vector3 = fit.get("span", Vector3.ONE)
	is_room = span.y >= 1.8 and minf(span.x, span.z) >= 2.4
	var s := 1.0
	var horiz := maxf(span.x, span.z)
	if horiz > 40.0:
		s = 12.0 / horiz
	elif horiz > 0.01 and horiz < 0.35:
		s = 1.6 / horiz
	_host.scale = Vector3.ONE * s
	_host.position = -stand * s
	_catcher.visible = not is_room
	world_bounds = _xform_aabb(splat_node.global_transform, gaussian.get("aabb"))


func _fit_play_origin(xf: Transform3D) -> Dictionary:
	var xyz: PackedVector3Array = gaussian.get("xyz")
	var count := xyz.size()
	var fallback := _xform_aabb(xf, gaussian.get("aabb")).get_center()
	if count <= 0:
		return {"stand": fallback, "span": Vector3.ONE}
	var stride := maxi(1, int(count / 8000.0))
	var ys: PackedFloat32Array = PackedFloat32Array()
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	for i in range(0, count, stride):
		var wp := xf * xyz[i]
		xs.append(wp.x)
		ys.append(wp.y)
		zs.append(wp.z)
	var n := ys.size()
	if n == 0:
		return {"stand": fallback, "span": Vector3.ONE}
	var y_sorted := ys.duplicate()
	y_sorted.sort()
	var x_sorted := xs.duplicate()
	x_sorted.sort()
	var z_sorted := zs.duplicate()
	z_sorted.sort()
	var y_lo := _percentile_sorted(y_sorted, 0.08)
	var y_hi := _percentile_sorted(y_sorted, 0.92)
	var span := Vector3(
		_percentile_sorted(x_sorted, 0.92) - _percentile_sorted(x_sorted, 0.08),
		maxf(y_hi - y_lo, 0.2),
		_percentile_sorted(z_sorted, 0.92) - _percentile_sorted(z_sorted, 0.08)
	)
	# Densest Y slice is the walking surface (floor), not AABB min (floaters).
	var floor_y := _densest_value(ys, y_lo, y_hi)
	var band := clampf(span.y * 0.12, 0.25, 1.4)
	var sx := 0.0
	var sz := 0.0
	var sn := 0
	for i in n:
		if absf(ys[i] - floor_y) > band:
			continue
		sx += xs[i]
		sz += zs[i]
		sn += 1
	if sn < 8:
		return {
			"stand": Vector3(_percentile_sorted(x_sorted, 0.5), floor_y, _percentile_sorted(z_sorted, 0.5)),
			"span": span,
		}
	return {
		"stand": Vector3(sx / float(sn), floor_y, sz / float(sn)),
		"span": span,
	}


static func _percentile_sorted(sorted_vals: PackedFloat32Array, t: float) -> float:
	if sorted_vals.is_empty():
		return 0.0
	var i := clampi(int(round((sorted_vals.size() - 1) * t)), 0, sorted_vals.size() - 1)
	return sorted_vals[i]


static func _densest_value(vals: PackedFloat32Array, lo: float, hi: float) -> float:
	if vals.is_empty():
		return lo
	if hi - lo < 0.05:
		return 0.5 * (lo + hi)
	const BINS := 40
	var counts := PackedInt32Array()
	counts.resize(BINS)
	var span := hi - lo
	for v in vals:
		if v < lo or v > hi:
			continue
		var b := clampi(int((v - lo) / span * float(BINS)), 0, BINS - 1)
		counts[b] += 1
	var best := 0
	for i in BINS:
		if counts[i] > counts[best]:
			best = i
	return lo + (float(best) + 0.5) * span / float(BINS)


func _estimate_lighting(res: Resource) -> Dictionary:
	var data: PackedFloat32Array = res.get("point_data_float")
	var xyz: PackedVector3Array = res.get("xyz")
	var count := int(res.get("point_count"))
	var out := {
		"ambient": Color(0.72, 0.74, 0.78),
		"key_color": Color(1.0, 0.97, 0.92),
		"key_dir": Vector3(-0.35, -0.82, -0.25).normalized(),
		"energy": 1.15,
	}
	if count <= 0 or data.size() < STRUCT_SIZE or xyz.size() != count:
		return out
	var stride := maxi(1, int(count / 3500.0))
	var amb := Color(0, 0, 0, 1)
	var n := 0
	var bright_dir := Vector3.ZERO
	var bright_w := 0.0
	var key_col := Color(0, 0, 0, 1)
	for i in range(0, count, stride):
		var base := i * STRUCT_SIZE
		if base + 14 >= data.size():
			break
		var col := Color(
			clampf(0.5 + SH_C0 * data[base + 12], 0.0, 4.0),
			clampf(0.5 + SH_C0 * data[base + 13], 0.0, 4.0),
			clampf(0.5 + SH_C0 * data[base + 14], 0.0, 4.0)
		)
		amb += col
		n += 1
		var lum := col.get_luminance()
		var p: Vector3 = xyz[i]
		if p.y > 0.05 and lum > 0.04:
			bright_dir += p * lum
			bright_w += lum
			key_col += col * lum
	if n > 0:
		amb /= float(n)
		amb.a = 1.0
		out["ambient"] = Color(clampf(amb.r, 0.05, 1.5), clampf(amb.g, 0.05, 1.5), clampf(amb.b, 0.05, 1.5))
		out["energy"] = clampf(amb.get_luminance() * 1.8 + 0.35, 0.4, 2.0)
	if bright_w > 0.001:
		var from := bright_dir / bright_w
		if from.length_squared() > 0.01:
			# Light travels from the bright region toward the play pad.
			out["key_dir"] = (-from).normalized()
		key_col /= bright_w
		out["key_color"] = Color(clampf(key_col.r, 0.4, 1.6), clampf(key_col.g, 0.4, 1.6), clampf(key_col.b, 0.4, 1.6))
	return out


func _apply_estimated_light_colors() -> void:
	var key_col: Color = estimate.get("key_color", Color.WHITE)
	var amb: Color = estimate.get("ambient", Color(0.7, 0.7, 0.75))
	var dir: Vector3 = estimate.get("key_dir", Vector3.DOWN)
	for light in find_children("*", "Light3D", true, false):
		var id := str((light as Light3D).get_meta("light_id", light.name))
		if id == "splat_key" and light is DirectionalLight3D:
			(light as Light3D).light_color = key_col
			var travel := dir.normalized()
			var origin := Vector3(0.0, 2.4, 0.0)
			(light as Node3D).position = origin
			var up := Vector3.UP
			if absf(travel.dot(up)) > 0.95:
				up = Vector3.FORWARD
			(light as Node3D).look_at(origin + travel, up)
			(light as Light3D).shadow_enabled = true
		elif id == "splat_fill":
			(light as Light3D).light_color = amb.lerp(Color(0.85, 0.88, 1.0), 0.25)
		elif id == "splat_rim":
			(light as Light3D).light_color = key_col.lerp(Color.WHITE, 0.2)


func _make_play_ring() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "PlayRing"
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.92
	mesh.outer_radius = 1.02
	mesh.rings = 24
	mesh.ring_segments = 12
	mi.mesh = mesh
	mi.position = Vector3(0.0, 0.01, 0.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.9, 1.0, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.set_surface_override_material(0, mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _make_catcher() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "ObjectShadowCatcher"
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.5, 4.5)
	mi.mesh = plane
	var mat := ShaderMaterial.new()
	var sh := load("res://assets/shadow_catcher.gdshader")
	if sh:
		mat.shader = sh
	mi.set_surface_override_material(0, mat)
	mi.visible = false
	return mi


func _cache_path() -> String:
	if path.is_empty() or gaussian == null:
		return ""
	var abs_path := SplatLoader.filesystem_path(path)
	var stamp := "%s|%s|%s" % [
		abs_path,
		str(FileAccess.get_modified_time(abs_path)),
		str(int(gaussian.get("point_count"))),
	]
	return CACHE_DIR.path_join("%s.res" % stamp.md5_text())


func _cancel_bake() -> void:
	if _bake_job != null and _bake_job.has_method("request_cancel"):
		_bake_job.request_cancel()
	if _bake_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_bake_task)
	_bake_task = -1
	_bake_job = null


func _is_smoke() -> bool:
	return (
		OS.get_environment("VR_VIEWER_SMOKE") == "1"
		or "--smoke" in OS.get_cmdline_args()
		or "--smoke" in OS.get_cmdline_user_args()
	)


func _exit_tree() -> void:
	_cancel_bake()


static func _xform_aabb(xf: Transform3D, aabb: AABB) -> AABB:
	if aabb.size == Vector3.ZERO:
		return AABB()
	var p := aabb.position
	var s := aabb.size
	var pts := [
		xf * p,
		xf * (p + Vector3(s.x, 0, 0)),
		xf * (p + Vector3(0, s.y, 0)),
		xf * (p + Vector3(0, 0, s.z)),
		xf * (p + Vector3(s.x, s.y, 0)),
		xf * (p + Vector3(s.x, 0, s.z)),
		xf * (p + Vector3(0, s.y, s.z)),
		xf * (p + s),
	]
	var acc := AABB(pts[0], Vector3.ZERO)
	for i in range(1, pts.size()):
		acc = acc.expand(pts[i])
	return acc
