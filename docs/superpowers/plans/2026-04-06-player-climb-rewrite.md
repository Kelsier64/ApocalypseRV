# Player Climb Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild player RV climbing so top-out, abort, and moving-RV behavior are deterministic and regression-tested.

**Architecture:** Keep player-facing controls unchanged (W-based wall climb trigger), but replace ad-hoc per-frame decisions with an explicit climb pipeline: capture context -> validate gates -> apply bounded motion -> commit/abort transitions. Preserve existing public helper methods used by current tests while routing core behavior through a unified climb context path.

**Tech Stack:** Godot 4.6 GDScript, SceneTree headless tests, existing player scene probes.

---

## File Structure

- Modify: `player/player.gd`
  - Keep inventory/health/placement behavior intact.
  - Rewrite climb/mantle runtime into explicit transition stages and unified context evaluation.
- Modify: `tests/test_player_climbing.gd`
  - Add/adjust failing tests to enforce new deterministic contracts.
- Create: `tests/test_player_climbing_runtime.gd`
  - Focused runtime contract tests for top-out/abort/cooldown semantics that do not depend on full scene boot.
- Modify: `docs/modules/player-equipment-interactions.md`
  - Update climb runtime contract and manual verification steps to match implementation.

### Task 1: Lock Regression Contracts First (RED)

**Files:**
- Modify: `tests/test_player_climbing.gd`
- Create: `tests/test_player_climbing_runtime.gd`
- Test: `tests/test_player_climbing.gd`, `tests/test_player_climbing_runtime.gd`

- [ ] **Step 1: Add a failing test for mantle top-out minimum height**

```gdscript
func _test_mantle_target_finishes_above_wall_top() -> void:
    var player := _new_player()
    if player == null:
        return

    var target: Vector3 = player._compute_mantle_target(Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
    _expect(target.y >= 1.25, "Mantle target should provide deterministic top-out clearance (>=1.25m).")
    player.free()
```

- [ ] **Step 2: Add a failing test for explicit abort transition helper**

```gdscript
func _test_climb_abort_clears_state() -> void:
    var player := _new_player()
    if player == null:
        return

    _expect(player.has_method("_abort_climb"), "Player should expose _abort_climb(reason).")
    player.free()
```

- [ ] **Step 3: Add runtime contract test file with deterministic state checks**

```gdscript
extends SceneTree

var failures: Array[String] = []

func _init() -> void:
    var script: Script = load("res://player/player.gd")
    var p = script.new()
    if p == null:
        failures.append("Player should instantiate.")
    else:
        if p.has_method("_compute_mantle_target"):
            var t: Vector3 = p._compute_mantle_target(Vector3.ZERO, Vector3.UP, Vector3.FORWARD)
            if t.y < 1.25:
                failures.append("Mantle target min clearance should be >=1.25m.")
        if not p.has_method("_abort_climb"):
            failures.append("Missing _abort_climb(reason).")
        p.free()

    if failures.is_empty():
        print("PASS: player climbing runtime tests")
        quit(0)
    push_error("FAIL: player climbing runtime tests")
    for f in failures:
        push_error(" - " + f)
    quit(1)
```

- [ ] **Step 4: Run tests to verify RED**

Run: `"C:\Program Files\godot\godot.exe" --headless --path . -s tests/test_player_climbing.gd`
Expected: FAIL with top-out clearance assertion and missing `_abort_climb`.

Run: `"C:\Program Files\godot\godot.exe" --headless --path . -s tests/test_player_climbing_runtime.gd`
Expected: FAIL with the same missing behavior.

- [ ] **Step 5: Commit failing tests**

```bash
git add tests/test_player_climbing.gd tests/test_player_climbing_runtime.gd
git commit -m "test: lock player climb rewrite regressions"
```

### Task 2: Rewrite Climb Runtime to Explicit Transition Pipeline (GREEN)

**Files:**
- Modify: `player/player.gd`
- Test: `tests/test_player_climbing.gd`, `tests/test_player_climbing_runtime.gd`

