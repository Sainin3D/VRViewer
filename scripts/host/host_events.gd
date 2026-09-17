class_name HostEvents
extends RefCounted

## Host-facing signals for library UI and future gallery plugins.
## This slice emits them from main.gd; adapters do not emit.

## The highlighted pack in the library list changed (may be null).
signal selection_changed(pack: LibraryPack)

## User opened a pack (activate / load).
signal pack_opened(pack: LibraryPack)

## Host is about to load mesh paths into ModelAssembly.
## shared_origin is true for multipart packs.
signal assembly_load_requested(paths: PackedStringArray, shared_origin: bool)
