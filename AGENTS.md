# Repository Guidelines

Shared instructions for every coding agent working in this repository. Agent-specific notes are at the end; Claude Code also reads [CLAUDE.md](CLAUDE.md).

## Project Structure

Godot 4.7.2 survival prototype; `world/main_world.tscn` is the main scene.

- `player/`, `enemies/`, `props/`: actors, interaction, AI, and items.
- `rv/`, `equipment/`: vehicle physics, save checkpoint, and mounted devices.
- `world/`: terrain streaming, chunks, POIs, procedural buildings, and interiors.
- `core/`: shared rules and contracts (items, saves, climbing math, placement, settings).
- `assets/`: runtime art; `art_source/`: editable sources and build inputs. Scenes live beside their scripts.
- `scripts/`: test runner, asset builders, and benchmarks.
- `tests/`: automated top-level `test_*.gd`, shared fixtures in `tests/support/`, and manual `*_playground` scenes.

## Sources of Truth

Code is the only authority for current behavior and versions. Read version constants from code, not from prose: `rv/checkpoint.gd` (`VERSION`), `rv/vehicle_snapshot.gd` (`VERSION`), and `world/terrain/world_profile.gd` (`generation_version`).

- Root `README.md`, `GDD.md`, and `architecture.md` describe usage, design, and architecture, but they contain dated history and can lag behind code. Verify any claim before relying on it, and fix stale statements you touch.
- `docs/guides/` and `docs/plans/` are working documents. `docs/validation/`, `docs/report/`, and `docs/archive/` are dated historical records: never treat their results as evidence for the current code.
- Do not hard-code counts that drift (number of tests, files, or versions) in documentation.

## Development Commands

Run from the repository root with `godot` on PATH (`C:\Program Files\godot\godot.exe`; pass `-Godot '<path>'` to the runner if it is not):

```powershell
godot --editor --path .
godot --path .
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

These open the editor, launch gameplay, and run every top-level `tests/test_*.gd` plus the main-scene smoke check. `-TestFilter` selects matching tests, with optional `-Smoke`; `-SmokeOnly` checks only main-scene startup; `-List` prints the selection without launching Godot. The runner stops at the first failure, so report which checks did not run. Logs: `.godot/test-logs/`. GitHub Actions runs the same default command in one Windows job. See `tests/README.md` for coverage and the runner self-tests.

New top-level `tests/test_*.gd` files run automatically: prefer extending an existing core test over adding another process.

## Coding and Testing

Follow the placement, reference, and cleanup rules in `docs/guides/codebase.md`. In short:

- Put a scene with the module that owns its behavior; shared pure logic goes in `core/`.
- `res://` paths and Godot UIDs are both references. When moving or deleting a script or scene, check both, plus dynamically built paths and `SaveSceneCatalog`. Keep `.uid` and `.import` files paired with their sources.
- Tests must not copy tuning values (light energy, colors, speeds, timings) from scenes as literals. Read the baseline from the scene or resource under test, or assert relative behavior, so tuning changes do not break tests silently.
- When a change alters a tuned value, run the tests that cover it before committing.

For documentation-only edits, verify relative links and consistency with code; record historical test results separately from checks run for the current change.

## Clarifying Requirements

Ask the user early when a requirement, preference, or tradeoff could materially affect the result. Offer concise choices when practical, and continue any work that can proceed independently.

## Save Data

Treat existing saves as disposable during development. Change save formats and save/load logic directly, including changes that break compatibility. Remove obsolete compatibility branches instead of extending them. You may delete old local saves when a clean start is needed.

## Gameplay Randomness

Treat randomness as a core part of gameplay. Use it to create meaningful variation across runs, especially in procedural generation, encounters, and loot. Preserve any guarantees the player relies on, and use fixed seeds when you need to reproduce a run.

## Token Efficiency and Validation Scope

