# ApocalypseRV — Workspace Instructions

A cooperative first-person survival game: players drive a beat-up RV through a procedurally generated post-apocalyptic highway, scavenging buildings, crafting upgrades, and surviving zombie attacks. Built with **Godot 4.6**, **Jolt Physics**, and **GL Compatibility renderer**.

---

## Run & Test

```bash
# Run the game (main scene is test_world.tscn)
godot --path . res://world/test_world.tscn

# Python offline tools (not Godot runtime — building gen helpers, migration scripts)
uv run main.py
uv run test_building_gen.py
```

There is no build step. Open in Godot 4.6 Editor and press **F5** to run.

---

## Project Structure

```
player/           # CharacterBody3D player: movement, inventory, health, interaction
enemies/          # Monster base class + zombie scene
equipment/        # RV-attachable machines (Equipment base, Scrapper, CraftingStation, TabletScreen)
rv/               # VehicleBody3D RV: driving, fuel/power, material inventory
props/            # RigidBody3D pickups: Prop base + concrete item scenes
world/            # WorldGenerator (chunk streaming) + ChunkGenerator (terrain/road/spawns)
world/building/   # BuildingGenerator (BSP room graph) + room templates
assets/           # Art assets
main.py           # Offline Python tooling (uv-managed)
```

---

## Architecture

### Key Classes & Scene Hierarchy (test_world.tscn)
```
TestWorld (Node3D)
├── RV (VehicleBody3D)          ← WorldGenerator tracks this, NOT the player
├── Player (CharacterBody3D)
│   ├── Camera3D
│   │   ├── PlayerInteract (RayCast3D)
│   │   └── HandMarker (Marker3D — created at runtime)
│   ├── InventoryUI (CanvasLayer — built programmatically)
│   └── HealthBarUI (CanvasLayer — built programmatically)
└── WorldGenerator (Node3D)    ← spawns/despawns ChunkGenerator nodes
```

### Cross-System Communication
| From | To | Method |
|------|-----|--------|
| Player | Equipment/Props | `player_interact.gd` RayCast3D calls `interact()` / `start_placement()` directly |
| Equipment | RV | `get_connected_rv()` walks tree upward, checks group `"rv"`, duck-typed |
| RV | TabletUI | `inventory_changed(item_name, amount)` signal |
| Monster | Player | `target_player.take_damage(amount)` after `has_method("take_damage")` check |
| Vehicle physics | Monster | Monster `HitBox` (Area3D) `body_entered` detects `VehicleBody3D` |
| World | Chunks | `WorldGenerator._process()` compares RV Z to chunk boundaries |

**No autoloads.** Cross-tree lookups use `get_tree().get_nodes_in_group()` (groups: `"player"`, `"monsters"`, `"rv"`, `"crafting_stations"`).

---

## GDScript Conventions

- `snake_case` variables/functions, `PascalCase` class names, `ALL_CAPS` constants
- Prefix internal functions with `_` (e.g. `_process_chase()`, `_build_terrain_mesh()`)
- `@onready var foo = $NodePath` for node references; `get_node_or_null()` defensively
- Duck-typing with `has_method()` and `"property" in obj` to avoid circular imports
- `@export_group("Name")` to organize inspector properties
- Player HUDs (inventory, health bar) are built entirely in `_ready()` — no `.tscn` files for them
- Connect signals with `.connect(callable)` or lambdas; disconnect before reconnect when re-using

---

## Critical Pitfalls

**Jolt Physics (not default Godot physics)**
All physics uses Jolt. Non-uniform scale on collision shapes causes Jolt errors — always use uniform `Vector3(x, x, x)` for scale tweens on nodes with CollisionShapes.

**Equipment placement collision exceptions**
After placing equipment on the RV, `add_collision_exception_with()` must be called on the entire parent chain. Forgetting this rockets the RV into the air. `cancel_placement()` must clean up with `remove_collision_exception_with()`.

**Scrapper is non-functional off-RV by design**
`get_connected_rv()` requires the scrapper to be a descendant of a node in group `"rv"`. Scrapper placed on the ground silently does nothing.

**WorldGenerator tracks RV, not Player**
`WorldGenerator.player` is set to `NodePath("../RV")` in the test scene. Chunk streaming is centered on the vehicle.

**`scene_file_path` for props**
`interactable_item.gd` uses `self.scene_file_path` to store drop/spawn paths. Programmatically instantiated props (not from `.tscn`) will have an empty path — there is a fallback only for `oil_barrel` and `scrap`.

**Noise seed is hardcoded**
`chunk_generator.gd` uses `noise.seed = 1337`. Multiplayer sync of world generation is a future task.

**Building doors have bugs**
`todo_for_ai`: "Doors have many bugs — some that should be sealed aren't, some that should be open are blocked." The procedural `BuildingGenerator` door/seal logic is known-broken.

**Renderer: GL Compatibility**
Not Vulkan/Forward+. Shader features are limited. Use the Compatibility render path for all materials and effects.

---

## Currently Implemented

Player movement/inventory/health, item pickup/drop, RV driving/boarding, RV material inventory, equipment placement system (ghost mode → reparent), Scrapper, CraftingStation, TabletScreen UI, procedural terrain + road (Bezier + noise), chunk streaming, procedural building generator (BFS room graph), zombie enemy (FSM + vehicle collision), monster loot drops.

## Not Yet Implemented (from GDD)

Manual transmission, fuel/power consumption gauges, RV damage model, multiplayer/voice chat, weather/day-night, sleep system, weight-based slowdown, clone pod, radar station, rooftop turret.
