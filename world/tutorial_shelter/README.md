# Tutorial shelter assets

Stage-one v11 layout: nine bays, 40 × 236 m interior. The old v7–v10 shelter is unchanged.

- `bay_gate.tscn` reuses the original shelter's leaf geometry, handles, warning strips and materials. Leaf collision remains 3.5 × 5 × 0.3 m. Its track is 0.55 m in front of the partition so opened leaves do not disappear inside the wall.
- `gate_button_model.tscn` reuses the original physical case, warning plate, button and lamp. `bay_gate_button.gd` inherits the original press/color animation; each instance owns its animated materials. Outside controls rotate the complete model toward the approaching player.
- `wall_surface.tscn` reuses a clipped 8 m section of the old `starting_shelter/facade.tscn` interior cast-wall skin, runoff, fracture and repair surfaces. Vertex wear colors and existing shader/texture references are preserved. Height adapts from 6.8 to 8.8 m; world-space texture mapping keeps texel density. `.res` meshes and `.tres` materials are the delivered reusable modules, without runtime mesh generation. Each module is 630 triangles.
- Large structural BoxMeshes have edges subdivided to at most 8 m to prevent directional shadow pancaking from clipping the huge roof triangles. Physical collision shapes are unchanged. Indoor fixtures cast shadows so light cannot pass through partitions and closed gates.

Final static mesh instance budget after the 2026-10-12 repair: 157,878 triangles, below 200,000. Source/intermediate extraction tools and render evidence stay in ignored `.godot/`. Full decorative treatment and performance tuning remain stage six.
