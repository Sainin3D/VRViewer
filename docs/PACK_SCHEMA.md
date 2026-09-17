# Pack / options schema (Karina-first)

Karina naming is inconsistent. We do **not** rename meshes for MVP. We describe them.

## Pack

Top-level folder under an artist vault. `pack_id` = kebab-case folder name (stable unless you deliberately change it). `content_hash` fingerprints meshes so renames/moves can rematch later.

## Parts

`parts[]`: `{ file, role, optional? }` with `file` relative to the pack folder (subpaths allowed: `Body/Body.stl`).

Roles (soft): `base`, `body`, `head`, `hair`, `accessory`, `prop`, `part`, `optional`.

## Options (our standard)

```json
"options": [{
  "id": "variant",
  "label": "Variant",
  "mode": "exclusive",
  "choices": [
    { "id": "sit", "label": "Sit", "folder": "Sit", "files": ["Sit/Chest.stl", "..."], "default": true }
  ]
}]
```

### Modes

| mode | meaning |
|------|---------|
| `exclusive` | pick one choice (Body vs BodyBulge; Sit vs Stnd; Scene vs Simple) |
| `toggle` | include optional extras (default usually off) — `(optional)` in filename |

### Inference used for seeding

1. **Slot families, not raw folders** — group immediate mesh subdirs by slot stem (`Body`/`BodyBulge`/`BSuit` → body; `Head`/`HeadAngry` → head). **Exclusive** only when a slot has 2+ folders. A lone `Body` + lone `Head` is one assembly (no variant UI), not Body XOR Head.
2. **Always-on leftovers** — root meshes and singleton-slot folders always load with the pack. `resolve_meshes` unions selected exclusive/toggle choices with `parts[]` not claimed by any choice.
3. **Optional** — name contains `optional` → toggle group, default off

Nested expression heads (Angry/Sad) stay inside a variant’s `files` for now; a later pass can split expression groups.

## Tags

Canonical kebab-case ids only. Seed tags are weak heuristics (`artist-karina`, `multipart`, keyword hits). Visual audit replaces/extends them — same ids as Issa vocabulary where they overlap (`ball-gag`, `hogtie`, …).

## Load rule (adapter)

`resolve_meshes` loads **default exclusive choices** + non-optional parts when no options exist; optional toggles stay off unless `default: true`.
