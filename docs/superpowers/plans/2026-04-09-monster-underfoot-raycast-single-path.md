# Monster Underfoot Raycast Single-Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce a single deterministic underfoot attack path where monster underfoot attacks only occur from UnderfootProbe raycast hits to floor equipment and only when tracked player is below the monster.

**Architecture:** Keep touching attack flow and underfoot attack flow separate. Underfoot flow becomes probe-hit-only with no candidate-list fallback, and authorization becomes player-only elevation gating. Tests are updated first to lock the contract, then implementation is minimized to satisfy tests.

**Tech Stack:** Godot 4.6, GDScript, SceneTree headless contract tests (`tests/test_monster_navigation.gd`)

---

## File Structure

- Modify: `enemies/monster.gd`
  - Keep existing combat/touching behavior intact.
  - Remove underfoot legacy fallback path.
  - Make underfoot target selection probe-hit-only.
  - Keep player-only authorization source for underfoot gate.

- Modify: `enemies/zombie.tscn`
  - Ensure `UnderfootProbe` exists and points downward with stable defaults.

- Modify: `tests/test_monster_navigation.gd`
  - Remove legacy underfoot fallback expectations.
  - Add contract tests for probe-only selection and player-only authorization.

### Task 1: Lock Single-Path Underfoot Contract Tests (RED)

**Files:**
- Modify: `tests/test_monster_navigation.gd`
- Test: `tests/test_monster_navigation.gd`

- [ ] **Step 1: Replace legacy underfoot fallback expectations with probe-only expectations**

```gdscript
func _test_select_underfoot_equipment_target_requires_probe_hit() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_select_underfoot_equipment_target"), "Monster should expose _select_underfoot_equipment_target().")
	if monster.has_method("_select_underfoot_equipment_target"):
		monster.position = Vector3(0.0, 1.0, 0.0)

		var equipment := _DummyDamageable.new()
		equipment.position = Vector3(0.1, 0.0, 0.0)
		equipment.add_to_group("monster_damageable")

		# No probe hit configured -> must not select by candidate list fallback.
		var chosen = monster._select_underfoot_equipment_target()
		_expect(chosen == null, "Underfoot selection should require downward ray hit and must not use candidate-list fallback.")

		equipment.free()

	monster.free()
```

- [ ] **Step 2: Add chassis/player exclusion contract from probe hit resolution**

```gdscript
func _test_underfoot_probe_hit_excludes_chassis_and_player() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_resolve_underfoot_damageable_from_collider"), "Monster should expose _resolve_underfoot_damageable_from_collider(collider).")
	if monster.has_method("_resolve_underfoot_damageable_from_collider"):
		var chassis := Node3D.new()
		chassis.add_to_group("chassis")
		chassis.add_to_group("monster_damageable")
		chassis.set_script(null)
		chassis.set("name", "DummyChassis")

		var player := Node3D.new()
		player.add_to_group("player")
		player.add_to_group("monster_damageable")

		var chassis_resolved = monster._resolve_underfoot_damageable_from_collider(chassis)
		var player_resolved = monster._resolve_underfoot_damageable_from_collider(player)
		_expect(chassis_resolved == null, "Underfoot resolver must exclude chassis targets.")
		_expect(player_resolved == null, "Underfoot resolver must exclude player targets.")

		chassis.free()
		player.free()

	monster.free()
```

- [ ] **Step 3: Add player-only authorization contract test**

```gdscript
func _test_underfoot_authorization_is_player_only() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_resolve_underfoot_tracking_target"), "Monster should expose _resolve_underfoot_tracking_target().")
	if monster.has_method("_resolve_underfoot_tracking_target"):
		var equipment := _DummyDamageable.new()
		equipment.add_to_group("monster_damageable")

		monster.target_player = null
		monster.current_combat_target = {
			"node": equipment,
			"position": equipment.position,
			"target_type": "equipment"
		}

		var tracking_target: Node3D = monster._resolve_underfoot_tracking_target()
		_expect(tracking_target == null, "Only player tracking source may authorize underfoot attacks.")

		equipment.free()

	monster.free()
```

