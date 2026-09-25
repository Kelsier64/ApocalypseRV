# 待機手肘方向修正，revision9

上一版只確認彎曲角度，未確認彎曲方向，導致左右手肘往前、前臂往後折。這是製作錯誤。

本輪以 Blender MCP 將 idle 的肘部 pole 從 Blender 前方 -Y 改到後方 +Y；手腕目標保持原位，現在肘尖朝後、前臂往角色前方微彎。左右肘彎約 15.6–15.9°。保留後腰修形、1.60 m 比例及自然站姿，其他十段正式 Action、網格、rest pose 與九份斷肢均未改。舊 idle 保存為 HISTORY8_idle，未混入輸出動畫。

[新版 Blender](../../art_source/player_masked_survivor/revisions/revision9/player_masked_survivor.blend)／[新版 Godot GLB](../../assets/models/player/revision9/player_masked_survivor.glb)。預設仍為 idle。骨架綁定仍是 A-pose；舊版 8 保留。

本輪驗證：

- [方向量測](../../art_source/player_masked_survivor/revisions/revision9/elbow_direction.json)：左右手 73 幀，肘部相對肩腕連線向後至少 32.84 mm，手腕相對肘部向前至少 44.55 mm；方向錯誤為零。
- [Blender idle 蒙皮](../../art_source/player_masked_survivor/revisions/revision9/blender_idle_audit.json)：新 idle 逐幀頂點有限、無缺權重、切口最大偏差 1.49e-8 m。這是本輪改動的 idle 檢查，其餘動作來源檢查見版 8 歷史報告。
- [二進位 GLB](../../art_source/player_masked_survivor/revisions/revision9/glb_audit.json)：1.60 m、12,066 三角面、55 骨、29 Mesh、5 材質、11 獨立動畫、root 固定與循環首尾一致。九份未變更斷肢亦驗證通過。
- 新建空白 Blender 場景 `VERIFY9 | actual exported GLB` 重新匯入，確認 55 骨、29 Mesh，保存在新版 .blend。
- [Godot 測試](../../art_source/player_masked_survivor/revisions/revision9/godot_audit.json)：新增 idle 每一幀的左右手方向回歸檢查。GLB 前方為 +Z，因此肘部必須位於肩腕連線後方，手腕必須在肘部前方。統一 runner 的 import、test_player_model、main-scene 全部 PASS。
- 實際操作 Godot 4.7.2 Vulkan / Forward+ 視窗，[側面截图](../../art_source/player_masked_survivor/godot_review_elbow/side.jpg)確認新的彎曲方向；[日誌](../../art_source/player_masked_survivor/godot_review_elbow/actual.log)沒有 script/runtime error。這不代表已測試全部玩法。

[Blender 側面近景](../../art_source/player_masked_survivor/previews/r9_side.png)。保留[版 7 已知限制](2026-09-25-player-arm-joints.md#已知限制)，本轮没有扩展成其他动作或整個角色的美術重製。
