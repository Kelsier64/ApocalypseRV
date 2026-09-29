# Bunker Blast Door - modeling prompt

- **Build:** A heavy blast door visual at the bunker exit checkpoint.
- **Replace:** `world/poi_kit/rooms/bunker/v2/entry.tscn:Visuals/ExitLeaf37, instancing world/poi_kit/furniture/bunker/blast_door_graybox.tscn:Visuals/Model`. **Design dimensions:** 2.15 W x 2.70 H x 0.12 D m. The graybox dimensions are design targets, not measurements of a finished model.
- **Appearance:** Single thick military blast leaf with wheel, warning stripe, inset armored plates, impacts and rust tracks. The EXIT sign must remain readable. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** Origin bottom center of leaf; front faces local +Z. In v2 entry the instance is at (0, 0, 2.73) m. This is a visual only: do not add collision or alter Walkway/Exit or the exit interaction.
- **Delivery:** `assets/models/bunker_blast_door/` for GLB and textures; `art_source/bunker_blast_door/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

Status: Graybox is in the bunker v2 kit; finished model has not been delivered.
