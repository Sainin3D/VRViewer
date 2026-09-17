class_name ModelLoader
extends RefCounted

const EXTENSIONS := ["glb", "gltf", "obj", "stl", "fbx"]


static func is_mesh_file(path: String) -> bool:
	return path.get_extension().to_lower() in EXTENSIONS


static func list_mesh_files(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(folder)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and is_mesh_file(name):
			out.append(folder.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


static func load_file(path: String) -> Node3D:
	if DirAccess.dir_exists_absolute(path):
		return null
	if not FileAccess.file_exists(path):
		push_error("ModelLoader: missing file %s" % path)
		return null
	var ext := path.get_extension().to_lower()
	var node: Node3D = null
	match ext:
		"glb", "gltf":
			node = _load_gltf(path)
		"fbx":
			node = _load_fbx(path)
		"stl":
			node = StlLoader.load_path(path)
		"obj":
			node = ObjLoader.load_path(path)
		_:
			push_error("ModelLoader: unsupported extension %s" % ext)
			return null
	if node == null:
		return null
	_convert_importer_meshes(node)
	var fill_missing := ext in ["stl", "fbx"] or not bool(node.get_meta("native_color", false))
	ensure_materials(node, ext in ["stl", "obj", "fbx"], fill_missing)
	snapshot_materials(node)
	if node.name.is_empty() or node.name == "Node":
		node.name = path.get_file().get_basename().validate_node_name()
	return node


static func clay_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.92, 0.92, 0.93, 1.0)
	mat.roughness = 0.38
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_make_opaque(mat, true)
	return mat


static func ensure_materials(node: Node, double_sided := false, fill_missing := true) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var src := mi.get_active_material(i)
				if src == null:
					if fill_missing:
						mi.set_surface_override_material(i, clay_material())
				else:
					var solid := solidify_material(src, double_sided)
					if mi.get_surface_override_material(i) != null:
						mi.set_surface_override_material(i, solid)
					elif mi.mesh is ArrayMesh:
						(mi.mesh as ArrayMesh).surface_set_material(i, solid)
					else:
						mi.set_surface_override_material(i, solid)
	for child in node.get_children():
		ensure_materials(child, double_sided, fill_missing)


static func snapshot_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mats: Array = []
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				mats.append(mi.get_active_material(i))
		mi.set_meta("saved_mats", mats)
	for child in node.get_children():
		snapshot_materials(child)


static func restore_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh and mi.has_meta("saved_mats"):
			var mats: Array = mi.get_meta("saved_mats")
			for i in mi.mesh.get_surface_count():
				var mat: Material = mats[i] if i < mats.size() else null
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		restore_materials(child)


static func solidify_material(src: Material, double_sided := false) -> Material:
	if src is BaseMaterial3D:
		var mat := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
		_make_opaque(mat, double_sided)
		return mat
	return src


static func _make_opaque(mat: BaseMaterial3D, double_sided: bool) -> void:
	mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	var albedo := mat.albedo_color
	albedo.a = 1.0
	mat.albedo_color = albedo
	mat.no_depth_test = false
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	mat.proximity_fade_enabled = false
	mat.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_DISABLED
	mat.refraction_enabled = false
	if double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED


static func triangle_count(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh:
			for i in mesh.get_surface_count():
				total += _surface_triangles(mesh, i)
	for child in node.get_children():
		total += triangle_count(child)
	return total


static func combined_aabb(node: Node3D) -> AABB:
	var boxes: Array[AABB] = []
	_collect_aabbs(node, Transform3D.IDENTITY, boxes, true)
	if boxes.is_empty():
		return AABB()
	var acc := boxes[0]
	for i in range(1, boxes.size()):
		acc = acc.merge(boxes[i])
	return acc


static func _collect_aabbs(node: Node, xf: Transform3D, boxes: Array[AABB], skip_own_transform: bool) -> void:
	var next_xf := xf
	if node is Node3D and not skip_own_transform:
		next_xf = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			boxes.append(_xform_aabb(next_xf, mi.mesh.get_aabb()))
	for child in node.get_children():
		_collect_aabbs(child, next_xf, boxes, false)


static func _xform_aabb(xf: Transform3D, aabb: AABB) -> AABB:
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
	var out := AABB(pts[0], Vector3.ZERO)
	for i in range(1, pts.size()):
		out = out.expand(pts[i])
	return out



static func _load_gltf(path: String) -> Node3D:
	_register_importer_extension()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("glTF load failed (%s): %s" % [error_string(err), path])
		return null
	var scene := doc.generate_scene(state)
	if scene == null:
		push_error("glTF generate_scene returned null: %s" % path)
		return null
	if scene is Node3D:
		return scene as Node3D
	var wrap := Node3D.new()
	wrap.name = path.get_file().get_basename().validate_node_name()
	wrap.add_child(scene)
	return wrap


static func _load_fbx(path: String) -> Node3D:
	if not ClassDB.class_exists("FBXDocument"):
		push_error("FBXDocument is not available in this Godot build")
		return null
	_register_importer_extension()
	var doc: RefCounted = ClassDB.instantiate("FBXDocument")
	var state: RefCounted = ClassDB.instantiate("FBXState")
	var err: Error = doc.call("append_from_file", path, state)
	if err != OK:
		push_error("FBX load failed (%s): %s" % [error_string(err), path])
		return null
	var scene: Node = doc.call("generate_scene", state)
	if scene == null:
		push_error("FBX generate_scene returned null: %s" % path)
		return null
	if scene is Node3D:
		return scene as Node3D
	var wrap := Node3D.new()
	wrap.name = path.get_file().get_basename().validate_node_name()
	wrap.add_child(scene)
	return wrap


static var _ext_registered := false


static func _register_importer_extension() -> void:
	if _ext_registered:
		return
	if ClassDB.class_exists("GLTFDocumentExtensionConvertImporterMesh"):
		var ext: RefCounted = ClassDB.instantiate("GLTFDocumentExtensionConvertImporterMesh")
		GLTFDocument.register_gltf_document_extension(ext)
	_ext_registered = true


static func _convert_importer_meshes(node: Node) -> void:
	for child in node.get_children():
		_convert_importer_meshes(child)
	if node.get_class() == "ImporterMeshInstance3D":
		_replace_importer_mesh(node)


static func _replace_importer_mesh(importer: Node) -> void:
	var mi := MeshInstance3D.new()
	mi.name = importer.name
	if importer is Node3D:
		mi.transform = (importer as Node3D).transform
		mi.visible = (importer as Node3D).visible
	var importer_mesh = importer.get("mesh")
	if importer_mesh != null and importer_mesh.has_method("get_mesh"):
		mi.mesh = importer_mesh.get_mesh()
	var parent := importer.get_parent()
	if parent == null:
		return
	var index := importer.get_index()
	for child in importer.get_children():
		importer.remove_child(child)
		mi.add_child(child)
	parent.remove_child(importer)
	parent.add_child(mi)
	parent.move_child(mi, index)
	importer.free()





static func _surface_triangles(mesh: Mesh, surface: int) -> int:
	var arrays := mesh.surface_get_arrays(surface)
	if arrays.is_empty():
		return 0
	var indices = arrays[Mesh.ARRAY_INDEX]
	if indices and indices.size() > 0:
		return int(indices.size() / 3)
	var verts = arrays[Mesh.ARRAY_VERTEX]
	if verts:
		return int(verts.size() / 3)
	return 0
