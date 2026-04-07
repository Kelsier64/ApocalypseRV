# Monster Navigation Unstuck Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild monster patrol/chase steering to be navigation-first with robust anti-stuck recovery so zombies stop getting trapped by walls/corners.

**Architecture:** Keep the existing AI state machine and combat lifecycle, but replace movement internals with a single steering contract shared by wander/chase. The contract uses NavigationAgent3D when valid map data exists and falls back to direct steering when navigation is unavailable. A progress watchdog detects stalls and triggers bounded re-path recovery.

**Tech Stack:** Godot 4.6, GDScript, NavigationAgent3D, headless SceneTree tests

---

### Task 1: Add Monster Navigation Contract Tests

**Files:**
- Create: `tests/test_monster_navigation.gd`
- Test: `tests/test_monster_navigation.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_test_navigation_contract_methods_exist()
	_test_fallback_direction_is_normalized()
	_test_stuck_progress_gate()
	_finish()

func _new_monster() -> Node:
	var monster_script: Script = load("res://enemies/monster.gd")
	_expect(monster_script != null, "Monster script should load.")
	if monster_script == null:
		return null
	var m: Node = monster_script.new()
	_expect(m != null, "Monster should instantiate.")
	return m

func _test_navigation_contract_methods_exist() -> void:
	var m := _new_monster()
	if m == null:
		return
	_expect(m.has_method("_can_use_navigation"), "Monster should expose _can_use_navigation().")
	_expect(m.has_method("_get_navigation_direction"), "Monster should expose _get_navigation_direction(destination).")
	_expect(m.has_method("_update_stuck_watchdog"), "Monster should expose _update_stuck_watchdog(delta, moving_intent).")
	m.free()

func _test_fallback_direction_is_normalized() -> void:
	var m := _new_monster()
	if m == null:
		return
	if m.has_method("_compute_fallback_direction"):
		var dir: Vector3 = m._compute_fallback_direction(Vector3.ZERO, Vector3(3, 0, 4))
		_expect(dir.is_equal_approx(Vector3(0.6, 0, 0.8)), "Fallback direction should normalize destination vector on XZ plane.")
	m.free()

func _test_stuck_progress_gate() -> void:
	var m := _new_monster()
	if m == null:
		return
	if m.has_method("_is_progress_too_small"):
		_expect(m._is_progress_too_small(0.01, 0.05), "Progress below threshold should be treated as stalled.")
		_expect(not m._is_progress_too_small(0.20, 0.05), "Progress above threshold should not be stalled.")
	m.free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("PASS: monster navigation tests")
		quit(0)
		return

	push_error("FAIL: monster navigation tests")
	for failure in failures:
		push_error(" - " + failure)
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_monster_navigation.gd`
Expected: FAIL with missing navigation helper method(s)

- [ ] **Step 3: Commit**

```bash
git add tests/test_monster_navigation.gd
git commit -m "test: add failing monster navigation contract tests"
```

### Task 2: Introduce Navigation Agent Scene Wiring

**Files:**
- Modify: `enemies/zombie.tscn`
- Test: `tests/test_monster_navigation.gd`

- [ ] **Step 1: Write the failing test update**

Add an assertion in `tests/test_monster_navigation.gd` that monster can look up `NavigationAgent3D` by node path when present.

```gdscript
_expect(m.has_method("_resolve_navigation_agent"), "Monster should expose _resolve_navigation_agent() helper.")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_monster_navigation.gd`
Expected: FAIL because helper/scene agent wiring is missing

- [ ] **Step 3: Write minimal implementation**

In `enemies/zombie.tscn`, add:

```tscn
[node name="NavigationAgent3D" type="NavigationAgent3D" parent="."]
path_desired_distance = 0.6
target_desired_distance = 1.2
```

In `enemies/monster.gd`, add `_resolve_navigation_agent()` and cache the node in `_ready()`.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_monster_navigation.gd`
Expected: PASS for agent-resolution assertions

- [ ] **Step 5: Commit**

```bash
git add enemies/zombie.tscn enemies/monster.gd tests/test_monster_navigation.gd
git commit -m "feat: wire monster navigation agent in zombie scene"
```

### Task 3: Implement Navigation-First Steering + Fallback

**Files:**
- Modify: `enemies/monster.gd`
- Test: `tests/test_monster_navigation.gd`

- [ ] **Step 1: Write the failing test update**

Add tests asserting:
- `_get_navigation_direction(destination)` returns nav-next direction when nav is valid.
- `_compute_fallback_direction(origin, destination)` returns planar normalized vector.

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_monster_navigation.gd`
Expected: FAIL on navigation direction behavior checks

- [ ] **Step 3: Write minimal implementation**

In `enemies/monster.gd`, add:

```gdscript
func _can_use_navigation() -> bool:
	return nav_agent != null and NavigationServer3D.map_get_iteration_id(nav_agent.get_navigation_map()) > 0

func _compute_fallback_direction(origin: Vector3, destination: Vector3) -> Vector3:
	var d := destination - origin
	d.y = 0.0
	return d.normalized()

func _get_navigation_direction(destination: Vector3) -> Vector3:
	if _can_use_navigation():
		nav_agent.target_position = destination
		var next := nav_agent.get_next_path_position()
		return _compute_fallback_direction(global_position, next)
	return _compute_fallback_direction(global_position, destination)
```

Update wander/chase movement to consume `_get_navigation_direction(...)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_monster_navigation.gd`
Expected: PASS for steering contract checks

- [ ] **Step 5: Commit**

```bash
git add enemies/monster.gd tests/test_monster_navigation.gd
git commit -m "feat: add navigation-first monster steering with fallback"
```

### Task 4: Implement Anti-Stuck Watchdog and Re-Path Recovery

**Files:**
- Modify: `enemies/monster.gd`
- Test: `tests/test_monster_navigation.gd`

- [ ] **Step 1: Write the failing test update**

Add tests for:
- progress threshold gate (`_is_progress_too_small`)
- stuck accumulation timer (`_update_stuck_watchdog`)
- cooldown gate (`_can_trigger_stuck_recovery`)

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_monster_navigation.gd`
Expected: FAIL on missing stuck helper behavior

- [ ] **Step 3: Write minimal implementation**

In `enemies/monster.gd` add exports/state:

```gdscript
@export var repath_interval: float = 0.25
@export var move_progress_threshold: float = 0.05
@export var stuck_time_threshold: float = 1.0
@export var stuck_recovery_cooldown: float = 0.8
@export var stuck_fallback_duration: float = 0.5
```

Add watchdog helpers and invoke from `_physics_process(delta)` while movement intent is active.
On stuck, refresh path target and apply short fallback steering window.

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_monster_navigation.gd`
Expected: PASS for stuck detection and recovery gates

- [ ] **Step 5: Run regression checks**

Run:
- `godot --headless -s tests/test_player_climbing.gd`
- `godot --headless -s tests/test_player_climbing_runtime.gd`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add enemies/monster.gd tests/test_monster_navigation.gd
git commit -m "feat: add monster anti-stuck watchdog and repath recovery"
```

### Task 5: Docs Sync

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/design/world-generation-and-poi.md`

- [ ] **Step 1: Update docs for actual monster navigation contract**

Document `_can_use_navigation`, `_get_navigation_direction`, fallback, and anti-stuck recovery behavior.

- [ ] **Step 2: Verify docs and code match**

Run: manual grep checks for helper names in docs and code
Expected: references match implemented symbols

- [ ] **Step 3: Commit**

```bash
git add docs/architecture.md docs/design/world-generation-and-poi.md
git commit -m "docs: sync monster navigation unstuck behavior"
```
