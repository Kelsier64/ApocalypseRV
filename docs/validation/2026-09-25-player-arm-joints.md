# 玩家肩膀／手肘重建，revision7

2026-09-25，Blender 5.2.2 LTS / MCP 1.7，Godot 4.7.2 stable official。

## 交付與修改

新版位於 [Blender 來源](../../art_source/player_masked_survivor/revisions/revision7/player_masked_survivor.blend) 與 [Godot GLB](../../assets/models/player/revision7/player_masked_survivor.glb)。既有根目錄檔案仍為版 6，沒有被本輪匯出覆寫。模型測試場與資產測試已改用 revision7。

- 重建左右肩袖橋接與上臂／前臂袖管，修掉肩上平臺和肘部過度收細再膨大的形狀。肩部橋接由兩條增為四條四邊面環線，新增 64 頂點、128 三角面。
- 肩部權重沿相連表面漸變，肩切口一致跟隨上臂；肘部以同一混合函數處理上臂、前臂和封口邊緣。手套與手指的原有拓樸、UV 和骨架保留。
- 封口外緣與袖子完全匹配，內層縮入袖管；斷肢匯出移除祖先依賴並正規化權重。九份獨立斷肢重新輸出，肩部分離仍帶前臂和手。
- 平滑法線跨越可分離接縫。Blender 編輯場景另有隱藏的連續法線參考 `EDIT_joint_shading_reference` 和局部 Data Transfer 遮罩，解決分件經 Armature 變形後各自重新計算法線的粗線。此參考不在 GLB 中；獨立斷肢也不依賴它。
- 維持 1.60 m 矮寬比例、55 骨、5 材質、29 Mesh、11 段正式動畫、18 封口；白面具獨立且無孔洞，無對講機。

本版 **12,066 三角面**，超過原訂 12,000 上限 66 面（0.55%）。原因是肩部變形環線，沒有為了壓回預算刪除封口或手指。衣料／固定色貼圖仍為 1024²，切口 512²，GLB 內嵌七張影像。

## 本輪檢查

1. [GLB 二進位檢查](../../art_source/player_masked_survivor/revisions/revision7/glb_audit.json)：全身＋九份斷肢通過。高度 1.600000024 m、腳底 0，UV0 齊全，最多三個有效權重、正規化、無負縮放，11 段動畫互相獨立、root 固定、循環首尾一致，染色因子與中性貼圖分開。
2. 在新空白 Blender 場景 `VERIFY7FINAL | actual exported GLB` 重新匯入本輪檔案：29 Mesh、55 骨、11 Action、高度約 1.60 m。重匯入場景保留在新版 .blend。正／側／背、坐姿、攀爬及基本材質預覽以此場景重新渲染；QA 與分離姿勢使用本輪來源。
3. [來源逐幀檢查](../../art_source/player_masked_survivor/revisions/revision7/blender_audit.json)：11 段正式動作全部頂點有限、無未加權頂點；切口邊緣最大偏差 0.0000001192 m。記錄每段接地幀和邊長變化，不以有限座標等同無穿模。
4. 專案統一 runner `scripts/test.ps1 -TestFilter test_player_model.gd`：`import`、`test_player_model`、`main-scene` 全部 PASS。[Godot 結構報告](../../art_source/player_masked_survivor/revisions/revision7/godot_audit.json) 確認本輪 12,066 面資產、精確動畫名／循環、換色不影響固定材質、九份斷肢可載入。不是全部遊戲測試。
5. 操作 Godot Vulkan / Forward+ 實際遊戲視窗：待機肩肘近景、赭色換色、坐姿、過頭懸掛、攀爬、左肩和左肘分離。肩肘沒有原先明顯的分件粗線；坐姿彎肘、抬臂仍維持連續輪廓。[待機](../../art_source/player_masked_survivor/godot_review_joints/final_idle.jpg)、[坐姿](../../art_source/player_masked_survivor/godot_review_joints/final_sit.jpg)、[抬手](../../art_source/player_masked_survivor/godot_review_joints/final_hang.jpg)、[攀爬](../../art_source/player_masked_survivor/godot_review_joints/final_climb.jpg)、[肩部分離](../../art_source/player_masked_survivor/godot_review_joints/final_shoulder_detached.jpg)、[肘部分離](../../art_source/player_masked_survivor/godot_review_joints/final_elbow_detached.jpg)、[換色](../../art_source/player_masked_survivor/godot_review_joints/final_tint.jpg)。[實機日誌](../../art_source/player_masked_survivor/godot_review_joints/actual_poses.log) 無 script/runtime error；完成後只關閉此次測試遊戲，保留使用者 Godot 編輯器。

來源與遊戲全身 GLB SHA-256 相同：`EA9EC13EAF3C49D6923B40D75BFADC5432CB8924D82D16E55D1A5FF0AB27E528`。

## 已知限制

極端抬臂仍有腋下布面拉伸。逐幀最大邊長比約 4.799（hang_idle），此數值包含短邊，不能當成衣料應變合格證明。

Blender 原生重新匯入 GLB 後，分件經 Armature 變形會各自重新計算法線，因此未加編輯參考的 `VERIFY7FINAL` 動畫預覽仍可能出現肘部明暗分界；這與 Godot 的 GPU 蒙皮法線表現不同。新版 .blend 的主編輯場景已加連續法線參考，Godot 實機近景亦已確認改善。重匯入預覽保留原樣以呈現此差異，不能拿 Blender 原生重匯入動畫渲染代替 Godot 實機畫面。

[封口可見性對照](../../art_source/player_masked_survivor/godot_review_joints/closure_visibility_audit.json) 使用八組 1000² 配對渲染，切換肩肘封口可見／隱藏：七組在 RGB 差異 0.02 門檻以上為零像素；攀爬第 19 幀前方視角有 24 像素差異，最大 0.267。仍有極小局部封口影響，不能宣稱任意姿勢完全無露邊。這個對照是 Blender 渲染測量，與 Godot 實機觀察分開記錄。

本轮改善肩肘銜接，沒有宣稱整個角色達到最終近景美術品質。衣領、褲襠、膝部與手掌仍有原首版的簡化形狀；沒有完成所有自交／動畫混合、實際方向盤握點或 RV 尺寸校對。布娃娃物理、第一人稱、斷肢遊戲規則與 UI 未在此實作。

## 重建

從保存的版 6 基準依序使用 Blender MCP 執行 `rebuild_arm_joints.py`、`setup_joint_shading.py`、`export_joint_revision7.py`。新版匯出腳本只新增版本目錄與場景，保留既有版 6／歷史場景。以新版 .blend 為編輯來源；不要再用舊 `export_assets.py` 覆寫這次版本。
