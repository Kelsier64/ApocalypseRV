# ApocalypseRV

Godot 4.6 first-person survival prototype: maintain an RV, travel through generated highway chunks, scavenge, and fight monsters.

## Develop

Install Godot 4.6.1 and put `godot` on PATH. From the repository root:

```powershell
godot --editor --path .
godot --path .
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

The test entry point imports assets, runs every `tests/test_*.gd` suite, and runs the main scene for 120 frames. It waits for the actual Godot process, checks exit codes and error logs, and fails on missing PASS markers. Logs are written to `.godot/test-logs/`. Pass `-Godot 'C:/path/to/godot.exe'` to use a specific executable. GitHub Actions uses the same entry point with Godot 4.6.1.

## Code map

- `player/player.gd`: movement, player modes, and scene coordination.
- `player/player_inventory.gd`: inventory capacity, selection, and consumption.
- `player/equipment_placement.gd`: equipment preview and placement input.
- `enemies/monster.gd`: AI/physics coordination; `combat_targeting.gd`: target selection policy.
- `rv/`, `equipment/`: vehicle and device behavior; `core/rv_connection.gd`: shared RV connection contract.
- `world/`: chunk streaming, POIs, and procedural buildings.

See [Repository Guidelines](AGENTS.md), [architecture](docs/architecture.md), and [design documents](docs/design/). Root `todo` and `todo_for_ai` are retained planning notes. Documents under `docs/superpowers/` are historical records, not current implementation instructions.

## Validation limits

Use `godot --path . res://tests/rv_climb_playground.tscn -- --replay` for a reproducible moving-RV climb demonstration. Blue is the player, red is the monster. F2 toggles motion, F3 starts auto-climb, F4 switches camera, F5 seats the player to test roof demolition, and R resets. Omit `-- --replay` for manual WASD/Space play. The playground drives the RV transform deterministically; the integration suite also exercises a physics-driven VehicleBody.

Headless checks cover moving-RV climbing, roof support, and demolition, but do not replace interactive checks of camera feel, wheel-driven handling, crowds, and placement alignment. Configured POI scenes, loot, and enemies must exist and load; the resource test rejects missing entries.
