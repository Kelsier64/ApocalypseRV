# ApocalypseRV Codex Guide

ApocalypseRV is a first-person survival prototype in Godot. The main scene is `world/main_world.tscn`. Keep project guidance in this file, workflows in `.agents/skills/`, and Codex configuration in `.codex/`. Use these entry points for agent guidance. Exclude `CLAUDE.md`, `.claude/`, and `.mcp.json` from routine reads and searches, and leave their maintenance to the other harness.

## Start here

- Use the live facts from `scripts/agent/session-context.ps1`. Run it once if startup context is absent. Use `scripts/agent/module-index.ps1 [filter]` to look up classes.
- `player/`, `enemies/`, and `props/` hold actors and interactables. `rv/` and `equipment/` hold vehicle and mounted systems. `world/` holds terrain, streaming, POIs, and buildings. `core/` holds shared rules. See the [codebase guide](docs/guides/codebase.md) for placement and cleanup.
- Verify current behavior in code. `docs/README.md` indexes the docs: `GDD.md` for design intent, `architecture.md` for cross-module structure, `docs/systems/<system>.md` for one system's features and contracts, `docs/guides/` for how-tos, and `docs/plans/` for unfinished work. Read the generation and save version constants in `world/terrain/world_profile.gd`, `rv/checkpoint.gd`, and `rv/vehicle_snapshot.gd`.

## Project rules

- Keep player-facing text in English and put hints, controls, item names, and status in screen-space UI. Never add `Label3D`, `TextMesh`, floating text, or hints hidden in textures. Use integrated textures, decals, or device-screen artwork for essential in-fiction text such as signs and instrument displays.
- Keep intermediate assets, logs, backups, and captures under `.godot/` or another ignored directory. Stage only deliverables and a few representative evidence images. Run `scripts/agent/check-staged.ps1` after staging and before committing.
- Git is trunk-based: finished work lands on `origin/main`. Commit each verified unit of work with only its own paths staged (never `git add -A`, `git add .`, `git commit -a` or `git stash`, because other sessions share this checkout). At the end of a task, fetch, rebase unpushed commits onto `origin/main`, and `git push origin HEAD:main`; hold the push and report on a rebase conflict or failing test. Put multi-day or risky work on its own branch and open a PR. Ask before force-pushing, hard resets, rewriting pushed commits, or deleting branches and worktrees you did not create.
- Change local save formats directly and remove obsolete compatibility branches. Save development is paused until late in the project (2026-11-15): keep the current F6/F9 checkpoint and its tests working, but do not extend it for new features. Register every new Item or Monster scene in `core/save_scene_catalog.gd`, because the tutorial stage restart and the F6 checkpoint share this whitelist.
- Use fixed seeds for reproduction while preserving intentional variation in generation, encounters, and loot.
- Read scene and resource values in tests or assert relative behavior. Avoid hard-coded copies of gameplay tuning.

## Work and verify

- Use PowerShell from the repo root. Godot is at `C:\Program Files\godot\godot.exe`; check `.godot-version` for the pinned version. If sandbox access blocks the executable, retry through the tool's escalation mechanism. For long commands, use `exec_command` with a short yield and wait on its session.
- Run the smallest useful automated check. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1` imports once and runs the top-level tests and main-scene smoke check. For Markdown-only edits, check wording and relative links with `scripts/agent/check-docs.ps1`.
- For game feel or manual validation, build or reuse a playground, launch it at the relevant state, and give the user a short checklist. For fixed visual states, inspect a relevant capture. Report what you verified and what still needs hands-on testing.
- Ask about material ambiguity or broad architecture changes. Keep scene integration and final verification in the active session. Use the Codex image workflow for reference images and keep generated inputs in ignored work folders until selected for delivery.

## Skills

| Skill | Use for |
| --- | --- |
| `apocalypse-rv-tests` | Selecting, running, writing, and debugging Godot tests |
| `apocalypse-rv-playtest` | Playgrounds, fixed renders, and hands-on validation |
| `apocalypse-rv-3d-scenes` | Building or integrating 3D content in Godot |
| `apocalypse-rv-image-to-3d` | Building reference images and generating 3D props with local ComfyUI |
| `apocalypse-rv-docs` | Maintaining project documentation |
| `apocalypse-rv-harness` | Maintaining this project's Codex guidance, hooks, and skills |
