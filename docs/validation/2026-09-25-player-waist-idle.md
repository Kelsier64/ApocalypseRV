# 玩家後腰與預設站姿修正，revision8

2026-09-25，使用 Blender MCP 修改版 7。[新版原檔](../../art_source/player_masked_survivor/revisions/revision8/player_masked_survivor.blend)、[Godot GLB](../../assets/models/player/revision8/player_masked_survivor.glb)。版 7 檔案完整保留。

## 修改

- 腰帶上方原本由窄腰突然外擴，後腰與兩側形成一圈凸起。將兩排環線沿腰帶到下胸的曲線重新過渡，共調整 42 頂點，最大位移約 2.20 cm，重新計算法線並更新 Blender 連續法線參考。保留布料皺褶貼圖、腰帶、UV、切口與前襟。
- 原 idle 把手肘推到身體前方，手腕抬得太高，且骨盆下沉造成蹲姿。重做這一段 2.4 秒／30 fps 循環待機：手腕約高 0.794 m，首幀肘彎約 15.73°，双臂自然下垂，減少骨盆下沉。保留輕微呼吸；其他十段正式動畫未改。
- Blender 開檔停在新版 idle 第 1 幀，視窗框住全身；Godot 模型測試場預設也改為 idle。A-pose 仍是骨架 rest pose，可在測試場按 R 檢查。
- 身高仍為 1.60 m，骨架 rest pose、骨名、三角面、材質與貼圖不變。九份獨立斷肢與面具沿用版 7 的相同檔案，已一併放入版 8 目錄；其 Blender 場景仍名為 `DETACHED7 | ...`。

## 本輪驗證

- [GLB 結構](../../art_source/player_masked_survivor/revisions/revision8/glb_audit.json)：12,066 三角面、55 骨、29 Mesh、5 材質、11 獨立動畫及九份斷肢通過；root 無位移，idle 首尾連續。
- [Blender 逐幀](../../art_source/player_masked_survivor/revisions/revision8/blender_audit.json)：所有正式動作座標有限、封口邊緣保持對齊、無缺權重。idle 全部 73 幀雙腳接地，最大切口偏差約 1.49e-8 m。新版另在空白場景 `VERIFY8 | actual exported GLB` 重匯入，確認 55 骨、29 Mesh。
- [Godot 報告](../../art_source/player_masked_survivor/revisions/revision8/godot_audit.json)：統一 runner 的 `import`、`test_player_model`、`main-scene` 全部 PASS。
- 實際啟動 Godot 4.7.2 Vulkan / Forward+ 測試視窗，無額外指定 clip 時確實顯示新 idle；操作 V 逐一檢查[正面](../../art_source/player_masked_survivor/godot_review_waist/front.jpg)、[側面](../../art_source/player_masked_survivor/godot_review_waist/side.jpg)、[背面](../../art_source/player_masked_survivor/godot_review_waist/back.jpg)。側面手肘不再大幅往前拱，後腰輪廓收順。[日誌](../../art_source/player_masked_survivor/godot_review_waist/actual.log) 無 script/runtime error。
- 來源與遊戲 GLB SHA-256 相同：`D2E4FC4F269F129BF4DDF485F730D8964651B0A40475704AE466A1139E80BD0F`。

Blender 同照明修正前後：[後腰之前](../../art_source/player_masked_survivor/previews/r8_before_back.png)／[後腰之後](../../art_source/player_masked_survivor/previews/r8_after_back.png)，[站姿之前](../../art_source/player_masked_survivor/previews/r8_before_side.png)／[站姿之後](../../art_source/player_masked_survivor/previews/r8_after_side.png)。這些為來源渲染，與上方 Godot 截圖分開記錄。

## 限制與製作紀錄

沿用[版 7 已知限制](2026-09-25-player-arm-joints.md#已知限制)：極端抬臂腋下拉伸、個別攀爬封口微小差異、Blender 原生 GLB 重匯入的分件法線差異；沒有宣稱任意動畫混合／全部自交通過。仍超出原三角面目標 66 面。未接入正式玩家控制器或 RV。

腳本：`refine_waist_revision8.py` → `setup_joint_shading.py` → `refine_idle_revision8.py` → `export_revision8.py`。舊 idle 保存在 `HISTORY7_idle`，不輸出正式 GLB；舊後腰網格基準 `REV7_WAIST_BASE` 不在場景中、不輸出。
