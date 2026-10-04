# Bunker Switchgear - modeling prompt

- **Build:** Power distribution switchgear for workshop and generator rooms.
- **Replace:** `world/poi_kit/furniture/bunker/switchgear_graybox.tscn:Visuals/Model`. **Design dimensions:** 1.20 W x 2.35 H x 0.72 D m. The graybox dimensions are design targets, not measurements of a finished model.
- **Appearance:** Tall industrial cabinet with hazard markings, scorched access doors, breakers and a few loose wires contained inside its silhouette. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** Keep wrapper collision. Origin bottom center; operable panel faces local +Z.
- **Delivery:** `assets/models/bunker_switchgear/` for GLB and textures; `art_source/bunker_switchgear/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

完成情況：2026-10-04 已透過本機 Pixal3D API 生成候選（[bunker_switchgear](../../../../assets/models/bunker_switchgear/bunker_switchgear_candidate.glb)），並通過 Godot 4.7.2 匯入與尺寸／原點檢查；[來源、預覽與待整理事項](../../../../art_source/bunker_switchgear/README.md)。只完成 API 試作，正式場景仍沿用既有外觀，接口與遊戲行為尚未驗收。
