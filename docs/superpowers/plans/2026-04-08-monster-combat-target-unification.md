# Monster Combat Target Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Monsters can attack chassis/equipment and keep attacking during climbing, while player remains the top priority outside climbing and is excluded while climbing.

**Architecture:** Keep existing AI state machine and locomotion flow, add a unified combat-target selection layer in monster logic, and route attack execution through a generic target path. Preserve existing helper contracts and movement behavior.

**Tech Stack:** Godot 4.6, GDScript, headless SceneTree tests

---

### Task 1: Add Failing Contract Tests For Unified Targets

**Files:**
- Modify: `tests/test_monster_navigation.gd`
- Test: `tests/test_monster_navigation.gd`

- [ ] **Step 1: Write failing test for player-priority selection in normal combat**

```gdscript
func _test_combat_target_selection_prioritizes_player_when_not_climbing() -> void:
	var monster := _new_monster()
	if monster == null:
		return
	_expect(monster.has_method("_select_combat_target"), "Monster should expose _select_combat_target(player_candidates, structure_candidates, is_climbing).")
	if monster.has_method("_select_combat_target"):
		var fake_player := Node3D.new()
		fake_player.add_to_group("player")
		var fake_chassis := Node3D.new()
		fake_chassis.add_to_group("monster_damageable")
		var chosen = monster._select_combat_target([fake_player], [fake_chassis], false)
		_expect(chosen != null and chosen.get("node", null) == fake_player, "Normal combat should prioritize player targets.")
		fake_player.queue_free()
		fake_chassis.queue_free()
	monster.free()
```

- [ ] **Step 2: Write failing test for climbing player exclusion**

```gdscript
func _test_combat_target_selection_excludes_player_while_climbing() -> void:
	var monster := _new_monster()
	if monster == null:
		return
	_expect(monster.has_method("_select_combat_target"), "Monster should expose _select_combat_target(player_candidates, structure_candidates, is_climbing).")
	if monster.has_method("_select_combat_target"):
		var fake_player := Node3D.new()
		fake_player.add_to_group("player")
		var fake_equipment := Node3D.new()
		fake_equipment.add_to_group("monster_damageable")
		var chosen = monster._select_combat_target([fake_player], [fake_equipment], true)
		_expect(chosen != null and chosen.get("node", null) == fake_equipment, "Climbing should exclude player targets.")
		fake_player.queue_free()
		fake_equipment.queue_free()
	monster.free()
```

- [ ] **Step 3: Write failing test for generic non-player damage execution path**

```gdscript
class _FakeDamageTarget extends Node3D:
	var total_damage: float = 0.0
	func take_damage(amount: float) -> void:
		total_damage += amount

func _test_attack_executor_damages_non_player_target() -> void:
	var monster := _new_monster()
	if monster == null:
		return
	_expect(monster.has_method("_execute_attack_on_target"), "Monster should expose _execute_attack_on_target(target_data).")
	if monster.has_method("_execute_attack_on_target"):
		var target := _FakeDamageTarget.new()
		monster.contact_damage = 12.0
		monster.attack_timer = 0.0
		monster._execute_attack_on_target({"node": target, "position": Vector3.ZERO, "target_type": "equipment"})
		_expect(target.total_damage > 0.0, "Attack executor should apply damage to non-player target.")
		target.queue_free()
	monster.free()
```

- [ ] **Step 4: Run test to verify it fails**

Run: `godot --headless -s tests/test_monster_navigation.gd`
Expected: FAIL mentioning missing `_select_combat_target` and `_execute_attack_on_target`.

- [ ] **Step 5: Commit**

```bash
git add tests/test_monster_navigation.gd
git commit -m "test: add failing unified combat target contracts"
```

### Task 2: Implement Unified Target Selection + Generic Attack Execution

**Files:**
- Modify: `enemies/monster.gd`
- Test: `tests/test_monster_navigation.gd`

- [ ] **Step 1: Write minimal target selection helpers**

```gdscript
func _select_combat_target(player_candidates: Array, structure_candidates: Array, is_climbing: bool) -> Dictionary:
	if not is_climbing and player_candidates.size() > 0:
		return _build_combat_target(player_candidates[0], "player")
	if structure_candidates.size() > 0:
		return _build_combat_target(structure_candidates[0], "structure")
	return {}
```

- [ ] **Step 2: Write minimal generic attack executor**

```gdscript
func _execute_attack_on_target(target_data: Dictionary) -> void:
	if attack_timer > 0.0:
		return
	var node := target_data.get("node", null)
	if node != null and is_instance_valid(node) and node.has_method("take_damage"):
		node.take_damage(contact_damage)
		attack_timer = attack_cooldown
```

- [ ] **Step 3: Integrate into normal and climbing attack paths**

```gdscript
# In physics/update flow, refresh current target and call attack executor from both normal ATTACK and climbing branches when gate passes.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s tests/test_monster_navigation.gd`
Expected: PASS for new target-selection and attack-executor checks.

- [ ] **Step 5: Commit**

```bash
git add enemies/monster.gd tests/test_monster_navigation.gd
git commit -m "feat: unify monster combat targets and climbing attack behavior"
```

### Task 3: Regression Verification

**Files:**
- Test: `tests/test_monster_navigation.gd`
- Test: `tests/test_player_climbing.gd`

- [ ] **Step 1: Run monster navigation contracts**

Run: `godot --headless -s tests/test_monster_navigation.gd`
Expected: PASS.

- [ ] **Step 2: Run climbing contracts for regression guard**

Run: `godot --headless -s tests/test_player_climbing.gd`
Expected: No new failures introduced by monster changes.

- [ ] **Step 3: Commit verification status (if code changed while fixing regressions)**

```bash
git add enemies/monster.gd tests/test_monster_navigation.gd
git commit -m "test: verify monster target unification regressions"
```
