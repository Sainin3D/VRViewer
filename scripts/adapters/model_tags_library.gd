class_name ModelTagsLibrary
extends LibraryProvider

## First-party adapter: model-tags.json sidecars under the in-app library/.
## Root may be res://library (artist vaults) or res://library/Karina (one vault).

const SIDECAR_NAME := "model-tags.json"
const PROVIDER := "model-tags"


var _root := ""


func provider_id() -> String:
	return PROVIDER


func display_name() -> String:
	return "model-tags.json library"


func set_root(path: String) -> void:
	_root = path.replace("\\", "/").rstrip("/")


func get_root() -> String:
	return _root


func list_packs() -> Array[LibraryPack]:
	var out: Array[LibraryPack] = []
	if _root.is_empty() or not DirAccess.dir_exists_absolute(_root):
		return out
	# Sidecar directly on root (unusual).
	_collect_sidecar(_root, out)
	var dir := DirAccess.open(_root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with(".") and dir.current_is_dir():
			var child := _root.path_join(name)
			# Pack folders directly under root (vault root = Karina).
			_collect_sidecar(child, out)
			# Artist vault: library/Karina/<Pack>
			_collect_child_packs(child, out)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _collect_child_packs(folder: String, out: Array[LibraryPack]) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with(".") and dir.current_is_dir():
			_collect_sidecar(folder.path_join(name), out)
		name = dir.get_next()
	dir.list_dir_end()


func resolve_meshes(pack: LibraryPack, selections: Dictionary = {}) -> PackedStringArray:
	var out := PackedStringArray()
	if pack == null or pack.folder.is_empty():
		return out
	var seen: Dictionary = {}
	var selected: Dictionary = {}

	if pack.options is Array and pack.options.size() > 0:
		for group in pack.options:
			if typeof(group) != TYPE_DICTIONARY:
				continue
			var mode := str(group.get("mode", "exclusive"))
			var gid := str(group.get("id", ""))
			var choices: Array = group.get("choices", [])
			if mode == "toggle":
				var enabled_ids: Dictionary = {}
				var has_sel := selections.has(gid)
				if has_sel:
					var raw: Variant = selections[gid]
					if raw is Array:
						for x in raw:
							enabled_ids[str(x)] = true
					elif typeof(raw) == TYPE_DICTIONARY:
						for k in raw:
							if bool(raw[k]):
								enabled_ids[str(k)] = true
					elif str(raw) != "":
						enabled_ids[str(raw)] = true
				for ch in choices:
					if typeof(ch) != TYPE_DICTIONARY:
						continue
					var cid := str(ch.get("id", ""))
					var on := false
					if has_sel:
						on = enabled_ids.has(cid)
					else:
						on = bool(ch.get("default", false))
					if on:
						_add_choice_files(pack, ch, selected)
			else:
				var picked: Dictionary = {}
				if selections.has(gid):
					var want := str(selections[gid])
					for ch in choices:
						if typeof(ch) != TYPE_DICTIONARY:
							continue
						if str(ch.get("id", "")) == want:
							picked = ch
							break
				if picked.is_empty():
					for ch in choices:
						if typeof(ch) != TYPE_DICTIONARY:
							continue
						if bool(ch.get("default", false)):
							picked = ch
							break
				if picked.is_empty() and choices.size() > 0 and typeof(choices[0]) == TYPE_DICTIONARY:
					picked = choices[0]
				if not picked.is_empty():
					_add_choice_files(pack, picked, selected)
		for full in selected.keys():
			out.append(str(full))
		# Always-on parts: anything in parts[] not claimed by an option choice.
		# Lets Body+Head assemblies keep Floor/etc., and Head stay loaded when
		# only Body vs BSuit is an exclusive slot.
		var claimed: Dictionary = {}
		for group2 in pack.options:
			if typeof(group2) != TYPE_DICTIONARY:
				continue
			for ch2 in group2.get("choices", []):
				if typeof(ch2) != TYPE_DICTIONARY:
					continue
				for f2 in ch2.get("files", []):
					var rel2 := _relative_name(str(f2))
					if rel2 != "":
						claimed[rel2.to_lower()] = true
		for rec2 in pack.parts:
			if not (rec2 is Dictionary):
				continue
			if bool(rec2.get("optional", false)):
				continue
			var rel_p := _relative_name(str(rec2.get("file", "")))
			if rel_p.is_empty() or claimed.has(rel_p.to_lower()):
				continue
			if rel_p.to_lower().contains("optional"):
				continue
			var full_p := pack.folder.path_join(rel_p)
			if not ModelLoader.is_mesh_file(full_p) or not FileAccess.file_exists(full_p):
				continue
			if selected.has(full_p):
				continue
			selected[full_p] = true
			out.append(full_p)
		if not out.is_empty():
			return out

	for rec in pack.parts:
		if not (rec is Dictionary):
			continue
		if bool(rec.get("optional", false)):
			continue
		var rel := _relative_name(str(rec.get("file", "")))
		if rel.is_empty():
			continue
		if rel.to_lower().contains("optional"):
			continue
		var full := pack.folder.path_join(rel)
		if not ModelLoader.is_mesh_file(full) or not FileAccess.file_exists(full):
			continue
		if seen.has(full):
			continue
		seen[full] = true
		out.append(full)
	if out.is_empty():
		return ModelLoader.list_mesh_files(pack.folder)
	return out


func _add_choice_files(pack: LibraryPack, choice: Dictionary, selected: Dictionary) -> void:
	var files: Array = choice.get("files", [])
	for f in files:
		var rel := _relative_name(str(f))
		if rel.is_empty():
			continue
		var full := pack.folder.path_join(rel)
		if ModelLoader.is_mesh_file(full) and FileAccess.file_exists(full):
			selected[full] = true
	var folder := str(choice.get("folder", "")).strip_edges()
	if folder != "" and files.is_empty():
		var sub := pack.folder.path_join(_relative_name(folder))
		if DirAccess.dir_exists_absolute(sub):
			for path in ModelLoader.list_mesh_files(sub):
				selected[path] = true


func _collect_sidecar(folder: String, out: Array[LibraryPack]) -> void:
	var sidecar := folder.path_join(SIDECAR_NAME)
	if not FileAccess.file_exists(sidecar):
		return
	# Dedupe by pack_id + folder
	for existing in out:
		if existing.folder == folder.replace("\\", "/"):
			return
	var pack := parse_sidecar(sidecar, folder)
	if pack != null:
		out.append(pack)


static func parse_sidecar(sidecar_path: String, folder: String) -> LibraryPack:
	var text := FileAccess.get_file_as_string(sidecar_path)
	if text.is_empty():
		return null
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("model-tags: invalid JSON %s" % sidecar_path)
		return null
	var data: Dictionary = parsed
	var pack := LibraryPack.new()
	pack.source_adapter = PROVIDER
	pack.folder = folder.replace("\\", "/")
	pack.schema_version = int(data.get("schema_version", 0))
	pack.pack_id = str(data.get("pack_id", "")).strip_edges()
	pack.display_name = str(data.get("display_name", pack.pack_id))
	pack.content_hash = str(data.get("content_hash", ""))
	var ident: Variant = data.get("identity", {})
	pack.identity = ident if typeof(ident) == TYPE_DICTIONARY else {}
	if pack.pack_id.is_empty():
		pack.pack_id = folder.get_file().to_lower()
	var raw_tags: Variant = data.get("tags", [])
	if raw_tags is Array:
		for t in raw_tags:
			var id := str(t).strip_edges()
			if id != "" and not pack.tags.has(id):
				pack.tags.append(id)
	var raw_parts: Variant = data.get("parts", [])
	if raw_parts is Array:
		for rec in raw_parts:
			if typeof(rec) != TYPE_DICTIONARY:
				continue
			var rel := _relative_name(str(rec.get("file", "")))
			if rel.is_empty():
				continue
			pack.parts.append({
				"file": rel,
				"role": str(rec.get("role", "")),
				"optional": bool(rec.get("optional", false)),
			})
	var raw_previews: Variant = data.get("previews", [])
	if raw_previews is Array:
		for p in raw_previews:
			var rel := _relative_name(str(p))
			if rel != "":
				pack.previews.append(rel)
	var raw_options: Variant = data.get("options", [])
	if raw_options is Array:
		pack.options = raw_options
	return pack


static func _relative_name(raw: String) -> String:
	var n := raw.strip_edges().replace("\\", "/")
	if n.is_empty():
		return ""
	if n.is_absolute_path() or n.begins_with("/") or (n.length() > 1 and n[1] == ":"):
		return ""
	if n.contains(".."):
		return ""
	while n.begins_with("./"):
		n = n.substr(2)
	return n
