# Repository Guidelines

## Project Structure

Godot 4.6.1 survival prototype; `world/test_world.tscn` is the main scene.

- `player/`, `enemies/`, `props/`: actors, interaction, AI, and items.
- `rv/`, `equipment/`: vehicle physics and mounted devices.
- `world/`: chunks, POIs, and procedural buildings.
- `core/`: shared contracts, climbing geometry, and RV support.
- `assets/`: art; scenes also live beside scripts.
- `tests/`: behavior suites and the interactive climbing playground.
- Root `GDD.md`, `architecture.md`, and `README.md`: current design, architecture, and usage. `docs/` is archived; see `docs/README.md`.

## Development Commands

Run from the repository root with `godot` on PATH:

```powershell
godot --editor --path .
godot --path .
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

These open the editor, launch gameplay, and run validation. The runner imports assets, executes every `tests/test_*.gd`, and checks main-scene startup. Logs: `.godot/test-logs/`. GitHub Actions uses the same runner.

## Coding and Testing

### Codex and Antigravity CLI Responsibilities

Antigravity CLI is installed locally. Prefer using it for routine development, well-scoped implementation tasks, repetitive edits, and batch image generation whenever its available capabilities fit the task.

- Codex owns planning, task breakdown, architecture decisions, integration review, acceptance checks, computer-use testing, and highly complex or difficult development.
- Before delegating, Codex defines the scope, relevant files, constraints, expected outputs, and acceptance criteria. Keep delegated work bounded and avoid concurrent edits to the same files.
- Check the locally installed CLI's help and supported capabilities before invoking it; do not invent commands, flags, or image-generation support. Use Antigravity for batch image generation when supported, with consistent asset specifications and output locations.
- Codex reviews generated code and assets, integrates the results, and runs the applicable automated and visual checks. A successful CLI run alone does not establish acceptance.
- If Antigravity is unavailable or unsuitable, Codex continues with available tools and briefly reports the limitation. Preserve unrelated work and follow all repository testing and preservation rules.

Use UTF-8, GDScript tabs, explicit types where practical, `snake_case` files/functions, `PascalCase` classes, and `UPPER_SNAKE_CASE` constants. Reuse `core/` contracts. No dedicated formatter or numeric coverage threshold exists.

Tests extend `SceneTree`, print `PASS`, and report failures with nonzero exit codes. Prefer observable behavior over private-helper assertions. Physics changes require production-scene regression tests and visual inspection.

## Computer Use: Game Testing

Read the installed `computer-use` skill and its guidance/API before desktop interaction. Use `node_repl` with `@oai/sky`; initialize `sky`, then call `list_windows()`. Select exactly one returned game window, obtain it with `get_window`, activate it, and inspect `get_window_state`. Never target the Godot editor by mistake or invent window IDs.

Launch through the shell tool, with an explicit log:

```powershell
godot --path . --log-file .godot/climb-playground.log res://tests/rv_climb_playground.tscn -- --replay
```

Omit `-- --replay` for manual WASD/Space play. Controls: F2 stops/toggles motion; F3 auto-climbs; F4 switches camera; F5 seats the player; R resets.

Observe, send one action with `sky.press_key`, then refresh the screenshot. Short key presses cannot substitute for sustained movement; use replay for continuous input. Verify both actors climb and remain aboard during turns; press F5 and verify roof HP reaches `DESTROYED` and the monster falls. Inspect the log for script errors.

Close only your test window afterward. Report observed results separately from automated checks and untested scenarios. Replay uses scripted vehicle motion; wheel-driven handling, rollovers, and crowds need additional testing.

## Commits and Preservation

Use existing `feat:`, `test:`, `chore:`, or `spec:` prefixes. PRs describe behavior, validation, related issues, and visual evidence. Preserve unrelated edits, original `todo` files, and historical `docs/superpowers/` records. Exclude `.godot/` caches from commits.
