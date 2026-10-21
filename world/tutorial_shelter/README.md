# Orientation support

This directory contains the current two-room orientation logic and shared building assets. The production building is [orientation_shelter.tscn](../orientation_shelter/orientation_shelter.tscn).

- `orientation_controller.gd` owns terminal identity, reception evidence, the automatic departure sensor and current course state (v4).
- `orientation_workshop.gd` records optional workshop transactions and applies the fresh-run vehicle faults once. Workshop state is v3 and requires the complete current target set.
- `orientation_recovery.gd` captures independent full-world retry boundaries and unlocks the same terminal's field manual on completion or skip.
- `bay_gate.tscn`, `industrial_light.tscn`, `wall_surface.tscn` and `posters/` remain shared art used by the production building.

Only the current course and workshop schemas load. Earlier orientation states, the former nine-bay course and their migration paths have been removed. The `legacy_*` mesh resources are authored surface assets, not save compatibility code.

Use [orientation_playground.tscn](../../tests/orientation_playground.tscn) for current scene inspection. [test_orientation_departure.gd](../../tests/test_orientation_departure.gd) exercises the native terminal, workshop, wheel-driven exit and checkpoint reload flow. Dated validation records under `docs/validation/` describe the versions tested at the time.
