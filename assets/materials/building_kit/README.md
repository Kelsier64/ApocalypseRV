# 建築 kit 材質來源

[BuildingKitMaterials](../../../world/building_kit/building_kit_materials.gd) 使用的照片貼圖，全部來自 [Poly Haven](https://polyhaven.com)，授權為 CC0。2026-11-22 透過 Poly Haven API 下載 1K JPG（albedo、OpenGL 法線、粗糙度），比對官方 MD5 後以 Pillow LANCZOS 縮成 512×512，品質 88。粗糙度存成灰階。

| 檔名前綴 | Poly Haven 資產 | 實際尺寸 | 作者 |
|---|---|---|---|
| `concrete_wall` | [painted_concrete](https://polyhaven.com/a/painted_concrete) | 2.0 m | Dario Barresi, Dimitrios Savva |
| `concrete_floor` | [concrete_floor](https://polyhaven.com/a/concrete_floor) | 2.08 m | eye-candy.xyz |
| `block_wall` | [concrete_block_wall](https://polyhaven.com/a/concrete_block_wall) | 2.0 m | Charlotte Baglioni |
| `plaster` | [peeling_painted_wall](https://polyhaven.com/a/peeling_painted_wall) | 1.8 m | Dimitrios Savva |
| `corrugated` | [rusty_corrugated_iron](https://polyhaven.com/a/rusty_corrugated_iron) | 2.0 m | Charlotte Baglioni |
| `steel` | [rusty_metal_02](https://polyhaven.com/a/rusty_metal_02) | 1.0 m | Rob Tuytel |
| `tiles` | [dirty_tiles](https://polyhaven.com/a/dirty_tiles) | 2.26 m | Matterfield, Jenelle van Heerden |
| `planks` | [distressed_painted_planks](https://polyhaven.com/a/distressed_painted_planks) | 1.6 m | Rob Tuytel |

實際尺寸是一張貼圖在世界中覆蓋的邊長，對應材質表的 `meters`；材質表的 `mean` 是 albedo 的平均色，用來把照片轉成明暗細節。換貼圖時兩者都要重算。

匯入設定：VRAM 壓縮、產生 mipmap，`*_normal.jpg` 標為法線貼圖。新增貼圖後先 `godot --headless --path . --import`，再把對應 `.import` 改成相同設定並重新匯入。
