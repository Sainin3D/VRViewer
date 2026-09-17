class_name TagIndex
extends RefCounted

## Exact-match index on LibraryPack.tags[]. Canonical tag ids are used as-is
## (no aliases in this slice). Rebuild after the provider rescans.

var _by_tag: Dictionary = {}
var _packs: Array[LibraryPack] = []


func rebuild(packs: Array) -> void:
	_by_tag.clear()
	_packs.clear()
	for item in packs:
		if not (item is LibraryPack):
			continue
		var pack: LibraryPack = item
		_packs.append(pack)
		for tag in pack.tags:
			var id := str(tag)
			if id.is_empty():
				continue
			if not _by_tag.has(id):
				var bucket: Array[LibraryPack] = []
				_by_tag[id] = bucket
			var list: Array[LibraryPack] = _by_tag[id]
			list.append(pack)
			_by_tag[id] = list


func all_tags() -> PackedStringArray:
	var keys: Array = _by_tag.keys()
	keys.sort()
	var out := PackedStringArray()
	for k in keys:
		out.append(str(k))
	return out


func packs_with_tag(tag_id: String) -> Array[LibraryPack]:
	var id := tag_id.strip_edges()
	if id.is_empty():
		return _packs.duplicate()
	if not _by_tag.has(id):
		var empty: Array[LibraryPack] = []
		return empty
	var list: Array[LibraryPack] = _by_tag[id]
	return list.duplicate()


static func filter_by_tag(packs: Array, tag_id: String) -> Array[LibraryPack]:
	var index := TagIndex.new()
	index.rebuild(packs)
	return index.packs_with_tag(tag_id)


## Comma-separated tags = AND. Empty query = all packs.
func packs_matching_query(query: String) -> Array[LibraryPack]:
	var q := query.strip_edges()
	if q.is_empty():
		return _packs.duplicate()
	var parts: PackedStringArray = PackedStringArray()
	for raw in q.split(","):
		var id := str(raw).strip_edges().to_lower()
		if id != "":
			parts.append(id)
	if parts.is_empty():
		return _packs.duplicate()
	var out: Array[LibraryPack] = []
	for pack in _packs:
		var ok := true
		for id in parts:
			var hit := false
			for t in pack.tags:
				if str(t).to_lower() == id:
					hit = true
					break
			if not hit:
				ok = false
				break
		if ok:
			out.append(pack)
	return out
