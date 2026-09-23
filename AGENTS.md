# Repository Guidelines

## Project Structure

Godot 4.7.2 survival prototype; `world/test_world.tscn` is the main scene.

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

These open the editor, launch gameplay, and run validation. The runner imports assets, executes every `tests/test_*.gd`, and checks main-scene startup. Logs: `.godot/test-logs/`. GitHub Actions uses the same runner.

## Coding and Testing

Follow the conventions and validation guidance in `architecture.md`. For documentation-only edits, verify relative links and source consistency; record historical test results separately from checks run for the current change.

## Collaboration

Report architecture issues; ask before major architecture changes. Handle Git when possible; ask the user when review is needed.

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

Use existing `feat:`, `test:`, `chore:`, or `spec:` prefixes. PRs describe behavior, validation, related issues, and visual evidence. Preserve unrelated edits, original `todo` files, and historical `docs/archive/superpowers/` records. Exclude `.godot/` caches from commits.
