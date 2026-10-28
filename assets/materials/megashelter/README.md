# Megashelter surface textures

Original albedo images generated with the built-in imagegen tool on 2026-10-28, copied unmodified into the repository. These are authored game textures, not calibrated material scans. The originals remain in the local generated-images library.

- `cast_concrete_albedo.png`: pale cast concrete with fine pores and sand grains. Source `exec-6ad09d0f-8e65-4faa-aad5-ab0210d299fe.png`.
- `aged_coating_albedo.png`: neutral matte enamel, sparse chipped paint and oxide, suitable for tinting. Source `exec-bcd16eae-49bf-4d85-9449-62084a540a19.png`.

Both source images are 1254 × 1254. Godot imports at up to 1024 pixels, with high-quality VRAM compression and mipmaps. The shader uses linear anisotropic sampling. Each tile covers 2 × 2 object-space metres; module dimensions do not stretch the texture.

Consumer: [megashelter surface shader](../../../world/megashelter/megashelter_surface.gdshader). Concrete, sealed cassettes and steel have separate roughness/specular/metallic responses. Shallow bump comes from image intensity and is artistic relief, not a measured normal map. Exposed spalls reuse the existing [aggregate texture](../ruined_wall/README.md), selected by vertex alpha; alpha does not control transparency. Runoff and dampness are shader-authored, concentrated below ledges and near ground level.

Generation specifications: seamless square base-color tiles, flat orthographic material coverage, uniform diffuse illumination, no baked directional light, borders, panel grids, fasteners, lettering, objects or preview spheres. Concrete: neutral warm light gray, dense cement, extremely fine pores, restrained mineral mottling, no coarse pebble aggregate, large fractures or camouflage patches. Coating: neutral gray baked enamel on steel, 90% intact paint, sparse narrow chips exposing graphite steel and dark umber oxide, no large black/orange islands. Both requested approximately 2 m physical coverage and seamless edges; repetition is softened in the shader by low-contrast object-space mineral and runoff variation.
