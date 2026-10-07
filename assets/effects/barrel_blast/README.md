# Barrel explosion resources

Original deterministic procedural assets, authored in [bake_resources.gd](../../../art_source/barrel_vfx/bake_resources.gd). No third-party recordings or textures. Distributable under the project's source terms.

- `turbulence.png`: 128 × 128 seamless grayscale cloud turbulence, lossless with mipmaps; sampled as data, not sRGB.
- `blast.wav`: 1.65-second mono explosion, 22,050 Hz, 16-bit source; sharp onset, descending bass, rumble and metallic tail. Playback uses the existing spatial audio attenuation.

See [source instructions](../../../art_source/barrel_vfx/README.md) for rebuilding. Runtime effects are independent of the BarrelMan model, AI, damage and saves.
