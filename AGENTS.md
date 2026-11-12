# ApocalypseRV Agent Guide

Single-player first-person survival prototype in Godot 4.7.2: drive an RV, scavenge buildings, craft, and survive monsters that climb and wreck the vehicle. Main scene: `world/main_world.tscn`. This file is shared by every coding agent; Claude Code also reads [CLAUDE.md](CLAUDE.md).

## Start Here

Facts that drift (branch state, version constants, test count, last full test result) come from the repository, not from prose. Claude Code receives them at session start; other agents run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent/session-context.ps1
```

Version constants live in `world/terrain/world_profile.gd` (`generation_version`), `rv/checkpoint.gd` and `rv/vehicle_snapshot.gd` (`VERSION`). For a full class index generated from code, run `scripts/agent/module-index.ps1 [filter]`.

Docs lag behind code. Root `README.md`, `GDD.md` and `architecture.md` state intent but carry dated history; `docs/validation/`, `docs/report/` and `docs/archive/` are historical records. Verify a doc claim against code before relying on it, and correct stale statements you touch.

## Map

| Path | Holds |
|---|---|
| `player/`, `enemies/`, `props/` | Actors, interaction, AI, items |
| `rv/`, `equipment/` | Vehicle physics, save checkpoint, mounted devices |
| `world/` | Terrain streaming, chunks, POIs, buildings, interiors |
| `core/` | Shared rules and contracts: items, saves, climbing math, placement, settings |
| `assets/`, `art_source/` | Runtime art; editable sources and build inputs |
| `tests/`, `scripts/` | Automated tests, fixtures, manual playgrounds; runner, builders, agent tools |

Placement, reference and cleanup rules: [docs/guides/codebase.md](docs/guides/codebase.md).

## Commands

```powershell
godot --editor --path .
godot --path .
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

The last command imports once, then runs every top-level `tests/test_*.gd` and the main-scene smoke check. It stops at the first failure unless you pass `-KeepGoing`. Load the `godot-tests` skill before choosing, writing or debugging tests.

## Hard Rules

1. **In-game text.** Use English and only what the player or setting needs. Never put hints, controls, item names or status in the 3D world, including `Label3D`, `TextMesh`, floating, camera-facing, glowing or unshaded text. Essential prompts belong in screen-space UI. World text is allowed only where the fiction demands it (a physical sign, a maker's plate, an instrument screen). Finish it as integrated texture, decal or device-screen art, and never smuggle hints into textures. This applies to reference images and generated assets too.
2. **Nothing intermediate in Git.** Keep work files, screenshots, recordings, logs, archives and editor backups (`.blend1`) under `.godot/` or another ignored path. Commit only game assets, code, tests, concise docs and at most a few representative evidence images. Run `scripts/agent/check-staged.ps1` before committing.
3. **Saves are disposable.** Change save formats directly, delete old local saves when needed, and remove compatibility branches instead of extending them.
4. **Randomness is gameplay.** Use it for meaningful variation in generation, encounters and loot. Preserve guarantees the player relies on, and use fixed seeds to reproduce a run.
5. **Tests read their baselines.** Never copy tuning values (energy, colors, speeds, timings) from scenes into tests as literals. Read them from the scene or resource under test, or assert relative behavior.

Claude Code enforces rules 1 and 2 with hooks. Other agents apply them by hand. `check-staged.ps1` also rejects new `Label3D`/`TextMesh` in game code, however the edit was made.

## Working Defaults

- Ask early when a requirement, preference or tradeoff could materially change the result. Offer concise choices and keep doing independent work.
- Report architecture problems you notice. Ask before large architectural changes.
- Validate with the smallest set that covers the changed behavior and its risks. Skip tests for simple, low-risk edits. For docs-only changes, check wording, consistency and links (`scripts/agent/check-links.ps1 <files>`); do not launch Godot.
- Report what you checked, what you did not, and any material uncertainty. When the user must inspect something, name exactly what. Never claim visual or hands-on verification you did not do.
- Work token-efficiently: use `rg`, read targeted ranges, batch independent reads, and reuse established findings.
- Delegate only narrow, self-contained work, such as broad searches or independent checks. Keep scene modeling and 3D integration in the main agent.

## Git

- Before new work, ask whether to branch from `origin/main`. Default: stay on the current branch, and keep follow-ups on it.
- Finish and validate, review `git status` and the diff, remove task-generated clutter, and commit the validated changes. Preserve and report unrelated user changes.
- Ask before pushing or creating or updating a PR.

## Skills

Load a skill when its trigger applies. Sources live in `.agents/skills/`. After changing a skill's `name` or `description`, run `scripts/agent/sync-skills.ps1` to regenerate the Claude Code entry points.

| Skill | Load when |
|---|---|
| `godot-tests` | Choosing, running, writing or debugging automated tests or CI failures |
| `playtest` | A change needs live on-screen verification in the running game |
| `docs-maintenance` | Editing `README.md`, `GDD.md`, `architecture.md`, or anything under `docs/` |
| `apocalypse-rv-3d-scenes` | Building or editing 3D scenes, or replacing visual assets |
| `comfyui-image-to-3d` | Generating a 3D prop from a reference image with local ComfyUI |

## Codex Notes

- If the sandbox cannot reach Godot (`C:\Program Files\godot\godot.exe`), retry with `sandbox_permissions: "require_escalated"`.
- Subagent models: `gpt-6.1-sol` for deep reasoning, `gpt-6-luna` for simple tasks, `gpt-6.1-terra` for desktop control.
- Hooks do not run for Codex: run `session-context.ps1` at the start and `check-staged.ps1` before every commit.
