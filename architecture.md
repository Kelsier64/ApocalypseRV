# ApocalypseRV 架構

[啟動與操作](README.md) · [遊戲設計](GDD.md) · [技術架構](architecture.md)

本文件描述目前的場景結構、模組責任、共用契約與狀態所有權，只寫跨模組的事。

- 版本以程式常數為準：世界生成 `world/terrain/world_profile.gd`（`generation_version`），存檔 `rv/checkpoint.gd` 與 `rv/vehicle_snapshot.gd`（`VERSION`）。
- 第 2 節只列主要子系統。完整類別清單從程式產生：`powershell -NoProfile -File scripts/agent/module-index.ps1 [關鍵字]`。
- 單一系統的功能、規則與實作細節在 [docs/systems/](docs/README.md#系統)，不寫在這裡。
- 舊存檔不相容時直接重新開局，不做遷移。

## 目錄

- [1. 執行環境與場景](#section-1)
- [2. 模組責任](#section-2)
- [3. 共用契約](#section-3)
- [4. 狀態與所有權](#section-4)
- [5. 主要流程](#section-5)
- [6. 已知限制](#section-6)
- [7. 測試與慣例](#section-7)

<a id="section-1"></a>

## 1. 執行環境與場景

目標開發／CI 版本 Godot 4.7.2（由 `.godot-version` 固定，runner 強制核對），60 Hz／Jolt Physics（velocity/position steps 各 32）、桌面 Forward+／Vulkan（Compatibility 可降級）。[project.godot](project.godot) 的入口為 [world/main_world.tscn](world/main_world.tscn)，[world/test_world.tscn](world/test_world.tscn) 保留 legacy 測試配置。目前沒有網路同步或任務系統；Checkpoint autoload 提供主世界檢查點。

專案功能標記為 4.7；開發與 CI 使用 4.7.2 stable。

```text
MainWorld
├── Player                  玩家、Camera、互動射線、UI
├── WorldEntities           共用動態物件容器
├── WorldGenerator
│   └── chunk               地形、道路、導航、POI 入口建築
├── PoiInstances            同局副本狀態、轉場、串流錨點
│   └── InteriorViewport    獨立 World3D，僅探索時存在
│       └── PoiInterior     房間／走廊／導航／WorldEntities／室內玩家
├── WorldClock              自然天氣與顯示霧合成
├── DarkAdaptation          依局部亮度的灰階顯示、視圖與距離設定
├── DeviationPressure       偏行判定、真實秒數事件與額外刷新
├── NewRv
│   └── Chassis             VehicleBody3D、油電、材料、耐久
│       ├── Wheel_*         VehicleWheel3D；獨立輪槽 hitbox 常駐底盤
│       ├── StructureSlots  門／牆／屋頂等固定車體結構
│       └── 座椅／插槽／加油孔／道具箱   已安裝的 Item
└── StartRun                車庫門、整備／出發／封閉狀態
```

正式 RV 使用獨立 starter_rv 配置，保留引擎、電池、兩包維修包、平板與完整駕駛室；工作台與分解機由起始車庫提供。new_rv 保留測試配置，不再包含發電機。

<a id="section-2"></a>

## 2. 模組責任

| 模組 | 檔案 | 邊界 |
|---|---|---|
| 玩家協調 | [player.gd](player/player.gd) | 攝影機、移動、攀爬、生命、座位／UI／放置授權、手持外觀 |
| 玩家背包 | [player_inventory.gd](player/player_inventory.gd) | 6 格、選取、大型限制與消耗，不持有場景節點 |
| 玩家部位 | [player_body_state.gd](player/player_body_state.gd) | 頭、左右整臂、左右整腿的完整性；Player 授權能力、切斷及安全重生，視覺效果不持有存檔真值 |
| 玩家斷肢外觀 | [player_dismemberment_visual.gd](player/player_dismemberment_visual.gd)、[player_detached_part.gd](player/player_detached_part.gd)、[player_gore.gd](player/player_gore.gd) | 分件／兩端封口、獨立斷肢物理、短血噴與限量血跡，與原骨架及生命狀態分開 |
| 玩家持物姿勢 | [player_carry_visual.gd](player/player_carry_visual.gd) | 裝備時同步完成握點／手臂 IK 再顯示物品；HandMarker 隸屬 Player，避免鏡頭輸入在物理步間單獨移動物品。依 is_large 使用單／雙手，缺專用握點時由可見三角面快取貼合點，排除隱藏網格與呈現複本。持物手保持完整接觸權重，初次解出的手腕基底鎖在持物座標；物品晃動與手臂在同一步求解，可達距離殘差再以共用物品框貼回真實掌面並重解支撐手，鬆手才混合回移動動畫。手電筒保留圓柄／指節與抓取照臉專用求解，手槍保留瞄準／換彈；屍體、專用支撐與 RV 機械維持其原支撐定位。下一次動畫取樣前還原骨姿，死亡保留求值姿勢、重生清除快取；不改物理／背包真值 |
| 第一人稱持物 | [player_first_person_carry.gd](player/player_first_person_carry.gd) | 一般單／雙手 Item、手電筒與手槍以 layer 22、獨立透明 SubViewport 顯示，沿用正式骨架姿勢與材質；一般取景 70°，手槍腰射使用完整視角基底與專用偏移，瞄準時混合至正式鏡頭的相同位置／FOV，偏移以當下袖子範圍限制，避免鏡頭穿入手臂。手槍顯示兩側存活手臂，手肘保持向外下方彎曲，低頭時不反轉；手電筒保留圓柄持握與實際 Beam；世界鏡頭、尺寸、陰影、實際槍口／射線與丟棄姿態維持原所有權。保留未替換身體／空手並支援缺手；低頭或蹲下時先把獨立鏡頭的位置、角度與 FOV 對齊正式鏡頭，再恢復完整本地身體，避免肩部接縫錯開；回正／站起反向交接，門檻保留緩衝避免反覆切換。抓取、攀爬、入座、爬行、死亡、放置、旁觀、超寬物品與 RV 連線設備沿用原呈現。最多同步四盞附近燈光，手持發光源另常駐並逐幀同步，避免漏掉短槍口閃光；排除夜間圖層重派，合成於既有色彩處理與 HUD 前，換 World3D 時重新綁定 |
| 互動 | [player_interact.gd](player/player_interact.gd) | 射線、目標提示與結果、E／F 獨立按鍵狀態、快速事件緩衝、輪胎安裝特例 |
| 放置 | [equipment_placement.gd](player/equipment_placement.gd) | 預覽位置／朝向、確認／取消輸入 |
| 共用物品 | [item.gd](props/item.gd) | Item 剛體、身分、耐久、大型旗標、回收、手持與服務接口 |
| RV | [chassis.gd](rv/chassis.gd) | 控制授權、引擎／排檔／手煞車入口、輪槽、耐久、固定 Item 登錄與重量／重心 |
| 能源 | [vehicle_energy.gd](rv/vehicle_energy.gd)、[battery_state.gd](rv/battery_state.gd) | 代理有效插槽的 BatteryState、集中物理步調度；燃油屬於底盤 |
| 材料 | [material_storage.gd](rv/material_storage.gd) | 本車存量、容量、原子扣款、溢出保留 |
| 保存 | [checkpoint.gd](rv/checkpoint.gd)、[vehicle_snapshot.gd](rv/vehicle_snapshot.gd) | 版本化磁碟檢查點、車輛／設備／輸入物件關係還原 |
| RV 互動轉接 | [fuel_port.gd](equipment/fuel_port.gd)、[wheel_hitbox.gd](rv/wheel_hitbox.gd) | 加油入口、拆輪 |
| 物品支撐與資料 | [item_mount.gd](core/item_mount.gd)、[item_definition.gd](core/item_definition.gd)、[item_state.gd](core/item_state.gd) | 固定／掉落、共用定義、物品狀態驗證及唯一所有權 |
| 專用設備 | [equipment/](equipment/) | scrapper 回收、tablet_screen/UI 顯示製作、crafting_station 出料、driver_seat 駕駛；VehicleEnergy 管理內建充電 |
| 串流 | [world_generator.gd](world/world_generator.gd) | 固定座標區塊窗口、分幀建立、遠景與距離清理 |
| 世界資料 | [world_field.gd](world/terrain/world_field.gd)、[world_profile.gd](world/terrain/world_profile.gd) | 獨立 RNG、三層噪音、區域權重、道路及停靠計畫、共用高度查詢 |
| 地形道路 | [chunk_generator.gd](world/chunk_generator.gd) | 網格、碰撞、路面、停靠設施、裝飾、實際碰撞導航和物資／敵人 |
| 場址計畫 | [exploration_site.gd](world/terrain/exploration_site.gd) | v3／v4 路線、平台、鏡像、窄口、圍牆分段及邊界，共用於整地／生成／導航／串流 |
| 顯示與偏好 | [game_settings.gd](core/game_settings.gd)、[outdoor_presentation.gd](world/outdoor_presentation.gd) | 全域偏好驗證／保存、viewport 品質與室外色調；Canvas UI 不縮放 |
| POI 外部 | [poi_config.gd](world/poi_config.gd)、[poi_spawner.gd](world/poi_spawner.gd) | v3 四種外觀、v2 原入口、穩定 ID／返回點與註冊 |
| 副本轉場 | [poi_instance_manager.gd](world/instances/poi_instance_manager.gd)、[poi_interior.gd](world/instances/poi_interior.gd) | 獨立世界、導航、返回、探索與玩家掉落物保存 |
| 隨機地堡 | [interior_layout.gd](world/instances/interior_layout.gd)、[interior_profile.gd](world/instances/interior_profile.gd)、[bunker_content.gd](world/instances/bunker_content.gd) | 可擴充房型、隨機 1–3 層、新訪 30–60 模組目標、manifest 版本 3 與一次性內容生成 |
| 怪物 | [monster.gd](enemies/monster.gd) | AI、導航、接觸觀測、攀爬、攻擊、車撞傷害、掉落 |
| 選敵 | [combat_targeting.gd](enemies/combat_targeting.gd) | 候選排序，使用 actor 提供的接觸判斷 |
| 生存與 SAN | [player_survival.gd](player/player_survival.gd)、[player_san_effects.gd](player/player_san_effects.gd)、[player_consumables.gd](player/player_consumables.gd)、[player_sleep.gd](player/player_sleep.gd) | 飢餓與 SAN 以模擬時間推進，由目前受控的身體保存；SAN 效果只作用於受控玩家及其座位；進食一次按壓只持有一次嘗試 |
| 幻影遭遇 | [white_apparition.gd](enemies/white_apparition/white_apparition.gd)、[black_apparition_encounter.gd](world/black_apparition_encounter.gd)、[apparition_perception.gd](core/apparition_perception.gd)、[apparition_light_exposure.gd](core/apparition_light_exposure.gd) | 暫態遭遇，屬於玩家目前的 World3D；視線與局部光照判定共用 core 規則 |
| 大樓定位 | [building_locator.gd](core/building_locator.gd)、[electronic_compass.gd](props/electronic_compass.gd) | 從生成計畫查找大型建築，包含未載入區塊；指南針是唯讀 Item，不保存搜尋目標 |
| 副本室內 | [interior_profiles.gd](world/instances/interior_profiles.gd)、[interior_layout.gd](world/instances/interior_layout.gd)、[poi_interior.gd](world/instances/poi_interior.gd)、`world/instances/megashelter_interior_*.gd` | 只解析已登錄的 profile；保存的布局 manifest 是唯一真值，回訪不重抽、不補貨；樓梯間目的地由 seed 抽選並保存 |
| 巨型避難所外殼 | [modular_megashelter.gd](world/megashelter/modular_megashelter.gd)、[megashelter_plan.gd](world/megashelter/megashelter_plan.gd) | 以 seed 逐步生長封閉外殼，只描述外觀尺寸，不是可玩平面 |
| 路燈 | [roadside_streetlights.gd](world/terrain/roadside_streetlights.gd)、[streetlight.gd](world/roadside_kit/streetlight.gd) | 整排規劃後分配到地面帶；夜間開燈與故障閃爍由世界時鐘驅動 |
| 顯示 | [hud_visibility.gd](core/hud_visibility.gd)、[dark_adaptation_profile.gd](world/dark_adaptation_profile.gd) | HUD 顯示閘門獨立於各 HUD 自身狀態；暗適應只改顯示，不改模擬時間或原生光照 |
| 偏行壓迫 | [deviation_pressure.gd](world/deviation_pressure.gd) | 只負責路線壓迫判定；既有角色保留原 AI 與生命週期 |

玩家外觀由 `player.tscn/Visuals/Model` 實例化 v020 GLB，原有 11 Mesh、41 變形骨、rest pose、1.60 m 尺寸與 v021 的 17 段正式動作保留。`PlayerModelVisual` 只管理顯示，不持有移動、生命或存檔狀態。Visuals 的 Y=0.25 對齊站立膠囊底部，繞 Y 180° 對齊控制器 -Z；站立攝影機位於根座標 (0, 1.78, -0.20)，實際眼高約 1.53 m。受傷時由 [player_dismemberment.glb](assets/models/player_dismemberment/player_dismemberment.glb) 提供分件與封口網格，依原 Skin 的骨名重映射；[player_injury_animations.glb](assets/models/player_dismemberment/player_injury_animations.glb) 的六段爬行／俯臥循環重定向到同一骨架。

`PlayerBodyState` 支援五個固定切口：`head`、`left_arm`、`right_arm`、`left_leg`、`right_leg`；每個切口有身體端及斷肢端封口。`sever_part` 先擷取當下姿態，再更新部位與能力；重複或未知切口拒絕。普通 `take_damage(amount)` 保留純扣血契約；正式 Raker 咬擊只授權左臂與頭部，油桶人 `apply_explosion_hit` 可從尚存四肢抽最多兩肢，不抽頭；其餘切口亦有獨立測試場。斷肢複製當下姿態及世界速度，以獨立骨架模擬：每條整臂 2 個物理骨、整腿 3 個、頭 1 個；原角色對應物理骨停用。場內最多保留 16 組斷肢、24 秒後清理；短血噴與撕裂聲伴隨切斷，血跡最多 32 個、48 秒內清理。這些是實作的清理預算，非已量測的效能上限。

缺任一腿就改為低姿態水平膠囊（半徑 0.24 m，一腿長 1.4 m、無腿長 0.95 m）與匍匐動畫，胸腹低貼地面、前臂交替拉動、剩餘腿向後拖行。第一人稱眼位為根座標 (0, 0.58, -0.48)，平地實際眼高約 0.33 m，不繼承動畫搖擺；播放速率依每循環 0.34 m 手掌拉動、67% 支撐期及實際移速換算。初次由站立切入時以 0.45 秒倒地混合暫停主動位移，重力及 RV 支撐仍作用。雙臂可用時，一腿爬行 0.8 m/s、無腿 0.55 m/s；只剩一臂為 0.35 m/s，無臂為 0。缺腿禁止衝刺、跳躍、攀爬及駕駛；缺一臂禁止攀爬、大物持握及設備搬移，保留小物、維修與雙腿完整時的駕駛。雙臂缺失禁止拾取、使用、維修及駕駛，仍可看周圍、查看背包、丟棄及存入已有物品。失效中的操作取消，背包物品及 ID 保留；不追加失血扣血。

檢查點必要的 `player.body={version:1,present:{五個部位:boolean}}` 保存存活缺肢，讀檔與跨 World3D 沿用原玩家部位，缺少欄位時拒絕載入。死亡約兩秒後以快取的原站立碰撞檢查安全位置，成功才恢復全部部位、生命及能力；受阻持續等待。斷肢和血跡屬暫態效果，不寫入檢查點。

InteractRay 明確排除自己的玩家碰撞體，避免從較高相機往下看時命中自身膠囊。PlayerGrab 對蹲姿抓取者沿用駕駛座的 0.17 m 下拉分量，加上原 0.18 m 前拉仍在 0.25 m 上限內，保留球體掃掠與固定視角；怪物模型、骨長與原動作不變。

本地攝影機排除第 18 顯示層的完整身體／頭套，納入腳本專用第 21 層的去頭顯示副本與六個完整陰影副本。其餘五個配件沿用第 1 層；預設外部／後照鏡攝影機看完整模型，不納入第 21 層。新建副本只過濾頭部三角形索引，原 Mesh、Skin、材質與權重不改。鏡面仍使用第 20 層；自訂燈若縮限 light_cull_mask，需納入第 21 層。本地副本關閉 GI，避免重複烘焙。此契約支援現有單人及跨 World3D 轉場；多人需要按攝影機所有權擴充，尚未實作。正式玩家移除 TEST 動作，由 PlayerLocomotionVisual 讀取控制器局部速度播放 idle／jog／run 四方向循環，0.16 秒混合，不使用 root motion；跳躍依上升／下降／接地切換三段非循環姿勢，落地 0.2 秒回穩且可立即再次跳起；梯子攀爬讀取相對 RV 的實際位移選取 hold／up，下降反向播放 up，車身搬運本身不驅動步態；顯示骨架依壁面距離補有限貼牆位移，第一人稱鏡頭同步同一世界位移，避免視點與身體分離；不移動控制器，鏡頭角度仍由滑鼠控制。混合前移除上一幀骨架補償避免累加，登頂／脫離時身體與鏡頭一起收回位移；死亡交接保留當下視點，重生恢復原站立眼位。登頂辨識既有向內轉移與支撐，容許接地旗標晚一幀，接 0.3 秒收手；手動脫離接落下姿勢。抓取仍保留最後姿勢，专用動畫待後續製作；入座顯示完整坐姿，由 PlayerDrivingVisual 將骨盆對齊椅墊、雙腿對齊踏板，雙手追蹤方向盤盤緣；油門／煞車帶動腳掌，方向盤顯示轉角限制為左右各 1.25 弧度，與原本手部幅度一致，手掌固定跟隨盤緣。駕駛鏡頭沿用本地去頭顯示層，外部相機仍見完整身體。控制器同步座椅位置與傾斜，離座清除骨架覆蓋並恢復站立方向；缺臂只停用該側握盤，被抓時手臂交給抓取覆蓋。正式死亡已接入 PlayerRagdoll，固定 60 Hz，保留 Jolt 32／32；布娃娃以局部轉動慣量及角阻尼穩定關節，2026-09-27 的落地／恢復及 79 組完整回歸結果見當時驗收。

PlayerRagdoll（`player/player_ragdoll.gd`）僅持有暫態物理與死亡鏡頭，生命／模式仍由 Player 管理。完整身體以不可變 rest pose 建立 14 個物理骨，再恢復當下動畫姿勢啟動物理，沿用 v020 碰撞與關節配置，腳部質量各 2.5 kg、完整身體合計 69.5 kg；腳部局部轉動慣量使用盒體公式的 6 倍，減少空中落地時的腳踝瞬間分離，關節限制及 60 Hz／Jolt 求解器設定不變；缺失部位的物理骨停用。第 8 碰撞層與環境接觸，排除自身膠囊。死亡解除抓取、座位、攀爬、UI 和放置，繼承世界速度並停用控制膠囊。第一人稱固定死亡起始方向、平移跟隨物理頭部；斷頭時在抓取／座位清理前保存世界視點，接續跟隨獨立頭顱被銜住及落地的位置，不繼承頭顱翻滾。物理初始化前後共用同一頭部碰撞中心，球體掃掠限制鏡頭偏移。被追蹤頭顱暫用本地相機排除的第 18 顯示層，另保留本地陰影，停止死亡或移除玩家時恢復一般顯示；頭顱被清除或移往別的 World3D 時暫留最後有效位置。只有沒有獨立頭顱來源的舊無頭狀態才以軀幹為錨點。本地身體和配件在死亡期間不遮住鏡頭，外部模型與陰影按部位狀態顯示。兩秒後以原站立膠囊檢查附近地面與淨空；受阻則每 0.25 秒重試。恢復後關閉 simulator 與碰撞、重設姿勢與全部部位、恢復控制並續播正式移動動畫；恢復前將當下物理姿勢及缺肢狀態複製成獨立 CorpseProp。跨 World3D 的死亡轉場取消會清除舊頭顱追蹤，在返回位置重新綁定物理。

2026-09-22 的舊怪物 GLB 試接與 Zombie 場景已非現行敵人契約；當時的模型、膠囊縮放及原地測試動畫見[歷史資產說明](assets/models/monster/README.md)。Raker 外觀與動作由下述場景負責，油桶人使用獨立場景。

獨立 `raker.tscn` 使用 v021 左右整手網格／權重／UV 重建、54 根變形骨與三節四指动画、v019 掌向、v018 口腔與 v012 頭部／軀幹加密模型原尺寸 2.18 m，遊戲外觀等比放大 1.20 倍至 2.616 m，含立體深眼窩、凹陷嘴部與內嵌 2K 污垢膚色貼圖；`Raker` 繼承 Monster 的導航／攀爬／RV 支撐，以剩餘近戰距離和玩家的徑向退速決定地面追逐速度，以 6 m/s² 調整並限制於 6.4 m/s。伸手抓向退離中的玩家時，沿鎖定方向跟進 0.24 秒，沿用角色碰撞和抓取接觸檢查。另有獨立追車狂奔（車速 +1.2 m/s、上限 18 m/s、加速 10 m/s²）、對一般玩家抓咬掙脫、對攀爬玩家與結構保留橫掃／專用攻擊、接觸時重新驗證傷害、受傷中斷和死亡布娃娃。低姿態膠囊 1.85 m，跨破口門檻維持低姿態；站起須有淨空。41 段原地骨架動畫由 `raker_visual.gd` 切換，含低姿態受傷／落地／死亡，匯入資源不共用修改。Raker 的新遭遇限於地堡副本。新訪地堡依上述獨立種類 RNG 選擇 Raker 或油桶人。SaveSceneCatalog 登錄其場景，既有 WorldActorSnapshot 保存物種類型與 HP。資產與限制見 [Raker 說明](assets/models/raker/README.md)。

Raker 車撞效果只由 Monster 新接受撞擊後的 hook 觸發，沿用共用傷害／冷卻及 RV 結算。相對法向接近速度 ≥9 m/s（約 32 km/h；Raker.vehicle_knockdown_min_approach_speed 可調）或死亡切入 15 個 PhysicalBone3D；較輕撞擊保留 0.55 秒擊退。切換延後至碰撞查詢結束，停用控制膠囊、動畫、頭手 IK、抓咬及 AI；物理骨承接當下姿態和撞擊速度。原始 GLB／54 骨／1.2 倍外觀不改，碰撞尺寸烘入放大倍率並抵銷 body_offset basis，保持物理 scale=1。碰撞層 128／mask 1，只與環境及車體接觸，不做布娃娃肢體互撞；CCD、關節限角及局部慣量維持原專案 60 Hz／Jolt 設定。初始手腳穿過車頭接觸面時，全姿態沿法線最多推出 1.2 m；撞擊點另有短粒子與程序音效。

存活 Raker 倒地至少 2.5 秒且全部身體速度低於 1 m/s 持續 0.35 秒後，檢查附近下方支撐與完整站立淨空；受阻持續等待，以 0.8 秒姿勢混合起身。死亡將正在模擬的外觀與物理骨轉交獨立 CorpseProp，保留撞擊動量；舊 AI 殼於 18 秒後清理，屍體不隨之消失，支撐移除仍會下落。根位置跟隨骨盆，外觀世界座標獨立，避免重複位移並支援距離清理。WorldActorSnapshot 對戶外存活倒地怪新增可選 ragdoll 字典（外觀世界 transform、54 個骨局部 pose、骨盆速度），先驗證再恢復；v6 保存死亡屍體改以 Item 狀態保存，不列為存活怪物。讀檔保留倒地姿勢，肢體角速度和恢復計時不保存。
RakerGrab 是怪物的暫態抓取狀態機，PlayerGrab 持有唯一抓取者、輸入、HUD 與鏡頭鎖。靜止伸手 0.36 秒、跟進伸手 0.24 秒，結束時重新驗證雙臂可達性和遮擋，再開始固定 1 秒倒數；6–10 次需求只抽一次，60% 以整數比例判定。BITE 階段分成前撲到咬合（`BITE_CONTACT`）與咬住甩扯（`BITE_TEAR`）：咬合時只通知受害者（輕微衝擊與噴濺，不扣血），階段結束（`BITE_DURATION`）才獨立扣血一次並斷肢，避開一般受傷冷卻，同一 tick 解除存活玩家的輸入、鏡頭和 HUD；怪物自行進入 RELEASE，死亡回呼重入清理時不重啟流程。咬擊與扯離片段按遊戲時間製作、原速播放，伸手片段依實際伸手時間加速。`RakerGrab.thrash()` 是甩頭的唯一時間函式，怪物姿勢、受害者鏡頭與被咬手臂都讀它，片段裡的身體扭轉也按同一組常數製作。玩家模式 GRABBED 優先於 SEATED，save/load 沿用 NORMAL gate 拒絕，無存檔欄位變更。駕駛事件和 Chassis 輪詢輸入都封鎖，仍保留車輛物理與鬆油門回收。雙方 tree_exiting、轉場、受傷、死亡、失去接觸／支撐、強制離座共用解除入口。

達 100% 次數時完全掙脫並取得既有抓取免疫；60% 至未滿 100% 的咬擊固定扣 50 HP 並切左臂，左臂已缺失則升級為斷頭致死，未達 60% 直接咬頭致死。左臂咬擊不足 50 HP 時仍由生命歸零觸發死亡，不再額外重複傷害。`bite_part` 在倒數結束鎖定，傷害幀重新驗證缺肢與抓取者；嘴部和抓握使用同一左臂／頭部目標，爬行玩家拒絕新抓取並沿用爪擊。頭與斷臂可在口部短暫銜接，再交給獨立物理。

RakerPoseModifier 使用 SkeletonModifier3D 在動畫後依實際臉向修正三節頸骨，權重 35%／35%／30%；一般追視為 180°/s、yaw ±90°、站立上 30°／蹲姿上 40°、下壓 25°。站立 reach／hold 保留原脊椎姿勢，頸部下壓可至 70°。三種 bite 都以嘴部接觸點求解三節脊椎，每節相對輸入最多 55°，不延長骨頭；0.045–0.18 秒快速前探。頭部咬擊沿用固定視角前方的臉部接觸點，避免追逐眼睛造成反覆翻動。左臂咬擊則接近實際肩膀，從正面咬住後向外撕扯；RELEASE 短暫保留最後求解姿勢，再混回原退開動畫。斷臂使用 modifier 在骨架局部座標快取的實際嘴部位置，不能在 callback 外讀取已恢復為輸入動畫的骨姿勢。

動畫由各 actor 獨立 AnimationLibrary 播放；接近檢查與頭部抓握沿用 RakerGrab.head_grip、臂長與肘部方向。座位抓咬的接觸檢查與視覺 IK 共用有限的手肘候選路徑，逐段射線檢查後選擇向上或沿座椅側緣的可行彎曲；咬手最深處若肩部起點被椅背角落擋住，另以最多 25° 鎖骨旋轉抬開肩部，再解算手臂，不改骨長或平移軀幹。完整牆面仍會中斷抓取，輸入釋放時序不變。雙掌朝內、指根向上及玩家腦後伸展，指節向掌心屈曲，前臂分攤 65% 扭轉。玩家被抓時以同一正式骨架抬臂掙扎，沿用原本高度：空手抬雙手，持物時保留握持手、只抬空手，缺失手臂不參與；大型物品在抓取期間暫停副手握持，解除後恢復。固定 1 秒抓取期間先看向怪物臉部，即使掙扎提早達 60% 也維持臉部取景。若仍有左臂且掙扎達 60%，怪物在 HOLD 最後 0.35 秒獨立準備手臂抓握；整段 HOLD 與接觸前的 BITE 都維持開場鎖定的看臉方向，直到咬中才轉向手臂。保留手電筒握持控制與抓取前的照明狀態，關閉的手電筒也視為持物。

頭部咬擊仍在開始時鎖定前拉方向：前拉 18 cm，駕駛另下拉 17 cm，總位移約 24.8 cm；以半徑 9 cm 球體掃掠阻擋，偏移存在鏡頭父節點座標以跟隨 RV。抓取開始以 0.15 秒抬頭看向怪物，頭部咬擊保留固定視角；near 暫設至不大於 1.2 cm。存活左臂咬擊在接觸當下交還輸入並解除抓取 HUD，保留玩家身體 yaw；額外鏡頭效果在接觸後 0.16 秒轉向咬手，停留至 0.32 秒，再於 0.85 秒時恢復抓取前的視角。不把取景角寫回身體，並保留這期間的新滑鼠輸入；步行與座位鏡頭共用此流程。轉場、入座、離座、死亡與改爬行時清除恢復偏移。座位維持原輸入所有權，轉場／死亡不搶回鏡頭。傷害幀暗紅閃光獨立衰減，咬手的遮罩強度較低以保留動作可讀性。

<a id="section-3"></a>

## 3. 共用契約

共用音效由 [Sfx](core/audio/sfx.gd) 根據目前聆聽的 viewport 播放 3D 一次性事件。POI 啟用自己的 `World3D` 時，由 [PoiInstanceManager](world/instances/poi_instance_manager.gd) 切換聆聽者，聲源池只接受同一世界的來源。音檔抽選和音高使用音效服務自己的亂數。事件預設依播放位置是否在 RV 車廂內走 `Cabin` 或 `Exterior`，`Sfx` 依聆聽位置雙向套用車殼隔音。混音由 [default_bus_layout.tres](default_bus_layout.tres) 定義，音量偏好由 GameSettings 套用。

- [groups.gd](core/groups.gd)：rv、chassis、items、monster_damageable、crafting_stations、player、monsters。Item 只加入 items，不加入 monster_damageable；正式程式用 `Groups.*`，部分測試用原字串釘住契約。
- [item_names.gd](core/item_names.gd)：物品、背包、配方和材料庫名稱常數。
- [rv_connection.gd](core/rv_connection.gd)：由父節點向祖先搜尋；RV 須為 Node3D、屬 rv 群組並提供 `add_item`／`deduct_materials`，避免 Item／Chassis 預載循環。
- [climb_math.gd](core/climb_math.gd)：RV 辨識、壁面幾何、附著位移與屋頂轉移共用計算。
- [rv_support.gd](core/rv_support.gd)：記住腳下精確支撐面和 RV transform，補償固定車板缺少的平台速度；支撐刪除、換車或單步位移過大時解除。
- [world_entities.gd](core/world_entities.gd)：建立／重用場景動態容器，場景釋放後可重建。

互動採 `interact(player)`／`interact_hold(player)` 方法契約，受傷目標提供 `take_damage(amount)`。群組與祖先階層錯誤可能造成離線或候選忽略，而非編譯錯誤。

### Item 統一規格

手槍與盒裝彈藥沿用 Item；`PistolRules` 集中容量、傷害、射速、射程、換彈與瞄準參數。`PlayerWeapon` 只擁有冷卻／換彈／瞄準暫態，背包 `state.pistol.loaded_rounds`／`state.ammo.rounds` 為唯一彈量來源，手持副本不回寫。換彈完成一次交易，按背包順序扣盒內發數、移除空盒，再以手槍 ID 保持選取。`ItemState` 驗證限定場景的整數範圍（手槍 0–12、彈藥盒 1–24），v6 保存版本保持，換彈暫態不保存。射線使用玩家所在 World3D，由視線與槍口遮擋檢查結算首個碰撞體；僅 Monster 接收傷害，Item／車體／牆阻擋。槍線終點沿用最終射線結果，落空則到射程終點；第一人稱只重投影起點以銜接畫面槍口，傷害與遮擋仍用實際槍口。槍線於玩家所在 WorldEntities 固定位置並在 0.09 秒內淡出；視線至槍口受阻時只保留原命中特效，避免從牆後畫線。持槍姿勢沿用同一套真實手臂，視覺滑套／彈匣和音效不持有遊戲彈量。

新增或修改可搬運物件沿用下列共用契約。原設備的功能腳本直接繼承 Item；引擎／電池仍須裝入相容插槽才能工作。固定 EngineBay／RearRamp 及車體結構保留各自施工／互動契約，不作為可拾取 Item。

| 面向 | 統一規則與來源 |
|---|---|
| 根節點與資料 | 繼承 [Item](props/item.gd)（RigidBody3D），ItemDefinition 集中 type_id、名稱、重量、最大耐久、大小、回收、直立限制與操作淨空。persistent_id、condition、enabled 及 service 屬實例；current_health 由 condition 與 max_health 換算，不另存第二份耐久。 |
| 外觀與碰撞 | 外觀子節點與功能碰撞分離；get_placement_bounds 合併根層 CollisionShape3D，新增／替換模型時需保持可驗證的占用範圍。bottom_face 指定貼合面，放置方向由共同規則決定；車體門扇的動態掃掠另由獨立結構類別處理。 |
| 安裝與歸屬 | get_connected_rv／refresh_rv_connection 取得真正所屬車；mount_support 是精確支撐，與車輛歸屬分開。initial_support 只供新場景預裝，讀檔使用保存的支撐 ID。一般設備自由貼面，預覽與確認都須通過 PlacementRules；可安裝於存活的固定結構，車體結構本身不進設備放置流程。 |
| 可用性與清理 | can_operate 檢查實物、固定、啟用、支撐、預覽、耐久與連車。先檢查拾取容量／手臂／使用狀態，再 prepare_pickup 停機、退料及解除支撐；失敗不變更原物件。removing／tree_exiting 令依附物連鎖掉落，繼承支撐點速度；取消預覽只刪顯示副本。 |
| 資源與供電 | 能源由 VehicleEnergy 調度，材料由本車 MaterialStorage 管理；設備／UI 不另持有一份油電材料總量。交易失敗不吞資源、不重複退款；生產輸入由工作站持有，缺電暫停，搬移／摧毀安全退料，出口受阻保留工作。 |
| 受損與修復 | 所有 Item 免疫怪物傷害，選敵、接觸、腳下及實際命中均拒絕，命中物品不向底盤轉交或穿透。其他授權損傷與維修沿用 take_damage／needs_repair／repair_health；損傷外觀只讀同一耐久來源。 |
| 保存 | 場景納入 SaveSceneCatalog；capture_item_state／restore_item_state 共用 ID、condition、回收結果、enabled、service 與專用子狀態，ItemState 驗證。世界記錄另保存 fixed、transform、physics 及 support；背包不保留舊支撐。所有權跨背包、倉庫、插槽、世界、副本及分解佇列，重複 ID 拒絕保存／載入。 |
| 接入驗證 | 以正式場景驗證預設方向／淨空、安裝／取消、跨車歸屬、斷電、支撐移除、歸零、資源清理及保存還原；功能另補適用測試。物理改動以[測試場](docs/guides/playgrounds.md)做實機攀爬／支撐／拆頂檢查。 |

現行自動回歸保留 [物品操作](tests/test_item_player.gd)、[物品保存](tests/test_item_persistence.gd) 及 [檢查點失敗恢復](tests/test_checkpoint_failures.gd)。凍結設備的碰撞力矩限制仍見第 6 節；遵守上述規格不代表大型外掛物理已解決。

<a id="section-4"></a>

## 4. 狀態與所有權

| 狀態 | 擁有者 | 資料 |
|---|---|---|
| 背包 | PlayerInventory | `{name, is_large, scene_path, state}` 陣列、active_slot；state 保存 ID、condition、scrap_yields、回收結果及電池子型別資料 |
| 玩家模式 | player.gd | NORMAL／PLACING／UI／SEATED／DEAD／GRABBED，由欄位推導優先模式，非完整集中狀態機 |
| 玩家部位完整性 | PlayerBodyState | `version=1`／`present` 五個布林值；檢查點 `player.body` 必填，缺欄位拒絕載入，與暫態斷肢及血跡分開 |
| 移動 | 各 actor | NORMAL／CLIMBING、附著 RV、前一 transform、接觸寬限、冷卻、RVSupport |
| 怪物意圖 | Monster | WANDER／CHASE／ATTACK、追蹤玩家、攻擊目標 |
| 車輛 | Chassis＋VehicleEnergy＋MaterialStorage | 控制、4 輪槽身分／耐久、引擎耐久代理、電池與材料；相容屬性轉送至專責狀態 |
| 世界物品 | Item | 穩定 ID、定義、condition、啟用、固定／散落、支撐及功能狀態；手持與預覽節點為 presentation_only，不啟動服務 |
| 生產工作 | 各工作站 | 配方 ID、預留材料、剩餘電費／時間、輸入物件所有權、待出料結果 |
| 串流 | WorldGenerator | active_chunks 的 node/index/start_z/end_z、next_band、building、WorldField 和 profile |
| 副本 | PoiInstanceManager／InteriorLayout | active_id、saved_instances actor 快照、rooms／edges、局部 RNG |

地形、入口和路旁靜態模組由 chunk 擁有。動態敵人、搜刮物、玩家丟棄品、合成品和死亡掉落使用所屬世界的 WorldEntities。室內與主場景根節點都以 entity_domain metadata 指定自己的容器，避免初始 ready 時 current_scene 尚未設定而落到 SceneTree 根。WorldGenerator 只清理同一 World3D、錨點後方超過 450 m 的動態物件。玩家進副本後，錨點固定在進入前位置。

例外：主場景既有物品仍在根部，拆下輪胎、成品與掉落電池使用 WorldEntities。室內物資和怪物死亡掉落都使用室內容器。

玩家 `enter_*`／`exit_*` 授權 UI、座位與放置，呼叫方須尊重拒絕。DEAD 阻擋輸入／移動；平板和座位在玩家死亡或設備失效時釋放模式。

TabletUI 在同一平板／玩家 UI 所有權內切換 TUI 與 SHELL，開啟預設 TUI；英文管理頁為 Overview、Energy、Equipment、Crafting、Structure。隱藏 Ctrl+C／Ctrl+D 退出 TUI，q 無綁定，Esc 始終關閉整台平板；切換及關閉須清理獨立 PopupMenu，事件由目前與 popup viewport 消耗。退出 UI 捕捉仍按住的遊戲操作，放開後才恢復。有電時 shell 起始只有提示符。TUI 與 shell 共用缺電警告，供電狀態不影響 UI 所有權。歷史及輸出有上限，補全不派送命令。RVTerminalCommands 以明確登錄表解析純文字及回傳允許的 UI action，提供 help／status／rvctl／clear／exit／cheat／time／weather，不執行 OS 命令或任意程式。時間與天氣只沿已連接 RV 的祖先尋找所屬 WorldClock，不使用全域查詢，以隔離待載入世界。飛行作弊由 `cheat fly true/false/status` 操作目前終端的玩家，使用獨立 FLYING 移動狀態：相機方向 WASD、Space／Ctrl 升降、Shift 加速；跳過重力、碰撞及攀爬，沿用 UI／設定輸入鎖。關閉前檢查目前姿勢的膠囊淨空；飛行中拒絕保存，入座、死亡及世界轉場清除。三種 unlimited 旗標屬 Chassis 暫態，不進 VehicleSnapshot；成功讀檔重建車輛後重設，失敗保留原世界。VehicleEnergy 統一處理有效電力及各消耗，仍要求可用插槽與電池；燃油判斷涵蓋啟動、消耗、充電保留量及音效。免費製作以既有 job.costs 保存空字典，付費工作保存實付材料，取消與施工失敗退款依實付額，不依當下作弊開關。RVTerminalPresenter 只做英文呈現，原始服務狀態及交易仍由既有 owner 管理。施工要求 TUI 開啟，退出只取消本終端授權的施工；製作工作屬 CraftingStation，退出或關閉平板仍繼續。完整指令見 [README](README.md)；核心資源測試共用 [terminal_checks](tests/support/terminal_checks.gd)，不另增程序。

<a id="section-5"></a>

## 5. 主要流程

各流程的細節在對應的系統文件：

| 流程 | 文件 |
|---|---|
| 開局、教學與啟程 | [opening](docs/systems/opening.md) |
| 世界生成、串流與公路事件 | [world](docs/systems/world.md) |
| 場址、地堡、巨型避難所與副本轉場 | [poi](docs/systems/poi.md) |
| Item 放置、支撐與倉庫 | [items](docs/systems/items.md) |
| 能源、分解、製作與平板 | [economy](docs/systems/economy.md) |
| 駕駛、維修、車殼與車況 | [rv](docs/systems/rv.md) |
| 攀爬、戰鬥與遭遇 | [enemies](docs/systems/enemies.md) |
| 玩家身體與生存 | [player](docs/systems/player.md) |
| 時間、天氣、霧與設定 | [environment](docs/systems/environment.md) |
| 檢查點保存 | [saves](docs/systems/saves.md) |

<a id="section-6"></a>

## 6. 已知限制

- 2026-09-22 審查的 A01（搬移未通知依附物）已由 Item 共用 removing／支撐鏈掉落處理；A02–A03 的玩家 UI 重力／RVSupport 及普通動態物件遠距清理限制仍需另查。A04 的 POI 離場取消及安全清理已修正。
- POI 導航生命週期及車內每隻怪物同步重建路徑的群體成本尚未量測；不代表已重現崩潰或卡頓。
- 設備仍是獨立凍結剛體。重量／重心已彙總，但側撞與大型外掛的碰撞力矩未合併到車體；翻車、偏載、怪物群需專項實測。
- 控制、輪槽與登錄仍共用 Chassis；能源、材料、保存已抽離，後續可按需求再拆控制／掛載服務。
- 配方出料使用產物根層的實際碰撞形狀檢查；新增產品需驗證碰撞配置與出料淨空。
- 簡化載重加總底盤、存活車體結構、已安裝引擎與有效的已安裝設備，並依位置計算重心；電池本體、抽象材料、庫存道具、燃油與鬆散貨物不納入車體質量。插槽與倉庫設備本體仍計重；游離道具保留既有剛體行為。BatteryState.weight 保留供道具物理使用，VehicleSnapshot 載入後以同一 update_load 重算車重，無需存檔遷移。首版檔位不模擬離合器／轉速。
- 保存只支援室外檢查點，沒有多人所有權、室內直接保存或多槽；目前支援往返串流。
- 隨機地堡只使用 16 個當前 content_version=2 廢棄房型，已增加家具、表面破損及暗房；九類複雜設備仍以灰盒等待建模交付。完整地表設施、更多物資／敵人變化與長局平衡仍未製作。
- 真實輪驅與停車倒車測試通過，但燃油關閉的測試場不是長途資源平衡證據；未宣稱全部玩法與模擬步組合完成驗收。

<a id="section-7"></a>

## 7. 測試與慣例

測試入口、覆蓋範圍與 CI 見[測試指南](tests/README.md)；agent 另見 `godot-tests` skill。

遵循 GDScript tabs、可行時明確型別、snake_case 檔案／函式、PascalCase class、UPPER_SNAKE_CASE 常數；重用 core 契約。新增 POI 必須有有效內容，新增物品需設回收產出，設備需驗證連線／取消／毀損。
