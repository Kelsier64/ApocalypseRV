# shelter-roof-filter-bank — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/shelter-roof-filter-bank/shelter-roof-filter-bank.md)。三個過濾箱與連續後風道可讀；保持靜態裝飾用途，屋頂碰撞與導航尚待接入檢查。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## shelter_roof_filter_bank

- [參考圖](../../docs/modeling/requests/shelter-roof-filter-bank/shelter-roof-filter-bank-image-to-3d-reference.png) · [原始 GLB](shelter_roof_filter_bank_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/shelter_roof_filter_bank/shelter_roof_filter_bank_candidate.glb) · [整理轉換](shelter_roof_filter_bank_preparation.json) · [六方向預覽](review_shelter_roof_filter_bank/views.png) · [Godot 渲染數據](review_shelter_roof_filter_bank/godot_review.json)。
- X×Y×Z = 9 × 1.5 × 5 m；原點為 包圍盒中心；9,980 個三角形。
- job `1056d9e6-a18c-4d18-91c3-e1382ee5665a`；原始 SHA256 `2b4cb0c387263600cc11b83cf471777fb547e6f6453ca2972f511ad5f8fa39da`。

```powershell
python scripts/prepare_request_model.py shelter_roof_filter_bank --size 9 1.5 5 --origin center --alignment estimated --fit stretch
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 的單視圖流程使用 Python 標準函式庫，三視圖輸入檢查另需 Pillow；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py shelter-roof-filter-bank --image shelter-roof-filter-bank-image-to-3d-reference.png --idempotency-key apocalypse-rv-shelter_roof_filter_bank-standard1024-seed42-289eb414f538524c
python scripts/generate_request_model.py shelter-roof-filter-bank --collect
```
