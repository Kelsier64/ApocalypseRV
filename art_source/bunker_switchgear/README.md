# bunker-switchgear — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/bunker-switchgear/bunker-switchgear.md)。櫃體、開關與門板可讀；標示文字不作功能資訊使用。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## bunker_switchgear

- [參考圖](../../docs/modeling/requests/bunker-switchgear/bunker-switchgear-image-to-3d-reference.png) · [原始 GLB](bunker_switchgear_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/bunker_switchgear/bunker_switchgear_candidate.glb) · [整理轉換](bunker_switchgear_preparation.json) · [六方向預覽](review_bunker_switchgear/views.png) · [Godot 渲染數據](review_bunker_switchgear/godot_review.json)。
- X×Y×Z = 1.2 × 2.3499999 × 0.72000003 m；原點為 底面中心；9,980 個三角形。
- job `22a21e3c-dada-4747-bb32-4585febe7e7c`；原始 SHA256 `dccc3ec7d4b1d451664abf1fa46e327e2b685314edf91d8ef0d2db2e7e723491`。

```powershell
python scripts/prepare_request_model.py bunker_switchgear --size 1.2 2.3499999 0.72000003 --origin bottom
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 使用 Python 標準函式庫；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py bunker-switchgear --image bunker-switchgear-image-to-3d-reference.png --idempotency-key apocalypse-rv-bunker_switchgear-standard1024-seed42-0dbf3b0e96de5d98
python scripts/generate_request_model.py bunker-switchgear --collect
```