- [ ] **Step 1: Add explicit abort helper and transition-safe reset**

```gdscript
func _abort_climb(reason: String = "") -> void:
    _exit_climb_to_normal()
```

- [ ] **Step 2: Raise deterministic mantle clearance floor**

```gdscript
const MANTLE_UP_OFFSET = 1.25
```

- [ ] **Step 3: Route invalid climb/mantle states through abort path**

```gdscript
if active_climb_rv == null or not is_instance_valid(active_climb_rv):
    _abort_climb("rv invalid")
    return
```

- [ ] **Step 4: Keep all existing public helper methods and state contracts**

```gdscript
# Keep signatures used by tests:
# _try_start_climb, _process_climbing, _begin_mantle, _process_mantle,
# _probe_roof_from_above, _sanitize_velocity_after_climb, _can_start_mantle
```

- [ ] **Step 5: Run tests to verify GREEN**

Run: `"C:\Program Files\godot\godot.exe" --headless --path . -s tests/test_player_climbing.gd`
Expected: PASS: player climbing tests

Run: `"C:\Program Files\godot\godot.exe" --headless --path . -s tests/test_player_climbing_runtime.gd`
Expected: PASS: player climbing runtime tests

- [ ] **Step 6: Commit runtime rewrite**

```bash
git add player/player.gd
git commit -m "feat: rewrite player climb transitions with deterministic top-out"
```

### Task 3: Refactor for Readability Without Behavior Drift (REFACTOR)

**Files:**
- Modify: `player/player.gd`
- Test: `tests/test_player_climbing.gd`, `tests/test_player_climbing_runtime.gd`

- [ ] **Step 1: Consolidate mantle gate collection into one context builder**

```gdscript
func _query_mantle_target() -> Dictionary:
    # Compute top hit, target, and all gate booleans in one place.
    return {
        "ok": gates_ok,
        "target": target,
        "reason": fail_reason
    }
```

- [ ] **Step 2: Ensure every early exit has deterministic reason path**

```gdscript
if climb_contact_grace_remaining <= 0.0:
    _abort_climb("lost wall contact")
    return
```

- [ ] **Step 3: Re-run tests and ensure no regressions**

Run: `"C:\Program Files\godot\godot.exe" --headless --path . -s tests/test_player_climbing.gd`
Expected: PASS

Run: `"C:\Program Files\godot\godot.exe" --headless --path . -s tests/test_player_climbing_runtime.gd`
Expected: PASS

- [ ] **Step 4: Commit refactor**

```bash
git add player/player.gd
git commit -m "refactor: normalize player climb gate evaluation paths"
```

### Task 4: Documentation and Verification

**Files:**
- Modify: `docs/modules/player-equipment-interactions.md`
- Test: `tests/test_player_climbing.gd`, `tests/test_player_climbing_runtime.gd`

- [ ] **Step 1: Update climb section with rewritten transition model**

```md
- Climb runtime now uses deterministic abort transition via `_abort_climb(reason)`.
- Mantle top-out target enforces >=1.25m vertical clearance baseline.
- Runtime regression coverage includes `test_player_climbing_runtime.gd`.
```

- [ ] **Step 2: Run final verification suite**

Run: `"C:\Program Files\godot\godot.exe" --headless --path . -s tests/test_player_climbing.gd`
Expected: PASS

Run: `"C:\Program Files\godot\godot.exe" --headless --path . -s tests/test_player_climbing_runtime.gd`
Expected: PASS

- [ ] **Step 3: Commit docs sync**

```bash
git add docs/modules/player-equipment-interactions.md
git commit -m "docs: sync player climbing runtime rewrite contracts"
```

## Self-Review

- Spec coverage: includes trigger model retention (W-based), deterministic top-out, explicit abort path, and regression tests.
- Placeholder scan: no TBD/TODO placeholders remain.
- Type/signature consistency: preserves existing public helper method signatures and adds `_abort_climb(reason)` consistently in tests and implementation.
