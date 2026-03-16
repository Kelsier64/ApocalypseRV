# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ApocalypseRV is a cooperative first-person survival game built with **Godot 4.6**, **Jolt Physics**, and **GL Compatibility** renderer. Players drive an RV through a procedurally generated post-apocalyptic highway, scavenging buildings, crafting upgrades, and fighting zombies.

## Commands

```bash
# Run the game (main scene: res://world/test_world.tscn)
godot --path . res://world/test_world.tscn

# Run a generation script headlessly
godot --headless -s <script.gd>

# Python offline tools (not Godot runtime)
uv run main.py
uv run test_building_gen.py
```

There is no build step or test suite. Open in Godot 4.6 Editor and press F5 to run.

## Architecture

### Scene Hierarchy (test_world.tscn)
```
TestWorld (Node3D)
├── RV / Chassis (VehicleBody3D)   ← WorldGenerator tracks THIS, not the Player
├── Player (CharacterBody3D)
│   ├── Camera3D
│   │   └── PlayerInteract (RayCast3D)
│   ├── InventoryUI (CanvasLayer, built in _ready())
│   └── HealthBarUI (CanvasLayer, built in _ready())
└── WorldGenerator (Node3D)        ← spawns/despawns ChunkGenerator nodes
```

### Cross-System Communication

**No autoloads.** Cross-tree lookups use `get_tree().get_nodes_in_group()` with groups: `"player"`, `"monsters"`, `"rv"`, `"chassis"`, `"crafting_stations"`.

| From → To | Method |
|-----------|--------|
| Player → Equipment/Props | `player_interact.gd` RayCast3D calls `interact()` / `start_placement()` |
| Equipment → RV | `get_connected_rv()` walks tree upward checking group `"rv"`, duck-typed |
| RV → TabletUI | `inventory_changed(item_name, amount)` signal |
| Monster → Player | `target_player.take_damage(amount)` via `has_method()` check |
| Monster ← Vehicle | HitBox (Area3D) `body_entered` detects VehicleBody3D |
| World → Chunks | `WorldGenerator._process()` compares RV Z position to chunk boundaries |

### Collision Layer Convention

- **Layer 1**: Physics (default for all physical bodies)
- **Layer 2**: Interaction-only (e.g., wheel hitboxes — invisible to chassis physics on mask 1)

### RV System (`rv/`)

Two implementations exist: `rv.gd` (class `RV`) and `chassis.gd` (class `Chassis`). `Chassis` is the newer version with additional features:
- **Wheel slot system**: 4 slots (FL/FR/RL/RR), wheels created programmatically as `VehicleWheel3D` + mesh + hitbox. Removable via hold-interact, installable from Prop inventory.
- **Inventory**: `add_item()`, `has_materials()`, `deduct_materials()`, `get_all_items()` with `inventory_changed` signal.
- **Fuel/power**: `current_fuel`/`max_fuel`, `current_power`/`max_power` (tracked but not yet consumed).
- **Debug driving**: Arrow keys always work regardless of `is_player_driving` state.

### Driver Seat (`equipment/driver_seat.gd`)

Player boards via hold-interact on the seat. Boarding disables player physics/collision, hides the player, activates the seat's Camera3D, and calls `rv.set_driving_state(true)`. Press E to exit (teleports player to the side). Uses `call_deferred("_setup_if_on_rv")` in `_ready()` to ensure the RV's group registration completes first.

### Equipment Placement Flow

1. Player holds F for 2s on Equipment → `start_placement()` freezes physics, applies ghost material
2. `_physics_process` raycasts from camera, positions ghost with surface/upright mode (toggle R)
3. Left-click confirms: reparents to hit target (walks up to find RV), calls `add_collision_exception_with()` on entire parent chain
4. Right-click cancels, restores original position

### World Generation Pipeline

1. **WorldGenerator** (`world/world_generator.gd`) — owns noise (terrain seed 1337, detail seed 7331), streams chunks based on RV position (3 ahead, 2 behind)
2. **ChunkGenerator** (`world/chunk_generator.gd`) — 150m chunks, builds terrain + road meshes via SurfaceTool, places POIs
3. **POIConfig** (`world/poi_config.gd`) — unified POI table with weight, footprint, loot tables, enemy config.
4. **POISpawner** (`world/poi_spawner.gd`) — RefCounted, weighted `pick_poi()`, spawns buildings/loot/enemies
5. **BuildingGenerator** (`world/building/building_generator.gd`) — BFS room graph on 9m occupancy grid, elevator-rooted procedural towers


### Prop System (`props/interactable_item.gd`, class_name `Prop`)

Base class for all pickups (extends RigidBody3D). Key exports: `item_name`, `is_large`, `scrap_yields` (dict of material → Vector2 min/max range), and hold visual offsets (`hold_position`, `hold_rotation`, `hold_scale`). Interaction uses duck-typing: calls `player.add_item(item_name, is_large, scene_file_path)`.

## Critical Pitfalls

**Jolt Physics** — Non-uniform scale on CollisionShapes causes Jolt errors. Always use uniform `Vector3(x, x, x)` for scale tweens on nodes with CollisionShapes.

**Equipment collision exceptions** — After placing equipment on the RV, `add_collision_exception_with()` must be called on the entire parent chain. Forgetting this rockets the RV into the air. `cancel_placement()` must clean up with `remove_collision_exception_with()`.

**Scrapper non-functional off-RV** — `get_connected_rv()` requires descendant of a node in group `"rv"`. Scrapper on the ground silently does nothing.

**`scene_file_path` for props** — `interactable_item.gd` uses `self.scene_file_path` for drop/spawn paths. Programmatically instantiated props have an empty path (fallbacks only for oil_barrel and scrap).

**Building door sealing is known-broken** — Procedural BuildingGenerator door/seal logic has bugs where some doors that should be sealed aren't, and vice versa.

**Deferred setup for equipment on RV** — Equipment that needs to find its parent RV in `_ready()` must use `call_deferred()` because the RV hasn't added itself to group `"rv"` yet during its own `_ready()`.

## GDScript Conventions

- `snake_case` vars/funcs, `PascalCase` classes, `ALL_CAPS` constants
- `_` prefix for internal functions
- Duck-typing with `has_method()` / `"property" in obj` to avoid circular imports
- `@export_group("Name")` for inspector organization
- Player HUDs built entirely in `_ready()` — no .tscn files for UI
- Use static typing where applicable

## Development Rules

- **Python**: Always use `uv` (`uv run <path>`)
- **Simple scenes**: Edit `.tscn` directly only for simple tasks
- **Complex scenes**: Write `SceneTree` generation scripts and run with `godot --headless -s`; always create fresh scripts (never reuse) to avoid overwriting manual edits
- **Editor tasks**: Provide `.gd` files + step-by-step Editor UI instructions instead of editing `.tscn` directly
