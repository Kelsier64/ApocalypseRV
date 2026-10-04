# Bunker Supply Chest - modeling prompt

- **Build:** A searchable military supply chest with a moving lid.
- **Replace:** `world/instances/bunker_cache.tscn:Visuals/Body and Visuals/LidPivot/Lid`. **Measured existing cache dimensions:** collision 0.90 W x 0.75 H x 0.70 D m; visible body 0.88 W x 0.62 H x 0.68 D m; visible lid 0.92 W x 0.11 H x 0.72 D m.
- **Appearance:** Small olive steel chest, clasp, worn stencil, handle, scratched corners and supply markings. Body and lid must be separate meshes so the existing search animation still opens the lid. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** Measured from the current cache scene. Keep root StaticBody3D, Collision, Status and script untouched. Origin bottom center; front is local +Z. Preserve the measured Visuals/LidPivot position (0, 0.68, -0.30) m and its rear hinge along local X; the measured Lid mesh offset from the pivot is (0, 0, 0.30) m. A standalone supply_chest_graybox.tscn is a dimensional reference, but the runtime cache scene is the replacement target.
- **Delivery:** `assets/models/bunker_supply_chest/` for GLB and textures; `art_source/bunker_supply_chest/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

完成情況：2026-10-04 已透過本機 Pixal3D API 生成候選（[bunker_supply_chest_body](../../../../assets/models/bunker_supply_chest/bunker_supply_chest_body_candidate.glb)、[bunker_supply_chest_lid](../../../../assets/models/bunker_supply_chest/bunker_supply_chest_lid_candidate.glb)），並通過 Godot 4.7.2 匯入與尺寸／原點檢查；[來源、預覽與待整理事項](../../../../art_source/bunker_supply_chest/README.md)。只完成 API 試作，正式場景仍沿用既有外觀，接口與遊戲行為尚未驗收。
