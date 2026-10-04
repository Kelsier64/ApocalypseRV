# wreck-car — 生成候選

2026-10-04 本機 Pixal3D API 試作；這些 GLB 已通過 Godot 匯入與包圍盒／原點檢查，尚未接入正式遊戲。每個 GLB 是單一靜態 mesh、單一材質、三張內嵌貼圖。Godot 匯入時另存的 PNG 與 `.import` 一併保留。

[需求](../../../docs/modeling/requests/wreck-car/wreck-car.md) · [原始來源與重現](../../../art_source/wreck_car/README.md)

車頭與底盤可讀，但側面多出參考圖沒有的懸垂幾何，需要清理；只有單一 mesh／材質，尚未分離烤漆、玻璃、金屬及輪胎，不符合 RoadsidePaint 接口，未接入道路或封路。

- [wreck_car_candidate.glb](wreck_car_candidate.glb)：2.4400001 × 2 × 4.73 m，9,940 三角形；[六方向預覽](../../../art_source/wreck_car/review_wreck_car/views.png)。
