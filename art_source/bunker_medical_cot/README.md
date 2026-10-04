# bunker-medical-cot — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/bunker-medical-cot/bunker-medical-cot.md)。床墊、頭尾架與床腳可讀；長軸 X，碰撞與床腳支撐尚待整合檢查。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## bunker_medical_cot

- [參考圖](../../docs/modeling/requests/bunker-medical-cot/bunker-medical-cot-image-to-3d-reference.png) · [原始 GLB](bunker_medical_cot_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/bunker_medical_cot/bunker_medical_cot_candidate.glb) · [整理轉換](bunker_medical_cot_preparation.json) · [六方向預覽](review_bunker_medical_cot/views.png) · [Godot 渲染數據](review_bunker_medical_cot/godot_review.json)。
- X×Y×Z = 2.0999999 × 0.85000002 × 0.94999999 m；原點為 底面中心；9,852 個三角形。
- job `308b31bf-34ed-4044-b016-91f6dfb2f87b`；原始 SHA256 `afd7b91e54ff3c8d3702bc6a754ca72b9d5c9c44e36fb2ad22828696dcf00378`。

```powershell
python scripts/prepare_request_model.py bunker_medical_cot --size 2.0999999 0.85000002 0.94999999 --origin bottom
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 使用 Python 標準函式庫；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py bunker-medical-cot --image bunker-medical-cot-image-to-3d-reference.png --idempotency-key apocalypse-rv-bunker_medical_cot-standard1024-seed42-73e4f3a070f9ecb7
python scripts/generate_request_model.py bunker-medical-cot --collect
```
