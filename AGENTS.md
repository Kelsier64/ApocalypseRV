# Repository Guidelines

## Project Structure

Godot 4.7.2 survival prototype; `world/main_world.tscn` is the main scene. 

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

These open the editor, launch gameplay, and run all 16 core tests plus main-scene startup. `-TestFilter` selects matching tests, with optional `-Smoke`; `-SmokeOnly` checks only main-scene startup. New top-level `tests/test_*.gd` files run automatically: prefer extending an existing core test over adding another process. See `tests/README.md` for coverage and runner self-tests. Logs: `.godot/test-logs/`. GitHub Actions uses the same default command in one Windows job.

### Godot Access (Codex / Windows)

Godot: `C:\Program Files\godot\godot.exe` (also on PATH). If the sandbox cannot find or access it, retry with `sandbox_permissions: "require_escalated"`. Use `& '<Godot path>'` in PowerShell and `scripts/test.ps1 -Godot '<Godot path>'` for tests.

## Coding and Testing

Follow the conventions and validation guidance in `architecture.md`. For documentation-only edits, verify relative links and source consistency; record historical test results separately from checks run for the current change.

## Clarifying Requirements

Use the user-input tool proactively when a requirement, preference, or tradeoff could materially affect the result. Ask early, offer concise choices when practical, and continue any work that can proceed independently.

## Save Data

Treat existing saves as disposable during development. Change save formats and save/load logic directly, including changes that break compatibility. You may delete old local saves when a clean start is needed.

## Gameplay Randomness

Treat randomness as a core part of gameplay. Use it to create meaningful variation across runs, especially in procedural generation, encounters, and loot. Preserve any guarantees the player relies on, and use fixed seeds when you need to reproduce a run.

## Token Efficiency and Validation Scope

- Default to a token-efficient workflow while preserving quality and the requested scope. Use `rg`, inspect targeted ranges and diffs, batch independent reads, and reuse established findings.
- Delegate narrowly with concise context; avoid duplicate exploration and validation. Keep tool output and reports focused on actionable results.
- Skip writing and running tests for simple, low-risk tasks. Review the diff and use direct checks where needed. For changes that need tests, choose the smallest set that covers the affected behavior and its risks. Expand only for related failures, unresolved risks, or explicit requirements. Reuse passing results when the relevant code has stayed the same.
- For documentation-only changes, check wording, consistency, and any changed links; do not launch Godot or run gameplay tests.
- For visual and art changes, use direct asset inspection, a render, or a screenshot whenever it can verify the result. Reserve computer-use for checks that require live interaction. Ask the user to inspect when their visual judgment or access is needed.
- Apply the game-testing workflow below only when relevant to the changed behavior. Run climbing, turning, and roof-destruction scenarios only for changes affecting those systems.
- Report briefly what was checked and any material uncertainty. If user inspection is needed, state exactly what they should inspect; never claim it has already been verified.

## In-Game Text

Use English for all in-game text. Keep wording concise and include it only where the player or setting needs it. Omit gameplay hints and tutorial copy. Keep essential interaction prompts in screen-space UI.

- Never place gameplay hints, controls, instructions, item names, or status labels on models or in the 3D world. This includes floating prompts, `Label3D`, `TextMesh`, and white, glowing, unshaded, or camera-facing text.
- World text is allowed only where it clearly belongs in the fiction (for example, an essential physical sign, manufacturer plate, or instrument display). Finish it as integrated game art using a texture, decal, or an actual device screen; match the surface, lighting, wear, scale, and placement. Do not convert hints into textures to bypass this rule, add decorative wording by default, or restore removed labels through scene generators.

## Subagents

Use subagents whenever a task is suitable for delegation. When delegating general tasks to a subagent, use `gpt-6.1-sol` for complex tasks(require deep reasoning),use `gpt-6-luna` for eazy tasks,use `gpt-6.1-terra` for computer-use tasks. Choose the subagent's reasoning effort based on the task's difficulty.
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

## Git

- Before starting new work, ask the user whether to create a new branch from origin/main. Create one only if the user agrees; otherwise continue on the current branch. Use the same branch for follow-ups.
- Complete the work and validation, then ask the user for approval before pushing or creating/updating a PR.
- Keep intermediate outputs gitignored from start to finish, including build/generation tools, screenshots, recordings, logs and backups. Deliver only necessary game assets, code, tests and concise docs; preserve unrelated local files.
- Review `git status` and the diff, clean up task-generated temporary files and accidental changes, and commit all validated task changes. Preserve and report unrelated or pre-existing user changes.
