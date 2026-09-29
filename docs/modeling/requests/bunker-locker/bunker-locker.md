# Bunker Locker - modeling prompt

- **Build:** A dented military personnel locker for guard rooms, barracks and checkpoints.
- **Replace:** `world/poi_kit/furniture/bunker/locker_graybox.tscn:Visuals/Model`. **Design dimensions:** 0.62 W x 1.90 H x 0.58 D m. The graybox dimensions are design targets, not measurements of a finished model.
- **Appearance:** Olive paint worn through to bare steel, bent door edges, a number stencil and a readable handle. Keep the silhouette slim and vertical; one locker, no loose parts. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** The existing StaticBody3D and CollisionShape3D remain in the wrapper. The model origin is the bottom center; its front and handle face local +Z.
- **Delivery:** `assets/models/bunker_locker/` for GLB and textures; `art_source/bunker_locker/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

Status: Graybox is in the bunker v2 kit; finished model has not been delivered.