- Default to a token-efficient workflow while preserving quality and the requested scope. Use `rg`, inspect targeted ranges and diffs, batch independent reads, and reuse established findings.
- Skip writing and running tests for simple, low-risk tasks. Review the diff and use direct checks where needed. For changes that need tests, choose the smallest set that covers the affected behavior and its risks. Expand only for related failures, unresolved risks, or explicit requirements. Reuse passing results when the relevant code has stayed the same.
- For documentation-only changes, check wording, consistency, and any changed links; do not launch Godot or run gameplay tests.
- Take screenshots only when you need to verify a specific visual result. Use direct asset inspection or a render when either is sufficient. Reserve desktop control for checks that require live interaction. Ask the user to inspect when their visual judgment or access is needed.
- Run climbing, turning, and roof-destruction scenarios only for changes affecting those systems.
- Report briefly what was checked and any material uncertainty. If user inspection is needed, state exactly what they should inspect; never claim it has already been verified.

## In-Game Text

Use English for all in-game text. Keep wording concise and include it only where the player or setting needs it. Omit gameplay hints and tutorial copy. Keep essential interaction prompts in screen-space UI.

- Never place gameplay hints, controls, instructions, item names, or status labels on models or in the 3D world. This includes floating prompts, `Label3D`, `TextMesh`, and white, glowing, unshaded, or camera-facing text.
- World text is allowed only where it clearly belongs in the fiction (for example, an essential physical sign, manufacturer plate, or instrument display). Finish it as integrated game art using a texture, decal, or an actual device screen; match the surface, lighting, wear, scale, and placement. Do not convert hints into textures to bypass this rule, add decorative wording by default, or restore removed labels through scene generators.

## Delegation and 3D Work

- Delegate only narrow, self-contained work, such as a broad search or an independent check, with concise context. Use a fast, cheap model for simple lookups and the strongest model for deep reasoning. Do not duplicate exploration or validation the main agent already did.
- Do scene modeling and general 3D work in the main agent. Before building or editing 3D scenes or replacing visual assets, read the `apocalypse-rv-3d-scenes` skill. For suitable static props, use the `comfyui-image-to-3d` skill directly. Keep the raw model, verify the result in context, and report unresolved problems accurately.
- Shared skill sources live in `.agents/skills/`. Edit them there; agent-specific entry points must stay thin pointers.

## Game Testing with Desktop Control

Use your agent's desktop-control tool and read its guidance first. Select exactly one game window; never target the Godot editor by mistake or invent window IDs.

Launch through the shell with an explicit log:

```powershell
godot --path . --log-file .godot/climb-playground.log res://tests/rv_climb_playground.tscn -- --replay
```

Omit `-- --replay` for manual WASD/Space play. Controls: F2 stops/toggles motion; F3 auto-climbs; F4 switches camera; F5 seats the player; R resets.

Observe the game before sending each key press. Refresh the screenshot only when you need to verify the on-screen result. Short key presses cannot substitute for sustained movement; use replay for continuous input. Verify both actors climb and remain aboard during turns; press F5 and verify roof HP reaches `DESTROYED` and the monster falls. Inspect the log for script errors.

Close only your test window afterward. Report observed results separately from automated checks and untested scenarios. Replay uses scripted vehicle motion; wheel-driven handling, rollovers, and crowds need additional testing.

## Git

- Before starting new work, ask the user whether to create a new branch from `origin/main`. Create one only if the user agrees; otherwise continue on the current branch (default). Use the same branch for follow-ups.
- Complete the work and validation, then ask the user for approval before pushing or creating/updating a PR.
- Keep intermediate outputs out of Git from start to finish: build/generation work files, screenshots, recordings, logs, archives, and editor backups (such as `.blend1`). Put them under `.godot/` or another ignored path. Commit only necessary game assets, code, tests, concise docs, and at most a few representative evidence images.
- Review `git status` and the diff, clean up task-generated temporary files and accidental changes, and commit all validated task changes. Preserve and report unrelated or pre-existing user changes.

## Agent-Specific Notes

### Codex

- Godot: if the sandbox cannot find or access it, retry with `sandbox_permissions: "require_escalated"`.
- Subagent models: `gpt-6.1-sol` for complex reasoning, `gpt-6-luna` for simple tasks, `gpt-6.1-terra` for desktop control.
- Desktop control: use `node_repl` with `@oai/sky`; initialize `sky`, call `list_windows()`, obtain the game window with `get_window`, activate it, inspect `get_window_state`, and send keys with `sky.press_key`.

### Claude Code

See [CLAUDE.md](CLAUDE.md).
