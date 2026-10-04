# bunker-filtration-pump — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/bunker-filtration-pump/bunker-filtration-pump.md)。濾筒、馬達與連接管形狀可讀；沒有新增管線 socket。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## bunker_filtration_pump

- [參考圖](../../docs/modeling/requests/bunker-filtration-pump/bunker-filtration-pump-image-to-3d-reference.png) · [原始 GLB](bunker_filtration_pump_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/bunker_filtration_pump/bunker_filtration_pump_candidate.glb) · [整理轉換](bunker_filtration_pump_preparation.json) · [六方向預覽](review_bunker_filtration_pump/views.png) · [Godot 渲染數據](review_bunker_filtration_pump/godot_review.json)。
- X×Y×Z = 1.4 × 1.4 × 0.80000001 m；原點為 底面中心；9,869 個三角形。
- job `ea795332-e08d-4951-b8cc-0583d21e032f`；原始 SHA256 `6c82844c0f8b71821aaa46d623df60957df5ddf083b41efa7f74f22e7ad8fbce`。

```powershell
python scripts/prepare_request_model.py bunker_filtration_pump --size 1.4 1.4 0.80000001 --origin bottom
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 使用 Python 標準函式庫；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py bunker-filtration-pump --image bunker-filtration-pump-image-to-3d-reference.png --idempotency-key apocalypse-rv-bunker_filtration_pump-standard1024-seed42-a4b8f79f35f2a560
python scripts/generate_request_model.py bunker-filtration-pump --collect
```
