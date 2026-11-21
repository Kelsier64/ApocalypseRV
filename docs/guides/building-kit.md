# 建築 kit 與建築製作流程

[文件索引](../README.md) · [POI 共用規範](poi-authoring.md) · [展示場指南](playgrounds.md)

建築外觀用 [BuildingKit](../../world/building_kit/building_kit.gd) 的建築詞彙組裝：帶門窗開口的牆、房間、樓板、屋頂、柱、梁、樓梯與飾帶，不再為每棟建築另寫 `box()`。kit 一次輸出一個 ArrayMesh（每種材質一個 surface）與一個方塊碰撞的 StaticBody3D，並用 `validate()` 檢查開口與懸空零件。[參考建築](../../world/building_kit/samples/service_block.gd)示範每種零件，也是 kit 測試的夾具。

## 慣例

- 單位公尺，Y 向上，建築主立面朝 +Z。`frame(at, yaw)` 設定接下來零件的區域原點，供房間或樓層各自定位。
- 標準尺寸是 [building_kit.gd](../../world/building_kit/building_kit.gd) 開頭的常數：層高、牆厚、樓板厚、門窗尺寸、窗台高、踏步。新建築先用這些尺寸，偏離時要有理由。
- 牆沿中心線從 a 畫到 b，外側朝 `(-d.y, 0, d.x)`。`room()` 讓前後牆包住轉角、側牆頂在內面，所以轉角沒有重疊面。開口的 `at` 是開口中心到牆起點的距離。
- 開口用 `BuildingKit.door()`、`BuildingKit.window()` 建立；窗可為完整玻璃（有碰撞）、破窗或無玻璃。kit 自動加兩面框、窗台板與寬窗的中梃。門洞碰撞淨空保持原尺寸。
- 樓梯只畫踏步，碰撞是一條穿過踏步中點的坡道。平台樓板自己加。
- 懸掛的零件（吊牌、纜線上的燈）傳 `hung: true`，否則 `validate()` 會判為懸空。
- 碰撞只給牆、樓板、柱與玻璃；框、飾帶、勒腳與屋簷沒有碰撞。依 [POI 場景層級](poi-authoring.md#3-尺度座標與場景層級)，對同一個 kit 呼叫兩次：`build(visuals, true, false)` 放進 `Visuals`，`build(collision, false, true)` 放進 `Collision`，參考建築就是這樣做。只要導航碰撞時只呼叫後者。

## 材質與色盤

材質在 [BuildingKitMaterials](../../world/building_kit/building_kit_materials.gd)。每種 finish 是一組 CC0 照片貼圖加一個色盤色：shader 只取照片的明暗細節，顏色由 tint 決定，所以所有建築都留在 [GDD](../../GDD.md#section-7) 的冷灰低飽和範圍。`keep` 讓鏽與污漬保留少量原色。shader 另外依建築本地高度加牆腳污漬，倒角邊加磨損。

- 內建 finish：`concrete`、`slab`、`block`、`plaster`、`paint`、`corrugated`、`steel`、`trim`、`tiles`、`wood`、`accent`、`glass`。
- 建築要自己的色調時，用 `BuildingKitMaterials.register(name, base, tint)` 從既有 finish 衍生，不要直接改內建色。
- 貼圖來源、授權與縮圖處理見[素材說明](../../assets/materials/building_kit/README.md)。

## 製作流程

每棟新建築或大改外觀都走以下關卡。前一關沒過，不進下一關。

1. **參考與風格表。** 先有一張參考圖（使用者提供，或依 [參考圖指南](../../.claude/skills/comfyui-image-to-3d/references/reference-images.md) 生成），再寫一份短風格表：用到的 finish、色調、細節密度、損壞程度。交給使用者確認。
2. **灰盒與動線。** 只用 kit 的牆、開口、樓板與樓梯組出量體，跑 `validate()`，放進展示場讓使用者實際走一遍。使用者同意量體與動線後，才開始做細節。
3. **細節。** 加框、飾帶、屋簷、雨棚、設備與損壞。特殊造型（彎曲雨棚、招牌、重點設備）交給 Blender 或圖片轉 3D，再以 wrapper 接入。
4. **自查與交付。** 用 `scripts/agent/review-scene.ps1` 渲染四個斜角、正面、側面、俯視與指定的視線高度畫面，對照參考圖讀過每張圖；再把展示場交給使用者做最後確認。代理自己的截圖檢查不算驗收。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/agent/review-scene.ps1 -Scene res://world/building_kit/samples/service_block.tscn -Eye '0,1.6,9:0,1.8,0;0,1.6,-3.5:0,1.4,3' -Clay
```

輸出在 `.godot/scene-review/<場景名>/`，含每張 PNG 與 `review.json`（範圍、三角面數、surface 與材質數）。

## 現況

kit 目前只有參考建築使用。既有建築仍各自用自己的方塊函式，遷移排在[計畫總覽](../plans/README.md)的待辦。
