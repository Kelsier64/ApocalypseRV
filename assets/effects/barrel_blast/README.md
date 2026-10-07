# Barrel explosion resources

Original Blender MCP volume renders and metal meshes, plus deterministic procedural audio. No third-party recordings or textures. Distributable under the project's source terms.

- `turbulence.png`: 128 × 128 seamless grayscale cloud turbulence, lossless with mipmaps; sampled as data, not sRGB.
- `fire_atlas.png` / `smoke_atlas.png`: two 2048 × 2048 straight-alpha RGBA atlases, 64 tiles each; Blender gas/fire simulation rendered from the editable blend. Shader interpolates adjacent frames and integrates their density within bounded volume proxies, clipped by opaque scene depth. This also covers cameras inside the plume.
- `fragments.glb`: dented lid and seven thick, curved barrel-wall pieces. Visual meshes only.
- `blast.wav`: 3-second mono explosion, 22,050 Hz, 16-bit source; filtered pressure, combustion roar, fuel bursts and rumble.
- `metal_land_1.wav` through `metal_land_3.wav`: 0.42-second metal impacts. Runtime limits simultaneous voices and plays these at fragment landings.

See [source instructions](../../../art_source/barrel_vfx/README.md) for rebuilding. Runtime effects are independent of the BarrelMan model, AI, damage and saves.
