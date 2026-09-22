# 裂爪 Raker

獨立的新怪物；目前遊戲使用 v017 動畫與 v012 加密模型，包含加深眼窩、凹陷嘴部及污垢貼圖，共 41 段動畫；待機／走路／奔跑／狂奔共用駝背、前彎頸部、收肘與朝內手掌，切換步態保留腳步相位。

主世界一般戶外站點新生成的敵人全部使用此場景；[正式主世界驗證](../../../tests/test_main_world_monsters.gd) 檢查實際生成模型。既有存檔保留已保存的物種，獨立室內副本仍使用 Zombie。

- 可編輯來源：[monster_refined_v017.blend](../../../art_source/monster_refined_v017/monster_refined_v017.blend)，細化場景 `MONSTER_REFINED_V017`；保留先前模型場景與動畫。原始動畫來源為 `C:/Users/evan4/Projects/3d/raker_animated_v008.blend`。
- 匯出資產：[raker.glb](raker.glb)，Blender 5.2.2 LTS，glTF 2.0 Binary；只匯出目前場景所選骨架／網格，NLA track 分片、約束烘焙、46 變形骨、Y-up。
- 中立腳底至頭頂 2.18 m，8,847 來源頂點、17,556 三角面、6 材質、UV0。2048 × 2048 污垢膚色貼圖內嵌於 GLB，眼窩與嘴部具有幾何深度。新增 jaw 下顎骨、加深口腔內壁，抓握和咬擊可張嘴；原有動畫閉嘴。
- Godot Model 不縮放，轉 Y 180° 使資產 +Z 面向角色 -Z；BodyMesh Y=0.25 與原有腳底座標契約一致。
- 站立膠囊 2.18 m，低姿態膠囊 1.60 m；v012 低姿態動畫實測最高約 1.501 m。站起需要真實碰撞淨空。

## 動畫

41 個獨立片段，60 fps（原片段保留時長），所有片段 root 固定。世界位移由 Monster／Raker 負責。

| 片段 | 秒 | 循環 | 命中秒 |
| --- | ---: | --- | ---: |
| idle | 2.4 | 是 | — |
| walk | 1.2 | 是 | — |
| chase | 0.8 | 是 | — |
| sprint | 0.6 | 是 | — |
| attack_left / attack_right | 1.2 | 否 | 0.72 |
| crouch_idle | 2.4 | 是 | — |
| crouch_walk | 1.2 | 是 | — |
| crouch_attack | 1.2 | 否 | 0.60 |
| climb_loop | 1.0 | 是 | — |
| hang_idle | 1.6 | 是 | — |
| attack_door | 1.2 | 否 | 0.78 |
| mantle | 0.7 | 否 | — |
| roof_settle | 約 0.67 | 否 | — |
| attack_down | 1.4 | 否 | 0.98 |
| slip_loop | 0.6 | 是 | — |
| fall_loop | 0.8 | 是 | — |
| land | 0.4 | 否 | — |
| hit_react | 0.3 | 否 | — |
| death | 1.3 | 否 | — |
| crouch_hit_react | 0.3 | 否 | — |
| crouch_land | 0.4 | 否 | — |
| crouch_death | 1.3 | 否 | — |

Godot 會消耗匯入名稱的 `_loop` 尾綴；外觀腳本的獨立 `game` library 恢復上述統一名稱。材質閃白和 AnimationLibrary 都由各 actor 獨立持有。

步行設計速度約 1.13 m/s、追擊約 2.3 m/s、低姿態約 0.4 m/s，按實際水平速度調整播放速率。狂奔使用獨立 0.6 秒循環，低伏、長跨步與擺臂；追車速度為車速 +1.2 m/s，上限 18 m/s，加速度 10 m/s²。車速至少 4 m/s 開始，降至 3 m/s 以下退出；上車、低姿態、攀爬、攻擊和重擊中斷皆退出。這些是原地動畫，沒有運行時腳掌地形 IK；陡坡和急轉仍可能滑步。攀爬沿用共用移動，沒有針對任意壁面做逐指抓點 IK。

## 重建和檢查

新版步態、匯出與來源要求見 [v017 說明](../../../art_source/monster_refined_v017/README.md)。沿用 v011 已烘焙贴圖；完成後將 `raker_refined_v017.glb` 複製到本目錄的 `raker.glb`，再執行 Raker 回歸與正式主世界模型測試。

[build_raker_animations.py](../../../scripts/build_raker_animations.py) 是從 v007 重建 v008 基礎動畫的歷史工作流程，預設會寫入正式 raker.glb；直接執行會覆蓋新版外觀，需先改為暫存輸出，再套用後續細化流程。

[v017 動畫檢查](../../../art_source/monster_refined_v017/audit.py) 掃描每個烘焙影格；[結果](animation_audit.json) 保存本版身體自交與牙齒互穿掃描结果（唇緣／牙根的刻意嵌合除外）。排除共用頂點的三角形，不代表任意跨動畫混合也已全部窮舉驗證。

[遊戲場景](../../../enemies/raker.tscn)、[動作與戰鬥測試](../../../tests/test_raker.gd)、[車內回歸](../../../tests/test_raker_cabin.gd)。

## 可動頸部與抓咬

`raker_pose_modifier.gd` 在動畫後處理追視；yaw 左右 90°，pitch 站立上 30°／蹲姿上 40°／下 25°，180°/s，neck_01／neck_02／head 分攤 35／35／30%。保留 v015 小幅抬頭基準，失去目標回復，身後跨 ±180° 不反覆翻向。咬擊由專用頭頸動畫接管。

新增 `grab_{stand,low,seat}_{reach,hold,bite,release,escape,miss}`：0.6／1.0 循環／0.65／0.35／0.45／0.45 秒。咬合傷害在 0.38 秒。雙臂以肩膀接觸點修正，駕駛目標抬肘跨過椅背；兩段手臂都檢查遮擋，無可達路徑時抓空，不移動玩家。

抓取固定抽 6–10 次新 Space 按壓，2 秒內滿額立即無傷脫困；期限到 ≥80% 扣 50，否則致命。玩家硬控保留重力、碰撞、RV 支撐；駕駛留座滑行。每次解除有 3 秒免抓，成功掙脫使怪物踉蹌 1 秒。8 傷害、死亡、移除、跨世界、座位或共同支撐失效都解除。攀爬中的玩家和結構沿用普通攻擊。

咬擊時三節脊椎前探，嘴部對準玩家臉前；玩家頭部最多前拉 28 cm，球體掃掠防止穿牆，解除後復位。0.38 秒咬合伴隨短促視角頓挫及 0.22 秒暗紅衝擊。[v017 驗收](../../../docs/validation/2026-09-23-raker-v017.md)。
