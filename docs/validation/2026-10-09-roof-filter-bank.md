# 屋頂過濾設備組驗證

2026-10-09。已替換正式 main world 使用之避難所 `Visuals/RoofPlantB` 外觀。

- 成品 5,998 三角面、5,751 頂點、3,254,560 bytes；9 × 1.5 × 5 m，bbox 中心原點、Y up、主要維修面 +Z，無動畫／骨架。
- 依使用者後續要求，放到東翼屋頂前緣 (17.7,11.75,9.8)，無旋轉、單位縮放；Collision/RoofPlantB 與隱藏 RoofPlantBGraybox 同步移位，9 × 1.5 × 5 m 盒碰撞和 navigation_solid 保留。混凝土支座移到 (17.7,10.75,9.8)，只改 132 個頂點位置；建築其餘 bytes、RoofPlantA 與其他節點不變，重建腳本同步更新。
- 正式 GLB／必要貼圖在 `assets/models/shelter_roof_filter_bank/`；可編輯 glTF、BIN、PNG 和整理參數在 `art_source/shelter_roof_filter_bank/`。
- 沿用專案透明參考圖，單次 TRELLIS.2 1024／seed 42 生成，raw 為 49,998 面，後端約 43.11 秒。Prompt ID：`3efcd07d-106f-420f-a811-d4c0186cc1d5`。
- 原始後方風道和箱體有間隙，在副本將 6,696 個風道／附屬件頂點沿原 Z -0.05 平移，使風道與箱體相接；未做 boolean union。Y 180° 轉正後校正尺寸與中心，場景位置未烘入。
- 比較 gltfpack 1.3 的 7,998 與 5,998 面候選，選後者：單組 9 m 屋頂裝飾可辨識三箱、濾網、維修蓋與底架，無須保留 50k 面。設定 -si 0.12 -se 0.02 -sp -sv -noq -kn -km。
- 降面後 5,069 個切線不正交，在整理副本修正；正式模型各屬性異常計數全部 0。三張貼圖 bytes 在生成、降面、來源和 Godot 抽圖後完全一致。

## 實際檢查

原模、修整來源、兩組候選與成品都目視檢查六方向材質／素色，包含背面與底部。
Godot 4.7.2 Forward+ 的實際屋頂預覽通過尺寸、中心、位置、碰撞、導航旗標與 +Z 射線檢查。
正式 main world／seed 42 已確認載入此 GLB。後續移位後使用實際玩家 Camera3D，玩家前庭位置 (17.7,0,30)、眼高 1.78 m、day 1 at 15:00，目視三個正面濾箱露出屋頂，視線射線到達設備正面 (17.70093,12.29099,12.299995)，未被女兒牆阻擋。這是程式定位玩家相機，未做人工步行巡查。
匯入與兩份原生預覽日誌無 SCRIPT ERROR／ERROR。

`test_poi_definitions`、`test_starting_shelter_terrain`、`test_starting_shelter`、main smoke **4/4 PASS**，移位後再次驗證，36.06 秒。
日誌 `.godot/test-logs/20261009-151451-987-selected-46756/`。
可編輯來源的結構／BIN／貼圖與 GLB 等價；由 raw 重建成品 SHA256 一致；raw 未修改。場景移位可逆還原為移位前內容，只同步模型、灰盒與碰撞的三個位置；支座僅 132 個位置頂點平移 (6.7,-1,32.8)，其他建築 buffer 不變。

## 保留限制

背面／底部為單圖推測，濾網主要靠材質呈現。以 1 µm 位置合併診斷，成品仍有 18 條非流形邊和 6 個重複三角形；沒有開放邊／零面積面，未宣稱流形。物理使用既有盒碰撞。
沒有多實例 FPS、人工完整巡查或本機全套回歸。參考圖沿用專案既存來源，本次沒有新增來源／授權核實。

依目前 Git 指引，生成 graph、raw、候選、工具、備份、截圖與日誌保留於忽略目錄 `.godot/art-work/shelter_roof_filter_bank/20261009-01/`，不列入 Git 交付；必要遊戲資產與可編輯來源保留。
本次沒有修改 skill；修正後屬性檢查可正確回報降面切線問題。生成時使用分支 `codex/shelter-roof-filter-bank`，當時尚未推送或建立 PR。屋頂邊緣檢查、相機腳本、截圖與備份保留於 `.godot/art-work/shelter_roof_filter_bank/20261009-edge/`。

Raw SHA256：`a9f7a56dad779341bce25301722fd4fed1da575ee8788dc1e6e7909e2461d68f`

Final SHA256：`f61d95837f461af7c5a61c77e92949170520ebfee0eafc75a722936c8ca845b7`

## 2026-10-10 變更整理檢查

沿用目前分支整理提交。重新確認可編輯來源／BIN／三張貼圖與 GLB 一致、支座只有 132 個位置頂點移動且其他 facade bytes 不變、文件相對連結存在。
相關測試 `test_poi_definitions`、`test_starting_shelter_terrain`、`test_starting_shelter` 與 main-scene smoke **4/4 PASS**（40.30 秒）；本輪日誌 `.godot/test-logs/20261010-142703-868-selected-18452/`。原有目視紀錄仍屬 2026-10-09；本輪未重做人工巡查。
