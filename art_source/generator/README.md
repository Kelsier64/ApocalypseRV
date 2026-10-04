# generator — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/generator/generator.md)。已手動調整偏航 -90°，使通風面朝 +Z、風扇朝 -X；固定包圍盒配合造成非等比縮放，機架形狀仍需美術確認。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## generator

- [參考圖](../../docs/modeling/requests/generator/generator-front-left-reference.png) · [原始 GLB](generator_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/generator/generator_candidate.glb) · [整理轉換](generator_preparation.json) · [六方向預覽](review_generator/views.png) · [Godot 渲染數據](review_generator/godot_review.json)。
- X×Y×Z = 0.80000001 × 0.60000002 × 1.2 m；原點為 包圍盒中心；9,910 個三角形。
- job `0aed0040-f18d-49d5-ab8d-b8eab2615463`；原始 SHA256 `3d87a71648d6be474a6c0ccae23b33e5e6923a1f52255cb3d51a1259d33b6a85`。

```powershell
python scripts/prepare_request_model.py generator --size 0.80000001 0.60000002 1.2 --origin center --yaw -90 --alignment estimated --fit stretch
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 的單視圖流程使用 Python 標準函式庫，三視圖輸入檢查另需 Pillow；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py generator --image generator-front-left-reference.png --idempotency-key apocalypse-rv-generator-standard1024-seed42-f8ce486884182cc7
python scripts/generate_request_model.py generator --collect
```
