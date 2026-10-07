# meshoptimizer 油桶比較試作

2026-10-07 使用官方 **gltfpack 1.3** 原生 Windows 工具，直接讀取 [收存原 GLB](../../retired_props/2026-09-29/oil_barrel.glb)。沒有修改原件、既有 Blender 3,000 面候選或正式道具場景。

[比較紀錄與 Godot 畫面](../../../docs/validation/2026-10-07-oil-barrel-meshoptimizer.md) · [重現腳本](run.ps1) · [單次處理時間](timings.json)

注意：以下是比較產物，**不是全部合格的遊戲資產**。所有模式都以 `-si 0.006001848` 嘗試約 3,000 三角形，保留原兩張 WebP，沒有重新烘焙。停用量化與 mesh compression，保留命名節點／材質：`-noq -kn -km`。

| 檔案 | 額外選項 | 實際三角形 | 狀態 |
|---|---|---:|---|
| strict.glb | `-se 0.01` | 22,114 | 標準減面，未達 3,000 目標 |
| permissive.glb | `-se 0.01 -sp` | 22,120 | 跨屬性切縫，未達目標 |
| permissive-update.glb | `-se 0.01 -sp -sv` | 22,154 | 畫面接近原件的比較候選；仍有非流形邊 |
| permissive-5pct.glb | `-se 0.05 -sp -sv` | 18,884 | 可見局部貼圖／輪廓變化 |
| aggressive.glb | `-se 0.05 -sa` | 2,763 | 貼圖嚴重錯亂，拒用 |
| permissive-maxerror.glb | `-se 1 -sp -sv` | 0 | 幾何全被移除，拒用；工具仍回傳退出碼 0 |

每個檔案旁有官方 JSON report 與本輪 tool log。`permissive-update.glb` 保留原 UV 與貼圖，沒有烘焙，也没有法線貼圖；GLB 1,219,660 bytes。現有 Blender 候選 3,000 三角形、2,948,012 bytes；貼圖编码／張數不同，不能以檔案大小推論 GPU 成本。

## 重現

從 [官方 release](https://github.com/zeux/meshoptimizer/releases/tag/v1.3) 下載 Windows zip，解壓後從專案根目錄執行：

```powershell
& './art_source/oil_barrel/meshoptimizer-v1.3/run.ps1' -Gltfpack '完整路徑/gltfpack.exe'
```

腳本只重寫本目錄試作與報告，先核對原件 SHA-256。原生工具只放 `.godot/oil-barrel-meshopt-tools/`，不加入專案依賴或正式資產。

工具 ZIP SHA-256：`f6e9c09d66af23da3da71b86f0652d2413e81c734e0aecd1cd3d0e6e6e8645c0`。
解壓後 EXE SHA-256：`a082a0db2332908133100332caeeddaa304afcf5e8094adc755ebdea8c720984`。

來源作者／授權狀態沿用原收存紀錄的未知狀態。
