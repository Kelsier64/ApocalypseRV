# shelter-roof-air-handler — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/shelter-roof-air-handler/shelter-roof-air-handler.md)。正面百葉、兩個排風罩及側面蓋可讀；保持靜態裝飾用途，屋頂碰撞與導航尚待接入檢查。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## shelter_roof_air_handler

- [參考圖](../../docs/modeling/requests/shelter-roof-air-handler/shelter-roof-air-handler-image-to-3d-reference.png) · [原始 GLB](shelter_roof_air_handler_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/shelter_roof_air_handler/shelter_roof_air_handler_candidate.glb) · [整理轉換](shelter_roof_air_handler_preparation.json) · [六方向預覽](review_shelter_roof_air_handler/views.png) · [Godot 渲染數據](review_shelter_roof_air_handler/godot_review.json)。
- X×Y×Z = 6 × 2 × 4 m；原點為 包圍盒中心；9,978 個三角形。
- job `9c62100d-2f66-4361-ab19-733ba883f1d4`；原始 SHA256 `d47c1b59a1775654a1bbd807b75b02b9befb281c4bbeb3e0fac8f95f2e514ca7`。

```powershell
python scripts/prepare_request_model.py shelter_roof_air_handler --size 6 2 4 --origin center --alignment estimated --fit stretch
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 的單視圖流程使用 Python 標準函式庫，三視圖輸入檢查另需 Pillow；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py shelter-roof-air-handler --image shelter-roof-air-handler-image-to-3d-reference.png --idempotency-key apocalypse-rv-shelter_roof_air_handler-standard1024-seed42-b5b7c3c266efe929
python scripts/generate_request_model.py shelter-roof-air-handler --collect
```

## 三視圖重測（5 件試作範圍）

[新候選、來源、等比縮放及預覽](threeview/README.md)。舊單視圖模型是歷史比較結果；包圍盒符合不等於幾何筆直。
