class_name SceneStore
extends RefCounted

const SCENES_DIR := "user://scenes"
const SCALE_PATH := "user://file_scales.cfg"


static func list_scenes() -> PackedStringArray:
	_ensure_dir()
	var out := PackedStringArray()
	var dir := DirAccess.open(SCENES_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".cfg"):
			out.append(name.get_basename())
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


static func save_scene(scene_name: String, data: Dictionary) -> bool:
	_ensure_dir()
	var safe := scene_name.validate_filename()
	if safe.is_empty():
		return false
	var cfg := ConfigFile.new()
	cfg.set_value("scene", "name", safe)
	cfg.set_value("scene", "environment", str(data.get("environment", "studio")))
	cfg.set_value("scene", "lighting", int(data.get("lighting", 0)))
	cfg.set_value("scene", "dimmer", float(data.get("dimmer", 1.0)))
	cfg.set_value("scene", "splat_path", str(data.get("splat_path", "")))
	cfg.set_value("scene", "keep_origin", bool(data.get("keep_origin", true)))
	cfg.set_value("scene", "size_percent", float(data.get("size_percent", 100.0)))
	cfg.set_value("scene", "rest_scale", float(data.get("rest_scale", 1.0)))
	cfg.set_value("scene", "assembly_position", data.get("assembly_position", Vector3.ZERO))
	cfg.set_value("scene", "assembly_rotation", data.get("assembly_rotation", Vector3.ZERO))
	cfg.set_value("scene", "assembly_scale", data.get("assembly_scale", Vector3.ONE))
	var parts: Array = data.get("parts", [])
	cfg.set_value("scene", "part_count", parts.size())
	for i in parts.size():
		var p: Dictionary = parts[i]
		var sec := "part_%s" % i
		cfg.set_value(sec, "path", str(p.get("path", "")))
		cfg.set_value(sec, "position", p.get("position", Vector3.ZERO))
		cfg.set_value(sec, "rotation", p.get("rotation", Vector3.ZERO))
		cfg.set_value(sec, "scale", p.get("scale", Vector3.ONE))
		cfg.set_value(sec, "global_position", p.get("global_position", p.get("position", Vector3.ZERO)))
		cfg.set_value(sec, "global_rotation", p.get("global_rotation", p.get("rotation", Vector3.ZERO)))
		cfg.set_value(sec, "global_scale", p.get("global_scale", p.get("scale", Vector3.ONE)))
	return cfg.save(_scene_path(safe)) == OK


static func load_scene(scene_name: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(_scene_path(scene_name)) != OK:
		return {}
	var parts: Array = []
	var count := int(cfg.get_value("scene", "part_count", 0))
	for i in count:
		var sec := "part_%s" % i
		var rec := {
			"path": str(cfg.get_value(sec, "path", "")),
			"position": cfg.get_value(sec, "position", Vector3.ZERO),
			"rotation": cfg.get_value(sec, "rotation", Vector3.ZERO),
			"scale": cfg.get_value(sec, "scale", Vector3.ONE),
		}
		if cfg.has_section_key(sec, "global_position"):
			rec["global_position"] = cfg.get_value(sec, "global_position", Vector3.ZERO)
			rec["global_rotation"] = cfg.get_value(sec, "global_rotation", Vector3.ZERO)
			rec["global_scale"] = cfg.get_value(sec, "global_scale", Vector3.ONE)
		parts.append(rec)
	return {
		"name": str(cfg.get_value("scene", "name", scene_name)),
		"environment": str(cfg.get_value("scene", "environment", "studio")),
		"lighting": int(cfg.get_value("scene", "lighting", 0)),
		"dimmer": float(cfg.get_value("scene", "dimmer", 1.0)),
		"splat_path": str(cfg.get_value("scene", "splat_path", "")),
		"keep_origin": bool(cfg.get_value("scene", "keep_origin", true)),
		"size_percent": float(cfg.get_value("scene", "size_percent", 100.0)),
		"rest_scale": float(cfg.get_value("scene", "rest_scale", 1.0)),
		"has_assembly_pose": cfg.has_section_key("scene", "assembly_position"),
		"assembly_position": cfg.get_value("scene", "assembly_position", Vector3.ZERO),
		"assembly_rotation": cfg.get_value("scene", "assembly_rotation", Vector3.ZERO),
		"assembly_scale": cfg.get_value("scene", "assembly_scale", Vector3.ONE),
		"parts": parts,
	}


static func delete_scene(scene_name: String) -> void:
	var path := _scene_path(scene_name)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func get_file_percent(path: String) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SCALE_PATH) != OK:
		return 0.0
	return float(cfg.get_value("scales", path, 0.0))


static func set_file_percent(path: String, percent: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SCALE_PATH)
	cfg.set_value("scales", path, percent)
	cfg.save(SCALE_PATH)


static func _scene_path(scene_name: String) -> String:
	return SCENES_DIR.path_join(scene_name.validate_filename() + ".cfg")


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SCENES_DIR):
		DirAccess.make_dir_recursive_absolute(SCENES_DIR)
