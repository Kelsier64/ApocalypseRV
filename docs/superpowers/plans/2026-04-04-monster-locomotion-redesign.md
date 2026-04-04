# Monster Locomotion Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace buggy monster movement internals with stable patrol/chase traversal that chooses walk, jump, or climb from obstacle height and supports floating undersides via unified edge/ledge logic.

**Architecture:** Keep existing high-level AI states and targeting/combat APIs, but replace traversal internals with a locomotion mode decision layer. Add probe-driven obstacle classification and deterministic climb resolution with success landing or drop+cooldown failure. Preserve compatibility with existing helper contracts used by current tests.

**Tech Stack:** Godot 4.6 GDScript, headless SceneTree tests

---

### Task 1: Add failing tests for new traversal behavior

**Files:**
- Modify: `tests/test_energy_system.gd`

- [ ] **Step 1: Write failing assertions for traversal helpers**

```gdscript
func _test_monster_navigation_and_climb_contracts() -> void:
	var monster := Monster.new()

	_expect(monster.has_method("_classify_obstacle_action"), "Monster should expose _classify_obstacle_action(height, has_clearance).")
	_expect(monster.has_method("_is_underside_normal"), "Monster should expose _is_underside_normal(normal).")
	_expect(monster.has_method("_should_drop_from_climb"), "Monster should expose _should_drop_from_climb(duration, climbed_height).")

	if monster.has_method("_classify_obstacle_action"):
		_expect(monster._classify_obstacle_action(0.15, true) == "ground", "Low obstacles should stay ground.")
		_expect(monster._classify_obstacle_action(0.7, true) == "jump", "Mid-height obstacles should choose jump.")
		_expect(monster._classify_obstacle_action(1.6, true) == "climb", "High obstacles should choose climb.")
```

- [ ] **Step 2: Run test to verify RED**

Run: `godot --headless -s tests/test_energy_system.gd`
Expected: FAIL because new helper methods do not exist yet.

- [ ] **Step 3: Commit failing test change**

```bash
git add tests/test_energy_system.gd
git commit -m "test: add failing monster locomotion traversal contracts"
```

### Task 2: Rebuild monster locomotion internals with mode decisions

**Files:**
- Modify: `enemies/monster.gd`

- [ ] **Step 1: Add locomotion mode data and tuning exports**

```gdscript
enum LocomotionMode { GROUND, JUMP, CLIMB }
@export_group("Traversal")
@export var jump_min_height: float = 0.35
@export var jump_max_height: float = 1.2
@export var jump_impulse: float = 6.0
@export var jump_cooldown: float = 0.85
@export var climb_max_height: float = 2.6
@export var underside_normal_threshold: float = -0.45
```

- [ ] **Step 2: Add helper APIs required by tests**

```gdscript
func _classify_obstacle_action(obstacle_height: float, has_top_clearance: bool) -> String:
	if obstacle_height < jump_min_height:
		return "ground"
	if has_top_clearance and obstacle_height <= jump_max_height:
		return "jump"
	return "climb"

func _is_underside_normal(surface_normal: Vector3) -> bool:
	return surface_normal.dot(Vector3.UP) <= underside_normal_threshold

func _should_drop_from_climb(elapsed: float, climbed_height: float) -> bool:
	return elapsed >= wall_climb_max_duration or climbed_height >= climb_max_height
```

- [ ] **Step 3: Replace old wall climb application with probe-driven locomotion**

```gdscript
# Pseudocode flow
# 1) Probe frontal obstacle + upper clearance
# 2) Classify action = ground/jump/climb
# 3) Jump: one-shot impulse with cooldown
# 4) Climb: stick-to-wall upward motion while searching ledge
# 5) On ledge found => land and return ground
# 6) On timeout/height cap => drop and cooldown
```

- [ ] **Step 4: Preserve existing helper contracts**

```gdscript
func _should_attempt_wall_climb(target_height_gap: float, has_wall_hit: bool, wall_normal: Vector3) -> bool:
	# Keep compatibility for current tests and callers, route through new gating logic
```

- [ ] **Step 5: Commit implementation**

```bash
git add enemies/monster.gd
git commit -m "feat: redesign monster locomotion with jump and unified climb"
```

### Task 3: Turn tests green and verify no regression

**Files:**
- Modify: `tests/test_energy_system.gd` (if assertion tuning needed)
- Modify: `docs/architecture.md` (if architecture behavior description changes)

- [ ] **Step 1: Run tests and verify GREEN**

Run: `godot --headless -s tests/test_energy_system.gd`
Expected: PASS with no new failures.

- [ ] **Step 2: Quick behavior verification in test world**

Run: `godot --path . res://world/test_world.tscn`
Expected:
- Monster patrol/chase still works.
- Small blockers trigger jump.
- Tall blockers trigger climb.
- Underside hits seek edge/ledge and either mount top or drop with cooldown.

- [ ] **Step 3: Sync architecture documentation if needed**

```markdown
Update Enemy Locomotion AI section to mention:
- obstacle-height-based jump vs climb
- unified underside handling
- climb drop cooldown behavior
```

- [ ] **Step 4: Commit verification/docs updates**

```bash
git add tests/test_energy_system.gd docs/architecture.md
git commit -m "test/docs: verify and document monster locomotion redesign"
```
