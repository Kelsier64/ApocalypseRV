# bunker-diesel-generator — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/bunker-diesel-generator/bunker-diesel-generator.md)。長形機殼、底座、通風與機械面可讀；服務面朝向及房間擺放尚待整合檢查。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## bunker_diesel_generator

- [參考圖](../../docs/modeling/requests/bunker-diesel-generator/bunker-diesel-generator-image-to-3d-reference.png) · [原始 GLB](bunker_diesel_generator_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/bunker_diesel_generator/bunker_diesel_generator_candidate.glb) · [整理轉換](bunker_diesel_generator_preparation.json) · [六方向預覽](review_bunker_diesel_generator/views.png) · [Godot 渲染數據](review_bunker_diesel_generator/godot_review.json)。
- X×Y×Z = 3.2 × 1.7 × 1.2 m；原點為 底面中心；9,680 個三角形。
- job `eb5d606e-421c-481e-b81e-283ee3cc7a9c`；原始 SHA256 `ee62fa36446d8504ed21f8f7edb3b128514dbd79b4024867f6c5e334a719f6f4`。

```powershell
python scripts/prepare_request_model.py bunker_diesel_generator --size 3.2 1.7 1.2 --origin bottom --alignment estimated --fit stretch
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 的單視圖流程使用 Python 標準函式庫，三視圖輸入檢查另需 Pillow；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py bunker-diesel-generator --image bunker-diesel-generator-image-to-3d-reference.png --idempotency-key apocalypse-rv-bunker_diesel_generator-standard1024-seed42-2dd23d34a285ca2d
python scripts/generate_request_model.py bunker-diesel-generator --collect
```
