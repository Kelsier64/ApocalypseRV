# scrapper 三視圖試作

**幾何不合格：盆體頂部封閉，缺少開口與空腔；不可接入遊戲。** 本次沒有重做滾輪。

2026-10-04 使用本機 API `threeview1024`、seed 42；單張等寬三格 PNG，順序 front / left / back。只測這五件資產之一，原單視圖結果另保留比較。

[需求](../../../docs/modeling/requests/scrapper/scrapper.md) · [三視圖輸入](../../../docs/modeling/requests/scrapper/scrapper-basin-threeview-reference.png) · [原始 GLB](scrapper_basin_raw.glb) · [候選 GLB](../../../assets/models/scrapper/scrapper_basin_threeview_candidate.glb) · [六方向預覽](../review_scrapper_basin_threeview/views.png) · [渲染數據](../review_scrapper_basin_threeview/godot_review.json) · [本輪檢查與限制](../../../docs/validation/2026-10-04-pixal3d-threeview.md)。

輸出保留 API +Y 向上、+Z 正面，以一個縮放值等比包含於設計包圍盒，不估計最小包圍盒軸向、不逐軸拉伸。實際 X×Y×Z=1.0500 × 0.5242 × 1.0461 m，10,000 triangles；原點方式 `bottom`。實際尺寸與 design target 不一定完全相同。匯入及相似變換驗證通過不代表空腔、材質分區或遊戲接口已完成。

來源：[API metadata](generation_basin.json)、[轉換紀錄](scrapper_basin_preparation.json)、[參考圖生成紀錄](reference-generation.json)。原始 SHA256 `b7482fb6ab20616f49052d11b71ec14a15414856671c87429055d4f6ddd7392f`；job `f60b09af-876c-4375-a441-544d7eeaf548`。後端 Pixal3D INT8 / ComfyUI；來源／授權沿用 [上層紀錄](../README.md)。沒有 Blender 編輯、拓撲修補或正式場景接入。

```powershell
python scripts/generate_request_model.py scrapper --part basin --image scrapper-basin-threeview-reference.png --preset threeview1024 --variant threeview
python scripts/generate_request_model.py scrapper --part basin --variant threeview --collect
python scripts/prepare_request_model.py scrapper_basin --folder scrapper --variant threeview --alignment source --fit uniform --size 1.05 0.7 1.05 --origin bottom
```

Python 需要 NumPy 和 Pillow。`--variant` 是保存路徑；完全相同的 asset/input/preset/seed 會以同一 idempotency key 復用 API job。
