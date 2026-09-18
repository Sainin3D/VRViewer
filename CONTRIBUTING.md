# Contributing to VR Viewer

Thanks for wanting to help. This project accepts changes through pull requests. **`main` is protected** — only [@Sainin3D](https://github.com/Sainin3D) can approve and merge.

## Quick path

1. Fork the repo (or use a branch if you already have write access).
2. Create a branch from `main` for your change.
3. Keep Godot **4.7** source-only: do not commit `Godot*.exe`, `.godot/`, or personal `library/` mesh vaults (see `.gitignore`).
4. Open a pull request **into `main`** and describe what changed and how you tested (desktop and/or SteamVR).
5. Wait for review. Stale review approvals are dismissed when new commits are pushed.

## What to work on

- Bug fixes and VR/desktop UX improvements
- Tagging / library adapter docs (`docs/`, `library/README.md`, `ADAPTERS.md`)
- Sample-safe content and tooling that does not ship copyrighted mesh packs

## What not to include

- Binary engine builds or large mesh libraries
- Secrets, tokens, or personal paths
- Unrelated reformatting of files you did not need to touch

## Questions

Open a GitHub Issue on this repo. Keep discussion in Issues/PRs so decisions stay public.
