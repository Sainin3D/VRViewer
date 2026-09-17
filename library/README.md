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
