# scrapper — 生成候選

2026-10-04 本機 Pixal3D API 試作；這些 GLB 已通過 Godot 匯入與包圍盒／原點檢查，尚未接入正式遊戲。每個 GLB 是單一靜態 mesh、單一材質、三張內嵌貼圖。Godot 匯入時另存的 PNG 與 `.import` 一併保留。

[需求](../../../docs/modeling/requests/scrapper/scrapper.md) · [原始來源與重現](../../../art_source/scrapper/README.md)

靜態盆體和一支可重複使用的滾輪分別生成；盆體上方有凹腔。外框尺寸已整理，0.91 m 開口、0.63 m 內高、兩滾輪配合與 CSG 旋轉接口尚未驗收。

- [scrapper_basin_candidate.glb](scrapper_basin_candidate.glb)：1.05 × 0.69999999 × 1.05 m，9,992 三角形；[六方向預覽](../../../art_source/scrapper/review_scrapper_basin/views.png)。
- [scrapper_roller_candidate.glb](scrapper_roller_candidate.glb)：0.40000001 × 1 × 0.40000001 m，9,996 三角形；[六方向預覽](../../../art_source/scrapper/review_scrapper_roller/views.png)。
