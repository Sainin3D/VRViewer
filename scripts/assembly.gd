class_name ModelAssembly
extends Node3D

signal changed

enum UnitMode { AUTO, MILLIMETERS, CENTIMETERS, METERS, INCHES }

const UNIT_SCALE := {
	UnitMode.MILLIMETERS: 0.001,
	UnitMode.CENTIMETERS: 0.01,
	UnitMode.METERS: 1.0,
	UnitMode.INCHES: 0.0254,
}

var origin_root: Node3D
var parts: Array[Node3D] = []
var link_groups: Dictionary = {}  # gid -> { name, root: Node3D, members: Array }
var part_link: Dictionary = {}  # part instance_id -> { gid, linked: bool }
var _next_link_id := 1
var part_paths: PackedStringArray = []
var keep_shared_origin := false
var model_tint := Color(0.92, 0.92, 0.93, 1.0)
var unit_mode: UnitMode = UnitMode.AUTO
var unit_scale := 1.0
var last_message := ""
var last_triangles := 0
var file_aabb := AABB()
var selected_part: Node3D = null
var rest_scale := 1.0
var size_percent := 100.0
var spawn_transform := Transform3D.IDENTITY

var _highlight_mat: StandardMaterial3D


func _ready() -> void:
	origin_root = Node3D.new()
	origin_root.name = "OriginRoot"
	add_child(origin_root)
	_highlight_mat = StandardMaterial3D.new()
	_highlight_mat.albedo_color = Color(0.95, 0.78, 0.32, 1.0)
	_highlight_mat.roughness = 0.4
	_highlight_mat.emission_enabled = true
	_highlight_mat.emission = Color(0.45, 0.28, 0.05)
	_highlight_mat.emission_energy_multiplier = 0.6
	_highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_highlight_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_highlight_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY


func clear() -> void:
	for child in origin_root.get_children():
		origin_root.remove_child(child)
		child.free()
	parts.clear()
	part_paths.clear()
	selected_part = null
	link_groups.clear()
	part_link.clear()
	last_triangles = 0
	file_aabb = AABB()
	last_message = "Cleared."
	transform = Transform3D.IDENTITY
	origin_root.transform = Transform3D.IDENTITY
	rest_scale = 1.0
	size_percent = 100.0
	spawn_transform = Transform3D.IDENTITY
	changed.emit()


func load_paths(paths: PackedStringArray, replace := true, fit := true) -> bool:
	var had_parts := not parts.is_empty()
	if replace:
		clear()
		had_parts = false
	if paths.is_empty():
		last_message = "No files selected."
		changed.emit()
		return false
	var start_n := parts.size()
	var errors: PackedStringArray = []
	var added := 0
	for path in paths:
		if _add_one(path, errors):
			added += 1
	if added == 0:
		last_message = "Failed to load: %s" % ", ".join(errors)
		changed.emit()
		return false
	file_aabb = _compute_file_aabb()
	if not had_parts:
		_apply_unit_scale()
		if fit:
			_fit_play_area()
			if parts.size() == 1:
				var saved := SceneStore.get_file_percent(part_paths[0])
				if saved > 0.0:
					set_size_percent(saved)
			_capture_spawn()
		else:
			rest_scale = maxf(scale.x, 0.0001)
	elif start_n < parts.size():
		# Append path: always put the new batch on the floor.
		# Multipart/shared-origin packs skip per-node centering, so without this
		# their AABB can sit below y=0 beside an already-fitted first pack.
		if keep_shared_origin:
			ground_parts_from_index(start_n)
		else:
			for i in range(start_n, parts.size()):
				_snap_node_to_world_floor(parts[i])
	var fail_n := errors.size()
	last_message = "Loaded %s file%s, %s tris." % [parts.size(), "" if parts.size() == 1 else "s", _format_int(last_triangles)]
	if fail_n:
		last_message += " Failed: %s." % ", ".join(errors)
	changed.emit()
	return true


