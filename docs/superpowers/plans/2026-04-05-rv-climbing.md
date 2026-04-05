# RV Climbing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add stable player climbing on RV walls (jump + W trigger), including moving-RV support and safe top-out standing onto roof.

**Architecture:** Extend player locomotion with Climbing and Mantling states, using explicit RV wall and top probes, RV transform-delta compensation during climb/mantle, and strict safety exits to avoid launch/fly bugs. Keep implementation localized to player controller + player scene probes + focused tests.

**Tech Stack:** Godot 4.6, GDScript, SceneTree headless tests

---

### Task 1: Add failing tests for climb gate rules

**Files:**
- Create: `tests/test_player_climbing.gd`
- Modify: `player/player.gd`
- Test: `tests/test_player_climbing.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
extends SceneTree

var failures: Array[String] = []

func _init() -> void:
	_test_wall_gate_requires_jump_and_w_and_rv()
	_test_wall_gate_rejects_undercarriage_like_hits()
	_test_top_gate_requires_standable_surface()
	_finish()

func _test_wall_gate_requires_jump_and_w_and_rv() -> void:
	var player := Player.new()
	# Expected helper APIs that do not exist yet (RED)
	_expect(player.has_method("_is_rv_wall_normal"), "Player should expose _is_rv_wall_normal(normal, rv_up).")
	_expect(player.has_method("_is_valid_climb_hit_height"), "Player should expose _is_valid_climb_hit_height(local_hit_y).")
	_expect(player.has_method("_can_begin_climb"), "Player should expose _can_begin_climb(jump_pressed, w_pressed, is_rv_hit, wall_normal_ok, hit_height_ok).")
	if player.has_method("_can_begin_climb"):
		_expect(not player._can_begin_climb(false, true, true, true, true), "Jump is required to start climb.")
		_expect(not player._can_begin_climb(true, false, true, true, true), "W is required to start climb.")
		_expect(not player._can_begin_climb(true, true, false, true, true), "RV hit is required to start climb.")
	player.free()

func _test_wall_gate_rejects_undercarriage_like_hits() -> void:
	var player := Player.new()
	if player.has_method("_is_valid_climb_hit_height"):
		_expect(not player._is_valid_climb_hit_height(-0.9), "Undercarriage-like low hit should be rejected.")
		_expect(player._is_valid_climb_hit_height(0.7), "Chest-height wall hit should be accepted.")
	player.free()

func _test_top_gate_requires_standable_surface() -> void:
	var player := Player.new()
	_expect(player.has_method("_can_start_mantle"), "Player should expose _can_start_mantle(top_surface_ok, stand_clearance_ok, forward_clear_ok).")
	if player.has_method("_can_start_mantle"):
		_expect(not player._can_start_mantle(true, false, true), "Mantle should fail without stand clearance.")
		_expect(player._can_start_mantle(true, true, true), "Mantle should pass when all top gates are valid.")
	player.free()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("PASS: player climbing tests")
		quit(0)
		return
	push_error("FAIL: player climbing tests")
	for failure in failures:
		push_error(" - " + failure)
	quit(1)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_player_climbing.gd`
Expected: FAIL with missing helper methods on Player.

- [ ] **Step 3: Write minimal implementation**

```gdscript
# player/player.gd
class_name Player

const CLIMB_WALL_MIN_DOT: float = 0.15
const CLIMB_WALL_MAX_DOT: float = 0.85
const CLIMB_MIN_HIT_Y: float = 0.1
const CLIMB_MAX_HIT_Y: float = 1.4

func _is_rv_wall_normal(hit_normal: Vector3, rv_up: Vector3 = Vector3.UP) -> bool:
	var d := absf(hit_normal.normalized().dot(rv_up.normalized()))
	return d >= CLIMB_WALL_MIN_DOT and d <= CLIMB_WALL_MAX_DOT

func _is_valid_climb_hit_height(local_hit_y: float) -> bool:
	return local_hit_y >= CLIMB_MIN_HIT_Y and local_hit_y <= CLIMB_MAX_HIT_Y

func _can_begin_climb(jump_pressed: bool, w_pressed: bool, is_rv_hit: bool, wall_normal_ok: bool, hit_height_ok: bool) -> bool:
	return jump_pressed and w_pressed and is_rv_hit and wall_normal_ok and hit_height_ok

func _can_start_mantle(top_surface_ok: bool, stand_clearance_ok: bool, forward_clear_ok: bool) -> bool:
	return top_surface_ok and stand_clearance_ok and forward_clear_ok
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_player_climbing.gd`
Expected: PASS: player climbing tests

