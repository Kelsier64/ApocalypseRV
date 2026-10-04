# Bunker Locker - modeling prompt

- **Build:** A dented military personnel locker for guard rooms, barracks and checkpoints.
- **Replace:** `world/poi_kit/furniture/bunker/locker_graybox.tscn:Visuals/Model`. **Design dimensions:** 0.62 W x 1.90 H x 0.58 D m. The graybox dimensions are design targets, not measurements of a finished model.
- **Appearance:** Olive paint worn through to bare steel, bent door edges, a number stencil and a readable handle. Keep the silhouette slim and vertical; one locker, no loose parts. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** The existing StaticBody3D and CollisionShape3D remain in the wrapper. The model origin is the bottom center; its front and handle face local +Z.
- **Delivery:** `assets/models/bunker_locker/` for GLB and textures; `art_source/bunker_locker/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

完成情況：2026-10-04 已透過本機 Pixal3D API 生成候選（[bunker_locker](../../../../assets/models/bunker_locker/bunker_locker_candidate.glb)），並通過 Godot 4.7.2 匯入與尺寸／原點檢查；[來源、預覽與待整理事項](../../../../art_source/bunker_locker/README.md)。只完成 API 試作，正式場景仍沿用既有外觀，接口與遊戲行為尚未驗收。
