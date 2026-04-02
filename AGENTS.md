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

## Development Rules

- **Python**: Always use `uv` (`uv run <path>`)
- **Simple scenes**: Edit `.tscn` directly only for simple tasks
- **Complex scenes**: Write `SceneTree` generation scripts and run with `godot --headless -s`; always create fresh scripts (never reuse) to avoid overwriting manual edits
- **Editor tasks**: Provide `.gd` files + step-by-step Editor UI instructions instead of editing `.tscn` directly
