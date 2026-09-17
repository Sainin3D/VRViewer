class_name LibraryProvider
extends RefCounted

## Host contract for a content library. Adapters subclass this and scan
## whatever layout they own. The host never interprets sidecar internals
## beyond LibraryPack fields.


func provider_id() -> String:
	return ""


func display_name() -> String:
	return provider_id()


func set_root(_path: String) -> void:
	pass


func get_root() -> String:
	return ""


func list_packs() -> Array[LibraryPack]:
	var empty: Array[LibraryPack] = []
	return empty


func resolve_meshes(_pack: LibraryPack) -> PackedStringArray:
	return PackedStringArray()
