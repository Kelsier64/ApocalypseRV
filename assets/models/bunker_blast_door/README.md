# bunker-blast-door — 生成候選

2026-10-04 本機 Pixal3D API 試作；這些 GLB 已通過 Godot 匯入與包圍盒／原點檢查，尚未接入正式遊戲。每個 GLB 是單一靜態 mesh、單一材質、三張內嵌貼圖。Godot 匯入時另存的 PNG 與 `.import` 一併保留。

[需求](../../../docs/modeling/requests/bunker-blast-door/bunker-blast-door.md) · [原始來源與重現](../../../art_source/bunker_blast_door/README.md)

門板、手輪與鏽蝕可讀；厚度被壓縮至 request 的 0.12 m。EXIT 字樣仍需保留既有 Label3D，不能依賴生成貼圖。

- [bunker_blast_door_candidate.glb](bunker_blast_door_candidate.glb)：2.1500001 × 2.7 × 0.12 m，9,998 三角形；[六方向預覽](../../../art_source/bunker_blast_door/review_bunker_blast_door/views.png)。
