# bunker-blast-door — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/bunker-blast-door/bunker-blast-door.md)。門板、手輪與鏽蝕可讀；厚度被壓縮至 request 的 0.12 m。EXIT 字樣仍需保留既有 Label3D，不能依賴生成貼圖。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## bunker_blast_door

- [參考圖](../../docs/modeling/requests/bunker-blast-door/bunker-blast-door-image-to-3d-reference.png) · [原始 GLB](bunker_blast_door_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/bunker_blast_door/bunker_blast_door_candidate.glb) · [整理轉換](bunker_blast_door_preparation.json) · [六方向預覽](review_bunker_blast_door/views.png) · [Godot 渲染數據](review_bunker_blast_door/godot_review.json)。
- X×Y×Z = 2.1500001 × 2.7 × 0.12 m；原點為 底面中心；9,998 個三角形。
- job `d11a8ac6-1600-4c59-b36a-1dab5708180e`；原始 SHA256 `d6f8f21424e37147bd02edc9fdd2c4f6e7494592ad56ce43702eabbb0ba4716f`。

```powershell
python scripts/prepare_request_model.py bunker_blast_door --size 2.1500001 2.7 0.12 --origin bottom --alignment estimated --fit stretch
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 的單視圖流程使用 Python 標準函式庫，三視圖輸入檢查另需 Pillow；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py bunker-blast-door --image bunker-blast-door-image-to-3d-reference.png --idempotency-key apocalypse-rv-bunker_blast_door-standard1024-seed42-0ffe31f1313cfe31
python scripts/generate_request_model.py bunker-blast-door --collect
```
