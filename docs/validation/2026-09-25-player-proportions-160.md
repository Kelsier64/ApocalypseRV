# 玩家矮壯比例版 6：2026-09-25

依使用者最新指示「大臂太粗、160 左右、比較矮寬、比較 goofy」調整。此要求取代原委託的 1.75 m；原始委託文件保持不動。

- 身高 **1.600 m**，腳底 0；縮短腿與軀幹，保留軀幹寬度、頭及靴子大小。
- 大臂沿骨軸局部收細最多約 25%，向肩及肘平滑過渡；主分件與兩端封口使用同一位移場。
- 在網格與骨架編輯資料中修改尺寸，Mesh／Armature 物件保持 Rotation 0、Scale 1。骨名與階層不變，rest 骨位置與長度更新。
- 依新版比例調整手腳目標、骨盆動作幅度與步幅，重新烘焙 11 段正式動畫及 QA 姿勢。root 仍固定，動作時長及循環設定不變。
- 全身、九份獨立斷肢及獨立白面具重新輸出。面具 Blender 插槽位置改為 `(0, -0.088, 1.485)`，GLB 對應 `(0, 1.485, 0.088)`；新版資產必須整套使用。
- 衣褶、UV、1K 圖集與可換色材質沿用版 5，沒有增加三角面。

## 本輪驗證

Blender 5.2.2 LTS / Blender MCP addon 1.7。完整 GLB 重匯入全新 Blender 場景，更新 32 張預覽。Godot 4.7.2 / Forward+ / RTX 4060 Laptop 實際視窗檢查。

- [二進位 GLB 檢查](../../art_source/player_masked_survivor/glb_audit.json)：高度 1.600000024 m、11,938 三角面、55 骨、5 材質、29 Mesh、11 段動畫、9 份獨立斷肢，無失敗。
- [來源逐幀檢查](../../art_source/player_masked_survivor/blender_audit.json)：全部正式動作頂點有限，切口配對最大誤差約 0.000000238 m，最大邊長比 2.671。站立與坐姿鞋底保持接地，步行左右接地區間與原紀錄一致。此檢查不保證所有自交與任意動畫過渡。
- 統一 runner `scripts/test.ps1 -TestFilter test_player_model.gd`：`import`、`test_player_model`、`main-scene` 全部 PASS；身高驗證契約改為 1.60 m。[本輪結果](../../art_source/player_masked_survivor/godot_review_proportions/automated_asset_check.json)。沒有執行全套玩法測試。
- 實際視窗：[待機](../../art_source/player_masked_survivor/godot_review_proportions/01_idle.png)、[步行正面](../../art_source/player_masked_survivor/godot_review_proportions/02_walk.png)、[步行側面](../../art_source/player_masked_survivor/godot_review_proportions/03_walk_side.png)、[坐姿](../../art_source/player_masked_survivor/godot_review_proportions/04_sit.png)、[懸掛](../../art_source/player_masked_survivor/godot_review_proportions/05_hang.png)、[攀爬](../../art_source/player_masked_survivor/godot_review_proportions/06_climb.png)、[左臂分離](../../art_source/player_masked_survivor/godot_review_proportions/07_detached.png)。觀察鏡位未見新增爆點或明顯破洞，分離時袖子與手一起移走，身體端封口可見。
- [步行日誌](../../art_source/player_masked_survivor/godot_review_proportions/inspection.log)及[姿勢日誌](../../art_source/player_masked_survivor/godot_review_proportions/pose-inspection.log)無腳本錯誤。本次測試視窗已關閉，使用者原編輯器保留。

來源與遊戲完整 GLB 的 SHA256 相同：`0984B2A861B5C11D2B45D6CFE17300D6396E16FB40EB3F260FE03D281EB92707`。

## 外觀對照與限制

同一 Blender 鏡位：[原 175 cm](../../art_source/player_masked_survivor/godot_review_proportions/before_175.png)、[新版 160 cm](../../art_source/player_masked_survivor/godot_review_proportions/after_160.png)。

這輪修改比例和大臂粗細；前臂袖褶、肩部低模輪廓、胯部水平轉折與衣領暗線仍是原有美術待精修項目。未做正式玩家／RV／第一人稱接入，物理骨、碰撞及道具握點仍需引擎校對。原 1.75 m 的 `.blend`、GLB 與動畫製作腳本保存在來源目錄 `history/revision5/`，目前來源為新版 1.60 m。

交付與設定見 [來源 README](../../art_source/player_masked_survivor/README.md)。
