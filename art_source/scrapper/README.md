# Precision scrapper visual

Authoring source: `build_scrapper.py` (Python, NumPy and Pillow). Regenerate from the repository root:

```powershell
python art_source/scrapper/build_scrapper.py --output assets/models/scrapper
```

The body is a hollow 1.05 m housing with a 0.91 m feed opening, dark teal paint, orange guard lips, steel liners, bearing cartridges and bolted service panels. Its origin and dimensions match the production equipment scene.

Each roller has ten seven-hook cutting discs, a machined shaft, spacer drums and end collars. Roller length follows local Y; `equipment/scrapper.tscn` retains the original typed CSG pivots and hides their primitive surfaces. The second cutting stack is mirrored and phased; axial offsets of ±0.02 m interleave the 0.034 m discs on a 0.080 m pitch, leaving 0.006 m between opposing disc faces. Teeth clear the opposing spacers and hopper walls throughout rotation.

Both GLBs contain deterministic 512 px albedo, metallic/roughness and subtle machining normal textures. Godot import embeds textures; there are no external atlas dependencies. Housing: 6,260 triangles / 5 surfaces. Roller: 9,568 triangles / 3 surfaces, shared by both instances. Total near-view budget: 25,396 triangles / 11 surfaces, before Godot LOD. Fine shape detail is concentrated in the cutter stacks.

2026-10-10 validation: Godot 4.7.2 Forward+ renders of the production equipment, cutter close-up, another rotation phase and actual RV installation; geometry normal/tangent checks; unchanged root physics, five collision shapes, hopper and original roller dimensions/pivots. `test_item_services`, `test_item_persistence`, `test_rv_physics_regression` and `test_rv_resource_cycle` passed. The resource cycle also checks that an unpowered recycler retains cutter pose and input progress and that both powered upper surfaces feed inward/down. Interactive gameplay was not tested in this change.
