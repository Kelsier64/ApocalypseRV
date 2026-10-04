# gas-can — Pixal3D 試作來源

2026-10-04 使用現有 request 參考圖呼叫 `http://127.0.0.1:8000`；全部使用 `standard1024`、seed 42。原始 GLB 原樣保留，候選經軸向估計、尺寸／原點整理及 Godot 4.7.2 渲染。沒有 Blender 編輯或遊戲場景整合。

需求：[原 request](../../docs/modeling/requests/gas-can/gas-can.md)。提把孔、封閉罐蓋與壓紋可讀；厚度沿 X，原點在包圍盒中心。尚未替換滿空罐，未驗收拾取、加油與保存。

來源與授權：沿用本 repository 的參考圖，未下載其他模型。生成後端為本機 Pixal3D INT8／ComfyUI；模型權重及生成輸出的授權未在本輪另行審核。原始 GLB 保留完整 workflow metadata，generation JSON 保留 job、參考圖 SHA256 和 API 原始驗證。

## gas_can

- [參考圖](../../docs/modeling/requests/gas-can/gas-can-diffuser-reference.png) · [原始 GLB](gas_can_raw.glb) · [API metadata](generation.json)。
- [候選 GLB](../../assets/models/gas_can/gas_can_candidate.glb) · [整理轉換](gas_can_preparation.json) · [六方向預覽](review_gas_can/views.png) · [Godot 渲染數據](review_gas_can/godot_review.json)。
- X×Y×Z = 0.39759523 × 0.84584963 × 0.82353514 m；原點為 包圍盒中心；9,986 個三角形。
- job `9e1f78b7-481b-44d1-b0ba-66ca914469bc`；原始 SHA256 `545cf486ec7df934cb574fb745c2591355dc6c0e3778b534af52d3e25c6f5b0d`。

```powershell
python scripts/prepare_request_model.py gas_can --size 0.39759523 0.84584963 0.82353514 --origin center
```

## 重現 API 呼叫

[提交／收取腳本](../../scripts/generate_request_model.py) 使用 Python 標準函式庫；[候選整理腳本](../../scripts/prepare_request_model.py) 另需 NumPy。候選整理採包圍盒方向估計及非等比縮放，不能代替接口與美術驗收；變換矩陣、縮放與偏移均保存在各 preparation JSON。

```powershell
python scripts/generate_request_model.py gas-can --image gas-can-diffuser-reference.png --idempotency-key apocalypse-rv-gas_can-standard1024-seed42-b8fe9998060dd3df
python scripts/generate_request_model.py gas-can --collect
```
