# 屋頂箱式通風機組：3D／ComfyUI skill 實測

2026-10-09。已完成參考圖生成、六視角檢查、尺寸／朝向整理、降面與正式屋頂外觀替換。

## 交付與整合

- 正式模型：`assets/models/shelter_roof_air_handler/shelter_roof_air_handler.glb`，5,998 三角面、5,166 頂點、2,841,476 bytes。
- 包圍盒精確為 6 × 2 × 4 m，原點為中心、Y up、主要百葉進氣面 +Z，無動畫／骨架。
- `world/starting_shelter/exterior_extension.tscn` 的 `Visuals/RoofPlantA` 改為 GLB 實例，保持 (-14,13,-22)、無旋轉、單位縮放。
- 原 BoxMesh 留為隱藏 `Visuals/RoofPlantAGraybox`；原場景另存於來源的 `graybox/`。獨立碰撞、導航旗標、RoofPlantB、facade 與包裝樹設定保留。
- 可編輯 glTF／BIN／PNG、未改 raw.glb、參考圖、生成參數、整理腳本及可重建腳本置於 `art_source/shelter_roof_air_handler/`。既存 20261007 空目錄保留。

## 生成與選擇

沿用 `docs/modeling/requests/shelter-roof-air-handler/shelter-roof-air-handler-image-to-3d-reference.png`，RGBA 1536 × 1024，具有透明背景。未重新生成參考圖。

既有本機服務啟動後，preflight READY；TRELLIS.2、1024、seed 42、50k 目標，只提交一次。Prompt ID：`3a88d0fb-99be-4c98-8188-e152ca770599`，實際執行 98.831 秒。
collect 保留原始 49,998 面 GLB 並停在 ART_REVIEW_REQUIRED，沒有把技術收檔等同美術驗收。

原始進氣面 +X；在副本烘入 Y -90° 旋轉、逐軸尺寸與中心校正，場景位移未烘入。
比較 gltfpack 1.3 的 9,998 面（-si .2 -se .01）及 5,998 面（-si .12 -se .02）候選，均加 -sp -sv -noq -kn -km。
原始、校正來源、兩候選及最終版都檢查六視角材質／素色，含背面與底部。
選 5,998 面：單台 6 m 屋頂裝飾在屋頂近景與全建築視角保留百葉、雙罩與維修蓋輪廓，成本足夠低；未做多實例 FPS 測量。
三張內嵌 PNG 的 SHA256 在整理、降面及 Godot 抽圖後一致；沒有宣稱 UV 或頂點 bytes 未改。

## Skill 結果與問題

3D scene skill 與修正後 ComfyUI skill 本次流程完成，未發現需再修改的 skill 程式故障。11 項離線 client 測試全部通過。

新屬性檢查在 raw 回報全部零異常；降面工具 -sv 更新屬性後，5,998 面候選有 4,130 個非正交切線，正確被 attribute_issues 記錄。
後續以整理腳本在工作副本正交化，最終法線、切線長度／方向與 handedness 異常計數全部為零，原 raw 不變。這是降面結果需整理，並非重送生成的理由。

另查拓樸：raw 有 6 條非流形邊；final 有 11 條非流形邊、2 個重複三角形（以 1 µm 位置合併統計），無開放邊或零面積三角形。這些限制仍保留並明確回報，沒有宣稱模型流形。
背面百葉／底部由單圖推測；罩口與百葉為靜態淺層外觀近似，無內部機械或旋轉風扇。
參考圖來源沿用專案提供內容，本次未新增來源／授權核實。

## 本次實際驗證

- Godot 4.7.2 匯入成功，原生 Forward+／Vulkan 屋頂近景與建築外觀渲染已目視檢查，無 SCRIPT ERROR／ERROR。
- `preview.gd`：實際匯入 6 × 2 × 4 m、中心位置、單位縮放、獨立原 BoxShape3D、navigation_solid、+Z 碰撞射線、隱藏灰盒全部 PASS。
- `test_poi_definitions`、`test_starting_shelter_terrain`、`test_starting_shelter` 與主世界 smoke：4/4 PASS，38.75 秒。包含既有擴建障礙／導航檢查。
- `rebuild.py` 實際在新目錄重建，最終 SHA256 一致。
- 場景差異可逆還原成原始 bytes，確認碰撞與其他節點未改；git diff --check 通過。
- 沒有人工遊戲巡查、同時多機組 FPS 或完整全套遊戲回歸。原生圖為實際 exterior_extension 場景的日光檢查，不代表全部天候／遊戲光照。

相關測試日誌：`.godot/test-logs/20261009-133240-689-selected-28680/`。
生成、所有候選、完整 batch review 與日誌：`.godot/art-work/shelter_roof_air_handler/20261009-01/`，保持忽略。

Raw SHA256：`c17d1ee5f39292895df68104c6583930a05877dd1be3f26dac565bef0cba4ee2`

Final SHA256：`d2e8541aa89cd074dd743b55e261db1ec9ae76f30b8ab7d64a5e7645a19e7118`


## 後續調整：移到地面可見的屋頂前緣

使用者要求地面玩家看得到，機組改到左翼面向前庭的屋頂前緣，局部中心 (-17.7,10,9.8)。
6 × 2 × 4 m 模型／GLB／貼圖不變，仍 +Z 進氣面、中心原點和單位縮放。
視覺、隱藏灰盒、獨立 BoxShape3D 同步移動，navigation_solid 保留。
混凝土支座中心改為 (-17.7,8.75,9.8)，大小 6.3 × 0.5 × 4.3 m，底部貼合左翼 8.5 m 的屋面、頂部支撐機組 9 m 的底面。
只改 facade.tscn 中這個支座的 132 個頂點位置；其他建築 buffers 與節點不變，重建來源 build_shelter_walls.gd 同步更新。

正式 main world、seed 42，玩家局部位置 (-17.7,0,30)，用實際 1.78 m 高相機朝機組拍摄。
地面可見百葉前面上部；設備本體與屋頂會遮擋底部／頂罩細節，沒有宣稱地面看見全模型。
上半部進氣面的視線射線先命中機組 BoxShape3D，局部命中約 (-17.6978,10.6030,11.8000)，沒有先命中牆。
此為腳本設定位置和朝向後的正式玩家相機檢查，沒有人工步行／滑鼠巡查。
原生 main world 和更新後 preview 無 ERROR／SCRIPT ERROR；preview 尺寸、位置、碰撞及導航旗標 PASS。
test_starting_shelter、test_starting_shelter_terrain、main-scene smoke 3/3 PASS，33.85 秒。
日誌 `.godot/test-logs/20261009-135728-517-selected-4672/`；移位備份／本次視角在 `.godot/art-work/shelter_roof_air_handler/20261009-edge/`。

本節取代上文原始 (-14,13,-22) 的場景位置；上文保留首次 skill 實測歷史。
