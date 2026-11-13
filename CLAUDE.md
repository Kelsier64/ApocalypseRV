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
- `.claude/skills/`: project skills (`apocalypse-rv-3d-scenes`, `comfyui-image-to-3d`). `AGENTS.md` is only a pointer to this file for other tools.

## Development Commands

Run from the repository root. Godot is at `C:\Program Files\godot\godot.exe` and on PATH.

```powershell
godot --editor --path .
godot --path .
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

These open the editor, launch gameplay, and run all 16 core tests plus main-scene startup. `-TestFilter` selects matching tests, with optional `-Smoke`; `-SmokeOnly` checks only main-scene startup; `-Godot '<path>'` overrides the executable. New top-level `tests/test_*.gd` files run automatically: prefer extending an existing core test over adding another process. See `tests/README.md` for coverage and runner self-tests. Logs: `.godot/test-logs/`. GitHub Actions uses the same default command in one Windows job.

Use the PowerShell tool for these commands (the Bash tool is Git Bash). Run the full suite and game launches with `run_in_background`.

## Coding and Testing

Follow the conventions and validation guidance in `architecture.md`. For documentation-only edits, verify relative links and source consistency; record historical test results separately from checks run for the current change.

## Clarifying Requirements

Use `AskUserQuestion` proactively when a requirement, preference, or tradeoff could materially affect the result. Ask early, offer concise choices with a recommendation, and continue any work that can proceed independently.

## Save Data

Treat existing saves as disposable during development. Change save formats and save/load logic directly, including changes that break compatibility. You may delete old local saves when a clean start is needed.

## Gameplay Randomness

Treat randomness as a core part of gameplay. Use it to create meaningful variation across runs, especially in procedural generation, encounters, and loot. Preserve any guarantees the player relies on, and use fixed seeds when you need to reproduce a run.

## Token Efficiency and Validation Scope

- Default to a token-efficient workflow while preserving quality and the requested scope. Use Grep/Glob, inspect targeted ranges and diffs, batch independent tool calls, and reuse established findings.
- Delegate narrowly with concise context; avoid duplicate exploration and validation. Keep tool output and reports focused on actionable results.
- Skip writing and running tests for simple, low-risk tasks. Review the diff and use direct checks where needed. For changes that need tests, choose the smallest set that covers the affected behavior and its risks. Expand only for related failures, unresolved risks, or explicit requirements. Reuse passing results when the relevant code has stayed the same.
- For documentation-only changes, check wording, consistency, and any changed links; do not launch Godot or run gameplay tests.
- Take screenshots only when you need to verify a specific visual result. Use direct asset inspection or a render when either is sufficient. Reserve computer use for checks that require live interaction. Ask the user to inspect when their visual judgment or access is needed.
- Apply the game-testing workflow below only when relevant to the changed behavior. Run climbing, turning, and roof-destruction scenarios only for changes affecting those systems.
- Report briefly what was checked and any material uncertainty. If user inspection is needed, state exactly what they should inspect; never claim it has already been verified.

## In-Game Text

Use English for all in-game text. Keep wording concise and include it only where the player or setting needs it. Omit gameplay hints and tutorial copy. Keep essential interaction prompts in screen-space UI.

- Never place gameplay hints, controls, instructions, item names, or status labels on models or in the 3D world. This includes floating prompts, `Label3D`, `TextMesh`, and white, glowing, unshaded, or camera-facing text.
- World text is allowed only where it clearly belongs in the fiction (for example, an essential physical sign, manufacturer plate, or instrument display). Finish it as integrated game art using a texture, decal, or an actual device screen; match the surface, lighting, wear, scale, and placement. Do not convert hints into textures to bypass this rule, add decorative wording by default, or restore removed labels through scene generators.

## Subagents

Use the Agent tool when a task is suitable for delegation and delegating saves more than it costs. Pick the model by difficulty:

- `opus`: complex tasks that need deep reasoning.
- `haiku`: easy, mechanical tasks (searches, renames, small edits).
- `sonnet`: computer-use game testing.

Give each subagent a clear scope and acceptance criteria, and review its output before it lands. Use `Explore` for broad read-only searches.

Do scene modeling and general 3D tasks yourself; read the `apocalypse-rv-3d-scenes` skill first. For suitable visual assets, use the `comfyui-image-to-3d` skill directly: the main agent chooses reference creation, generation, inspection, edits and integration as the task needs. Keep the raw model, verify the result in context, and report unresolved problems accurately. For a second opinion or parallel work from Gemini, the user-level `agy` skill delegates to Antigravity CLI.

## Computer Use: Game Testing

Launch the game with the PowerShell tool (`run_in_background`) and an explicit log:

```powershell
godot --path . --log-file .godot/climb-playground.log res://tests/rv_climb_playground.tscn -- --replay
```

Omit `-- --replay` for manual WASD/Space play. Controls: F2 stops/toggles motion; F3 auto-climbs; F4 switches camera; F5 seats the player; R resets.

Read the `anthropic-skills:computer-use` skill, load the `mcp__computer-use__*` tools in one ToolSearch call, and `request_access` for Godot. The editor and the game share the Godot executable: take a screenshot first and make sure the running game window, not the editor, is frontmost before sending input.

Observe before each action and send one key at a time with `key`. Refresh the screenshot only when you need to verify the on-screen result. Short presses cannot substitute for sustained movement; use replay (or `hold_key`) for continuous input. Verify both actors climb and remain aboard during turns; press F5 and verify roof HP reaches `DESTROYED` and the monster falls. Inspect the log for script errors.

Close only your test window afterward. Report observed results separately from automated checks and untested scenarios. Replay uses scripted vehicle motion; wheel-driven handling, rollovers, and crowds need additional testing.

## Git

- Before starting new work, ask the user whether to create a new branch from origin/main. Create one only if the user agrees; otherwise continue on the current branch (default). Use the same branch for follow-ups.
- Complete the work and validation, then ask the user for approval before pushing or creating/updating a PR.
- Keep intermediate outputs gitignored from start to finish, including build/generation tools, screenshots, recordings, logs and backups. Deliver only necessary game assets, code, tests and concise docs; preserve unrelated local files.
- Review `git status` and the diff, clean up task-generated temporary files and accidental changes, and commit all validated task changes. Preserve and report unrelated or pre-existing user changes.
