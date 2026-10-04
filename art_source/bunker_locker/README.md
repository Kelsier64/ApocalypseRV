# bunker-locker — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/bunker-locker/bunker-locker.md)。已根據正反面渲染手動調整偏航 90°，使門把與百葉面朝 +Z；編號字樣需由 wrapper 保留。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## bunker_locker

- [參考圖](../../docs/modeling/requests/bunker-locker/bunker-locker-image-to-3d-reference.png) · [原始 GLB](bunker_locker_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/bunker_locker/bunker_locker_candidate.glb) · [整理轉換](bunker_locker_preparation.json) · [六方向預覽](review_bunker_locker/views.png) · [Godot 渲染數據](review_bunker_locker/godot_review.json)。
- X×Y×Z = 0.62 × 1.9 × 0.57999998 m；原點為 底面中心；9,980 個三角形。
- job `c383cb36-d78f-4494-a112-cbcb57e2dcab`；原始 SHA256 `ccfd43b8424a0b477b8b7d3dd2ff1b8e195bcc3e958e2c30836eb42dff5dc248`。

```powershell
python scripts/prepare_request_model.py bunker_locker --size 0.62 1.9 0.57999998 --origin bottom --yaw 90 --alignment estimated --fit stretch
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 的單視圖流程使用 Python 標準函式庫，三視圖輸入檢查另需 Pillow；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py bunker-locker --image bunker-locker-image-to-3d-reference.png --idempotency-key apocalypse-rv-bunker_locker-standard1024-seed42-5d89d001646f1766
python scripts/generate_request_model.py bunker-locker --collect
```