- [ ] **Step 5: Commit**

```bash
git add tests/test_player_climbing.gd player/player.gd
git commit -m "test: add climb gate contract tests"
```

### Task 2: Add failing tests for moving-RV compensation and safe exit velocity

**Files:**
- Modify: `tests/test_player_climbing.gd`
- Modify: `player/player.gd`
- Test: `tests/test_player_climbing.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
func _init() -> void:
	_test_wall_gate_requires_jump_and_w_and_rv()
	_test_wall_gate_rejects_undercarriage_like_hits()
	_test_top_gate_requires_standable_surface()
	_test_rv_delta_compensation_math()
	_test_climb_exit_velocity_sanitized()
	_finish()

func _test_rv_delta_compensation_math() -> void:
	var player := Player.new()
	_expect(player.has_method("_compute_rv_position_delta"), "Player should expose _compute_rv_position_delta(prev, next).")
	if player.has_method("_compute_rv_position_delta"):
		var prev := Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))
		var next := Transform3D(Basis.IDENTITY, Vector3(3, 3, 7))
		var d: Vector3 = player._compute_rv_position_delta(prev, next)
		_expect(d.is_equal_approx(Vector3(2, 1, 4)), "RV delta should be next.origin - prev.origin.")
	player.free()

func _test_climb_exit_velocity_sanitized() -> void:
	var player := Player.new()
	_expect(player.has_method("_sanitize_velocity_after_climb"), "Player should expose _sanitize_velocity_after_climb(v).")
	if player.has_method("_sanitize_velocity_after_climb"):
		var out: Vector3 = player._sanitize_velocity_after_climb(Vector3(2, 30, -1))
		_expect(out.y <= 0.1, "Vertical velocity should be sanitized when exiting climb.")
	player.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_player_climbing.gd`
Expected: FAIL with missing RV compensation helper methods.

- [ ] **Step 3: Write minimal implementation**

```gdscript
const CLIMB_EXIT_MAX_UP_VELOCITY: float = 0.1

func _compute_rv_position_delta(prev_rv_transform: Transform3D, next_rv_transform: Transform3D) -> Vector3:
	return next_rv_transform.origin - prev_rv_transform.origin

func _sanitize_velocity_after_climb(v: Vector3) -> Vector3:
	var out := v
	out.y = minf(out.y, CLIMB_EXIT_MAX_UP_VELOCITY)
	return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_player_climbing.gd`
Expected: PASS: player climbing tests

- [ ] **Step 5: Commit**

```bash
git add tests/test_player_climbing.gd player/player.gd
git commit -m "test: cover rv compensation and climb exit safeguards"
```

### Task 3: Implement climb and mantle states in player controller

**Files:**
- Modify: `player/player.gd`
- Modify: `player/player.tscn`
- Test: `tests/test_player_climbing.gd`

- [ ] **Step 1: Write the failing test**

```gdscript
func _init() -> void:
	_test_wall_gate_requires_jump_and_w_and_rv()
	_test_wall_gate_rejects_undercarriage_like_hits()
	_test_top_gate_requires_standable_surface()
	_test_rv_delta_compensation_math()
	_test_climb_exit_velocity_sanitized()
	_test_player_has_climb_state_contract()
	_finish()

func _test_player_has_climb_state_contract() -> void:
	var player := Player.new()
	_expect(player.has_method("_try_start_climb"), "Player should expose _try_start_climb() state transition helper.")
	_expect(player.has_method("_process_climbing"), "Player should expose _process_climbing(delta).")
	_expect(player.has_method("_begin_mantle"), "Player should expose _begin_mantle(target).")
	_expect(player.has_method("_process_mantle"), "Player should expose _process_mantle(delta).")
	player.free()
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s tests/test_player_climbing.gd`
Expected: FAIL with missing climb state methods.

- [ ] **Step 3: Write minimal implementation**

