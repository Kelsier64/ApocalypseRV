# Bunker Bunk Bed - modeling prompt

- **Build:** A two tier barracks bunk with abandoned bedding.
- **Replace:** `world/poi_kit/furniture/bunker/bunk_bed_graybox.tscn:Visuals/Model`. **Design dimensions:** 2.00 W x 1.85 H x 0.90 D m. The graybox dimensions are design targets, not measurements of a finished model.
- **Appearance:** Steel frame, thin stained mattresses, one crumpled blanket, paint chips and subtle rust. The ladder and two tiers must read from a distance; avoid debris protruding into aisles. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** Keep the wrapper collision volume unchanged. Origin is bottom center, long axis local X, access/front at local +Z.
- **Delivery:** `assets/models/bunker_bunk_bed/` for GLB and textures; `art_source/bunker_bunk_bed/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

完成情況：2026-10-04 已透過本機 Pixal3D API 生成候選（[bunker_bunk_bed](../../../../assets/models/bunker_bunk_bed/bunker_bunk_bed_candidate.glb)），並通過 Godot 4.7.2 匯入與尺寸／原點檢查；[來源、預覽與待整理事項](../../../../art_source/bunker_bunk_bed/README.md)。只完成 API 試作，正式場景仍沿用既有外觀，接口與遊戲行為尚未驗收。
