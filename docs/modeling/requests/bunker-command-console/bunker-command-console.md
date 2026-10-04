# Bunker Command Console - modeling prompt

- **Build:** A military command terminal bank for the signal room.
- **Replace:** `world/poi_kit/furniture/bunker/command_console_graybox.tscn:Visuals/Model`. **Design dimensions:** 1.80 W x 1.20 H x 0.72 D m. The graybox dimensions are design targets, not measurements of a finished model.
- **Appearance:** Angular old military console, dark inactive CRT screens, scratched olive panel, recessed switches and a few intermittent amber indicators. Dense detail belongs in the model and textures, not extra wrapper meshes. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** Keep wrapper collision. Origin bottom center; operator stands at local +Z.
- **Delivery:** `assets/models/bunker_command_console/` for GLB and textures; `art_source/bunker_command_console/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

完成情況：2026-10-04 已透過本機 Pixal3D API 生成候選（[bunker_command_console](../../../../assets/models/bunker_command_console/bunker_command_console_candidate.glb)），並通過 Godot 4.7.2 匯入與尺寸／原點檢查；[來源、預覽與待整理事項](../../../../art_source/bunker_command_console/README.md)。只完成 API 試作，正式場景仍沿用既有外觀，接口與遊戲行為尚未驗收。
