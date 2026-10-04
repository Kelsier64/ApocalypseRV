# shelter-roof-air-handler 三視圖試作

主箱體整體水平，但百葉局部變形、寬深比例與設計不符，尚未達正式交付要求。

2026-10-04 使用本機 API `threeview1024`、seed 42；單張等寬三格 PNG，順序 front / left / back。只測這五件資產之一，原單視圖結果另保留比較。

[需求](../../../docs/modeling/requests/shelter-roof-air-handler/shelter-roof-air-handler.md) · [三視圖輸入](../../../docs/modeling/requests/shelter-roof-air-handler/shelter-roof-air-handler-threeview-reference.png) · [原始 GLB](shelter_roof_air_handler_raw.glb) · [候選 GLB](../../../assets/models/shelter_roof_air_handler/shelter_roof_air_handler_threeview_candidate.glb) · [六方向預覽](../review_shelter_roof_air_handler_threeview/views.png) · [渲染數據](../review_shelter_roof_air_handler_threeview/godot_review.json) · [本輪檢查與限制](../../../docs/validation/2026-10-04-pixal3d-threeview.md)。

輸出保留 API +Y 向上、+Z 正面，以一個縮放值等比包含於設計包圍盒，不估計最小包圍盒軸向、不逐軸拉伸。實際 X×Y×Z=3.9452 × 2.0000 × 2.6398 m，9,996 triangles；原點方式 `center`。實際尺寸與 design target 不一定完全相同。匯入及相似變換驗證通過不代表空腔、材質分區或遊戲接口已完成。

來源：[API metadata](generation.json)、[轉換紀錄](shelter_roof_air_handler_preparation.json)、[參考圖生成紀錄](reference-generation.json)。原始 SHA256 `36394ebc85be71d569d41f86a96ee6753a09e41f2e05563b3dea046bc78b2d5b`；job `ed2b3fc7-9a2c-4d36-9993-3408f862c8ca`。後端 Pixal3D INT8 / ComfyUI；來源／授權沿用 [上層紀錄](../README.md)。沒有 Blender 編輯、拓撲修補或正式場景接入。

```powershell
python scripts/generate_request_model.py shelter-roof-air-handler --image shelter-roof-air-handler-threeview-reference.png --preset threeview1024 --variant threeview
python scripts/generate_request_model.py shelter-roof-air-handler --variant threeview --collect
python scripts/prepare_request_model.py shelter_roof_air_handler --variant threeview --alignment source --fit uniform --size 6.0 2.0 4.0 --origin center
```

Python 需要 NumPy 和 Pillow。`--variant` 是保存路徑；完全相同的 asset/input/preset/seed 會以同一 idempotency key 復用 API job。
