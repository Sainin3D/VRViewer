class_name SplatLoader
extends RefCounted

## Runtime loader for Gaussian splat files. Uses GDGS 3.3.0 decoders so a
## user-picked .ply/.splat/.sog/.glb/.usdz does not need an editor import.

const EXTENSIONS := ["ply", "splat", "sog", "usdz"]
const OPTIONAL_MESH_SPLAT := ["glb", "gltf"]
const APP_DIR := "res://splats"

const BUILDER_PATH := "res://addons/gdgs/importers/builders/gaussian_resource_builder.gd"
const PLY_READER_PATH := "res://addons/gdgs/importers/parsers/binary_ply_reader.gd"
const STANDARD_PLY_PATH := "res://addons/gdgs/importers/decoders/standard_ply_decoder.gd"
const COMPRESSED_PLY_PATH := "res://addons/gdgs/importers/decoders/compressed_ply_decoder.gd"
const SPLAT_DEC_PATH := "res://addons/gdgs/importers/decoders/splat_decoder.gd"
const SOG_DEC_PATH := "res://addons/gdgs/importers/decoders/sog_decoder.gd"
const GLTF_DEC_PATH := "res://addons/gdgs/importers/decoders/gltf_decoder.gd"
const NUREC_DEC_PATH := "res://addons/gdgs/importers/decoders/nurec_decoder.gd"


static func is_available() -> bool:
	return ResourceLoader.exists(BUILDER_PATH, "Script") and ResourceLoader.exists(STANDARD_PLY_PATH, "Script")


static func is_splat_file(path: String) -> bool:
	var ext := path.get_extension().to_lower()
	if ext in EXTENSIONS:
		return true
	# .compressed.ply uses a double suffix; get_extension() is still "ply".
	return path.to_lower().ends_with(".compressed.ply")


static func may_be_gaussian_mesh(path: String) -> bool:
	return path.get_extension().to_lower() in OPTIONAL_MESH_SPLAT


static func app_dir() -> String:
	var path := ProjectSettings.globalize_path(APP_DIR).replace("\\", "/")
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
	return path


static func filesystem_path(path: String) -> String:
	var p := path.replace("\\", "/")
	if p.begins_with("res://") or p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	return p


static func load_path(path: String) -> Dictionary:
	if not is_available():
		return _fail("Gaussian splat plugin is missing (addons/gdgs).")
	var abs_path := filesystem_path(path)
	if abs_path.is_empty() or not FileAccess.file_exists(abs_path):
		return _fail("Splat file not found: %s" % path.get_file())
	var decode: Dictionary = _decode_source(abs_path)
	if not decode.get("ok", false):
		return _fail(str(decode.get("message", "Could not decode splat.")))
	var builder: GDScript = load(BUILDER_PATH)
	if builder == null:
		return _fail("Gaussian resource builder failed to load.")
	var build: Dictionary = builder.build(decode["canonical"])
	if not build.get("ok", false):
		return _fail(str(build.get("message", "Could not build gaussian resource.")))
	var resource: Resource = build.get("resource")
	if resource == null:
		return _fail("Decoder produced no gaussian resource.")
	return {
		"ok": true,
		"resource": resource,
		"path": abs_path,
		"point_count": int(resource.get("point_count")),
		"aabb": resource.get("aabb"),
		"message": "Loaded %s gaussians." % _format_int(int(resource.get("point_count"))),
	}


static func _decode_source(source_file: String) -> Dictionary:
	var lower := source_file.to_lower()
	if lower.ends_with(".gltf") or lower.ends_with(".glb"):
		return _call_decode(GLTF_DEC_PATH, source_file)
	if lower.ends_with(".splat"):
		return _call_decode(SPLAT_DEC_PATH, source_file)
	if lower.ends_with(".sog"):
		return _call_decode(SOG_DEC_PATH, source_file)
	if lower.ends_with(".usdz"):
		return _call_decode(NUREC_DEC_PATH, source_file)
	if lower.ends_with(".ply"):
		var reader: GDScript = load(PLY_READER_PATH)
		if reader == null:
			return _fail("PLY reader failed to load.")
		var header: Dictionary = reader.read(source_file, false)
		if not header.get("ok", false):
			return header
		if _is_compressed_ply(source_file, header, reader):
			return _call_decode(COMPRESSED_PLY_PATH, source_file)
		return _call_decode(STANDARD_PLY_PATH, source_file)
	return _fail("Unsupported gaussian splat extension: %s" % source_file.get_extension())


static func _call_decode(script_path: String, source_file: String) -> Dictionary:
	if not ResourceLoader.exists(script_path, "Script"):
		return _fail("Decoder missing: %s" % script_path.get_file())
	var script: GDScript = load(script_path)
	if script == null or not script.can_instantiate():
		return _fail("Decoder failed to compile: %s" % script_path.get_file())
	var result: Variant = script.call("decode", source_file)
	if typeof(result) != TYPE_DICTIONARY:
		return _fail("Decoder returned nothing.")
	return result


static func _is_compressed_ply(source_file: String, header: Dictionary, reader: GDScript) -> bool:
	if source_file.to_lower().ends_with(".compressed.ply"):
		return true
	var chunk_element: Dictionary = reader.get_element(header, "chunk")
	var vertex_element: Dictionary = reader.get_element(header, "vertex")
	if chunk_element.is_empty() or vertex_element.is_empty():
		return false
	var property_map: Dictionary = vertex_element.get("property_map", {})
	return (
		property_map.has("packed_position")
		and property_map.has("packed_rotation")
		and property_map.has("packed_scale")
		and property_map.has("packed_color")
	)


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}


static func _format_int(n: int) -> String:
	var s := str(n)
	var out := ""
	var i := s.length()
	var c := 0
	while i > 0:
		i -= 1
		if c == 3:
			out = "," + out
			c = 0
		out = s[i] + out
		c += 1
	return out
