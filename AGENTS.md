# ApocalypseRV - Agentic AI Coding Guidelines

This document provides instructions for AI coding agents operating within the ApocalypseRV repository. It outlines how to run, test, and style code for this cooperative first-person survival game built with **Godot 4.6**, **Jolt Physics**, and **GL Compatibility renderer**.

---

## 1. Build, Lint, and Test Commands

ApocalypseRV does not have a traditional compilation step for the game itself, as it relies on the Godot engine. However, there are Python-based offline tools managed by `uv`.

### Running the Game
To run the game (the main scene is `test_world.tscn`):
```bash
godot --path . res://world/test_world.tscn
```
*Note: If testing within the Godot 4.6 Editor, simply press **F5**.*

### Python Offline Tools & Tests
The repository uses Python (managed via `uv`) for offline tooling like generation helpers and migration scripts.

- **Run main tooling script:**
  ```bash
  uv run main.py
  ```
- **Run a single test (e.g., building generation test):**
  ```bash
  uv run test_building_gen.py
  ```
*(Agent Note: Always use `uv run <script_name>.py` to execute Python scripts in this repository to ensure the correct environment and dependencies are used.)*

---

## 2. Code Style & Conventions

The codebase primarily consists of **GDScript** for the game engine and **Python** for offline tooling. Ensure all code adheres to these guidelines.

### GDScript Guidelines

#### Naming Conventions
- **Variables & Functions:** Use `snake_case` (e.g., `health_points`, `calculate_damage()`).
- **Internal/Private Members:** Prefix with an underscore `_` (e.g., `_process_chase()`, `_build_terrain_mesh()`, `_current_state`).
- **Class Names (and Node types):** Use `PascalCase` (e.g., `CharacterBody3D`, `InventoryManager`).
- **Constants:** Use `ALL_CAPS` (e.g., `MAX_INVENTORY_SIZE`).

#### Formatting & Syntax
- **Node References:** Always use `@onready var foo = $NodePath` for node references. Use `get_node_or_null()` when dealing with dynamic or uncertain node structures to program defensively.
- **Inspector Properties:** Use `@export_group("Name")` to organize exported variables in the Godot inspector.
- **UI Construction:** Player HUDs (inventory, health bar) are built entirely programmatically in `_ready()`—do not rely on `.tscn` files for them.
- **Signals:** Connect signals programmatically using `.connect(callable)` or lambdas. Always disconnect before reconnecting when re-using nodes.

#### Typing & Imports
- **Duck-Typing:** Avoid circular imports or hard dependencies by utilizing duck-typing. Use `has_method("method_name")` and `"property" in obj` before interacting with external nodes (e.g., `if target.has_method("take_damage"): target.take_damage(amount)`).
- **Node Lookups:** There are **no autoloads (singletons)**. For cross-tree lookups, rely on the SceneTree's group system: `get_tree().get_nodes_in_group("group_name")`. (Valid groups: `"player"`, `"monsters"`, `"rv"`, `"crafting_stations"`).

#### Error Handling
- Fail gracefully. Since GDScript does not use traditional try-catch blocks for game logic, always check if a node exists (`is_instance_valid()`, `!= null`) before accessing its properties.

### Python Guidelines (Offline Tools)
- Follow standard **PEP 8** formatting.
- Use explicit type hinting for function arguments and return types.
- Ensure any file operations use context managers (`with open(...) as f:`).

---

## 3. Architecture & Cross-System Communication

### Scene Hierarchy (`test_world.tscn`)
```
TestWorld (Node3D)
├── RV (VehicleBody3D)          <- WorldGenerator tracks this, NOT the player
├── Player (CharacterBody3D)
│   ├── Camera3D
│   │   ├── PlayerInteract (RayCast3D)
│   │   └── HandMarker (Marker3D - created at runtime)
│   ├── InventoryUI (CanvasLayer - built programmatically)
│   └── HealthBarUI (CanvasLayer - built programmatically)
└── WorldGenerator (Node3D)    <- spawns/despawns ChunkGenerator nodes
```

### Communication Patterns
- **Player -> Equipment/Props:** The `player_interact.gd` RayCast3D calls `interact()` or `start_placement()` directly on the target object.
- **Equipment -> RV:** Equipment scripts search up the tree structure to find a connected RV using duck-typing and group checks (`"rv"`).
- **RV -> UI:** The RV communicates inventory changes via signals like `inventory_changed(item_name, amount)`.
- **Physics -> Logic:** Monster HitBoxes (`Area3D`) use `body_entered` to detect the `VehicleBody3D` (RV).

---

## 4. Critical Pitfalls & Important Context (Copilot Rules)

When modifying code, you MUST keep these constraints in mind:

- **Jolt Physics:** The game uses Jolt Physics, not Godot's default engine. Non-uniform scaling on collision shapes will cause Jolt errors. **Always** use uniform scale (e.g., `Vector3(x, x, x)`) for tweens or scaling on nodes with `CollisionShape3D`.
- **Equipment Placement Collision:** After placing equipment on the RV, you must call `add_collision_exception_with()` on the entire parent chain to prevent physics glitches that rocket the RV into the air. If placement is cancelled, `remove_collision_exception_with()` must be called to clean up.
- **Scrapper Dependency:** The Scrapper equipment is non-functional off the RV by design. Its `get_connected_rv()` method requires it to be a descendant of a node in the `"rv"` group.
- **World Tracking:** The `WorldGenerator` tracks the RV (`NodePath("../RV")`), **not** the player. Chunk streaming centers on the vehicle.
- **Prop Instantiation:** `interactable_item.gd` relies on `self.scene_file_path` to store paths for drops/spawns. Props instantiated programmatically (not from a `.tscn`) will have an empty path. Ensure fallback logic exists (currently only implemented for `oil_barrel` and `scrap`).
- **Generation Seed:** The noise seed in `chunk_generator.gd` is currently hardcoded (`noise.seed = 1337`).
- **Building Doors:** The procedural `BuildingGenerator` door/seal logic is currently known to be buggy (some doors are sealed when they shouldn't be, etc.). Proceed with caution when editing BSP room graph logic.
- **Renderer Limits:** The project uses the **GL Compatibility** renderer. Do not write shaders or use features that require Vulkan/Forward+.
