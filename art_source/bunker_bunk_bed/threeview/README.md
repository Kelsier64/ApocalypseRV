# bunker-bunk-bed 三視圖試作

主柱大致直立，局部接點軟化；實際高度 1.2682 m 低於設計 1.85 m，比例尚不合格。

2026-10-04 使用本機 API `threeview1024`、seed 42；單張等寬三格 PNG，順序 front / left / back。只測這五件資產之一，原單視圖結果另保留比較。

[需求](../../../docs/modeling/requests/bunker-bunk-bed/bunker-bunk-bed.md) · [三視圖輸入](../../../docs/modeling/requests/bunker-bunk-bed/bunker-bunk-bed-threeview-reference.png) · [原始 GLB](bunker_bunk_bed_raw.glb) · [候選 GLB](../../../assets/models/bunker_bunk_bed/bunker_bunk_bed_threeview_candidate.glb) · [六方向預覽](../review_bunker_bunk_bed_threeview/views.png) · [渲染數據](../review_bunker_bunk_bed_threeview/godot_review.json) · [本輪檢查與限制](../../../docs/validation/2026-10-04-pixal3d-threeview.md)。

輸出保留 API +Y 向上、+Z 正面，以一個縮放值等比包含於設計包圍盒，不估計最小包圍盒軸向、不逐軸拉伸。實際 X×Y×Z=1.5924 × 1.2682 × 0.9000 m，9,994 triangles；原點方式 `bottom`。實際尺寸與 design target 不一定完全相同。匯入及相似變換驗證通過不代表空腔、材質分區或遊戲接口已完成。

來源：[API metadata](generation.json)、[轉換紀錄](bunker_bunk_bed_preparation.json)、[參考圖生成紀錄](reference-generation.json)。原始 SHA256 `1cc115479d0254729d07496534c0a4000ffe38e602ac1d5cbbaae05cde626d53`；job `56651a5d-b8c6-44ce-8eec-6e4c0848fdb7`。後端 Pixal3D INT8 / ComfyUI；來源／授權沿用 [上層紀錄](../README.md)。沒有 Blender 編輯、拓撲修補或正式場景接入。

```powershell
python scripts/generate_request_model.py bunker-bunk-bed --image bunker-bunk-bed-threeview-reference.png --preset threeview1024 --variant threeview
python scripts/generate_request_model.py bunker-bunk-bed --variant threeview --collect
python scripts/prepare_request_model.py bunker_bunk_bed --variant threeview --alignment source --fit uniform --size 2.0 1.85 0.9 --origin bottom
```

Python 需要 NumPy 和 Pillow。`--variant` 是保存路徑；完全相同的 asset/input/preset/seed 會以同一 idempotency key 復用 API job。
