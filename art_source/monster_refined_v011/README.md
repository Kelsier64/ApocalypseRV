# 怪物 v011：污垢、深眼窩與嘴部

2026-09-22，依使用者回饋「材質不夠髒 眼窩不夠深 少嘴巴」，在 Blender 5.2.2 LTS 修改 v010。

- [Blender 原檔](monster_refined_v011.blend)：場景 `MONSTER_REFINED_V011`，內含貼圖；保留先前場景與共享動畫。
- [GLB 模型](raker_refined_v011.glb)：22 段動畫、45 根變形骨，PNG 已內嵌。已依使用者後續要求接入[正式遊戲資產](../../assets/models/raker/raker.glb)。
- [2048 × 2048 膚色貼圖](raker_albedo_2k.png)：更深的土色污斑、眼周與眼下拖痕、頸部和腋下積垢、較髒的手腳。
- [頭部特寫](head.png)、[全身斜前方](threequarter.png)、[正面](front.png)、[側面](side.png)、[背面](back.png)、[低姿態](crouch.png)。圖片均為實際模型的 Blender 渲染。

眼窩擴大並向內加深，最大額外凹陷約 3.4 cm。新增具有幾何深度的狹長口腔、內凹暗面與不規則唇緣，最大雕刻位移約 3.1 cm。嘴部隨頭骨運動，尚無獨立下顎骨或張嘴動畫。

[驗證數據](validation.json)：2.180000067 m，2,966 頂點、5,928 三角面；0 非流形邊、0 零面積面、0 未綁定頂點。22 段動畫共 729 影格的非相鄰三角形穿插檢查全部通過，未窮舉跨動畫混合。

模型製作階段：Godot 4.7.2 直接載入此 GLB，檢查身高、45 根骨骼、22 段動畫、UV 與兩個材質的貼圖，結果 PASS；日誌 `.godot/refined-v011-import.log`。後續正式接入的驗證另見[接入紀錄](../../docs/validation/2026-09-22-raker-v011.md)。

重建順序：[refine.py](refine.py) → [audit.py](audit.py) → [finish.py](finish.py)。需要 v010 場景存在；腳本路徑在檔案頂端。refine 只重建自己產生的 v011 場景，手動編輯請先另存。finish 烘焙貼圖、匯出模型並渲染檢視。修改後重新產生 validation.json。
