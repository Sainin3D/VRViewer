# library/ (local vaults — not in git)

This folder holds **your** artist/pack vaults for **Library** mode. Mesh packs are gitignored on purpose (size + licensing).

## Layout

```
library/
  <Artist>/
    <Pack>/
      model-tags.json    # sidecar: tags, parts, options, previews
      *.stl / previews…
```

Example (not shipped): `library/Karina/...`

## Quick start for your own packs

1. Create `library/YourName/MyPack/`.
2. Drop mesh files (and optional preview JPGs) into that folder.
3. Add a `model-tags.json` (see [docs/PACK_SCHEMA.md](../docs/PACK_SCHEMA.md) and the root [README](../README.md#library-mode--tagging)).
4. In the app, switch to **Library** — it scans `res://library`.

The viewer never requires renaming your STLs; the sidecar describes them.

## Godot import / cache

Put a `.gdignore` file in this folder (this repo ships one). That tells the **editor** not to import thousands of STLs when you open the project.

The app still reads packs at **runtime** via the real filesystem path (`ProjectSettings.globalize_path("res://library")`). Fast editor open + Library mode both work.

If you already waited through a huge first import, delete the project `.godot/` folder once after pulling this change, then reopen — Godot will stop chewing the vault.

