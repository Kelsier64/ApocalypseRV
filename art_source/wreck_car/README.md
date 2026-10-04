# wreck-car — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/wreck-car/wreck-car.md)。車頭與底盤可讀，但側面多出參考圖沒有的懸垂幾何，需要清理；只有單一 mesh／材質，尚未分離烤漆、玻璃、金屬及輪胎，不符合 RoadsidePaint 接口，未接入道路或封路。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## wreck_car

- [參考圖](../../docs/modeling/requests/wreck-car/wreck-car-image-to-3d-reference.png) · [原始 GLB](wreck_car_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/wreck_car/wreck_car_candidate.glb) · [整理轉換](wreck_car_preparation.json) · [六方向預覽](review_wreck_car/views.png) · [Godot 渲染數據](review_wreck_car/godot_review.json)。
- X×Y×Z = 2.4400001 × 2 × 4.73 m；原點為 底面中心；9,940 個三角形。
- job `a9bf2de4-3d7d-4f0a-9862-8831f83d9002`；原始 SHA256 `7dbc9659128d923a7fd1524a08588cdddd723bf2f4c23a13ca30adbfbd763020`。

```powershell
python scripts/prepare_request_model.py wreck_car --size 2.4400001 2 4.73 --origin bottom --offset 0.0 0.0 0.025 --alignment estimated --fit stretch
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 的單視圖流程使用 Python 標準函式庫，三視圖輸入檢查另需 Pillow；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py wreck-car --image wreck-car-image-to-3d-reference.png --idempotency-key apocalypse-rv-wreck_car-standard1024-seed42-ef7d03429d74dd55
python scripts/generate_request_model.py wreck-car --collect
```

## 三視圖重測（5 件試作範圍）

[新候選、來源、等比縮放及預覽](threeview/README.md)。舊單視圖模型是歷史比較結果；包圍盒符合不等於幾何筆直。
