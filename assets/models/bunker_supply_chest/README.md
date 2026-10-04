# bunker-supply-chest — 生成候選

2026-10-04 本機 Pixal3D API 試作；這些 GLB 已通過 Godot 匯入與包圍盒／原點檢查，尚未接入正式遊戲。每個 GLB 是單一靜態 mesh、單一材質、三張內嵌貼圖。Godot 匯入時另存的 PNG 與 `.import` 一併保留。

[需求](../../../docs/modeling/requests/bunker-supply-chest/bunker-supply-chest.md) · [原始來源與重現](../../../art_source/bunker_supply_chest/README.md)

箱體與箱蓋由各自參考圖分別生成；箱體開口可見。候選尚未掛到 LidPivot，鉸鏈對齊、閉合間隙與搜尋動畫未驗收。

- [bunker_supply_chest_body_candidate.glb](bunker_supply_chest_body_candidate.glb)：0.88 × 0.62 × 0.68000001 m，9,914 三角形；[六方向預覽](../../../art_source/bunker_supply_chest/review_bunker_supply_chest_body/views.png)。
- [bunker_supply_chest_lid_candidate.glb](bunker_supply_chest_lid_candidate.glb)：0.92000002 × 0.11 × 0.72000003 m，8,718 三角形；[六方向預覽](../../../art_source/bunker_supply_chest/review_bunker_supply_chest_lid/views.png)。
