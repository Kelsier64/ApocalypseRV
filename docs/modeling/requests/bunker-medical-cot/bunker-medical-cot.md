# Bunker Medical Cot - modeling prompt

- **Build:** An abandoned field medical cot.
- **Replace:** `world/poi_kit/furniture/bunker/medical_cot_graybox.tscn:Visuals/Model`. **Design dimensions:** 2.10 W x 0.85 H x 0.95 D m. The graybox dimensions are design targets, not measurements of a finished model.
- **Appearance:** Enamel steel bed frame, dirty pale mattress and a restrained blood stain. Preserve the thin silhouette and avoid attached carts or clutter. Match the low saturation industrial horror bunker materials.
- **Origin, facing, interface:** Keep the wrapper collision unchanged. Origin bottom center, long axis local X, patient access at local +Z.
- **Delivery:** `assets/models/bunker_medical_cot/` for GLB and textures; `art_source/bunker_medical_cot/` for editable source. Replace only the stated visuals and preserve scene node names, collisions and interactions.

完成情況：2026-10-04 已透過本機 Pixal3D API 生成候選（[bunker_medical_cot](../../../../assets/models/bunker_medical_cot/bunker_medical_cot_candidate.glb)），並通過 Godot 4.7.2 匯入與尺寸／原點檢查；[來源、預覽與待整理事項](../../../../art_source/bunker_medical_cot/README.md)。只完成 API 試作，正式場景仍沿用既有外觀，接口與遊戲行為尚未驗收。
