# Bunker Filtration Pump - modeling prompt

- **Build:** The bunker water and air filtration pump.
- **Replace:** `world/poi_kit/furniture/bunker/filtration_pump_graybox.tscn:Visuals/Model`. **Design dimensions:** 1.40 W x 1.40 H x 0.80 D m. The graybox dimensions are design targets, not measurements of a finished model.
- **Appearance:** One coherent heavy pump unit with motor housing, broad filter cylinder, corroded pipes terminating at the model bounds, and water staining. Make it legible without an assembly of tiny primitives. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** Keep wrapper collision. Origin bottom center; inspection panel faces local +Z. No gameplay pipe sockets exist yet.
- **Delivery:** `assets/models/bunker_filtration_pump/` for GLB and textures; `art_source/bunker_filtration_pump/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

完成情況：2026-10-04 已透過本機 Pixal3D API 生成候選（[bunker_filtration_pump](../../../../assets/models/bunker_filtration_pump/bunker_filtration_pump_candidate.glb)），並通過 Godot 4.7.2 匯入與尺寸／原點檢查；[來源、預覽與待整理事項](../../../../art_source/bunker_filtration_pump/README.md)。只完成 API 試作，正式場景仍沿用既有外觀，接口與遊戲行為尚未驗收。