func _add_one(path: String, errors: PackedStringArray) -> bool:
	var node := ModelLoader.load_file(path)
	if node == null:
		errors.append(path.get_file())
		return false
	node.set_meta("source_path", path)
	var before := AABB()
	if not parts.is_empty():
		before = world_aabb()
	origin_root.add_child(node)
	parts.append(node)
	part_paths.append(path)
	last_triangles += ModelLoader.triangle_count(node)
	if not bool(node.get_meta("native_color", false)):
		_tint_node(node, model_tint)
		ModelLoader.snapshot_materials(node)
	# Shared-origin parts must keep file scale; origin_root already carries unit scale.
	# Independent parts get their own mm/m guess without double-scaling.
	if not keep_shared_origin and parts.size() > 1:
		var longest := _aabb_of(node).get_longest_axis_size()
		var root_s := maxf(origin_root.scale.x, 0.0001)
		if longest > 20.0 and root_s > 0.5:
			node.scale = Vector3.ONE * 0.001
		elif longest <= 20.0 and root_s < 0.05:
			node.scale = Vector3.ONE * (1.0 / root_s)
	if not keep_shared_origin:
		var box := _aabb_of(node)
		node.position -= box.get_center() * node.scale.x
		if parts.size() > 1:
			_offset_new_part(node, before)
	return true


func _offset_new_part(node: Node3D, before: AABB) -> void:
	var box := _xform_aabb(node.global_transform, _aabb_of(node))
	var gap := 0.2
	var dx := (before.position.x + before.size.x + gap) - box.position.x
	node.global_position.x += dx




func ground_parts_from_index(start_index: int) -> void:
	## Shift parts[start_index..] so the batch AABB sits on y=0 (world).
	if start_index < 0 or start_index >= parts.size():
		return
	var box := AABB()
	var has := false
	for i in range(start_index, parts.size()):
		var b := _xform_aabb(parts[i].global_transform, _aabb_of(parts[i]))
		box = b if not has else box.merge(b)
		has = true
	if not has:
		return
	var dy := -box.position.y
	if absf(dy) < 0.00001:
		return
	for i in range(start_index, parts.size()):
		parts[i].global_position.y += dy
	changed.emit()


func offset_parts_from_index(start_index: int, gap := 0.35) -> void:
	## Slide newly added parts to the +X side of everything before start_index.
	if start_index <= 0 or start_index >= parts.size():
		return
	var before := AABB()
	var has_before := false
	for i in range(start_index):
		var box := _xform_aabb(parts[i].global_transform, _aabb_of(parts[i]))
		before = box if not has_before else before.merge(box)
		has_before = true
	if not has_before:
		return
	var after := AABB()
	var has_after := false
	for i in range(start_index, parts.size()):
		var box2 := _xform_aabb(parts[i].global_transform, _aabb_of(parts[i]))
		after = box2 if not has_after else after.merge(box2)
		has_after = true
	if not has_after:
		return
	var dx := (before.position.x + before.size.x + gap) - after.position.x
	for i in range(start_index, parts.size()):
		parts[i].global_position.x += dx
	ground_parts_from_index(start_index)
	changed.emit()



func set_unit_mode(mode: UnitMode) -> void:
	unit_mode = mode
	if parts.is_empty():
		return
	_apply_unit_scale()
	_frame_for_inspect()
	changed.emit()


func set_keep_shared_origin(value: bool) -> void:
	keep_shared_origin = value
	if part_paths.is_empty():
		return
	var stored := part_paths.duplicate()
	load_paths(stored)


func set_view_scale(value: float) -> void:
	set_size_percent((value / maxf(rest_scale, 0.0001)) * 100.0)


func view_scale() -> float:
	return scale.x


func set_size_percent(percent: float) -> void:
	size_percent = clampf(percent, 10.0, 400.0)
	var s := rest_scale * (size_percent / 100.0)
	scale = Vector3.ONE * maxf(s, 0.0001)
	_snap_to_floor()
	if parts.size() == 1:
		SceneStore.set_file_percent(part_paths[0], size_percent)
	changed.emit()


func return_to_origin() -> void:
	var kept := size_percent
	position = spawn_transform.origin
	rotation = spawn_transform.basis.get_euler()
	set_size_percent(kept)


func set_model_tint(color: Color) -> void:
	model_tint = color
	for part in parts:
		_tint_node(part, color)
		ModelLoader.snapshot_materials(part)
	changed.emit()


