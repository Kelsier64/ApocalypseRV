# bunker-bunk-bed — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/bunker-bunk-bed/bunker-bunk-bed.md)。雙層床、梯架與床墊可讀；細支架、床腳支撐及走道間隙尚待裝入 wrapper 後檢查。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## bunker_bunk_bed

- [參考圖](../../docs/modeling/requests/bunker-bunk-bed/bunker-bunk-bed-image-to-3d-reference.png) · [原始 GLB](bunker_bunk_bed_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/bunker_bunk_bed/bunker_bunk_bed_candidate.glb) · [整理轉換](bunker_bunk_bed_preparation.json) · [六方向預覽](review_bunker_bunk_bed/views.png) · [Godot 渲染數據](review_bunker_bunk_bed/godot_review.json)。
- X×Y×Z = 2 × 1.85 × 0.89999998 m；原點為 底面中心；9,900 個三角形。
- job `caf7f356-6147-427c-84c6-1c8fc21e669c`；原始 SHA256 `71b974646695ea6c2ffe4cf9ed3d7cbf2b79d7b8a74e264eee13c03866aa4e1f`。

```powershell
python scripts/prepare_request_model.py bunker_bunk_bed --size 2 1.85 0.89999998 --origin bottom
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 使用 Python 標準函式庫；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py bunker-bunk-bed --image bunker-bunk-bed-image-to-3d-reference.png --idempotency-key apocalypse-rv-bunker_bunk_bed-standard1024-seed42-f9b2a8a584b4b5d3
python scripts/generate_request_model.py bunker-bunk-bed --collect
```
