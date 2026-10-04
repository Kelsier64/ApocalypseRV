# Bunker Diesel Generator - modeling prompt

- **Build:** A fixed diesel generator for the bunker power hall.
- **Replace:** `world/poi_kit/furniture/bunker/diesel_generator_graybox.tscn:Visuals/Model`. **Design dimensions:** 3.20 W x 1.70 H x 1.20 D m. The graybox dimensions are design targets, not measurements of a finished model.
- **Appearance:** Aged military diesel set on a skid, vented metal hood, exhaust outlet, belt cage, fuel stains and corrosion. The fixed generator must have a readable long low silhouette. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** Keep wrapper collision. Origin bottom center, crankshaft length along local X; service face local +Z. The asset is static.
- **Delivery:** `assets/models/bunker_diesel_generator/` for GLB and textures; `art_source/bunker_diesel_generator/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

完成情況：2026-10-04 已透過本機 Pixal3D API 生成候選（[bunker_diesel_generator](../../../../assets/models/bunker_diesel_generator/bunker_diesel_generator_candidate.glb)），並通過 Godot 4.7.2 匯入與尺寸／原點檢查；[來源、預覽與待整理事項](../../../../art_source/bunker_diesel_generator/README.md)。只完成 API 試作，正式場景仍沿用既有外觀，接口與遊戲行為尚未驗收。