func _tint_node(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var src := mi.get_active_material(i)
				if src is BaseMaterial3D:
					var mat := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
					mat.albedo_color = color
					mi.set_surface_override_material(i, mat)
				elif src == null:
					var clay := ModelLoader.clay_material()
					clay.albedo_color = color
					mi.set_surface_override_material(i, clay)
	for child in node.get_children():
		_tint_node(child, color)


func _capture_spawn() -> void:
	rest_scale = maxf(scale.x, 0.0001)
	size_percent = 100.0
	spawn_transform = transform


func _snap_to_floor() -> void:
	if parts.is_empty():
		return
	var box := world_aabb()
	position.y += -box.position.y


func _fit_play_area() -> void:
	if parts.is_empty():
		return
	rotation = Vector3.ZERO
	scale = Vector3.ONE
	var local := _aabb_of(origin_root)
	var longest := local.get_longest_axis_size() * origin_root.scale.x
	if longest < 0.00001:
		_snap_to_floor()
		return
	scale = Vector3.ONE * (1.2 / longest)
	_place_on_floor(Vector3(0.0, 0.0, -1.4))
	rest_scale = scale.x
	size_percent = 100.0


func dump_state() -> Dictionary:
	return {
		"keep_origin": keep_shared_origin,
		"size_percent": size_percent,
		"rest_scale": rest_scale,
		"assembly_position": position,
		"assembly_rotation": rotation,
		"assembly_scale": scale,
		"parts": dump_parts(),
	}


func dump_parts() -> Array:
	var out: Array = []
	for part in parts:
		var gscale := part.global_transform.basis.get_scale()
		out.append({
			"path": str(part.get_meta("source_path", "")),
			"position": part.position,
			"rotation": part.rotation,
			"scale": part.scale,
			"global_position": part.global_position,
			"global_rotation": part.global_rotation,
			"global_scale": gscale,
		})
	return out


func apply_part_transforms(records: Array) -> void:
	var used: Dictionary = {}
	for rec in records:
		var path := str(rec.get("path", ""))
		var part := _part_for_path(path, used)
		if part == null:
			continue
		if rec.has("global_position"):
			var gpos: Vector3 = rec.get("global_position", part.global_position)
			var grot: Vector3 = rec.get("global_rotation", part.global_rotation)
			var gscl: Vector3 = rec.get("global_scale", part.global_transform.basis.get_scale())
			var basis := Basis.from_euler(grot)
			var sx := gscl.x if absf(gscl.x) > 0.000001 else 1.0
			var sy := gscl.y if absf(gscl.y) > 0.000001 else 1.0
			var sz := gscl.z if absf(gscl.z) > 0.000001 else 1.0
			part.global_transform = Transform3D(basis.scaled(Vector3(sx, sy, sz)), gpos)
		else:
			part.position = rec.get("position", part.position)
			part.rotation = rec.get("rotation", part.rotation)
			part.scale = rec.get("scale", part.scale)
	changed.emit()


func restore_pose(data: Dictionary) -> void:
	var rest := float(data.get("rest_scale", rest_scale))
	if rest > 0.000001:
		rest_scale = rest
	size_percent = clampf(float(data.get("size_percent", size_percent)), 10.0, 400.0)
	position = data.get("assembly_position", position)
	rotation = data.get("assembly_rotation", rotation)
	scale = data.get("assembly_scale", scale)
	spawn_transform = transform


func _part_for_path(path: String, used: Dictionary) -> Node3D:
	for part in parts:
		if str(part.get_meta("source_path", "")) != path:
			continue
		var id := part.get_instance_id()
		if used.has(id):
			continue
		used[id] = true
		return part
	return null


func nearest_part(from: Vector3, max_dist: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist
	for part in parts:
		var box := _xform_aabb(part.global_transform, _aabb_of(part))
		var d := _distance_to_aabb(from, box)
		if d <= best_d:
			best_d = d
			best = part
	return best


func _snap_node_to_world_floor(node: Node3D) -> void:
	var box := _xform_aabb(node.global_transform, _aabb_of(node))
	node.global_position.y += -box.position.y


static func _distance_to_aabb(p: Vector3, box: AABB) -> float:
	var min_p := box.position
	var max_p := box.position + box.size
	var closest := Vector3(
		clampf(p.x, min_p.x, max_p.x),
		clampf(p.y, min_p.y, max_p.y),
		clampf(p.z, min_p.z, max_p.z)
	)
	return p.distance_to(closest)


func world_aabb() -> AABB:
	if parts.is_empty():
		return AABB()
	return _xform_aabb(global_transform, _aabb_of(self))


func size_meters() -> Vector3:
	return world_aabb().size


func select_part(part: Node3D) -> void:
	selected_part = part
	_refresh_highlight()
	changed.emit()


func select_part_index(index: int) -> void:
	if index < 0 or index >= parts.size():
		select_part(null)
		return
	select_part(parts[index])


func nudge_selected(delta: Vector3) -> void:
	if selected_part == null:
		return
	selected_part.position += delta
	changed.emit()


func pick_part(from: Vector3, dir: Vector3) -> Node3D:
	var best: Node3D = null
	var best_t := 1.0e9
	for part in parts:
		var box := _xform_aabb(part.global_transform, _aabb_of(part))
		var hit := _ray_aabb(from, dir, box)
		if hit >= 0.0 and hit < best_t:
			best_t = hit
			best = part
	return best


func _center_each_part() -> void:
	for part in parts:
		var box := _aabb_of(part)
		part.position -= box.get_center()


func _apply_unit_scale() -> void:
	unit_scale = _resolve_unit_scale()
	origin_root.scale = Vector3.ONE * unit_scale


func _resolve_unit_scale() -> float:
	if unit_mode != UnitMode.AUTO:
		return UNIT_SCALE[unit_mode]
	var longest := file_aabb.get_longest_axis_size()
	# CAD/print meshes are usually millimeters. Real-meter assets are typically < ~20 units.
	if longest > 20.0:
		return 0.001
	return 1.0


func _frame_for_inspect(target_size := 1.15) -> void:
	if file_aabb.size == Vector3.ZERO:
		file_aabb = _compute_file_aabb()
	var longest := file_aabb.get_longest_axis_size() * unit_scale
	var inspect := 1.0
	if longest > 0.00001:
		inspect = target_size / longest
	scale = Vector3.ONE * inspect
	rotation = Vector3.ZERO
	_place_on_floor(Vector3(0.0, 0.0, -1.4))
	rest_scale = scale.x
	size_percent = 100.0


func _place_on_floor(center_xz: Vector3) -> void:
	var local := _aabb_of(origin_root)
	var s := unit_scale * scale.x
	var scaled := AABB(local.position * s, local.size * s)
	var center := scaled.get_center()
	position.x = center_xz.x - center.x
	position.z = center_xz.z - center.z
	position.y = -scaled.position.y


func _compute_file_aabb() -> AABB:
	# AABB of parts in origin_root local space, ignoring unit scale.
	var stored := origin_root.scale
	origin_root.scale = Vector3.ONE
	var box := _aabb_of(origin_root)
	origin_root.scale = stored
	return box


func _refresh_highlight() -> void:
	for part in parts:
		if part == selected_part:
			_set_override(part, _highlight_mat)
		else:
			ModelLoader.restore_materials(part)


func _set_override(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_set_override(child, mat)


func _aabb_of(node: Node) -> AABB:
	var boxes: Array[AABB] = []
	_collect_aabbs(node, Transform3D.IDENTITY, boxes, true)
	if boxes.is_empty():
		return AABB()
	var acc := boxes[0]
	for i in range(1, boxes.size()):
		acc = acc.merge(boxes[i])
	return acc


func _collect_aabbs(node: Node, xf: Transform3D, boxes: Array[AABB], skip_own_transform: bool) -> void:
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


static func _ray_aabb(from: Vector3, dir: Vector3, box: AABB) -> float:
	if dir.length_squared() < 0.0000001:
		return -1.0
	var inv := Vector3(
		INF if is_zero_approx(dir.x) else 1.0 / dir.x,
		INF if is_zero_approx(dir.y) else 1.0 / dir.y,
		INF if is_zero_approx(dir.z) else 1.0 / dir.z
	)
	var t0 := (box.position - from) * inv
	var t1 := (box.position + box.size - from) * inv
	var tmin := Vector3(minf(t0.x, t1.x), minf(t0.y, t1.y), minf(t0.z, t1.z))
	var tmax := Vector3(maxf(t0.x, t1.x), maxf(t0.y, t1.y), maxf(t0.z, t1.z))
	var t_enter := maxf(tmin.x, maxf(tmin.y, tmin.z))
	var t_exit := minf(tmax.x, minf(tmax.y, tmax.z))
	if t_exit < 0.0 or t_enter > t_exit:
		return -1.0
	return t_enter if t_enter >= 0.0 else 0.0


static func _format_int(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = s[i] + out
		count += 1
	return out


func create_link_group(display_name: String, member_parts: Array, linked := true) -> String:
	## Wrap members under a group root (preserves global transforms). Pack loads use this.
	var members: Array[Node3D] = []
	for p in member_parts:
		if p is Node3D and is_instance_valid(p) and parts.has(p):
			members.append(p)
	if members.is_empty():
		return ""
	var gid := "g%d" % _next_link_id
	_next_link_id += 1
	var root := Node3D.new()
	root.name = "LinkGroup_%s" % gid
	origin_root.add_child(root)
	for part in members:
		_detach_from_any_group(part)
		var gt := part.global_transform
		var parent := part.get_parent()
		if parent:
			parent.remove_child(part)
		root.add_child(part)
		part.global_transform = gt
		part_link[part.get_instance_id()] = {"gid": gid, "linked": linked}
	link_groups[gid] = {"name": display_name, "root": root, "members": members.duplicate()}
	changed.emit()
	return gid


func _detach_from_any_group(part: Node3D) -> void:
	var id := part.get_instance_id()
	if not part_link.has(id):
		return
	var info: Dictionary = part_link[id]
	var gid := str(info.get("gid", ""))
	if not link_groups.has(gid):
		part_link.erase(id)
		return
	var g: Dictionary = link_groups[gid]
	var members: Array = g.get("members", [])
	members.erase(part)
	g["members"] = members
	if members.is_empty():
		var root: Node3D = g.get("root")
		if root and is_instance_valid(root) and root.get_child_count() == 0:
			root.queue_free()
		link_groups.erase(gid)
	part_link.erase(id)


func set_part_linked(part: Node3D, linked: bool) -> void:
	if part == null or not is_instance_valid(part):
		return
	var id := part.get_instance_id()
	if not part_link.has(id):
		return
	var info: Dictionary = part_link[id]
	var gid := str(info.get("gid", ""))
	if not link_groups.has(gid):
		return
	var g: Dictionary = link_groups[gid]
	var root: Node3D = g.get("root")
	if root == null or not is_instance_valid(root):
		return
	var gt := part.global_transform
	if linked:
		# Re-link keeps current pose/offset.
		if part.get_parent() != root:
			var parent := part.get_parent()
			if parent:
				parent.remove_child(part)
			root.add_child(part)
			part.global_transform = gt
		info["linked"] = true
	else:
		# Unlink: keep world pose under origin_root.
		if part.get_parent() != origin_root:
			var parent2 := part.get_parent()
			if parent2:
				parent2.remove_child(part)
			origin_root.add_child(part)
			part.global_transform = gt
		info["linked"] = false
	part_link[id] = info
	changed.emit()


func is_part_linked(part: Node3D) -> bool:
	if part == null:
		return false
	var id := part.get_instance_id()
	if not part_link.has(id):
		return false
	return bool(part_link[id].get("linked", false))


func get_part_group_id(part: Node3D) -> String:
	if part == null:
		return ""
	var id := part.get_instance_id()
	if not part_link.has(id):
		return ""
	return str(part_link[id].get("gid", ""))


func get_part_group_name(part: Node3D) -> String:
	var gid := get_part_group_id(part)
	if gid == "" or not link_groups.has(gid):
		return ""
	return str(link_groups[gid].get("name", gid))


func grab_root_for(part: Node3D) -> Node3D:
	## VR grab target: group root if linked, else the part.
	if part == null or not is_instance_valid(part):
		return null
	if not is_part_linked(part):
		return part
	var gid := get_part_group_id(part)
	if gid == "" or not link_groups.has(gid):
		return part
	var root: Node3D = link_groups[gid].get("root")
	if root and is_instance_valid(root):
		return root
	return part


func remove_part(part: Node3D) -> bool:
	## Delete one part (not the whole group).
	if part == null or not is_instance_valid(part):
		return false
	var idx := parts.find(part)
	if idx < 0:
		return false
	_detach_from_any_group(part)
	if selected_part == part:
		selected_part = null
	parts.remove_at(idx)
	if idx < part_paths.size():
		part_paths.remove_at(idx)
	part.queue_free()
	changed.emit()
	return true


func list_part_rows() -> Array:
	var rows: Array = []
	for i in range(parts.size()):
		var part := parts[i]
		var path := part_paths[i] if i < part_paths.size() else ""
		rows.append({
			"part": part,
			"path": path,
			"name": path.get_file() if path != "" else part.name,
			"gid": get_part_group_id(part),
			"group_name": get_part_group_name(part),
			"linked": is_part_linked(part),
		})
	return rows


func create_link_group_from_index(start_index: int, display_name: String) -> String:
	if start_index < 0 or start_index >= parts.size():
		return ""
	var members: Array = []
	for i in range(start_index, parts.size()):
		members.append(parts[i])
	return create_link_group(display_name, members, true)


