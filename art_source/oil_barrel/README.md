# 油桶減面試作來源

2026-10-06 依使用者要求直接修改提供的 GLB。原始 Downloads 檔與 [收存原件](../retired_props/2026-09-29/oil_barrel.glb) 的 SHA-256 相同：`58326447acdfb7d8ba9fc90c8efc345fd9b8e365d93393f287aba8b192646694`。兩份原件均未改動；作者、授權狀態沿用收存紀錄的未知狀態。

- [可編輯 Blender 來源](oil_barrel_optimized.blend)：`OilBarrel_Optimization_20261006` 場景保留隱藏的高模 `OilBarrel_Source_High` 與低模 `oil_barrel`。原先開啟的 Blender Scene 保留；以 save-copy 儲存，沒有覆寫使用者原檔。
- [顏色](oil_barrel_basecolor.png)、[法線](oil_barrel_normal.png)、[金屬／粗糙度](oil_barrel_metalrough.png)：皆為 1024×1024，亦已 packed 到 Blend。金屬／粗糙度圖的 G 為粗糙度、B 為金屬度；R 沿用來源，不作 AO 使用。
- [遊戲用 GLB](../../assets/models/oil_barrel/oil_barrel.glb)：只含選取的低模、單一材質與三張內嵌 PNG。
- [當時檢查與比較](../../docs/validation/2026-10-06-oil-barrel-optimization.md)。2026-10-07 [油桶人實作](../../docs/validation/2026-10-07-barrel-man.md) 將此 GLB 接入普通道具、地堡裝飾桶與怪物骨架掛點；GLB 本身未修改。
- 2026-10-07 [meshoptimizer 直接減面比較](meshoptimizer-v1.3/README.md) 另存於子目錄；沒有替換這份 Blender 候選。

## 製作參數

Blender 5.2.2 LTS、Blender MCP。直接對原 UV 減面到約 12,000 三角形會留下碎裂；合併原 UV 頂點後減面到約 3,000，會出現桶身折疊。沒有將這兩種失敗試作交付為資產。

成功流程：從原 GLB 的副本以 **0.0035 m voxel remesh** 建立封閉網格，再用 collapse decimation 降到 **3,000 三角形**，開啟 triangulate 與 smooth shading。不是重新設計桶身造型；沿用原模型表面。

Smart UV Project 的 angle limit 為 66°、island margin 為 0.012。Cycles 1 sample、selected-to-active、cage extrusion 0.015 m、max ray distance 0.06 m、padding 12 px。顏色使用 DIFFUSE color-only；法線使用 tangent NORMAL；來源金屬／粗糙度圖以 emission 轉移到新 UV。沒有額外調整原本藍色彩度。

烘焙後尺寸對齊原道具，原點置中、匯出 Y-up。極少數超過圓柱邊界的頂點向內限制，使整個外觀落在半徑 0.32958984 m、高 1 m 的既有碰撞體積內。匯出限制為 active scene + selection，避免帶入原 Blender 場景的 Cube。

再次匯出時在工作場景選取 `oil_barrel`，使用 GLB、Y-up、active scene + selection，關閉 animation。保留原始高模與貼圖，勿覆寫收存原件。
