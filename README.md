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

1. Clone this repo.
2. Install Godot 4.7 (standard).
3. Optional: place `Godot_v4.7-stable_win64.exe` next to `project.godot` and double-click `run.bat`, **or** open `project.godot` from the Godot Project Manager and press Play.
4. Sample meshes live in `samples/` — try **Classic files** → `samples/assembly` → **Add all**.

Logs (if the window flashes and closes): `%APPDATA%\Godot\app_userdata\VR Model Viewer\logs\godot.log`.

### SteamVR / OpenXR

1. Start SteamVR with the headset on.
2. SteamVR → **Settings → OpenXR** → set **SteamVR** as the OpenXR runtime.
3. Launch the app → **Enter VR** (or `F1`). **A** shows/hides the dashboard; **Esc** exits VR.

Godot talks to the headset through **OpenXR**, not the legacy OpenVR plugin.

### VR controls (Index / similar)

| Input | Action |
| --- | --- |
| **A** (or menu) | Show / hide / recenter dashboard |
| Trigger on dashboard | Click UI |
| Stick / trackpad over dashboard | Scroll |
| Trigger near model | Grab |
| Both triggers near model | Scale |
| Left stick (not on board) | Walk |
| Right stick flick | Snap turn |

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

Active personal / workshop tool. VR dashboard, Library tagging, and pack options are evolving; large private vaults stay out of git by design.
