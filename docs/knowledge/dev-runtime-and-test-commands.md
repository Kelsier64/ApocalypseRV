# Knowledge: Dev Runtime and Test Commands

## 1. Why This Matters
A reliable command baseline reduces ambiguity and makes docs-backed verification repeatable for everyone touching the project.

## 2. Trigger Conditions
Use this guide when:
- Running the game locally.
- Executing headless Godot scripts.
- Running offline Python helper scripts.
- Verifying energy-system regression behavior.

## 3. Canonical Workflow
1. Open workspace root.
2. Ensure Godot executable is available in shell path.
3. Run target command from repository root.
4. Observe output and confirm expected scene/test behavior.

## 4. Commands/APIs/Procedures
Run game main scene:
- `godot --path . res://world/test_world.tscn`

Run headless generation/debug script:
- `godot --headless -s <script.gd>`

Run Python offline tools (project rule: use `uv`):
- `uv run main.py`
- `uv run test_building_gen.py`

Run energy system test script:
- `godot --headless -s tests/test_energy_system.gd`

Expected success indicator for energy tests:
- Output includes `PASS: energy system tests`.

## 5. Source Types
- User-provided project instructions in repository.
- Godot project configuration and test scripts.
- Existing test output artifact.

## 6. Edge Cases and Failure Patterns
- Running commands outside repo root can break relative resource paths (for example, `res://world/test_world.tscn`).
- Missing Godot executable in PATH causes command failure.
- Running Python tools without `uv` violates project conventions.

## 7. Validation Checklist
- [ ] Command run from repository root.
- [ ] Main scene launches without immediate script errors.
- [ ] Headless test prints pass/fail summary.
- [ ] Python scripts run via `uv`.

## 8. Related Modules
- `docs/modules/world-generation.md`
- `docs/modules/rv-energy-and-equipment.md`

## 9. Source Materials Used
- `AGENTS.md`
- `project.godot`
- `tests/test_energy_system.gd`
- `tests/test_energy_system.out.txt`

## 10. Completeness Notes
This knowledge doc covers local dev/run/test command conventions visible in the repository. CI and packaging commands are not documented because no pipeline config is present.