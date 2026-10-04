# wreck-car 三視圖試作

**幾何不合格：車頂形成三角尖峰、車長明顯壓縮；不可接入遊戲。**

2026-10-04 使用本機 API `threeview1024`、seed 42；單張等寬三格 PNG，順序 front / left / back。只測這五件資產之一，原單視圖結果另保留比較。

[需求](../../../docs/modeling/requests/wreck-car/wreck-car.md) · [三視圖輸入](../../../docs/modeling/requests/wreck-car/wreck-car-threeview-reference.png) · [原始 GLB](wreck_car_raw.glb) · [候選 GLB](../../../assets/models/wreck_car/wreck_car_threeview_candidate.glb) · [六方向預覽](../review_wreck_car_threeview/views.png) · [渲染數據](../review_wreck_car_threeview/godot_review.json) · [本輪檢查與限制](../../../docs/validation/2026-10-04-pixal3d-threeview.md)。

輸出保留 API +Y 向上、+Z 正面，以一個縮放值等比包含於設計包圍盒，不估計最小包圍盒軸向、不逐軸拉伸。實際 X×Y×Z=2.4400 × 1.3583 × 2.2200 m，9,986 triangles；原點方式 `bottom`。實際尺寸與 design target 不一定完全相同。匯入及相似變換驗證通過不代表空腔、材質分區或遊戲接口已完成。

來源：[API metadata](generation.json)、[轉換紀錄](wreck_car_preparation.json)、[參考圖生成紀錄](reference-generation.json)。原始 SHA256 `979220312192ceb3f6d125333c0a2082dcae67c081e39554f2311f25fd8d0e29`；job `331960ec-ee2e-40ba-a8cc-43b5afe0bd67`。後端 Pixal3D INT8 / ComfyUI；來源／授權沿用 [上層紀錄](../README.md)。沒有 Blender 編輯、拓撲修補或正式場景接入。

```powershell
python scripts/generate_request_model.py wreck-car --image wreck-car-threeview-reference.png --preset threeview1024 --variant threeview
python scripts/generate_request_model.py wreck-car --variant threeview --collect
python scripts/prepare_request_model.py wreck_car --variant threeview --alignment source --fit uniform --size 2.44 2.0 4.73 --origin bottom --offset 0.0 0.0 0.025
```

Python 需要 NumPy 和 Pillow。`--variant` 是保存路徑；完全相同的 asset/input/preset/seed 會以同一 idempotency key 復用 API job。
