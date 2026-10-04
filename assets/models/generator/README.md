# generator — 生成候選

2026-10-04 本機 Pixal3D API 試作；這些 GLB 已通過 Godot 匯入與包圍盒／原點檢查，尚未接入正式遊戲。每個 GLB 是單一靜態 mesh、單一材質、三張內嵌貼圖。Godot 匯入時另存的 PNG 與 `.import` 一併保留。

[需求](../../../docs/modeling/requests/generator/generator.md) · [原始來源與重現](../../../art_source/generator/README.md)

已手動調整偏航 -90°，使通風面朝 +Z、風扇朝 -X；固定包圍盒配合造成非等比縮放，機架形狀仍需美術確認。

- [generator_candidate.glb](generator_candidate.glb)：0.80000001 × 0.60000002 × 1.2 m，9,910 三角形；[六方向預覽](../../../art_source/generator/review_generator/views.png)。
