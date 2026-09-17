class_name ObjLoader
extends RefCounted

## Runtime OBJ + MTL loader. One file becomes one MeshInstance3D with a
## surface per material so Kd / map_Kd / vertex colours survive in the viewer.

const MAX_TRIANGLES := 8_000_000


static func load_path(path: String) -> MeshInstance3D:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("OBJ: cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var text := file.get_as_text()
	file.close()
	var folder := path.get_base_dir()
	var positions: Array[Vector3] = []
	var colors_in: Array[Color] = []
	var normals_in: Array[Vector3] = []
	var uvs_in: Array[Vector2] = []
	var materials: Dictionary = {}
	var surf_order: PackedStringArray = []
	var surfs: Dictionary = {}
	var current := "_default"
	_ensure_surf(surfs, surf_order, current)
	var tri_count := 0
	var has_vertex_color := false

	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		if line.begins_with("\uFEFF"):
			line = line.substr(1).strip_edges()
		var parts := line.split(" ", false)
		if parts.is_empty():
			continue
		match parts[0]:
			"mtllib":
				var mtl_name := line.substr(parts[0].length()).strip_edges()
				if mtl_name.is_empty() and parts.size() >= 2:
					mtl_name = parts[1]
				_parse_mtl(folder.path_join(mtl_name), folder, materials)
			"usemtl":
				current = parts[1] if parts.size() >= 2 else "_default"
				if current.is_empty():
					current = "_default"
				_ensure_surf(surfs, surf_order, current)
			"v":
				if parts.size() >= 4:
					positions.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
					if parts.size() >= 7:
						colors_in.append(Color(parts[4].to_float(), parts[5].to_float(), parts[6].to_float()))
						has_vertex_color = true
					else:
						colors_in.append(Color.WHITE)
			"vn":
				if parts.size() >= 4:
					normals_in.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
			"vt":
				if parts.size() >= 3:
					uvs_in.append(Vector2(parts[1].to_float(), 1.0 - parts[2].to_float()))
			"f":
				var face := parts.slice(1)
				if face.size() < 3:
					continue
				var fan := _triangulate(face)
				var surf: Dictionary = surfs[current]
				var out_verts: PackedVector3Array = surf["verts"]
				var out_normals: PackedVector3Array = surf["normals"]
				var out_uvs: PackedVector2Array = surf["uvs"]
				var out_cols: PackedColorArray = surf["colors"]
				for corner in fan:
					var idx := _parse_corner(corner)
					var p_i := _resolve_index(positions.size(), idx[0])
					if p_i < 0:
						continue
					out_verts.append(positions[p_i])
					out_cols.append(colors_in[p_i] if p_i < colors_in.size() else Color.WHITE)
					var n_i := _resolve_index(normals_in.size(), idx[2])
					if n_i >= 0:
						out_normals.append(normals_in[n_i])
						surf["has_n"] = true
					else:
						out_normals.append(Vector3.UP)
					var t_i := _resolve_index(uvs_in.size(), idx[1])
					if t_i >= 0:
						out_uvs.append(uvs_in[t_i])
						surf["has_uv"] = true
					else:
						out_uvs.append(Vector2.ZERO)
				surf["verts"] = out_verts
				surf["normals"] = out_normals
				surf["uvs"] = out_uvs
				surf["colors"] = out_cols
				tri_count += int(fan.size() / 3)
				if tri_count > MAX_TRIANGLES:
					push_error("OBJ: too many triangles in %s" % path)
					return null

	var mesh := ArrayMesh.new()
	var native := has_vertex_color
	for surf_name in surf_order:
		var surf: Dictionary = surfs[surf_name]
		var verts: PackedVector3Array = surf["verts"]
		if verts.size() < 3:
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		if bool(surf.get("has_n", false)):
			arrays[Mesh.ARRAY_NORMAL] = surf["normals"]
		if bool(surf.get("has_uv", false)):
			arrays[Mesh.ARRAY_TEX_UV] = surf["uvs"]
		if has_vertex_color:
			arrays[Mesh.ARRAY_COLOR] = surf["colors"]
		var surface_index := mesh.get_surface_count()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if not bool(surf.get("has_n", false)):
			var st := SurfaceTool.new()
			st.create_from(mesh, surface_index)
			st.generate_normals()
			var rebuilt := st.commit()
			if rebuilt and rebuilt.get_surface_count() > 0:
				var rebuilt_arrays := rebuilt.surface_get_arrays(0)
				mesh.surface_remove(surface_index)
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rebuilt_arrays)
				surface_index = mesh.get_surface_count() - 1
		var mat := _material_from_mtl(materials.get(surf_name, {}), has_vertex_color)
		if _mtl_has_color(materials.get(surf_name, {})) or has_vertex_color:
			native = true
		mesh.surface_set_material(surface_index, mat)

	if mesh.get_surface_count() == 0:
		push_error("OBJ: no faces in %s" % path)
		return null
	var mi := MeshInstance3D.new()
	mi.name = path.get_file().get_basename().validate_node_name()
	mi.mesh = mesh
	mi.set_meta("native_color", native)
	return mi


