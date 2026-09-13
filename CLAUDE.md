# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ApocalypseRV is a cooperative first-person survival game built with **Godot 4.6**, **Jolt Physics**, and the **GL Compatibility** renderer. Players drive an RV through a procedurally generated post-apocalyptic highway, scavenging buildings, crafting upgrades, and fighting zombies.

## Commands

`godot` (4.6) is on PATH.

```bash
# Run the game (main scene: res://world/test_world.tscn)
godot --path . res://world/test_world.tscn

# Run a single test (SceneTree scripts; print PASS / push_error FAIL, exit 0/1)
godot --headless --path . -s tests/test_monster_navigation.gd
godot --headless --path . -s tests/test_player_climbing.gd

# Run a scene-generation script headlessly
godot --headless -s <script.gd>
```

Run `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1` for imports, all tests, and main-scene smoke validation. GitHub Actions runs the same entry point. There is no separate lint step. If Python tooling is ever needed, always use `uv` (`uv run <path>`).

## Development Rules

- **Simple scenes**: Edit `.tscn` directly only for simple tasks
- **Complex scenes**: Write `SceneTree` generation scripts and run with `godot --headless -s`; always create fresh scripts under `./scripts` (never reuse to avoid overwriting manual edits)
- **Editor tasks**: Provide `.gd` files + step-by-step Editor UI instructions instead of editing `.tscn` directly

## Architecture

Detailed docs live in `docs/`: `architecture.md` (system overview), `docs/design/*` (behavior design), `docs/modules/*` (per-component contracts), and `GDD.md` (game design doc, Traditional Chinese). Directories map 1:1 to runtime domains:

- **`world/`** — chunk streaming pipeline: `world_generator.gd` keeps a behind/current/ahead chunk window keyed on player Z position; `chunk_generator.gd` builds terrain/road/nav mesh per chunk; `poi_spawner.gd` + `poi_config.gd` do weighted POI selection; `world/building/` generates multi-room procedural buildings from room definitions.
- **`rv/`** — `chassis.gd` is the RV core: driving physics, fuel/power economy, material inventory, wheel slots, durability.
- **`equipment/`** — placeable RV devices (generator, crafting station, scrapper, driver seat, tablet UI). `equipment.gd` is the base class; equipment finds its RV **by walking ancestors and duck-typing** (checking for methods like `add_item`/`deduct_materials`), so reparenting nodes can silently break the connection.
- **`player/`** — FPS movement with a NORMAL/CLIMBING locomotion state machine (`player.gd`), plus interaction raycasting (`player_interact.gd`) against props/equipment via duck-typed `interact`/`interact_hold`.
- **`enemies/monster.gd`** — monster AI: WANDER/CHASE/ATTACK states crossed with NORMAL/CLIMBING locomotion; can climb walls and attack RV structure while climbing; underfoot attacks go through a single deterministic raycast path.

### Cross-cutting contracts

- **`core/` holds the shared contracts**: `groups.gd` (group-name constants — runtime code must use `Groups.*`; tests pin the raw strings on purpose), `item_names.gd` (inventory item names), `climb_math.gd` (climb geometry shared by player and monster; their `_is_rv_wall_normal`-style helpers are thin wrappers whose names the tests pin), `world_entities.gd` (ownership rule: chunk-static content dies with its chunk, active entities live in the shared `WorldEntities` container and are distance-despawned by the world generator).
- **Group membership** is the wiring mechanism between systems: `rv`, `chassis`, `equipment`, `monster_damageable`, `rv_power_generators`, `crafting_stations`, `player`, `monsters`. Renaming or dropping a group breaks behavior with no compile error.
- **Player top-level modes** (NORMAL/PLACING/UI/SEATED/DEAD) are mutually exclusive; transitions go through `enter_*`/`exit_*` helpers on `player.gd` that return false on refusal — callers must abort their side of the flow when refused.
- **Tests are behavior contracts.** `tests/*.gd` are self-contained `SceneTree` scripts that assert specific helper methods exist and gate behaviors (climb start/abort rules, attack range gates, underfoot raycast authorization). When refactoring `player.gd` or `monster.gd`, run the matching test — renaming a helper the tests reference is a contract change, not just a rename.
- **Guard-heavy error handling**: systems null-check dependencies and degrade silently (e.g., POI spawner filters out missing scene paths with a one-time warning), so missing assets shift gameplay rather than crash.

### Refactored boundaries
- `player/player_inventory.gd` owns inventory data/rules; `player/equipment_placement.gd` owns placement state and input. The player retains scene presentation, movement, and mode authorization.
- `enemies/combat_targeting.gd` owns target ranking; the monster supplies world observations and executes attacks. New tests should prefer module behavior over private helper-name checks.
- `core/rv_connection.gd` defines the equipment RV lookup contract. Placement confirmation/cancellation refreshes the connection; lazy validation covers external reparenting and initialization order.
- `docs/superpowers/` is historical reference only. Keep `todo` and `todo_for_ai` unchanged unless the user requests edits.