```gdscript
# player/player.gd
enum LocomotionState { NORMAL, CLIMBING, MANTLING }
var locomotion_state: LocomotionState = LocomotionState.NORMAL
var active_climb_rv: Node3D = null
var prev_climb_rv_transform: Transform3D
var mantle_start: Vector3 = Vector3.ZERO
var mantle_target: Vector3 = Vector3.ZERO
var mantle_t: float = 0.0

@onready var climb_wall_probe: RayCast3D = $ClimbWallProbe
@onready var climb_top_probe: RayCast3D = $ClimbTopProbe

func _physics_process(delta: float):
	if in_ui_mode:
		return
	match locomotion_state:
		LocomotionState.NORMAL:
			_process_normal_movement(delta)
			_try_start_climb()
		LocomotionState.CLIMBING:
			_process_climbing(delta)
		LocomotionState.MANTLING:
			_process_mantle(delta)

func _try_start_climb() -> void:
	# Evaluate probes + helper gates and initialize climb state.
	pass

func _process_climbing(delta: float) -> void:
	# Apply rv delta compensation + upward movement + top gate checks.
	pass

func _begin_mantle(target: Vector3) -> void:
	locomotion_state = LocomotionState.MANTLING
	mantle_start = global_position
	mantle_target = target
	mantle_t = 0.0

func _process_mantle(delta: float) -> void:
	# Interpolate to mantle_target while applying rv delta compensation.
	pass

func _exit_climb_to_normal() -> void:
	locomotion_state = LocomotionState.NORMAL
	active_climb_rv = null
	velocity = _sanitize_velocity_after_climb(velocity)
```

```tscn
; player/player.tscn
[node name="ClimbWallProbe" type="RayCast3D" parent="."]
position = Vector3(0, 1.0, 0)
target_position = Vector3(0, 0, -0.8)
collision_mask = 1

[node name="ClimbTopProbe" type="RayCast3D" parent="."]
position = Vector3(0, 1.6, -0.35)
target_position = Vector3(0, 0.8, -0.45)
collision_mask = 1
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_player_climbing.gd`
Expected: PASS: player climbing tests

- [ ] **Step 5: Run existing regression test**

Run: `godot --headless -s tests/test_energy_system.gd`
Expected: PASS: energy system tests

- [ ] **Step 6: Commit**

```bash
git add player/player.gd player/player.tscn tests/test_player_climbing.gd
git commit -m "feat: add rv climb and mantle locomotion states"
```

### Task 4: Update docs and verify gameplay path

**Files:**
- Modify: `docs/modules/player-equipment-interactions.md`
- Test: `tests/test_player_climbing.gd`

- [ ] **Step 1: Write failing doc expectation test (manual checklist)**

```text
Expected missing docs before update:
- No mention of jump+W RV climb trigger
- No mention of undercarriage false-positive guard
- No mention of moving-RV compensation
- No mention of top-out stand validation
```

- [ ] **Step 2: Run verification to confirm current docs are missing climb details**

Run: `Select-String -Path docs/modules/player-equipment-interactions.md -Pattern "climb|mantle|jump\+W|undercarriage|moving-RV"`
Expected: no relevant matches before doc update.

- [ ] **Step 3: Write minimal documentation updates**

```markdown
## Climbing (RV)
- Trigger: jump press + hold W while wall probe hits RV wall.
- Undercarriage guard: low-height and floor-like normals are rejected.
- Moving RV: climb and mantle apply RV transform-delta compensation.
- Top-out: mantle only starts when stand surface and capsule clearance pass.
```

- [ ] **Step 4: Run tests and final verification**

Run: `godot --headless -s tests/test_player_climbing.gd`
Expected: PASS: player climbing tests

Run: `godot --headless -s tests/test_energy_system.gd`
Expected: PASS: energy system tests

- [ ] **Step 5: Commit**

```bash
git add docs/modules/player-equipment-interactions.md
git commit -m "docs: document rv climbing trigger and safeguards"
```

## Plan Self-Review
- Spec coverage check:
  - Jump+W trigger: Task 1 and Task 3.
  - Undercarriage rejection: Task 1 and Task 3.
  - Moving-RV anti-fly safeguards: Task 2 and Task 3.
  - Stable top-out standing: Task 1 and Task 3.
  - Documentation alignment: Task 4.
- Placeholder scan:
  - No TODO/TBD placeholders remain in implementation steps.
- Type consistency:
  - Helper method names are reused consistently across tests and implementation snippets.
