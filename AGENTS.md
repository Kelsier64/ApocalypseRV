# Repository Guidelines

## Project Structure

Godot 4.7.2 survival prototype; `world/main_world.tscn` is the main scene. `world/test_world.tscn` remains the legacy test fixture.

- `player/`, `enemies/`, `props/`: actors, interaction, AI, and items.
- `rv/`, `equipment/`: vehicle physics and mounted devices.
- `world/`: chunks, POIs, and procedural buildings.
- `core/`: shared contracts, climbing geometry, and RV support.
- `assets/`: art; scenes also live beside scripts.
- `tests/`: behavior suites and the interactive climbing playground.
- Root `GDD.md`, `architecture.md`, and `README.md`: current design, architecture, and usage. `docs/` contains active plans, guides, validation and research; only `docs/archive/` is historical. See `docs/README.md`.

## Development Commands

Run from the repository root with `godot` on PATH:

```powershell
godot --editor --path .
godot --path .
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

These open the editor, launch gameplay, and run the quick behavior suite. Use `scripts/test.ps1 -Suite full` for all active tests and main-scene startup; `-TestFilter` selects only matching tests, with optional `-Smoke`. Classify every new `test_*.gd` in `tests/suites.json`. See `tests/README.md` for profiles, timings and runner self-tests. Logs: `.godot/test-logs/`. GitHub Actions runs all profiles through the same runner.

### Godot Access (Codex / Windows)

Godot: `C:\Users\evan4\AppData\Local\Programs\Godot\Godot.exe`. If the sandbox cannot find or access it, retry with `sandbox_permissions: "require_escalated"`. Use `& '<Godot path>'` in PowerShell and `scripts/test.ps1 -Godot '<Godot path>'` for tests.

## Coding and Testing

Follow the conventions and validation guidance in `architecture.md`. For documentation-only edits, verify relative links and source consistency; record historical test results separately from checks run for the current change.

## Subagents

Use subagents whenever a task is suitable for delegation. When delegating general tasks to a subagent, use `gpt-6.1-sol` for complex tasks(require deep reasoning),use `gpt-6-luna` for eazy tasks. Choose the subagent's reasoning effort based on the task's difficulty.
Do scene modeling and general 3D tasks yourself. For suitable visual assets, use [comfyui-image-to-3d](.agents/skills/comfyui-image-to-3d/SKILL.md) directly: the main agent chooses reference creation, generation, inspection, edits and integration as the task needs. Modeling requests and specialized subagents are optional when a handoff is useful. Keep the raw model, verify the result in context, and report unresolved problems accurately.

## Computer Use: Game Testing

Read the installed `computer-use` skill and its guidance/API before desktop interaction. Use `node_repl` with `@oai/sky`; initialize `sky`, then call `list_windows()`. Select exactly one returned game window, obtain it with `get_window`, activate it, and inspect `get_window_state`. Never target the Godot editor by mistake or invent window IDs.

Launch through the shell tool, with an explicit log:

```powershell
godot --path . --log-file .godot/climb-playground.log res://tests/rv_climb_playground.tscn -- --replay
```

Omit `-- --replay` for manual WASD/Space play. Controls: F2 stops/toggles motion; F3 auto-climbs; F4 switches camera; F5 seats the player; R resets.

Observe, send one action with `sky.press_key`, then refresh the screenshot. Short key presses cannot substitute for sustained movement; use replay for continuous input. Verify both actors climb and remain aboard during turns; press F5 and verify roof HP reaches `DESTROYED` and the monster falls. Inspect the log for script errors.

Close only your test window afterward. Report observed results separately from automated checks and untested scenarios. Replay uses scripted vehicle motion; wheel-driven handling, rollovers, and crowds need additional testing.

## Git Workflow and Ignored Outputs

- Start every new feature, fix, or documentation task on a separate `codex/<short-description>` branch before editing. Base independent work on the latest `origin/main`; continue the same branch for follow-up work on an existing task or PR. Preserve unrelated local changes and use a separate worktree when needed.
- Finish the work and run the appropriate validation, then commit, push the branch, and create a PR. Do not deliver completed work only as local changes or commits, and do not merge the PR unless the user asks.
- Before generating any intermediate output, add or verify narrow `.gitignore` rules for its location. Keep those rules in effect throughout implementation, validation, and PR delivery. Prefer an already ignored workspace such as `.godot/art-work/<task>/` or `.godot/test-logs/`.
- Keep build/export artifacts, modeling and generation scripts, intermediate asset candidates, raw intermediate authoring files and backups, screenshots, recordings, logs, caches, and temporary dependencies out of Git unless the user explicitly requests them. Preserve these files locally; do not delete user files to clean up a PR.
- Commit the final game assets, required Godot runtime/import scripts, maintained tests, and concise documentation. Generated runtime models, textures, and audio are deliverables, not intermediate outputs. Do not blanket-ignore asset extensions or whole source/test directories, and do not force-add intermediate outputs.
- Before committing or creating the PR, inspect the staged paths, file count, sizes, and diff; verify ignore rules with `git check-ignore`. Stage only the intended deliverables, with no screenshots, generation tools, or other incidental files added by a broad `git add .`.

## Commits and Preservation

Use existing `feat:`, `test:`, `chore:`, or `spec:` prefixes. PRs describe behavior, validation, and related issues. Keep visual capture evidence local unless the user explicitly requests it in Git. Preserve unrelated edits, original `todo` files, and historical `docs/archive/superpowers/` records. Exclude `.godot/` caches from commits.
