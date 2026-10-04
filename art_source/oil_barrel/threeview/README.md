# oil-barrel 三視圖試作

桶身整體直立，但桶箍／桶蓋有波浪、頂部塞口與比例仍待整理；未達正式交付要求。

2026-10-04 使用本機 API `threeview1024`、seed 42；單張等寬三格 PNG，順序 front / left / back。只測這五件資產之一，原單視圖結果另保留比較。

[需求](../../../docs/modeling/requests/oil-barrel/oil-barrel.md) · [三視圖輸入](../../../docs/modeling/requests/oil-barrel/oil-barrel-threeview-reference.png) · [原始 GLB](oil_barrel_raw.glb) · [候選 GLB](../../../assets/models/oil_barrel/oil_barrel_threeview_candidate.glb) · [六方向預覽](../review_oil_barrel_threeview/views.png) · [渲染數據](../review_oil_barrel_threeview/godot_review.json) · [本輪檢查與限制](../../../docs/validation/2026-10-04-pixal3d-threeview.md)。

輸出保留 API +Y 向上、+Z 正面，以一個縮放值等比包含於設計包圍盒，不估計最小包圍盒軸向、不逐軸拉伸。實際 X×Y×Z=0.6592 × 0.9022 × 0.6565 m，9,966 triangles；原點方式 `center`。實際尺寸與 design target 不一定完全相同。匯入及相似變換驗證通過不代表空腔、材質分區或遊戲接口已完成。

來源：[API metadata](generation.json)、[轉換紀錄](oil_barrel_preparation.json)、[參考圖生成紀錄](reference-generation.json)。原始 SHA256 `b8f8c2dd6275ccf987032eaaa2d15233b2feaae235f4a6dfe933ecfd41f67cf8`；job `f57b5d4c-4f8b-47e3-955a-d42249e0f726`。後端 Pixal3D INT8 / ComfyUI；來源／授權沿用 [上層紀錄](../README.md)。沒有 Blender 編輯、拓撲修補或正式場景接入。

```powershell
python scripts/generate_request_model.py oil-barrel --image oil-barrel-threeview-reference.png --preset threeview1024 --variant threeview
python scripts/generate_request_model.py oil-barrel --variant threeview --collect
python scripts/prepare_request_model.py oil_barrel --variant threeview --alignment source --fit uniform --size 0.65917968 1.0 0.65917968 --origin center
```

Python 需要 NumPy 和 Pillow。`--variant` 是保存路徑；完全相同的 asset/input/preset/seed 會以同一 idempotency key 復用 API job。
