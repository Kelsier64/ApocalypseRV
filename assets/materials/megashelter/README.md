# Megashelter procedural surfaces

The current [surface shader](../../../world/megashelter/megashelter_surface.gdshader) generates concrete, peeling mineral paint and corroded steel directly from seeded 3D noise. It does not sample albedo images or combine bitmap tiles. [ModularMegashelter](../../../world/megashelter/modular_megashelter.gd) supplies the palette, stable building seed and real drainage geometry.

All material fields use continuous building-local metres, including corners, adjacent modules and the forecourt. There are no per-module coordinate resets, mirrored images or floor-row sampling changes. Coarse mineral variation and weathering distort a finer peeling field; fine noise roughens its edges and exposed cement. Steel uses a separate corrosion field and dark oxide/rust colours. These are artistic procedural materials, not calibrated scans.

Rain noise is stretched vertically and keeps the same phase across modules. UV2 retains module metadata and actual ledge height; only the height influences runoff strength below wall tops or beam/lintel undersides. Rust-water trails follow up to four real drain lines, prioritising the entrance pair. Damp accumulates at the base; exposed horizontal slabs collect broad irregular dirt. Authored spalls use vertex alpha to expose procedural granular cement, without transparency.

Features at decimetre/metre scales supply the visible wear. Subpixel noise converges to its mean and small relief fades with pixel footprint to reduce shimmer in the retro filter and reduced render scales. Noise is computed per fragment, trading image sampling for arithmetic; this is not a guarantee of lower cost on every GPU. The original three merged material batches, sealed backing, collision, exposed rebar and damaged vents remain.

## Previous bitmap sources

The following earlier assets are retained for reference and are no longer loaded by the megashelter. Original 1254 × 1254 albedo images were generated with the built-in imagegen tool on 2026-10-28 and copied unmodified; the originals also remain in the local generated-images library.

- `cast_concrete_albedo.png`: fine cast concrete. Source `exec-6ad09d0f-8e65-4faa-aad5-ab0210d299fe.png`.
- `aged_coating_albedo.png`: enamel with sparse chipped paint. Source `exec-bcd16eae-49bf-4d85-9449-62084a540a19.png`.
- `decayed_facade_albedo.png`: flaking paint, exposed cement and mildew. Source `exec-6f505a0a-59e8-4c0d-9d04-ad1af8f35246.png`.
- `corroded_steel_albedo.png`: dark oxide and charcoal paint. Source `exec-87571762-bfc8-4b65-ab43-7575c442047d.png`.

Their import configurations remain unchanged (1024 px limit for base maps, 512 px for decay maps, high-quality VRAM compression and mipmaps). They were authored base colours with diffuse illumination, not measured PBR scans. Their earlier sampling and collage-based variation are superseded by the procedural material.
