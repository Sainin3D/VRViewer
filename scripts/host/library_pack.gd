class_name LibraryPack
extends RefCounted

## One content pack discovered by a LibraryProvider. Paths are always
## relative to `folder` (the sidecar directory). Absolute sidecar paths
## are stripped by the adapter.

var pack_id := ""
var display_name := ""
var folder := ""
var tags: PackedStringArray = PackedStringArray()
var parts: Array = []
var options: Array = []
var previews: PackedStringArray = PackedStringArray()
var content_hash := ""
var identity: Dictionary = {}
var schema_version := 0
var source_adapter := ""


func has_tag(tag_id: String) -> bool:
	return tags.has(tag_id)


func is_multipart() -> bool:
	if tags.has("multipart"):
		return true
	var n := 0
	for rec in parts:
		if rec is Dictionary and str(rec.get("file", "")) != "":
			n += 1
	return n > 1
