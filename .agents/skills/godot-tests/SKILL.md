---
name: godot-tests
description: Use when choosing, running, writing or debugging ApocalypseRV automated Godot tests (scripts/test.ps1, tests/test_*.gd), reading test logs, or investigating CI failures.
---

# Godot Tests

## Run

```powershell
./scripts/test.ps1 -List                                    # show the selection, no engine
./scripts/test.ps1 -TestFilter 'test_item_*.gd,test_pistol.gd'
./scripts/test.ps1 -TestFilter test_item_player.gd -Smoke   # add main-scene smoke
./scripts/test.ps1 -TestFilter test_pistol.gd -SkipImport   # assets unchanged since last import
./scripts/test.ps1 -KeepGoing                               # full run, report every failure
```

- Each check runs in its own headless Godot process with `--fixed-fps 60`. `-RealTime` drops the fixed rate for comparison only.
- A check passes only with exit code 0, a non-empty log, a `PASS:` line, and no `ERROR:`, `SCRIPT ERROR:`, `FAIL:` or crash lines. Any `push_error` fails it.
- Without `-KeepGoing` the run stops at the first failure. Always say which selected checks did not run.
- `test_streaming_generation` dominates a full run (minutes). Select it only for terrain, roads, weather, fog, streetlights, POI placement or streaming changes.

## Choose

1. Find the covering test in the coverage table in [tests/README.md](../../../tests/README.md).
2. Confirm with `rg <ClassOrFunction> tests/`. Shared contracts in `tests/support/` run inside their parent tests.
3. Add `-Smoke` when the change touches `world/main_world.tscn`, HUD, settings, startup or player movement.
4. Headless tests do not cover visuals, feel, rollovers or crowds. Use the `playtest` skill or ask the user.

## Read Failures

- Logs: `.godot/test-logs/<stamp>-<mode>-<pid>/`, one `<check>.log` each, plus `results.json` (selection, status, timing, commit, dirty tree).
- An assertion failure is an `ERROR: FAIL: <message>` line followed by a GDScript backtrace that gives the test file and line.
- Before changing a test after a tuning commit, decide whether it guards intent or only copied a value. Fix copied values by reading the baseline from the scene; do not just update the literal.

## Write

- Extend an existing core test instead of adding a top-level file: each top-level `tests/test_*.gd` is a new process in every run. Put shared fixtures in `tests/support/`.
- Follow the existing shape (for example [test_rv_braking.gd](../../../tests/test_rv_braking.gd)): `extends SceneTree`, a `check(ok, message)` helper that collects failures, `print("PASS: ...")` when clean, and `quit(0 if failures.is_empty() else 1)`.
- Wait on conditions with `tests/support/test_wait.gd`, not wall-clock sleeps. Scale tick counts with `Engine.physics_ticks_per_second`.
- Use fixed seeds. Never assert literals copied from scenes; read them from the node or resource.
- After editing `scripts/test.ps1`, run `./scripts/test-runner.tests.ps1`. It needs no Godot.

## CI

`.github/workflows/tests.yml` runs the runner self-tests, then `scripts/test.ps1 -KeepGoing` with the pinned Godot on one Windows job. Markdown-only and `docs/` changes skip CI. On failure, the `godot-test-logs` artifact holds the same log folder.
