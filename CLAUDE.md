# ApocalypseRV

Single-player first-person survival prototype in Godot 4.7.2: drive an RV, scavenge buildings, craft, and survive monsters that climb and wreck the vehicle. Main scene: `world/main_world.tscn`. This file is the single source of project instructions; `AGENTS.md` only points other agents here.

## Start Here

Facts that drift (branch state, version constants, test count, last full test result) come from the repository, not from prose. A SessionStart hook prints them via `scripts/agent/session-context.ps1`.

Version constants live in `world/terrain/world_profile.gd` (`generation_version`), `rv/checkpoint.gd` and `rv/vehicle_snapshot.gd` (`VERSION`). For a class index generated from code, run `scripts/agent/module-index.ps1 [filter]`.

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
| `.claude/` | Skills, hook settings; `.mcp.json` configures the Blender MCP server |

Placement, reference and cleanup rules: [docs/guides/codebase.md](docs/guides/codebase.md).

## Commands

Godot is at `C:\Program Files\godot\godot.exe` and on PATH. Use the PowerShell tool (the Bash tool is Git Bash) and `run_in_background` for test runs and game launches.

```powershell
godot --editor --path .
godot --path .
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

The last command imports once, then runs every top-level `tests/test_*.gd` and the main-scene smoke check. It stops at the first failure unless you pass `-KeepGoing`. Load the `godot-tests` skill before choosing, writing or debugging tests.

Python: `python` on PATH may be the Microsoft Store stub. Use `$env:USERPROFILE\Apps\ComfyUI\pixal3d-runtime\.venv\Scripts\python.exe` (Pillow + numpy) or `$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe` (Pillow). Never install Python globally without asking.

## Hard Rules

1. **In-game text.** Use English and only what the player or setting needs. Never put hints, controls, item names or status in the 3D world, including `Label3D`, `TextMesh`, floating, camera-facing, glowing or unshaded text. Essential prompts belong in screen-space UI. World text is allowed only where the fiction demands it (a physical sign, a maker's plate, an instrument screen). Finish it as integrated texture, decal or device-screen art, and never smuggle hints into textures. This applies to reference images and generated assets too.
2. **Nothing intermediate in Git.** Keep work files, screenshots, recordings, logs, archives and editor backups (`.blend1`) under `.godot/` or another ignored path. Commit only game assets, code, tests, concise docs and at most a few representative evidence images.
3. **Saves are disposable.** Change save formats directly, delete old local saves when needed, and remove compatibility branches instead of extending them.
4. **Randomness is gameplay.** Use it for meaningful variation in generation, encounters and loot. Preserve guarantees the player relies on, and use fixed seeds to reproduce a run.
5. **Tests read their baselines.** Never copy tuning values (energy, colors, speeds, timings) from scenes into tests as literals. Read them from the scene or resource under test, or assert relative behavior.

Hooks in `.claude/settings.json` enforce rules 1 and 2: before edits they block `Label3D`/`TextMesh` in game code, and before `git commit` they run `scripts/agent/check-staged.ps1`. When a hook blocks, fix the cause or ask the user; never route around it.

## Working Defaults

- Use `AskUserQuestion` early when a requirement, preference or tradeoff could materially change the result. Offer concise choices with a recommendation and keep doing independent work.
- Report architecture problems you notice. Ask before large architectural changes.
- Validate with the smallest set that covers the changed behavior and its risks. Skip tests for simple, low-risk edits. For docs-only changes, check wording, consistency and links (`scripts/agent/check-links.ps1 <files>`); do not launch Godot.
- Report what you checked, what you did not, and any material uncertainty. When the user must inspect something, name exactly what. Never claim visual or hands-on verification you did not do.
- Work token-efficiently: use Grep/Glob, read targeted ranges, batch independent tool calls, and reuse established findings.

## Delegation

Discuss first, then dispatch the agreed plan with the user-level `dispatch` skill. Project specifics:

- Keep scene modeling and 3D integration in the main agent.
- Models: `opus` for deep reasoning, `haiku` for lookups and mechanical edits, `sonnet` for implementation and computer-use game testing.
- **Prefer agy to save Claude tokens.** Antigravity CLI (Gemini, user-level `agy` skill) runs on a separate quota. Send it work that is cheaper to check than to do: broad code research and summaries, code review and second opinions, test-log and CI triage, first drafts of docs, and mechanical multi-file edits. Give it a full brief (it reads `AGENTS.md`, which points here) and run it in the background. Use `--mode plan` for read-only work; for edits, point it at a separate worktree and review the diff before anything lands.
- **Generate every image with agy** (reference images, textures, concept art, icons). Run it in an empty folder outside the repo and read the result before use; [reference images](.claude/skills/comfyui-image-to-3d/references/reference-images.md) has the tested call and checks.
- Keep with Claude: work that needs this conversation's context, 3D integration, harness changes, and final verification.

## Skills

Project skills live in `.claude/skills/`. Load one when its trigger applies.

| Skill | Load when |
|---|---|
| `godot-tests` | Choosing, running, writing or debugging automated tests or CI failures |
| `playtest` | A change needs render captures or live on-screen verification in the running game |
| `docs-maintenance` | Editing `README.md`, `GDD.md`, `architecture.md`, or anything under `docs/` |
| `apocalypse-rv-3d-scenes` | Building or editing 3D scenes, or replacing visual assets |
| `comfyui-image-to-3d` | Generating a 3D prop from a reference image with local ComfyUI |
| `harness-maintenance` | Editing CLAUDE.md, AGENTS.md, skills, hooks, `scripts/agent/` or `.mcp.json` |
