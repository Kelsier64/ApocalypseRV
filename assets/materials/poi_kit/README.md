# Concrete wall albedo

- Asset: [concrete_albedo.png](concrete_albedo.png)
- Generated on 2026-09-15 using the built-in image generation tool; no CLI/API fallback.
- Used by [concrete.tres](../../../world/poi_kit/materials/concrete.tres), with local triplanar projection. This is a base-color map only. Seamlessness was requested; the tiled result still needs inspection on each final model and at its intended scale.
- The image is copied into the project; runtime does not depend on the Codex image output directory.

Generation prompt:

> Use case: stylized-concept. Asset type: seamless tileable albedo texture for a low-poly first-person post-apocalyptic industrial building in Godot. Create one square, edge-to-edge material swatch of aged pale gray concrete plaster with subtle chipped paint, fine pores, small hairline cracks and sparse desaturated grime. Orthographic straight-on surface scan, uniform flat diffuse illumination, no directional shadows, no ambient occlusion, no vignette, no perspective, no objects, no wall edges, no seams or panels, no lettering, no border, no watermark. Medium-low contrast, readable at game scale, restrained realistic surface detail. All four edges must tile seamlessly. This is only a base-color map, not a rendered room or PBR contact sheet.
