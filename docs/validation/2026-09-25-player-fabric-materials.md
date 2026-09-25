# 玩家工作服與頭套材質：2026-09-25

> 歷史版本：使用者指出本版衣服紋理無法辨識，因此本版的結構檢查通過不代表布紋外觀通過。後續版本改用 2K 衣料與同時作用於 Base Color、Roughness、Normal 的織紋；本頁截圖及 SHA256 只記錄當時輸出。

本輪依使用者授權，透過 Blender MCP 更新工作服與米色頭套材質，重新輸出完整角色及九份斷肢 GLB。材質第一輪完成；角色仍有低模輪廓與薄布邊緣待精修，並非完整近景美術驗收。

## 交付變更

- 工作服：中性灰 Base Color 保留獨立深灰綠 tint；增加低對比布紋、口袋／前襟／領片車縫線、背部接縫、膝肘磨損與少量污漬。明暗變化代表布料色差與磨損，未加入固定光照或 AO。
- 頭套：固定米色，增加帽頂拼接、後腦中線、頸口收邊、细布紋及輕微髒污。仍與面具分離。
- 衣料與固定色圖集各有 1024² Base Color、Roughness、OpenGL tangent-space Normal，共六張 1k PNG；切口繼續使用 512² PNG。GLB 內嵌七張影像，Blender 原檔亦打包影像。Normal 為原創布紋高度場轉換，沒有宣稱高模雕刻烘焙。
- 保留原有 UV0、五材質、55 根骨、11 動畫、10 主分件與 18 封口。完整角色仍為 11,938 三角面、1.75 m。
- 檢查現有厚領片與口袋相對軀幹的間距，微調前襟位置，改用面積加權的布片法線。沒有增加面數；並未消除所有 Godot 細暗線。
- `mask_default` 保持純白、無貼圖與 Normal、無孔洞；沒有增加對講機。
- [測試場](../../tests/player_model_playground.gd) 增加衣料前景／頭套背面鏡位，以及 B 切換 studio、dim interior、daylight。這是檢視照明，未更動正式關卡光源。

## 本輪驗證

[來源 GLB](../../art_source/player_masked_survivor/player_masked_survivor.glb) 與 [遊戲 GLB](../../assets/models/player/player_masked_survivor.glb) 的 SHA256 一致：`8FB11EE503B0070AF38AFE61B9456BB19EC00E48A2D57BBC72584589A8CF8998`。

- [實際 GLB 結構檢查](../../art_source/player_masked_survivor/glb_audit.json)：尺寸、朝向、權重、UV、材質、獨立動畫、root、循環首尾與九份斷肢依賴檢查無失敗。
- [Blender 逐幀檢查](../../art_source/player_masked_survivor/blender_audit.json)：所有正式 Action 的變形頂點有限，切口配對最大誤差約 0.000000238 m。這不是所有三角面自交或動畫混合的窮舉驗證。
- 專案 runner：`scripts/test.ps1 -TestFilter test_player_model.gd`，`import`、`test_player_model`、`main-scene` 全部 PASS。新增兩材質的 Normal／Roughness 匯入與 1k Normal 尺寸檢查，另確認白面具沒有 Normal 或 Base Color 貼圖。[本輪結果](../../art_source/player_masked_survivor/godot_review_materials/automated_asset_check.json)。
- 完整 GLB 重新匯入新的 Blender 場景；更新 30 張預覽，包括換色、近景、QA 姿勢與分離圖。基本外觀使用重匯入網格，QA 姿勢與分離圖使用來源；未宣稱每張圖都完成手動美術驗收。
- 實際啟動 Godot 4.7.2 / Forward+ / RTX 4060 Laptop 測試視窗，檢查下列最終輸出。未只以 Blender 渲染代替遊戲檢查。[視窗日誌](../../art_source/player_masked_survivor/godot_review_materials/inspection.log) 無腳本錯誤。測試視窗已關閉，使用者編輯器未關閉。

| 實際觀察 | 證據 |
|---|---|
| 日光下工作服維持布料色差與啞光外觀；薄前襟／領片仍見細暗線 | [工作服](../../art_source/player_masked_survivor/godot_review_materials/03_fabric_daylight.png) |
| 上衣、袖子同步變赭色，頭套、面具、橘条與手套維持原色；全身含褲管另有 Blender 重匯入預覽 | [Godot 赭色](../../art_source/player_masked_survivor/godot_review_materials/04_fabric_ochre.png)、[全身赭色](../../art_source/player_masked_survivor/previews/tint_ochre.png) |
| 米色頭套後腦及頸口接縫可辨識 | [日光](../../art_source/player_masked_survivor/godot_review_materials/05_hood_daylight.png) |
| 柔和照明下頭套與衣服顏色分離 | [Studio](../../art_source/player_masked_survivor/godot_review_materials/06_hood_studio.png) |
| 冷暗光下頭套縫線保留，但對比較低 | [室內暗光](../../art_source/player_masked_survivor/godot_review_materials/07_hood_dim.png) |

## 剩餘限制

細暗線在日光角度仍可見，初輪關閉自動 LOD 也沒有消除，不能歸因為 LOD 已解決。肩腋、頭套外輪廓與手掌仍偏低模，布料細節受 1k 圖集像素密度限制。這輪檢查以固定鏡位為主，未完成移動鏡頭／所有距離的閃爍驗收，也未做正式玩家、第一人稱鏡頭、RV、道具對位、物理骨或玩法測試。

製作來源：[refine_fabric_materials.py](../../art_source/player_masked_survivor/refine_fabric_materials.py)。它在既有 revision 2 網格與 UV 上產生原創 PNG，沒有外部材質授權依賴。修改幾何或 UV 後需重烘材質，再執行 [export_assets.py](../../art_source/player_masked_survivor/export_assets.py) 以同步完整與斷肢資產。
