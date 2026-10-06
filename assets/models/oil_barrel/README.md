# 油桶遊戲模型試作

[oil_barrel.glb](oil_barrel.glb) 是 2026-10-06 從使用者原 GLB 修整、減面及重新烘焙的候選版本。**尚未接入 `props/oil_barrel.tscn`**，正式道具仍為灰盒。

- 3,000 三角形；1,502 個唯一幾何位置，GLB 因 UV／法線切縫匯出 2,558 個頂點。
- 一個 mesh、一個 opaque PBR 材質；顏色、法線、金屬／粗糙度三張 1024×1024 內嵌 PNG，無必要的 glTF 擴充或外部貼圖依賴。
- GLB 原點置中、Y-up；外觀完整收在原道具半徑 0.32958984 m、高 1 m 的圓柱碰撞範圍內。
- 根／mesh 名為 `oil_barrel`。模型不含碰撞、剛體或物品程式；整合時保留 [原道具包裝](../../../props/oil_barrel.tscn) 的碰撞、質量、握持標記與保存路徑。
- Godot 預設將內嵌貼圖抽出為同目錄的三張 PNG；將 GLB、PNG 及各自的 `.import` 一起保留。

[可編輯來源與製作參數](../../../art_source/oil_barrel/README.md) · [本輪驗證](../../../docs/validation/2026-10-06-oil-barrel-optimization.md)

來源作者與授權尚未核實；沒有因減面而變更來源紀錄。
