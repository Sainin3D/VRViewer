class_name StlLoader
extends RefCounted

const MAX_TRIANGLES := 8_000_000


static func load_path(path: String) -> MeshInstance3D:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("STL: cannot open %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if bytes.is_empty():
		push_error("STL: empty file %s" % path)
		return null
	if _looks_ascii(bytes):
		return _from_ascii(bytes.get_string_from_utf8(), path)
	return _from_binary(bytes, path)


static func _looks_ascii(bytes: PackedByteArray) -> bool:
	if bytes.size() < 15:
		return false
	var head := bytes.slice(0, mini(80, bytes.size())).get_string_from_ascii().to_lower()
	if not head.begins_with("solid"):
		return false
	# Some binary STLs still start with "solid". Prefer ASCII only when facets exist in text.
	var probe := bytes.slice(0, mini(1024, bytes.size())).get_string_from_ascii().to_lower()
	return probe.contains("facet")


static func _from_binary(bytes: PackedByteArray, path: String) -> MeshInstance3D:
	if bytes.size() < 84:
		push_error("STL: truncated binary header in %s" % path)
		return null
	var tri_count := bytes.decode_u32(80)
	if tri_count <= 0 or tri_count > MAX_TRIANGLES:
		push_error("STL: invalid triangle count %s in %s" % [tri_count, path])
		return null
	var expected := 84 + tri_count * 50
	if bytes.size() < expected:
		push_error("STL: truncated binary body in %s (need %s bytes, have %s)" % [path, expected, bytes.size()])
		return null
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	verts.resize(tri_count * 3)
	normals.resize(tri_count * 3)
	var offset := 84
	for i in tri_count:
		var nx := bytes.decode_float(offset)
		var ny := bytes.decode_float(offset + 4)
		var nz := bytes.decode_float(offset + 8)
		var n := Vector3(nx, ny, nz)
		if n.length_squared() < 0.000001:
			n = Vector3.UP
		else:
			n = n.normalized()
		var base := i * 3
		for v in 3:
			var vo := offset + 12 + v * 12
			verts[base + v] = Vector3(
				bytes.decode_float(vo),
				bytes.decode_float(vo + 4),
				bytes.decode_float(vo + 8)
			)
			normals[base + v] = n
		offset += 50
	return _mesh_instance(verts, normals, path.get_file())


static func _from_ascii(text: String, path: String) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var current_normal := Vector3.UP
	for raw_line in text.split("\n"):
		var line := raw_line.strip_edges()
		if line.is_empty():
			continue
		var lower := line.to_lower()
		if lower.begins_with("facet normal"):
			var parts := line.split(" ", false)
			if parts.size() >= 5:
				current_normal = Vector3(parts[2].to_float(), parts[3].to_float(), parts[4].to_float())
				if current_normal.length_squared() < 0.000001:
					current_normal = Vector3.UP
				else:
					current_normal = current_normal.normalized()
		elif lower.begins_with("vertex"):
			var parts := line.split(" ", false)
			if parts.size() >= 4:
				verts.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
				normals.append(current_normal)
	if verts.size() < 3 or verts.size() % 3 != 0:
		push_error("STL: ASCII parse produced %s vertices in %s" % [verts.size(), path])
		return null
	if verts.size() / 3 > MAX_TRIANGLES:
		push_error("STL: too many triangles in %s" % path)
		return null
	return _mesh_instance(verts, normals, path.get_file())


static func _mesh_instance(verts: PackedVector3Array, normals: PackedVector3Array, node_name: String) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = node_name.get_basename().validate_node_name()
	mi.mesh = mesh
	return mi
