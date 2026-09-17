# Library adapters

This viewer is a **host**. A gallery plugin (or this repo’s first-party `model-tags` adapter) discovers **packs**; the host loads meshes through the existing `ModelLoader` / `ModelAssembly` path.

Dogfood pack: `path/to/Issa` (`pack_id` `issa`, tags include `ball-gag`). Do not rename those STLs.

## Host guarantees

- `LibraryProvider` (`scripts/host/library_provider.gd`) is the only scan API the UI talks to.
- `LibraryPack` is the unit of listing: `pack_id`, `display_name`, `folder`, `tags[]`, `parts[]`, `previews[]`, `content_hash`, `identity`, `schema_version`.
- `TagIndex.packs_with_tag(id)` is **exact match** on `tags[]` (no aliases in this slice). Empty query = all packs.
- `HostEvents` signals: `selection_changed`, `pack_opened`, `assembly_load_requested(paths, shared_origin)`.
- Mesh load stays in the host: `ModelLoader.load_file` + `ModelAssembly.load_paths`. Multipart packs use **shared origin**.
- Sidecar **absolute paths are ignored**. The pack folder is always the directory that contains the sidecar.

## Adapter duties

- Implement `LibraryProvider`: `set_root`, `list_packs`, `resolve_meshes`.
- Scan only what you own. The first-party adapter (`scripts/adapters/model_tags_library.gd`) looks for `model-tags.json` in the root **and one level of subfolders**.
- Parse `schema_version`, `pack_id`, `tags`, `parts`, `previews`, `content_hash`, `identity`. Drop unknown fields.
- `resolve_meshes` returns existing mesh files under `pack.folder` (from `parts[].file`, else a folder listing). Never pass sidecar absolute paths through.
- Do not move, rename, or rewrite user mesh files.

## Try it

1. Enable **Library (model-tags)** in the Files panel.
2. Point the folder field at `path/to/Issa` (or the parent folder if you keep many packs).
3. Type `ball-gag` in the tag filter — pack `issa` should remain.
4. Activate the pack (or Add selected) to load `Base.stl` / `Body.stl` / `Head.stl` / … with shared origin.