- [ ] **Step 4: Register these tests in `_init()` and remove now-invalid nearest/fallback underfoot expectations**

```gdscript
func _init() -> void:
	# ... keep existing unrelated tests ...
	_test_select_underfoot_equipment_target_requires_probe_hit()
	_test_underfoot_probe_hit_excludes_chassis_and_player()
	_test_underfoot_authorization_is_player_only()
	# Remove legacy tests that assert candidate-list nearest selection without probe hit.
	_finish()
```

- [ ] **Step 5: Run test to verify RED**

Run: `godot --headless --path . -s tests/test_monster_navigation.gd`
Expected: FAIL with at least one new assertion indicating underfoot selection/authorization still depends on legacy behavior.

- [ ] **Step 6: Commit failing test baseline**

```bash
git add tests/test_monster_navigation.gd
git commit -m "test: lock underfoot probe-only and player-only authorization contracts"
```

### Task 2: Implement Probe-Only Underfoot Selection (GREEN)

**Files:**
- Modify: `enemies/monster.gd`
- Test: `tests/test_monster_navigation.gd`

- [ ] **Step 1: Remove underfoot legacy fallback selector and make selector probe-only**

```gdscript
func _select_underfoot_equipment_target() -> Node3D:
	var raycast_target := _get_underfoot_raycast_target()
	if raycast_target != null:
		return raycast_target
	return null
```

- [ ] **Step 2: Remove candidate-list based legacy selector function entirely**

```gdscript
# Delete function:
# func _select_underfoot_equipment_target_legacy(structure_candidates: Array, max_planar_distance: float, max_height_delta: float) -> Node3D:
# 	...
```

- [ ] **Step 3: Update callsites to no-argument underfoot selector**

```gdscript
func _try_attack_underfoot_equipment(tracking_target_node: Node3D, structure_candidates_override: Array = []) -> bool:
	if tracking_target_node == null or not is_instance_valid(tracking_target_node):
		return false
	if not _is_tracking_target_below(_get_node_target_position(tracking_target_node), underfoot_target_below_margin):
		return false

	var underfoot_target := _select_underfoot_equipment_target()
	if underfoot_target == null:
		return false

	var previous_attack_timer := attack_timer
	_execute_attack_on_target(_build_combat_target(underfoot_target, "equipment"))
	return attack_timer > previous_attack_timer
```

- [ ] **Step 4: Keep target type whitelist strict in resolver path**

```gdscript
func _is_underfoot_equipment_candidate(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if node.is_in_group("player") or node.is_in_group("chassis"):
		return false
	if not node.is_in_group("monster_damageable"):
		return false
	if not node.has_method("take_damage"):
		return false
	return true
```

- [ ] **Step 5: Run test to verify GREEN for new contracts**

Run: `godot --headless --path . -s tests/test_monster_navigation.gd`
Expected: PASS for newly added underfoot probe-only and player-only authorization tests.

- [ ] **Step 6: Commit implementation**

```bash
git add enemies/monster.gd
git commit -m "feat: enforce probe-only underfoot target selection"
```

### Task 3: Keep Underfoot Authorization Player-Only and Isolated from Touching Flow

**Files:**
- Modify: `enemies/monster.gd`
- Modify: `tests/test_monster_navigation.gd`
- Test: `tests/test_monster_navigation.gd`

- [ ] **Step 1: Keep/confirm player-only tracking source in underfoot resolver**

```gdscript
func _resolve_underfoot_tracking_target() -> Node3D:
	if target_player and is_instance_valid(target_player):
		return target_player
	var combat_target := _get_current_combat_target_node()
	if combat_target != null and combat_target.is_in_group("player"):
		return combat_target
	return null
```

- [ ] **Step 2: Ensure touching path does not pass structure fallback into underfoot selection**