static func _ensure_surf(surfs: Dictionary, order: PackedStringArray, key: String) -> void:
	if surfs.has(key):
		return
	surfs[key] = {
		"verts": PackedVector3Array(),
		"normals": PackedVector3Array(),
		"uvs": PackedVector2Array(),
		"colors": PackedColorArray(),
		"has_n": false,
		"has_uv": false,
	}
	order.append(key)


static func _parse_mtl(mtl_path: String, obj_folder: String, materials: Dictionary) -> void:
	var path := mtl_path.replace("\\", "/")
	if not FileAccess.file_exists(path):
		path = obj_folder.path_join(mtl_path.get_file())
	if not FileAccess.file_exists(path):
		push_warning("OBJ: missing MTL %s" % mtl_path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var text := file.get_as_text()
	file.close()
	var mtl_folder := path.get_base_dir()
	var current := ""
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var parts := line.split(" ", false)
		if parts.is_empty():
			continue
		var key := parts[0].to_lower()
		match key:
			"newmtl":
				current = parts[1] if parts.size() >= 2 else ""
				if current != "":
					if not materials.has(current):
						materials[current] = {}
			"kd":
				_set_mtl_color(materials, current, "kd", parts)
			"ka":
				_set_mtl_color(materials, current, "ka", parts)
			"ks":
				_set_mtl_color(materials, current, "ks", parts)
			"ke":
				_set_mtl_color(materials, current, "ke", parts)
			"ns":
				if current != "" and parts.size() >= 2:
					materials[current]["ns"] = parts[1].to_float()
			"ni":
				if current != "" and parts.size() >= 2:
					materials[current]["ni"] = parts[1].to_float()
			"d":
				if current != "" and parts.size() >= 2:
					materials[current]["d"] = parts[1].to_float()
			"tr":
				if current != "" and parts.size() >= 2:
					materials[current]["d"] = 1.0 - parts[1].to_float()
			"illum":
				if current != "" and parts.size() >= 2:
					materials[current]["illum"] = parts[1].to_int()
			"map_kd":
				_set_mtl_map(materials, current, "map_kd", line, mtl_folder, obj_folder)
			"map_ks":
				_set_mtl_map(materials, current, "map_ks", line, mtl_folder, obj_folder)
			"map_ke":
				_set_mtl_map(materials, current, "map_ke", line, mtl_folder, obj_folder)
			"map_bump", "bump", "norm", "map_n":
				_set_mtl_map(materials, current, "map_bump", line, mtl_folder, obj_folder)


static func _set_mtl_color(materials: Dictionary, current: String, key: String, parts: PackedStringArray) -> void:
	if current.is_empty() or parts.size() < 4:
		return
	materials[current][key] = Color(parts[1].to_float(), parts[2].to_float(), parts[3].to_float())


static func _set_mtl_map(materials: Dictionary, current: String, key: String, line: String, mtl_folder: String, obj_folder: String) -> void:
	if current.is_empty():
		return
	var tex := _texture_path_from_map_line(line)
	if tex.is_empty():
		return
	var resolved := _resolve_texture(tex, mtl_folder, obj_folder)
	if resolved != "":
		materials[current][key] = resolved


static func _texture_path_from_map_line(line: String) -> String:
	var parts := line.split(" ", false)
	if parts.size() < 2:
		return ""
	return parts[parts.size() - 1].replace("\\", "/")


static func _resolve_texture(tex: String, mtl_folder: String, obj_folder: String) -> String:
	var name := tex.replace("\\", "/")
	var candidates := PackedStringArray([
		name,
		mtl_folder.path_join(name),
		obj_folder.path_join(name),
		mtl_folder.path_join(name.get_file()),
		obj_folder.path_join(name.get_file()),
		obj_folder.path_join("textures").path_join(name.get_file()),
		obj_folder.path_join("maps").path_join(name.get_file()),
	])
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""


static func _load_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		push_warning("OBJ: could not load texture %s" % path)
		return null
	if img.is_compressed():
		img.decompress()
	return ImageTexture.create_from_image(img)


static func _mtl_has_color(props: Dictionary) -> bool:
	if props.is_empty():
		return false
	if props.has("map_kd"):
		return true
	if props.has("kd"):
		var kd: Color = props["kd"]
		if absf(kd.r - kd.g) > 0.02 or absf(kd.g - kd.b) > 0.02:
			return true
		if kd.r < 0.82 or kd.r > 0.98:
			return true
	return props.has("ke")


static func _material_from_mtl(props: Dictionary, vertex_color: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.92, 0.93, 1.0)
	mat.roughness = 0.38
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if props.has("kd"):
		var kd: Color = props["kd"]
		kd.a = 1.0
		mat.albedo_color = kd
	if props.has("map_kd"):
		var tex := _load_texture(str(props["map_kd"]))
		if tex:
			mat.albedo_texture = tex
			if not props.has("kd"):
				mat.albedo_color = Color.WHITE
	if props.has("ks"):
		var ks: Color = props["ks"]
		mat.metallic = clampf((ks.r + ks.g + ks.b) / 3.0, 0.0, 1.0)
	if props.has("ns"):
		var ns := float(props["ns"])
		mat.roughness = clampf(1.0 - (ns / 256.0), 0.12, 1.0)
	if props.has("ke"):
		var ke: Color = props["ke"]
		if ke.get_luminance() > 0.001:
			mat.emission_enabled = true
			mat.emission = ke
			mat.emission_energy_multiplier = 1.0
	if props.has("map_ke"):
		var emit_tex := _load_texture(str(props["map_ke"]))
		if emit_tex:
			mat.emission_enabled = true
			mat.emission_texture = emit_tex
	if props.has("map_bump"):
		var bump := _load_texture(str(props["map_bump"]))
		if bump:
			mat.normal_enabled = true
			mat.normal_texture = bump
	if vertex_color:
		mat.vertex_color_use_as_albedo = true
	return mat


static func _triangulate(face: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(1, face.size() - 1):
		out.append(face[0])
		out.append(face[i])
		out.append(face[i + 1])
	return out


static func _parse_corner(token: String) -> Array[int]:
	var bits := token.split("/")
	var pi := 0
	var ti := 0
	var ni := 0
	if bits.size() >= 1 and bits[0] != "":
		pi = bits[0].to_int()
	if bits.size() >= 2 and bits[1] != "":
		ti = bits[1].to_int()
	if bits.size() >= 3 and bits[2] != "":
		ni = bits[2].to_int()
	return [pi, ti, ni]


static func _resolve_index(arr_size: int, index: int) -> int:
	if index > 0:
		var i := index - 1
		if i >= 0 and i < arr_size:
			return i
	elif index < 0:
		var i := arr_size + index
		if i >= 0 and i < arr_size:
			return i
	return -1
