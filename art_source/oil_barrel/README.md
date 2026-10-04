# oil-barrel — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/oil-barrel/oil-barrel.md)。原始輸出傾斜，已整理為 Y 向上的中心原點候選；桶箍、封閉蓋及鏽蝕可讀。未驗收拾取與回收。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## oil_barrel

- [參考圖](../../docs/modeling/requests/oil-barrel/oil-barrel-image-to-3d-reference.png) · [原始 GLB](oil_barrel_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/oil_barrel/oil_barrel_candidate.glb) · [整理轉換](oil_barrel_preparation.json) · [六方向預覽](review_oil_barrel/views.png) · [Godot 渲染數據](review_oil_barrel/godot_review.json)。
- X×Y×Z = 0.65917969 × 1 × 0.65917969 m；原點為 包圍盒中心；9,934 個三角形。
- job `1ef3e623-82a7-4627-8228-5b059972a498`；原始 SHA256 `ce765c0823406e99c2a27dbfe3a6cbc4489305adcb78ee0459e1b671bfaee958`。

```powershell
python scripts/prepare_request_model.py oil_barrel --size 0.65917969 1 0.65917969 --origin center
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 使用 Python 標準函式庫；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py oil-barrel --image oil-barrel-image-to-3d-reference.png --idempotency-key apocalypse-rv-oil-barrel-standard1024-seed42-20261004-v1
python scripts/generate_request_model.py oil-barrel --collect
```
