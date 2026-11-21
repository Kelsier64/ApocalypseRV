---
name: apocalypse-rv-tests
description: Select, run, write, and debug ApocalypseRV Godot tests, runner logs, and CI failures.
---

# ApocalypseRV Tests

Use the [coverage table](../../../tests/README.md) and search tests for the affected classes. Run `./scripts/test.ps1 -TestFilter 'test_item_*.gd,test_rv_braking.gd'`. Add `-Smoke` for startup, main scene, HUD, player movement, or settings. Use `-List` to check selection without Godot and `-KeepGoing` when you need all results.

- Include `test_streaming_generation` for terrain, roads, weather, fog, streetlights, POI placement, or streaming. Allow several minutes for it.
- Inspect `.godot/test-logs/<run>/results.json` and the corresponding check logs. Report selected checks that never ran.
- Prefer extending relevant existing tests. Use fixtures and condition waits in `tests/support/`, fixed seeds, and scene or resource values for tuning baselines.
- Run `./scripts/test-runner.tests.ps1` after editing the runner. For CI, check the `godot-test-logs` artifact and [.github/workflows/tests.yml](../../../.github/workflows/tests.yml).
