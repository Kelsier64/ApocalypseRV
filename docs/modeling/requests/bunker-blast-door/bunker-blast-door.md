# Bunker Blast Door - modeling prompt

- **Build:** A heavy blast door visual at the bunker exit checkpoint.
- **Replace:** `world/poi_kit/rooms/bunker/v2/entry.tscn:Visuals/ExitLeaf37, instancing world/poi_kit/furniture/bunker/blast_door_graybox.tscn:Visuals/Model`. **Design dimensions:** 2.15 W x 2.70 H x 0.12 D m. The graybox dimensions are design targets, not measurements of a finished model.
- **Appearance:** Single thick military blast leaf with wheel, warning stripe, inset armored plates, impacts and rust tracks. The EXIT sign must remain readable. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** Origin bottom center of leaf; front faces local +Z. In v2 entry the instance is at (0, 0, 2.73) m. This is a visual only: do not add collision or alter Walkway/Exit or the exit interaction.
- **Delivery:** `assets/models/bunker_blast_door/` for GLB and textures; `art_source/bunker_blast_door/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

完成情況：2026-10-04 已透過本機 Pixal3D API 生成候選（[bunker_blast_door](../../../../assets/models/bunker_blast_door/bunker_blast_door_candidate.glb)），並通過 Godot 4.7.2 匯入與尺寸／原點檢查；[來源、預覽與待整理事項](../../../../art_source/bunker_blast_door/README.md)。只完成 API 試作，正式場景仍沿用既有外觀，接口與遊戲行為尚未驗收。