```gdscript
func _select_touching_attack_target(player_candidates: Array, structure_candidates: Array, tracking_target_node: Node3D = null) -> Dictionary:
	# ... touching candidate logic unchanged ...

	if tracking_target_node != null and is_instance_valid(tracking_target_node):
		if _is_tracking_target_below(_get_node_target_position(tracking_target_node), underfoot_target_below_margin):
			var underfoot_target := _select_underfoot_equipment_target()
			if underfoot_target != null:
				return _build_combat_target(underfoot_target, "equipment")

	return {}
```

- [ ] **Step 3: Add explicit test that structure candidates cannot force underfoot attack without probe hit**

```gdscript
func _test_underfoot_attack_does_not_use_structure_candidates_without_probe_hit() -> void:
	var monster := _new_monster()
	if monster == null:
		return

	_expect(monster.has_method("_try_auto_attack_touching_targets"), "Monster should expose _try_auto_attack_touching_targets(...).")
	if monster.has_method("_try_auto_attack_touching_targets"):
		monster.position = Vector3(0.0, 1.0, 0.0)
		monster.contact_damage = 5.0
		monster.attack_timer = 0.0

		var equipment := _DummyDamageable.new()
		equipment.position = Vector3(0.1, 0.0, 0.0)
		equipment.add_to_group("monster_damageable")

		var tracking_player := Node3D.new()
		tracking_player.position = Vector3(0.0, 0.2, 0.0)
		tracking_player.add_to_group("player")

		var attacked := monster._try_auto_attack_touching_targets(tracking_player, [], [equipment])
		_expect(not attacked, "Without probe hit, structure candidates must not trigger underfoot attack.")
		_expect(is_zero_approx(equipment.damage_received), "Without probe hit, no underfoot damage should be applied.")

		equipment.free()
		tracking_player.free()

	monster.free()
```

- [ ] **Step 4: Run test suite to verify no touching regression and underfoot isolation**

Run: `godot --headless --path . -s tests/test_monster_navigation.gd`
Expected: PASS with touching-player/chassis/equipment tests still green and underfoot single-path tests green.

- [ ] **Step 5: Commit isolation fixes**

```bash
git add enemies/monster.gd tests/test_monster_navigation.gd
git commit -m "refactor: isolate underfoot attack from touching candidate fallback"
```

### Task 4: Scene Probe Wiring and Final Verification

**Files:**
- Modify: `enemies/zombie.tscn`
- Test: `tests/test_monster_navigation.gd`

- [ ] **Step 1: Ensure UnderfootProbe is present with downward target and stable origin**

```tscn
[node name="UnderfootProbe" type="RayCast3D" parent="."]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.0, 0)
target_position = Vector3(0, -2.2, 0)
```

- [ ] **Step 2: Run full monster contract suite**

Run: `godot --headless --path . -s tests/test_monster_navigation.gd`
Expected: `PASS: monster navigation tests`

- [ ] **Step 3: Record final behavior checks against acceptance criteria**

```text
Checklist:
- Legacy underfoot fallback function removed
- Underfoot target selected only from probe hit
- Player-only tracking authorization preserved
- Chassis excluded from underfoot equipment target class
- Monster navigation tests pass
```

- [ ] **Step 4: Commit final wiring/verification updates**

```bash
git add enemies/zombie.tscn tests/test_monster_navigation.gd enemies/monster.gd
git commit -m "test: verify underfoot attack raycast single-path contract"
```

## Plan Self-Review

- Spec coverage check:
  - Probe-only detection: Task 1 + Task 2
  - Player-only authorization: Task 1 + Task 3
  - Chassis exclusion from underfoot equipment: Task 1 + Task 2
  - Remove fallback semantics: Task 1 + Task 2 + Task 3
  - Full contract verification: Task 4

- Placeholder scan:
	- No placeholder tokens remain in steps.

- Type/signature consistency:
  - Underfoot selector signature is normalized to `_select_underfoot_equipment_target()` and updated consistently across all planned callsites/tests.
