# 加油機 GLB 匯入樣板

`fuel_pump.glb` 是本專案自製的低模外部模型，用於驗證「GLB → Godot 外觀 → 保留遊戲碰撞」流程。**不是下載或採購的第三方素材，也尚未驗證特定素材商店的檔案。** 無外部貼圖、字型或第三方模型依賴；使用六組內嵌 PBR 材質，1400 個三角形。

可重建來源為 [build_fuel_pump_glb.py](../../../scripts/build_fuel_pump_glb.py)，只使用 Python 標準函式庫。輸出 glTF 2.0 二進位模型，可匯入 Godot 或 Blender。本輪實際驗證 Godot 匯入，未在 Blender 中操作。

```powershell
python scripts/build_fuel_pump_glb.py
godot --headless --editor --path . --import --quit
```

## 模型規格

- 公尺、Y 向上、展示面朝 +Z，原點在底座中心地面。
- 高 2.255 m，底座 1.35 × 1.10 m，油管向 +X 側突出；整體 X 約 -0.675～0.842 m。
- 模型／Godot 外層根節點縮放都是 `(1,1,1)`，不需要匯入後旋轉或縮放修正。
- 所有 mesh 與材質在 GLB 中；不包含碰撞、腳本、物資或互動節點。
- GLB 不使用 Godot 的 `-col` 等自動碰撞命名。`.glb.import` 一併保存匯入設定。

## 遊戲外層與替換步驟

[fuel_pump.tscn](../../../world/poi_kit/furniture/fuel_pump.tscn) 為穩定的遊戲場景：

```text
FuelPump
├── Visuals
│   ├── Model      匯入 fuel_pump.glb
│   ├── Readout    Godot Label3D
│   └── Notice     Godot Label3D
└── Collision
    ├── Base
    ├── Pedestal
    └── Head
```

1. 把新 GLB 放在素材目錄，記錄來源、授權、作者與修改；原始素材另存，不直接改 Godot 匯入快取。
2. 在外部建模工具對齊本規格的尺寸、原點與朝向；替換 `Visuals/Model` 的場景引用。
3. 保留 Collision、外層場景路徑，以及字樣／物資／互動等遊戲節點。若模型形狀或尺寸改變，重新設計並驗證碰撞，不能只假定舊碰撞仍適合。
4. 在加油站測試場 F6 近看，F7 比較原灰盒；檢查支撐、穿模、朝向與材質。F8 可保存畫面。
5. 執行 `scripts/test.ps1 -TestFilter test_gas_station.gd`，檢查匯入尺寸、碰撞不變、導航、步行及 E 拾取。

原始灰盒保存在 [fuel_pump_graybox.tscn](../../../world/poi_kit/furniture/fuel_pump_graybox.tscn)。F7 只在測試場載入其 Visuals；不替換實際加油機、不新增第二套碰撞、不重建物資。四座加油機共用同一模型，無需逐座修改。加油機仍是停用造景。
