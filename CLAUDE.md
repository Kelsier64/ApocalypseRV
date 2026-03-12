# Python Development Rules

1. Always use `uv` to run/manage the environment:
   ```bash
   uv init
   uv run <path>
   ```

# Godot Development Rules

When assisting with Godot 4.x development:

1. **Simple Scenes**: Only generate or edit `.tscn` files directly if the task is simple.

2. **Scene Generation Automation**: For complex scene setups, heavily favor writing with `SceneTree` (e.g., `generate_scenes.gd`) to programmatically build and save `.tscn` files. Execute via Godot CLI in headless mode:
   ```bash
   godot --headless -s generate_scenes.gd
   ```

3. **Editor Assistance**: When handling complex tasks, instead of modifying `.tscn` files directly, provide the required GDScript (`.gd`) files and give explicit, step-by-step instructions on what needs to be done via the Godot Editor UI.

4. **Fresh Generation Scripts**: **Never re-use EditorScript.** When using an `EditorScript` to generate a `.tscn` file, always create new script content instead of reusing previous versions to avoid accidentally overwriting the user's manual modifications.

5. **GDScript Generation**: Ensure GDScript is compatible with Godot 4.x. Use static typing where applicable and follow standard Godot naming conventions.

6. **CLI Usage**: Feel free to use the Godot CLI tool (`godot --headless`) to run tests, validate scripts, or execute command-line tasks if helpful.
