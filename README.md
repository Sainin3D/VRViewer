# VR Viewer

Desktop + SteamVR / OpenXR viewer for 3D-print and CAD meshes. Browse folders or a tagged **Library** of packs, assemble multi-part models on a shared origin, and inspect them with a desktop orbit camera or in room-scale VR.

Built with **Godot 4.7** (Forward+ / Vulkan) and OpenXR.

## Features

- Load **glTF, GLB, OBJ, STL, FBX** at runtime from disk (not imported into the project)
- **Classic files** browser or **Library** mode (`model-tags.json` sidecars, tag filter, pack options)
- Shared-origin multipart assembly (CAD/print kits) or side-by-side placement
- Units: Auto / mm / cm / m / inch
- Desktop orbit / pan / zoom / fly; Frame and reset pose
- VR: floating dashboard (laser + trigger), grab / two-hand scale, locomotion, snap turn
- Environments: Studio, Dungeon, Foggy battlefield, Penthouse, Passthrough, Gaussian splat
- Model tint presets + mixer

Private artist vaults (e.g. large pack libraries) stay on your machine — see [`library/README.md`](library/README.md). This repo does **not** ship Godot binaries or mesh vaults.

## Requirements

| Need | Notes |
| --- | --- |
| [Godot 4.7](https://godotengine.org/download/windows/) Windows 64-bit | Standard build, **not** .NET |
| Vulkan GPU | Forward+ will not run on OpenGL-only machines |
| SteamVR + OpenXR (for VR) | Set SteamVR as the OpenXR runtime |

## Run

This is a **Godot 4.7 project** (source). We do **not** ship the Godot editor binary in git — you bring one of these:

### Option A — Portable exe in the project folder (easiest handoff)

1. Clone / copy this repo.
2. Download [Godot 4.7 Windows 64-bit](https://godotengine.org/download/windows/) (standard build, **not** .NET).
3. Put `Godot_v4.7-stable_win64.exe` next to `project.godot` (same folder as `run.bat`).
4. Double-click **`run.bat`** (opens the **editor**). Use `run.bat play` only when you want to run the main scene without the editor.

`run.bat` / `./run.sh` prefer that local binary and open the **editor** by default (same as double-clicking Godot and opening the project). `run.bat play` / `./run.sh play` runs the main scene instead.

### Option B — Installed Godot

1. Install Godot 4.7 system-wide (or via Scoop/package manager) so `godot` is on `PATH`, **or** install under a normal Godot folder.
2. Double-click `run.bat` / run `./run.sh`, **or** open `project.godot` from the Godot Project Manager and press Play.

### VR

Start SteamVR first, then Play (or F6).

Logs (if the window flashes and closes): `%APPDATA%\Godot\app_userdata\VR Model Viewer\logs\godot.log`.

> **Players vs contributors:** contributors run the editor as above. A one-click “game only” build for players is a separate Godot **export** (Windows/Linux pack) we can add later — that is not the same as committing `Godot*.exe` into the repo.

## Library mode & tagging

**Library** scans `res://library/<Artist>/<Pack>/` for packs that have a `model-tags.json` sidecar. Classic folder browsing stays available for raw folders.

### Sidecar (source of truth)

Each pack folder gets a `model-tags.json`. Minimum useful fields:

```json
{
  "schema_version": 1,
  "pack_id": "my-pack",
  "display_name": "My Pack",
  "tags": ["hogtie", "latex"],
  "parts": [
    { "file": "Body.stl", "role": "body" },
    { "file": "Head.stl", "role": "head" }
  ],
  "previews": ["1.jpg"],
  "options": []
}
```

- **tags**: kebab-case ids; Library filter is **AND** across tokens you type.
- **parts**: mesh files relative to the pack folder (subfolders allowed, e.g. `Body/Torso.stl`).
- **previews**: image paths relative to the pack folder.
- **options**: exclusive / toggle groups for variants (Body vs BodyBulge, optional accessories). Full rules: [`docs/PACK_SCHEMA.md`](docs/PACK_SCHEMA.md).

The host loads **selected options** plus always-on parts that are not claimed by a choice. Lone `Body` + `Head` folders are one assembly (no false XOR picker); true alts (e.g. `Body` / `BSuit`, `Sit` / `Stnd`) become exclusive choices.

### Add your own library

1. Create `library/YourArtist/YourPack/` and drop meshes (+ optional preview images).
2. Write `model-tags.json` as above (or copy from `docs/PACK_SCHEMA.md`).
3. Open the project in Godot → **Library** mode → filter / select → **Add pack**.

Adapters: first-party scanner is `scripts/adapters/model_tags_library.gd`. Host API notes: [`ADAPTERS.md`](ADAPTERS.md).

## Project layout

```
scripts/          # viewer, XR, assembly, loaders, Library host/adapters
scenes/           # main scene
assets/           # built-in art
addons/gdgs/      # Gaussian splat renderer (MIT)
samples/          # tiny demo meshes
splats/           # splat captures (demo included)
library/          # local vaults only (meshes gitignored)
docs/             # pack schema / tagging
```

## License

Application code in this repository: **MIT** (unless a file says otherwise).

Third-party: `addons/gdgs` is MIT (GDGS). Your mesh packs and previews remain **your** content — do not assume redistributable rights for anything you drop under `library/`.

## Status

Active workshop tool. VR dashboard, Library tagging, and pack options are evolving; large private vaults stay out of git by design.

## Troubleshooting


### First open is slow / building cache forever

If `library/` holds a big mesh vault, Godot will try to **import** it unless the folder has a `.gdignore`. This repo includes `library/.gdignore` so the editor skips that vault; Library mode still loads packs at runtime. After pulling, delete `.godot/` once and reopen so old import work is discarded.

### `Could not find type "EnvironmentStage"` (and a cascade of missing class names)

That usually means Godot has not rebuilt its script class cache (the `.godot/` folder is gitignored except for a seed cache). It is **not** caused by adding packs under `library/`.

1. Fully quit Godot.
2. Delete the project’s `.godot/` folder (keep `project.godot` and `scripts/`).
3. Open the folder that contains `project.godot` with **Godot 4.7**.
4. Wait for the import/scan to finish, then run the main scene again.

If it still fails, confirm `scripts/stage/environment_stage.gd` and friends exist after your pull, and that Editor Settings is not treating GDScript warnings as errors.

