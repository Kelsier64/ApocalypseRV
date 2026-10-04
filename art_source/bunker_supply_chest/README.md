# bunker-supply-chest — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/bunker-supply-chest/bunker-supply-chest.md)。箱體與箱蓋由各自參考圖分別生成；箱體開口可見。候選尚未掛到 LidPivot，鉸鏈對齊、閉合間隙與搜尋動畫未驗收。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## bunker_supply_chest_body

- [參考圖](../../docs/modeling/requests/bunker-supply-chest/bunker-supply-chest-body-image-to-3d-reference.png) · [原始 GLB](bunker_supply_chest_body_raw.glb) · [API metadata](generation_body.json)。
- [候選 GLB](../../assets/models/bunker_supply_chest/bunker_supply_chest_body_candidate.glb) · [整理轉換](bunker_supply_chest_body_preparation.json) · [六方向預覽](review_bunker_supply_chest_body/views.png) · [Godot 渲染數據](review_bunker_supply_chest_body/godot_review.json)。
- X×Y×Z = 0.88 × 0.62 × 0.68000001 m；原點為 底面中心；9,914 個三角形。
- job `0a6a5149-ea17-4102-a634-e1366bd674cd`；原始 SHA256 `b9ea443d34d8274e5ef4aee490d43faa4650545e383f315861e364957f618bc3`。

```powershell
python scripts/prepare_request_model.py bunker_supply_chest_body --folder bunker_supply_chest --size 0.88 0.62 0.68000001 --origin bottom --alignment estimated --fit stretch
```

## bunker_supply_chest_lid

- [參考圖](../../docs/modeling/requests/bunker-supply-chest/bunker-supply-chest-lid-image-to-3d-reference.png) · [原始 GLB](bunker_supply_chest_lid_raw.glb) · [API metadata](generation_lid.json)。
- [候選 GLB](../../assets/models/bunker_supply_chest/bunker_supply_chest_lid_candidate.glb) · [整理轉換](bunker_supply_chest_lid_preparation.json) · [六方向預覽](review_bunker_supply_chest_lid/views.png) · [Godot 渲染數據](review_bunker_supply_chest_lid/godot_review.json)。
- X×Y×Z = 0.92000002 × 0.11 × 0.72000003 m；原點為 包圍盒中心；8,718 個三角形。
- job `15f1c946-80b1-411d-b83a-cb2dd47ad929`；原始 SHA256 `a8b3b639563a2f5b5a34e52cf619530508bb8e5d3014e7586b751f2667b94013`。

```powershell
python scripts/prepare_request_model.py bunker_supply_chest_lid --folder bunker_supply_chest --size 0.92000002 0.11 0.72000003 --origin center --alignment estimated --fit stretch
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 的單視圖流程使用 Python 標準函式庫，三視圖輸入檢查另需 Pillow；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py bunker-supply-chest --part body --image bunker-supply-chest-body-image-to-3d-reference.png --idempotency-key apocalypse-rv-bunker_supply_chest_body-standard1024-seed42-32da312ce7edf76f
python scripts/generate_request_model.py bunker-supply-chest --part body --collect
python scripts/generate_request_model.py bunker-supply-chest --part lid --image bunker-supply-chest-lid-image-to-3d-reference.png --idempotency-key apocalypse-rv-bunker_supply_chest_lid-standard1024-seed42-3fbe68fc5de0c54a
python scripts/generate_request_model.py bunker-supply-chest --part lid --collect
```
