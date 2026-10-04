# scrapper — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/scrapper/scrapper.md)。靜態盆體和一支可重複使用的滾輪分別生成；盆體上方有凹腔。外框尺寸已整理，0.91 m 開口、0.63 m 內高、兩滾輪配合與 CSG 旋轉接口尚未驗收。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## scrapper_basin

- [參考圖](../../docs/modeling/requests/scrapper/scrapper-static-basin-reference.png) · [原始 GLB](scrapper_basin_raw.glb) · [API metadata](generation_basin.json)。
- [候選 GLB](../../assets/models/scrapper/scrapper_basin_candidate.glb) · [整理轉換](scrapper_basin_preparation.json) · [六方向預覽](review_scrapper_basin/views.png) · [Godot 渲染數據](review_scrapper_basin/godot_review.json)。
- X×Y×Z = 1.05 × 0.69999999 × 1.05 m；原點為 底面中心；9,992 個三角形。
- job `d1120bdc-88fd-4daf-a54b-3f57dceb29ac`；原始 SHA256 `1d0fbe2ddf1fc1e1b0c86a491b8203eb016f130e701a8e23197fcf0ccd5025dc`。

```powershell
python scripts/prepare_request_model.py scrapper_basin --folder scrapper --size 1.05 0.69999999 1.05 --origin bottom --alignment estimated --fit stretch
```

## scrapper_roller

- [參考圖](../../docs/modeling/requests/scrapper/scrapper-isolated-roller-reference.png) · [原始 GLB](scrapper_roller_raw.glb) · [API metadata](generation_roller.json)。
- [候選 GLB](../../assets/models/scrapper/scrapper_roller_candidate.glb) · [整理轉換](scrapper_roller_preparation.json) · [六方向預覽](review_scrapper_roller/views.png) · [Godot 渲染數據](review_scrapper_roller/godot_review.json)。
- X×Y×Z = 0.40000001 × 1 × 0.40000001 m；原點為 包圍盒中心；9,996 個三角形。
- job `d21be558-d4b0-4413-a948-d86b98b6ebfe`；原始 SHA256 `944b859acb24a1095d2c5ec592bbc08f9c3938a0f1d082082de4f9f4e1ecab26`。

```powershell
python scripts/prepare_request_model.py scrapper_roller --folder scrapper --size 0.40000001 1 0.40000001 --origin center --alignment estimated --fit stretch
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 的單視圖流程使用 Python 標準函式庫，三視圖輸入檢查另需 Pillow；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py scrapper --part basin --image scrapper-static-basin-reference.png --idempotency-key apocalypse-rv-scrapper_basin-standard1024-seed42-7ba3f9885145085f
python scripts/generate_request_model.py scrapper --part basin --collect
python scripts/generate_request_model.py scrapper --part roller --image scrapper-isolated-roller-reference.png --idempotency-key apocalypse-rv-scrapper_roller-standard1024-seed42-ddff91e5e25fb726
python scripts/generate_request_model.py scrapper --part roller --collect
```

## 三視圖重測（5 件試作範圍）

[新候選、來源、等比縮放及預覽](threeview/README.md)。舊單視圖模型是歷史比較結果；包圍盒符合不等於幾何筆直。
