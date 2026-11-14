# ApocalypseRV 架構

[啟動與操作](README.md) · [遊戲設計](GDD.md) · [技術架構](architecture.md)

本文件描述目前的場景結構、模組責任、共用契約、狀態所有權與主要流程。

- 版本以程式常數為準：世界生成 `world/terrain/world_profile.gd`（`generation_version`），存檔 `rv/checkpoint.gd` 與 `rv/vehicle_snapshot.gd`（`VERSION`）。
- 第 2 節只列主要子系統。完整類別清單從程式產生：`powershell -NoProfile -File scripts/agent/module-index.ps1 [關鍵字]`。
- 各功能的實作細節見[功能實作契約](docs/guides/feature-contracts.md)。歷史狀態見 git log、[驗收紀錄](docs/validation/README.md)與[封存段落](docs/archive/architecture-history-2026-11.md)。
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

專案功能標記為 4.7；開發與 CI 使用 4.7.2 stable。舊驗收紀錄中的 4.6.1 CI 是歷史資訊，不代表目前支援第二個引擎版本。

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

### 起始避難所與世界識別

`WorldProfile.opening_shelter_id()` 決定起始建築、局部整地與開場流程，與戶外生成版本分開。一般 profile 預設選擇兩室 `orientation_shelter`。Demo 在計算出生位置前複製繼承的主世界 profile，只改用按鈕開門的單間車庫。`cheat_test_profile.gd` 也覆寫建築選擇，讓 `cheat_test_world.tscn` 使用當前世界生成，同時保留單間車庫及完整起始 RV。作弊測試場沒有教學或檢查點存讀檔，預設三種資源作弊全開。

起始建築外殼擴為 50 × 45 × 14 m，封閉側翼與主樓使用原生幾何完成立面，僅獨立屋頂設備保留灰盒；中央車庫與活動門接口保留。場址 Resource 的 bounds 同步管理整地／植被排除，側後方土坡依 building_bounds 計算。外殼的靜態盒碰撞以 navigation_solid 標記，ChunkGenerator 將其轉成投影障礙，避免碰撞盒下方留下可走地形；鄰區重建沿用相同標記。模型需求與本輪驗收見 [擴建紀錄](docs/validation/2026-10-01-shelter-expansion.md)。

Checkpoint 要求 `world_id=shelter`、當前生成版本與完整 `start_state`；只載入受信任的 `world/main_world.tscn`。StartRun v1 要求 phase 為 preparing／started／sealed、一個 bay gate 布林值與當前兩室教學。門移動期間拒絕保存。恢復開場狀態發生於子節點 ready 前，動態物件完成轉移後重新套用敵人狀態。

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

本地攝影機排除第 18 顯示層的完整身體／頭套，納入腳本專用第 21 層的去頭顯示副本與六個完整陰影副本。其餘五個配件沿用第 1 層；預設外部／後照鏡攝影機看完整模型，不納入第 21 層。新建副本只過濾頭部三角形索引，原 Mesh、Skin、材質與權重不改。鏡面仍使用第 20 層；自訂燈若縮限 light_cull_mask，需納入第 21 層。本地副本關閉 GI，避免重複烘焙。此契約支援現有單人及跨 World3D 轉場；多人需要按攝影機所有權擴充，尚未實作。正式玩家移除 TEST 動作，由 PlayerLocomotionVisual 讀取控制器局部速度播放 idle／jog／run 四方向循環，0.16 秒混合，不使用 root motion；跳躍依上升／下降／接地切換三段非循環姿勢，落地 0.2 秒回穩且可立即再次跳起；梯子攀爬讀取相對 RV 的實際位移選取 hold／up，下降反向播放 up，車身搬運本身不驅動步態；顯示骨架依壁面距離補有限貼牆位移，第一人稱鏡頭同步同一世界位移，避免視點與身體分離；不移動控制器，鏡頭角度仍由滑鼠控制。混合前移除上一幀骨架補償避免累加，登頂／脫離時身體與鏡頭一起收回位移；死亡交接保留當下視點，重生恢復原站立眼位。登頂辨識既有向內轉移與支撐，容許接地旗標晚一幀，接 0.3 秒收手；手動脫離接落下姿勢。抓取仍保留最後姿勢，专用動畫待後續製作；入座顯示完整坐姿，由 PlayerDrivingVisual 將骨盆對齊椅墊、雙腿對齊踏板，雙手追蹤方向盤盤緣；油門／煞車帶動腳掌，方向盤顯示轉角限制為左右各 1.25 弧度，與原本手部幅度一致，手掌固定跟隨盤緣。駕駛鏡頭沿用本地去頭顯示層，外部相機仍見完整身體。控制器同步座椅位置與傾斜，離座清除骨架覆蓋並恢復站立方向；缺臂只停用該側握盤，被抓時手臂交給抓取覆蓋。正式死亡已接入 PlayerRagdoll，固定 60 Hz，保留 Jolt 32／32；布娃娃以局部轉動慣量及角阻尼穩定關節，2026-09-27 的落地／恢復及 79 組完整回歸結果見當時驗收。見 [角色整合驗收](docs/validation/2026-09-27-player-model-integration.md)與[死亡布娃娃驗收](docs/validation/2026-09-27-player-death-integration.md)。

PlayerRagdoll（`player/player_ragdoll.gd`）僅持有暫態物理與死亡鏡頭，生命／模式仍由 Player 管理。完整身體以不可變 rest pose 建立 14 個物理骨，再恢復當下動畫姿勢啟動物理，沿用 v020 碰撞與關節配置，腳部質量各 2.5 kg、完整身體合計 69.5 kg；腳部局部轉動慣量使用盒體公式的 6 倍，減少空中落地時的腳踝瞬間分離，關節限制及 60 Hz／Jolt 求解器設定不變；缺失部位的物理骨停用。第 8 碰撞層與環境接觸，排除自身膠囊。死亡解除抓取、座位、攀爬、UI 和放置，繼承世界速度並停用控制膠囊。第一人稱固定死亡起始方向、平移跟隨物理頭部；斷頭時在抓取／座位清理前保存世界視點，接續跟隨獨立頭顱被銜住及落地的位置，不繼承頭顱翻滾。物理初始化前後共用同一頭部碰撞中心，球體掃掠限制鏡頭偏移。被追蹤頭顱暫用本地相機排除的第 18 顯示層，另保留本地陰影，停止死亡或移除玩家時恢復一般顯示；頭顱被清除或移往別的 World3D 時暫留最後有效位置。只有沒有獨立頭顱來源的舊無頭狀態才以軀幹為錨點。本地身體和配件在死亡期間不遮住鏡頭，外部模型與陰影按部位狀態顯示。兩秒後以原站立膠囊檢查附近地面與淨空；受阻則每 0.25 秒重試。恢復後關閉 simulator 與碰撞、重設姿勢與全部部位、恢復控制並續播正式移動動畫；恢復前將當下物理姿勢及缺肢狀態複製成獨立 CorpseProp。跨 World3D 的死亡轉場取消會清除舊頭顱追蹤，在返回位置重新綁定物理。斷頭鏡頭驗證見 [斷肢驗收補記](docs/validation/2026-10-03-player-dismemberment.md#head-camera-20261004)；既有動作與關節交接歷史驗收見 [v021 動作驗收](docs/validation/2026-09-27-player-animations-v021.md)。

2026-09-22 的舊怪物 GLB 試接與 Zombie 場景已非現行敵人契約；當時的模型、膠囊縮放及原地測試動畫見[歷史資產說明](assets/models/monster/README.md)與[驗收](docs/validation/2026-09-22-monster-model.md)。Raker 外觀與動作由下述場景負責，油桶人使用獨立場景。

獨立 `raker.tscn` 使用 v021 左右整手網格／權重／UV 重建、54 根變形骨與三節四指动画、v019 掌向、v018 口腔與 v012 頭部／軀幹加密模型原尺寸 2.18 m，遊戲外觀等比放大 1.20 倍至 2.616 m，含立體深眼窩、凹陷嘴部與內嵌 2K 污垢膚色貼圖；`Raker` 繼承 Monster 的導航／攀爬／RV 支撐，以剩餘近戰距離和玩家的徑向退速決定地面追逐速度，以 6 m/s² 調整並限制於 6.4 m/s。伸手抓向退離中的玩家時，沿鎖定方向跟進 0.24 秒，沿用角色碰撞和抓取接觸檢查。另有獨立追車狂奔（車速 +1.2 m/s、上限 18 m/s、加速 10 m/s²）、對一般玩家抓咬掙脫、對攀爬玩家與結構保留橫掃／專用攻擊、接觸時重新驗證傷害、受傷中斷和死亡布娃娃。低姿態膠囊 1.85 m，跨破口門檻維持低姿態；站起須有淨空。41 段原地骨架動畫由 `raker_visual.gd` 切換，含低姿態受傷／落地／死亡，匯入資源不共用修改。Raker 的新遭遇限於地堡副本。新訪地堡依上述獨立種類 RNG 選擇 Raker 或油桶人。SaveSceneCatalog 登錄其場景，既有 WorldActorSnapshot 保存物種類型與 HP。資產與限制見 [Raker 說明](assets/models/raker/README.md)。

Raker 車撞效果只由 Monster 新接受撞擊後的 hook 觸發，沿用共用傷害／冷卻及 RV 結算。相對法向接近速度 ≥9 m/s（約 32 km/h；Raker.vehicle_knockdown_min_approach_speed 可調）或死亡切入 15 個 PhysicalBone3D；較輕撞擊保留 0.55 秒擊退；本輪驗證見 [門檻調整](docs/validation/2026-10-10-raker-impact-threshold.md)。切換延後至碰撞查詢結束，停用控制膠囊、動畫、頭手 IK、抓咬及 AI；物理骨承接當下姿態和撞擊速度。原始 GLB／54 骨／1.2 倍外觀不改，碰撞尺寸烘入放大倍率並抵銷 body_offset basis，保持物理 scale=1。碰撞層 128／mask 1，只與環境及車體接觸，不做布娃娃肢體互撞；CCD、關節限角及局部慣量維持原專案 60 Hz／Jolt 設定。初始手腳穿過車頭接觸面時，全姿態沿法線最多推出 1.2 m；撞擊點另有短粒子與程序音效。

存活 Raker 倒地至少 2.5 秒且全部身體速度低於 1 m/s 持續 0.35 秒後，檢查附近下方支撐與完整站立淨空；受阻持續等待，以 0.8 秒姿勢混合起身。死亡將正在模擬的外觀與物理骨轉交獨立 CorpseProp，保留撞擊動量；舊 AI 殼於 18 秒後清理，屍體不隨之消失，支撐移除仍會下落。根位置跟隨骨盆，外觀世界座標獨立，避免重複位移並支援距離清理。WorldActorSnapshot 對戶外存活倒地怪新增可選 ragdoll 字典（外觀世界 transform、54 個骨局部 pose、骨盆速度），先驗證再恢復；v6 保存死亡屍體改以 Item 狀態保存，不列為存活怪物。讀檔保留倒地姿勢，肢體角速度和恢復計時不保存。驗收與輪驅重播見 [Raker 車撞布娃娃](docs/validation/2026-10-02-raker-impact-ragdoll.md)。
RakerGrab 是怪物的暫態抓取狀態機，PlayerGrab 持有唯一抓取者、輸入、HUD 與鏡頭鎖。靜止伸手 0.36 秒、跟進伸手 0.24 秒，結束時重新驗證雙臂可達性和遮擋，再開始固定 1 秒倒數；6–10 次需求只抽一次，60% 以整數比例判定。咬合第 0.22 秒獨立扣血一次，避開一般受傷冷卻，同一 tick 解除存活玩家的輸入、鏡頭和 HUD；怪物自行進入 0.35 秒 RELEASE，死亡回呼重入清理時不重啟流程。Blender 咬合原在 0.38 秒，以 BITE_SPEED（0.38／0.22）同步加速，咬擊混合縮至 0.035 秒；伸手動畫以 0.6／0.36 倍速播放。玩家模式 GRABBED 優先於 SEATED，save/load 沿用 NORMAL gate 拒絕，無存檔欄位變更。駕駛事件和 Chassis 輪詢輸入都封鎖，仍保留車輛物理與鬆油門回收。雙方 tree_exiting、轉場、受傷、死亡、失去接觸／支撐、強制離座共用解除入口。

達 100% 次數時完全掙脫並取得既有抓取免疫；60% 至未滿 100% 的咬擊固定扣 50 HP 並切左臂，左臂已缺失則升級為斷頭致死，未達 60% 直接咬頭致死。左臂咬擊不足 50 HP 時仍由生命歸零觸發死亡，不再額外重複傷害。`bite_part` 在倒數結束鎖定，傷害幀重新驗證缺肢與抓取者；嘴部和抓握使用同一左臂／頭部目標，爬行玩家拒絕新抓取並沿用爪擊。頭與斷臂可在口部短暫銜接，再交給獨立物理。

RakerPoseModifier 使用 SkeletonModifier3D 在動畫後依實際臉向修正三節頸骨，權重 35%／35%／30%；一般追視為 180°/s、yaw ±90°、站立上 30°／蹲姿上 40°、下壓 25°。站立 reach／hold 保留原脊椎姿勢，頸部下壓可至 70°。三種 bite 都以嘴部接觸點求解三節脊椎，每節相對輸入最多 55°，不延長骨頭；0.045–0.18 秒快速前探。頭部咬擊沿用固定視角前方的臉部接觸點，避免追逐眼睛造成反覆翻動。左臂咬擊則接近實際肩膀，從正面咬住後向外撕扯；RELEASE 短暫保留最後求解姿勢，再混回原退開動畫。斷臂使用 modifier 在骨架局部座標快取的實際嘴部位置，不能在 callback 外讀取已恢復為輸入動畫的骨姿勢。

動畫由各 actor 獨立 AnimationLibrary 播放；接近檢查與頭部抓握沿用 RakerGrab.head_grip、臂長與肘部方向。座位抓咬的接觸檢查與視覺 IK 共用有限的手肘候選路徑，逐段射線檢查後選擇向上或沿座椅側緣的可行彎曲；咬手最深處若肩部起點被椅背角落擋住，另以最多 25° 鎖骨旋轉抬開肩部，再解算手臂，不改骨長或平移軀幹。完整牆面仍會中斷抓取，輸入釋放時序不變；回歸見 [CI 玩家與 Raker 修正](docs/validation/2026-10-05-ci-player-raker.md)。雙掌朝內、指根向上及玩家腦後伸展，指節向掌心屈曲，前臂分攤 65% 扭轉。玩家被抓時以同一正式骨架抬臂掙扎，沿用原本高度：空手抬雙手，持物時保留握持手、只抬空手，缺失手臂不參與；大型物品在抓取期間暫停副手握持，解除後恢復。固定 1 秒抓取期間先看向怪物臉部，即使掙扎提早達 60% 也維持臉部取景。若仍有左臂且掙扎達 60%，怪物在 HOLD 最後 0.35 秒獨立準備手臂抓握；整段 HOLD 與接觸前的 BITE 都維持開場鎖定的看臉方向，直到咬中才轉向手臂。保留手電筒握持控制與抓取前的照明狀態，關閉的手電筒也視為持物。

頭部咬擊仍在開始時鎖定前拉方向：前拉 18 cm，駕駛另下拉 17 cm，總位移約 24.8 cm；以半徑 9 cm 球體掃掠阻擋，偏移存在鏡頭父節點座標以跟隨 RV。抓取開始以 0.15 秒抬頭看向怪物，頭部咬擊保留固定視角；near 暫設至不大於 1.2 cm。存活左臂咬擊在接觸當下交還輸入並解除抓取 HUD，保留玩家身體 yaw；額外鏡頭效果在接觸後 0.16 秒轉向咬手，停留至 0.32 秒，再於 0.85 秒時恢復抓取前的視角。不把取景角寫回身體，並保留這期間的新滑鼠輸入；步行與座位鏡頭共用此流程。轉場、入座、離座、死亡與改爬行時清除恢復偏移。座位維持原輸入所有權，轉場／死亡不搶回鏡頭。傷害幀暗紅閃光獨立衰減，咬手的遮罩強度較低以保留動作可讀性。見 [咬手第一人稱驗收](docs/validation/2026-10-03-player-arm-bite-pov.md)；[固定抓咬視角](docs/validation/2026-09-24-raker-fixed-grab-view.md) 保留為頭部咬擊的歷史驗收。

<a id="section-3"></a>

## 3. 共用契約

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
| 接入驗證 | 以正式場景驗證預設方向／淨空、安裝／取消、跨車歸屬、斷電、支撐移除、歸零、資源清理及保存還原；功能另補適用測試。物理改動依 playtest skill 做實機攀爬／支撐／拆頂檢查。 |

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

### 世界

WorldGenerator 建立 WorldField／WorldProfile／POISpawner → 正式 v9 初始後 2／目前 1／前 2 個固定網格帶（共用 profile 保留前 3 帶） → 查詢區域／道路／停靠計畫 → 共用整地結果生成地表、路面與碰撞 → 安置靜態內容 → 烘焙導航並生成動態內容。行駛中的建立分多影格執行，完成前不發佈到 active_chunks；一次只有一個建立作業。

串流比較室外玩家或副本錨點 Z，維護前後窗口並可回頭載入。WorldField 以世界座標計算有界道路曲線，WorldProfile 預設生成 `WorldProfile.CURRENT_GENERATION`、路寬 15／10 m、坡度上限 8%、區域長 900 m／過渡 240 m。獨立 RNG 域隔離道路、停靠、地形、外觀、物資及敵人，場址 ID 固定當前格式。Checkpoint 要求完整 profile 與相同的 generation_version，不使用舊版預設。

外部停靠點位置為 index×450±75 m。v4 起始維修廠位於 (335.2,6,-45)，v3 保留 (135,6,-45)，每三點兩個離路入口、一個小補給；v2 保留 (49,0,-45) 近路維修站與原比例。ExplorationSite 以道路局部座標建立左右及前後鏡像模板，檢查完整場址是否落在版本對應碰撞帶內（v4 寬 900 m，v2／v3 寬 450 m），必要時改向另一側；無無限重抽。WorldField.surface 將場址平台、緩坡、步道及保留區整合到共用取樣，公路高度優先。spawn_site 使用同一份 building/road/frame/id/seed，外觀不消耗物資 RNG。四款外觀沿用既有入口及副本。

地形網格使用相鄰取樣圈計算法線，邊界共享世界位置及高度。v4／v3 導航分別涵蓋 900／450 m 寬碰撞帶，cell_size=0.25 m；v2 維持 240 m／0.5 m。使用實體碰撞，排除高 7 cm 的重複瀝青層，補相鄰地形、圍牆與建築碰撞資料；邊界資料由共用計畫提供，不依賴相鄰 chunk 載入順序。v3／v4 高容許 detail 誤差抑制噪音坡面新增的重疊細三角形，可通行輪廓仍由 voxel 決定；v2 保留原設定。非同步烘焙後發佈獨立 NavigationMesh，navigation_ready 等待 region 和 map 真正同步，避免初始空網格。怪物地面高低差仍使用導航；path_height_offset 對齊角色腳底；落地且已到達路徑點水平範圍時，以實際腳下高度推進路徑點，避免簡化網格埋入土坡造成繞圈。未移動的目標不重複重設路徑；移動目標維持 0.25 秒更新間隔。

場址牆段依中心 Z 歸唯一 chunk；整地跨帶查詢同一計畫。玩家位於場址 bounds 或室內 stream_anchor 時，protected_bands 保留並補建停車區、路線及建築的區塊與 halo。ForestScenery 以獨立 RNG 的 8 m 網格抖動形成樹林與可撞毀灌叢，逐列分幀規劃，樹幹簡化碰撞也提供相鄰導航 halo；快取至多 16 個帶。ForestMeshes 快取四款不對稱針葉樹、兩款枯樹與三款灌叢，共九批 MultiMesh；forest_art_variants 獨立亂數只選外觀，不改既有樹位、碰撞與 seed。遠景左右及前方網格只提供視覺。新造景延續分幀建立，build_ms／max_slice_ms 記錄成本。

世界細節分兩層，都只是「視覺＋實體障礙」，不產生物資或敵人：

- **地形特徵層** [WorldFeatures](world/terrain/world_features.gd)（`WorldField.features`）：每 300 m 一格，只用未混合的原始地形規劃池塘／湖、泥土支線與盡頭空地、路旁與野地場景地塊、高壓電塔；一格完整擁有其特徵，規劃絕不呼叫 `surface()`。`WorldField.surface()` 經 `apply()` 套用水面、岸邊、路床高度與保留區，另回傳 `occupied`（不含路肩保留）與 `track`（寫入地形頂點色 alpha，供 `terrain_v14.gdshader` 畫泥路）。[FeatureBuilder](world/scatter/feature_builder.gd) 把特徵建成節點，遺跡小場景來自 [VignetteKit](world/scatter/vignette_kit.gd)。
- **散佈圖層** [ScatterScenery](world/scatter/scatter_scenery.gd)：[ScatterCatalog](world/scatter/scatter_catalog.gd) 列出規則（[ScatterLayer](world/scatter/scatter_layer.gd)），每層有獨立 RNG 流 `scatter_<id>`、各地貌權重與程序化網格（[ScatterMeshes](world/scatter/scatter_meshes.gd)）。規劃讀區塊的 [TerrainGrid](world/terrain/terrain_grid.gd)，物件貼在玩家看到的三角面上；實體散佈離帶接縫與路緣保留間距，路肩留給 RoadSpawns。

道路細節由 [RoadDetails](world/terrain/road_details.gd) 建立：路面著色條（`road_surface.gdshader`）、碎石路肩、電線桿與電線、彎道標誌及標柱，全部是路線的純函數，鄰帶可描述彼此的電線桿。標誌、標柱與圍欄是 [BreakableProps](world/scatter/breakable_props.gd)：只在 `TreeImpact.SHRUB_LAYER` 與 RV 碰撞，每個目標以 `vehicle_speed_retained` 決定 RV 撞擊後保留的速度比例，撞倒後以 `roadside:` 鍵寫入 `destroyed_trees` 帳本。樹木仍由 ForestScenery 管，因為倒樹與存檔契約綁在它身上。

室外日夜照明由 WorldClock 控制，Forward+ 使用局部體積霧與遠景距離霧，Compatibility 降級只保留距離霧。GameSettings autoload 管理全域顯示、輸入與音量偏好；Esc SettingsMenu 是設定入口，F8 不再處理顯示。值在載入與寫入時檢查型別、有限值及範圍；缺漏或非法持久化欄位各自回預設。偏好寫入獨立 ConfigFile，不進角色／車輛或 Checkpoint 快照，短時間多次滑桿變更合併保存，關閉選單時 flush，錯誤由 save_completed 與 last_save_error 回報。偏好僅使用目前設定格式，舊顯示設定不遷移。

register_viewport 把 3D 縮放、抗鋸齒與陰影品質套用到主 viewport 及新建立的室內 SubViewport。舊解析度模式維持室外目標高度 540、最高 1，室內原生解析度；手動 50–100% 解析度同時套用室內外。復古色調與解析度分開，亮度／對比／飽和度使用 3D 後製，Canvas UI 保持清晰。品質預設只修改解析度、抗鋸齒、陰影與霧，其他欄位不變，個別品質調整後保留「自訂」來源，即使數值又與預設相同也不自動改回；此來源隨偏好保存，只有明確選取預設或重設顯示頁才切回預設。霧品質只影響體積霧，不改距離霧、WorldClock 天氣或光照；Compatibility 的體積霧控制不可用。視窗模式使用確認倒數，取消或逾時回復原設定；headless 不可驗證原生視窗輸出。

啟動預設全螢幕，已保存的視窗模式仍優先；視窗模式的初始尺寸為 1280×720。GameSettings 在獨立視窗啟動時，若超出螢幕可用區域的 90%，等比例縮小並置中，保留標題列與工作列空間。嵌入編輯器及 headless 不調整原生視窗。`UILayout` 共用血條、快捷列、設定、平板、教學終端與倉庫的 CanvasLayer 縮放：以 1280×720 放大高解析度 UI，小視窗則保留至少 960×540 的邏輯佈局並縮小顯示；寬螢幕保留額外寬度，平板依邏輯寬度切換欄數。每幀只比較目前 viewport 尺寸，變更才更新，因此玩家移入室內 SubViewport 後仍可適應縮放。原生 3D 尺寸與解析度比例獨立；邊界、錨點、縮放點擊與 viewport 搬移的歷史驗收見 [UI 紀錄](docs/validation/2026-10-03-settings-ui.md)，目前需另行畫面檢查。

SettingsMenu 不設定 SceneTree.paused，玩家 settings_open 是額外輸入遮罩。Player、互動射線、DriverSeat 與 Chassis 共同使用 is_gameplay_input_blocked，涵蓋事件與 held-key 輪詢；關閉時記錄仍按住的操作，放開後才恢復。重力、傷害冷卻、車頂支撐、世界時間、敵人與油電照常推進。駕駛期間釋放油門／腳煞車／轉向，不改引擎、gear 或 handbrake。平板與放置擁有各自 Esc 優先權；被抓、死亡、讀檔及 POI 轉場時拒絕設定入口，失去 actor 所有權時關閉。步行／駕駛 FOV 與滑鼠設定從服務即時更新現有及新建立的相機。

設定介面的 bool 控制使用 ButtonGroup 互斥「關／開」按鈕，勾選與背景共同表示狀態，容器不加入焦點輪巡。畫質組合 0 在 UI 命名「遊戲預設」，不改既有偏好欄位或預設值；render_mode 0／1 顯示「依場景自動／自訂比例」。解析度摘要讀玩家所在 viewport 的實際尺寸及 scaling_3d_scale，開啟期間持續更新，避免把尚未使用的儲存比例當成目前畫面，並支援室內與視窗縮放。自動模式隱藏比例滑桿。

`InteriorLayout` 生成版本 3 manifest，新訪隨機目標 30–60 模組、1–3 層，透過完整 socket transform 接合與三維 AABB 排斥擴展；候選／接口耗盡可提早停止。樓梯與新層首房原子安置，普通分類按 Profile 權重抽選，各層共用。`InteriorRoomDefinition` 以 ID＋內容版本解析，場景提供 footprint／clear_height／socket，新增普通尺寸／分類不改生成器。已保存 v3 manifest 原樣讀取，不套新房數目標。

`PoiInterior` 統一組裝、封牆、導航、探索、出生／出口與玩家掉落物保存。未接通 socket 的門框移除，牆板留在自身占地內，避免共享可見面閃爍。導航發布 immutable mesh 並等待 region／map 同步。`BunkerContent` 在初訪用獨立 RNG 配置深處一具 70% 耐久強化引擎，以及上限 2–12 件散落物、1–5 個各含兩件小型物資的補給箱；合法位置不足時不強行達標。敵人生成最多嘗試 `clamp(房間數 / 15, 1, 4)` 個合格房間，每次獨立以 30% 機率從可擴充候選池選出 Raker，因此可沒有敵人，也可有多隻。合格房間避開入口 24 m 房間連接距離及 18 m 空間距離。`BunkerCache` 使用靜態碰撞與分離視覺；玩家長按 E 1 秒，一次領一件，背包拒收不刪物。地圖按實際占用及保存層距繪製 B1–B3，只顯示樓層、房間輪廓、連線與樓梯圖示；2026-11-08 移除常駐房名、房數、目標位置及返回／按鍵說明，探索記錄仍持續更新。

保存實際布局與內容，不依 seed 重抽；`CheckpointSchema` 驗證逐房版本、接口對齊、占用、連通、內容與補給箱快照。剩餘補給品保留 Item 完整狀態與 ID，活 actor 保留位置及生命；既有布局不補抽新物資。新增目錄／修改權重不改變已訪布局，缺失或不支援版本拒絕。Checkpoint 只接受 v6，不再轉換或清除 pre-bunker 舊資料，舊檔保持原樣。原生成器／專用資產已移除。詳見 [地堡契約](docs/guides/bunker-interior.md)。

PoiInstanceManager 在入口互動後鎖定玩家輸入、建立 own_world_3d 的 SubViewport，完成載入後 reparent 原玩家與 UI。根 CanvasLayer 顯示 viewport texture，輸入轉交子 viewport，視窗縮放同步。室內設定開啟時，根合成層由 20 提升至 60 並隱藏室外 POI 標題；關閉後恢復，避免室外 HUD 蓋住選單。正常退出先保存室內 Item、活怪與補給箱的完整剩餘狀態，再把原玩家移回主世界並檢查返回落點，釋放副本幾何。saved_instances 供同局重返重建相同布局與內容；室外檢查點把這份資料一併寫入磁碟。非活動副本不繼續模擬。轉場有明確狀態與操作序號；離場取消沿共用安全收尾路徑保存室內狀態、恢復控制並清理暫建 viewport。

WorldEntities.same_world 用於群組選敵、碰撞例外及串流清理；怪物每 physics tick 清掉跨世界的快取玩家目標。只有原玩家與背包透過入口轉移；原設備作為背包 Item 可帶進地堡並放置。實例快照共用 Item／Monster，保存室內散落與固定物品，未連接 RV 的原設備不提供車輛服務。

地堡新增 16 個房間內容版本 2，只接受目前內容版本，布局仍為 version 3。新版家具碰撞獨立於 Visuals/Model；封牆沿用所在房間的牆／塗裝材質。BunkerLighting 以保存 seed、room ID 與固定版本字串做 SHA-256 排序，選出四捨五入後 60% 的普通模組熄燈，排除 entry／stairs；不消耗布局或內容 RNG，不增加存檔欄位。舊房間內容版本直接拒絕。

Flashlight 是小型 Item，初始世界以場景實例放在地面。`state.flashlight={charge,on}` 使用獨立欄位，不能混用 RV 的 `state.battery`；VehicleSnapshot 驗證有限 0–100 電量和開關型別，SaveSceneCatalog 明確登錄場景。玩家背包狀態為耗电真值，手持節點只鏡射 Spotlight；在 NORMAL、選取且可見照明時按 100/300 每秒扣電。PlayerGrab 在抓取開始前記錄實際亮燈狀態；原本亮著的手電筒在 GRABBED 期間保持可見、正常耗電，由持物姿勢將燈頭朝向抓取者臉部，解除後恢復一般朝向。切換、丟棄及倉庫移轉在序列化前關燈；模式暫停不耗電。讀檔用原 actor 替換流程清除初始地面實例，不另補發。

### Item 放置與支撐

固定物品長 F 兩秒 → 檢查容量／雙手／使用狀態 → 停止服務並拾取；長按成功抑制同次 F 短按。手持短 F 在放開時進入 EquipmentPlacement，背包仍擁有物品，另建 presentation_only ghost；預覽期間暫時隱藏手持模型，只顯示目標輪廓，取消時恢復手持顯示。PlacementRules 檢查所有碰撞層、朝向、操作空間及支撐循環，允許靜態表面、固定結構與固定 Item，拒絕散落物、角色、活動門扇與坡板。左鍵重新檢查位置、距離、手臂及 inventory slot／ID，建立實物並成功固定後才消耗背包；右鍵／Esc 保留物品，G 取消後丟出。

ItemMount 分開管理本車歸屬與 mount_support：固定於 RV 的物品登錄本車，靜態表面上的物品仍歸 WorldEntities。支撐 removing／tree_exiting 先停機，再延後解除固定，帶支撐點速度恢復物理。牆壁拆掉，上面的設備／其他 Item 會掉落成可拾取物；ID、耐久及內容物保留。移除底層物品令其上物品分別掉落，不收進同一背包。工作台退未完成材料、分解機釋放投入物、電池插槽另行掉電池，道具箱移除不清空底盤倉庫；共用停止入口避免重複退料。

### 能源、道具與生產

BatterySocket 繼承 Item 並保存 installed_battery；VehicleEnergy 透過弱參照查詢底盤的有效插槽，Chassis.current_power/max_power 保留代理介面。同車最多接通一顆電池，未接入的背包／倉庫電池不參與供電。搬移開始、支撐脫落或損壞時，插槽將 BatteryState 轉成世界 Item 並清空自己；掉落點在車體外，繼承車輛點速度。取消搬移不自動收回。

底盤直接保存 current_fuel/max_fuel；FuelPort 只提供加油交易，拆除、損壞或多裝入口均不改變存量／容量。BatterySocket 交換先檢查新電池與舊電池去處，滿背包使用原槽位；沒有有效插槽就沒有隱藏電量。

Chassis 物理步呼叫 VehicleEnergy：扣引擎油耗 → 依平板設定執行內建充電 → 電池待機支出 → 工作站 step_work。充電預設啟用，門檻 80%、燃油保留 5；每秒最多發電 1.8、額外耗油 0.6，並另計引擎燃油。電量不高於門檻時開始充電，滿電或達到保留油量時停止額外充電；無油停止引擎。v6 檢查點以必要 charging 字典保存設定；舊版便攜發電機記錄驗證拒絕，不遷移。玩家進副本時室外照常模擬。

Item 或屍體所屬 PhysicalBone 進 HopperArea → Scrapper 解析整具屍體並取得唯一 processing_owner，保存物理快照 → 一個處理槽分步付費 → 固定一次回收結果 → MaterialStorage 接受後才刪物。缺電保留進度；滿庫保留完成結果；供電／佇列可用時重試料斗內尚未接收的重疊物；拆卸／摧毀恢復輸入物理。

一般剛體由 ScrapperFeedMotion 收集實際 mesh／collider 的變換邊界。料斗感測涵蓋保守的 0.87 m 開口與槽底至邊框上方（局部 Y 0.07–1.375 m）。接收依實際幾何與碰撞接觸，不要求物件原點或外接框中心置中；大型物件已歪斜卡入也會重試接收。足跡過大的物件須實際碰到中央 0.6 m 料道，且在兩軸有足夠重疊；側面及斜跨角落的擦框不接管。小物限制每步旋轉，使全部角點位於保守的 0.87 m 開口。大型或足跡過大的 Item 改由 ScrapperContactFeed 保留連續表面；建立時細分原三角形，保留 UV、StandardMaterial3D 基色／法線貼圖、UV 變換與主要 PBR 數值。上方共用完整剛體姿勢，實際旋轉後最低點碰到刀齒才建立咬合；七次短暫停頓／拉入搭配約 20° 傾倒，下方 1.08 m 以下局部折皺，0.84 m 以下完整收進保守開口，0.705 m 刀面不規則裁切。輪胎減少金屬折皺幅度；局部法線依變形重算。網格只建立一次，後續以進度驅動 shader，不再生成空中方塊。原 Item 保持尺度、產量、耐久、ID 與 processing_owner；視覺 helper 無碰撞或獨立收益。取消還原原物品姿勢、可見度、材質和碰撞，完成或輸入失效時清除全部效果節點。

service.inputs 可選 feed.start／feed.pose 保存完整局部變換；大型輸入另存有限且介於 0–1 的 feed.progress。載入以初始姿勢及進度確定性重建接觸變形，停電或零時間工作不推進；尚未建立視覺 helper 時重新保存也保留 saved_feed。ItemState 驗證有限 Transform3D 與進料進度，兼容既有沒有 feed 的保存。

活體進 HopperArea 時先驗證實際重疊且身體中心進入口、同世界、供電與可用容量，同步以弱引用登記唯一 actor／佇列預留，再延後致死，避免在物理訊號中修改碰撞。執行前重驗條件；取消、轉移與失效會釋放預留。Player 先死亡並保留完整物理骨；成功付費的工作步施加咬入衝量，至少相隔 0.15 秒切離一個實際接觸滾輪的部位（頭最後）。切離前捕捉求值後的骨姿勢與線／角速度，移除原骨架的相應碰撞鏈，避免重複物理；全部部位切離後才複製 CorpseProp 軀幹；玩家停掉原骨架物理並隱藏，保留鏡頭、計時器與背包，復活不重留屍體。Raker 使用其既有 corpse_prop；BarrelMan／SlenderSpeaker 保留原特殊死亡語義。裝置快照仍只保存正式屍體輸入，暫態預留不存檔；斷肢為無收益效果，以獨立 PhysicalBone 與衝量吸入、缺電停止切割計時、停止時恢復原材質並釋放鬆散物理。安全復活查詢另排除有電 HopperArea。 ScrapperCrushEffect 由正式設備持有，重用七組 CPUParticles3D（總預算 286 粒）與共享合成 WAV；僅成功付費的正時間 step_work 推進特效，使用輸入 ID 切換首次噴濺，成功材料入庫才觸發完成噴濺。粒子採世界座標、沒有碰撞／收益／存檔；拆卸清除尾跡，沒有服務心跳或失去供電則停音停射。驗收見 [活體分解](docs/validation/2026-10-10-scrapper-living.md)。

CorpseProp（`props/corpse.tscn`）共用玩家／Raker 的既有模型、碰撞體與關節。凍結的第 2 層球形代理跟隨骨盆，提供 E 拾取及分解機偵測；鬆散屍體以第 8 層 PhysicalBone 模擬落地。大型道具需要雙手並鎖定手持欄位，沿用背包／倉庫規則。手持時仍由 PhysicalBone、關節與重力模擬完整骨架；手部目標使用頻率 36 的臨界阻尼速度追隨及移動目標前饋。屍體支撐中心依骨盆與胸部物理骨中點配置於玩家局部 `(0, 1.52, -0.37)`，兩處均受支撐並將質量提高為 6 倍；所有手持骨線性阻尼為 0.6、角阻尼至少 2.8。即時髖部／胸部底緣抓握標記隨骨架更新，並先於玩家手臂 IK 套用。G 丟棄、保存及回收沿用既有物理姿勢流程；佇列等待時停止物理骨；付費進料先同步建立 processing 等候階段，再恢復骨段碰撞與模擬，逐段吸入，避免稍後執行的接管回呼重新關閉已啟動的模擬。ScrapperFeedMotion 對每個骨段的八個碰撞角點檢查料斗範圍；完整進入口且抵達刀齒後才關掉該骨段碰撞，抵達刀齒後解除該段與相鄰骨段的關節；Godot 4.7.2 的 joint_type=NONE 不清除既存伺服器約束，故保留物理姿勢／速度並透過移出、重新加入節點清除。全部低於切割面才停止模擬，將已吞入骨移到非 simulator 的 ConsumedBones；節點留存直到整具屍體刪除，避免父骨刪除後的快取指標與重啟時後代骨重新模擬。剩餘骨重啟後還原實際姿勢／速度，已吞入皮膚固定世界姿勢。仍在邊框外的骨段保持碰撞；所有骨段吞入後才能完成回收。取消重建完整屍體物理，完成才刪除。玩家／怪物屍體均產出 Unknown Material 2–4、Unrefined Fuel 1–2。

屍體 `state.corpse` v1 保存類型、五部位狀態、骨架相對道具的 transform、41／54 個局部骨姿勢；驗證類型、拓樸、有限變換與大型旗標。既有 Item 流程涵蓋背包、道具箱、世界、副本及分解輸入，納入 v6 檢查點保存；不保存各肢體角速度或手持暫態。屍體不再按死亡秒數消失，但仍受世界既有距離串流／場址保存規則影響。測試及可見驗收見 [屍體搬運與分解](docs/validation/2026-10-04-corpse-props.md)。

RecipeDefinition/RecipeCatalog 定義十一個配方（汽油罐、兩款電池、輪胎、兩款引擎、引擎維修包、玩家身體、手電筒、手槍與盒裝子彈）。平板只 request_craft，工作站檢查有效性／完整電費並預留材料，進度逐步耗電；取消退材料，已用電不退。完成後檢查出料空間才生成；堵塞保留待出料工作。spawn_item 的即時介面也在完整驗證後扣材料與電費，失敗回復。成品屬於本世界 WorldEntities，繼承 RV 點速度；製作電池初始電量為零。製作手電筒滿電且關閉，手槍裝填 12 發，子彈每盒 24 發，沿用物品場景預設。

MaterialStorage 保存底盤數字材料，material_capacity 預設 300；容量不依賴設備，超額只允許消費／退款，不再領出 Material Bundle。底盤 stored_items 保存完整道具記錄，item_capacity 預設 24 格。ItemBox 開啟不耗電的 item_storage_ui；同車箱子共用底盤倉庫，先驗證容量／背包大型限制再轉移，按鈕保留原項目快照以拒絕過期操作。搬移、損壞、斷線與玩家死亡關閉 UI。

### 駕駛、維修與保存

控制仍由 Chassis 集中協調，未另做 VehicleController 類別。引擎狀態與入座分離，方向鍵遙控只可由測試明確啟用。輪槽常駐，即使沒有輪胎仍可射線互動；輪胎 ID／condition 在拆裝間保留。RepairOperation 累計持續瞄準時間，一般設備／輪胎完成才扣 2 Metal Parts 並補 60 HP；引擎另用專用維修包；切換目標、移動車輛、發動引擎或中斷免費取消。

Checkpoint autoload 在主場景攔截 F6/F9。保存限室外 NORMAL 模式、沒有 POI 轉場、地形建立或車體施工。Variant 序列化禁用 objects，Checkpoint／VehicleSnapshot 均為 v6；先寫 `.tmp`、flush 並讀回比對，上次有效檔備份為 `.bak`，再 rename 至 `user://rv_checkpoint_v6.save`。舊版本直接拒絕，不執行遷移或舊路徑偵測。CheckpointSchema 與 SaveSceneCatalog 驗證完整欄位、值域、POI、場景根類別、槽位、支撐引用及循環；磁碟錯誤按階段回報。

F9 先在停用物理與處理的獨立 World3D 暫建完整候選世界，等待地形與導航就緒，再套用 actors；原世界直到提交成功才釋放。WorldEntities.transfer 保留設備的支撐、電池和工作生命週期。失敗或逾時恢復原世界，來源存檔不變。

檢查點包括玩家背包／位置／生命、世界 seed／profile／有效 bands、RV、鬆散 actors 與已訪 POI 記憶。主場景 enter_tree 先配置保存的地形範圍，生成時跳過動態物資；ready 先按槽還原車體結構，再建立設備、接回支撐、電池、輪胎、油料、材料及工作，最後恢復模擬。車輛 structures 保存槽位、型態、耐久及門角度，校驗唯一占用、相容型態、有限耐久與角度；毀壞槽位不自動補回。Item support 保存 kind=chassis＋rv、kind=item＋id、kind=structure＋rv／slot 或 kind=static＋相對場景錨點路徑；拒絕相依循環，已失效的合法支撐令物品恢復散落。分解機輸入不重複列入室外 actors，電池只存於設備 service；道具倉庫與底盤容量沿用現有資料。沒有舊版遷移、室內直接保存或多槽；目前仍保存休眠 walk-in 場址，尚未提供場址外所有散落物的永久歷史恢復。

### 攀爬與戰鬥

玩家蹲下由 `Player.crouching` 管理，與缺腿觸發的 `is_crawling()` 分開。按住 Ctrl 接地進入，速度 2 m/s；膠囊高度 1.05 m，保持原半徑與腳底。放開後查詢站姿空間，阻擋時維持蹲姿；禁止蹲跳、衝刺與攀梯。UI／抓取凍結姿勢所有權，受傷爬行優先，入座與重生清除蹲姿。Checkpoint v6 要求 bool `player.crouching` 及完整身體、體力與耗盡旗標，恢復時先套碰撞體以支援低處讀檔。`Locomotion` 播放獨立 `crouch` 動畫庫並平滑降低視角 0.58 m，持物層沿實際肩高調整；原骨架、蒙皮與網格不變。動作資產見 [蹲下動畫](assets/animations/player/README.md)，存檔錯誤與恢復由 `test_checkpoint_failures` 覆蓋，完整蹲姿行為需另行驗收。

玩家只能從 RVLadder 兩端進入攀爬；牆面命中不再授權玩家攀車。RVLadder 繼承 Item，side_door_ladder／roof_ladder 使用原設備搬移、取消、支撐依賴、耐久及 v6 保存，登錄獨立 rv_ladders 群組。W 上爬、S 下爬、Space 脫離，A/D 不橫移；起點以完整膠囊腳底校正，進出梯與每步移動使用實體掃掠。登頂必須有真實可站立支撐，關門及封住開口均會阻擋。攀爬按 RV transform 差追蹤平移與旋轉，梯子搬移／毀損／失去支撐即安全脫離並繼承平台速度。梯子在兩種放置模式均保持背面 -Z 貼牆、+Z 朝外；牆面原始射線命中及細移直接決定位置，不重寫接觸點、不提供預設錨點。只接受近乎垂直的真實牆面，地板、天花板和活動門扇拒絕安裝；靜態牆面安裝歸 WorldEntities，避免支撐卸載時連同梯子被釋放。

接梯需面向梯子（dot ≥ 0.8），左右誤差不超過 0.25 m；下端向外接近範圍為攀爬線外 0.22 m，上端以實際落腳點前後 0.25 m 判斷。进入攀爬只建立狀態，不立即改位置；ENTRY 以 1.4 m/s 逐步抬腳、對齊，每步實體掃掠並跟隨車輛，鬆開 W/S 暫停。攀升／下降為 1.6 m/s。到頂進入 TOP，持續 W 不再跨出；先放開移動鍵，再以玩家面向和 WASD 控制水平移動。腳下真實支撐確認後，只做垂直 LANDING 落地，不朝 top_landing_point 推送，也不播放頂端前傾收手動畫。離開梯頂可觸及範圍而無支撐時恢復重力，Space 可隨時脫離。當前行為見 [手動離梯](docs/validation/2026-10-06-ladder-manual-exit.md)；先前接近手感驗收見 [接梯手感修正](docs/validation/2026-10-06-ladder-transitions.md)。

PlayerInventory.is_holding_large_item 只讀 active_item.is_large。持大型物品時禁止上／下梯，同一次持續按鍵只提示一次；攀爬中取得大型物品立即經 _abort_climb → _exit_climb_to_normal 脫離，不更動物品記錄。登梯／下降共用現有攀升動畫，下降反向播放；姿勢補償改以梯子平面定位，車輛搬運不驅動步態。

兩個 RV 預設均裝側門梯與車內梯；短梯靠側門下方車體外壁、支撐為底盤，長梯貼左側內牆、支撐為 LeftMiddle 固定牆板。長梯上端穿過中片屋頂開口到平台，短梯越過門檻，均以膠囊掃掠及真實支撐驗證。屋頂為三個固定槽 `roof_0`／`roof_1`／`roof_2`，Z 中心 -4／0／4 m，每片 4 × 4 m、50 kg、120 HP；初始前後普通，中片左側開孔。三槽皆允許 `rv_ceiling`／`rv_ceiling_hatch`，後者以四塊網格及真實碰撞盒留出局部 x=-1.8～-0.35、z=-0.8～0.8 m 開口。橘色邊框不跨洞；雨遮逐片讀取真實碰撞，開口與毀壞片均不遮雨。梯子模型來源 scripts/build_rv_ladders.py，含內嵌 128px 磨損貼圖，沒有外部建模需求單。先前右側／單片屋頂驗收為歷史結果，見 [貼牆 RV 梯子](docs/validation/2026-10-05-rv-wall-ladders.md)。

Monster 結合 NavigationAgent3D、直接追蹤 fallback、卡住監測與高度協助。MonsterBoarding 管理附近入口選擇、掛門／登頂模式、接觸前相對速度抽樣、抓握耐力、恢復和車頂失衡；ClimbMath／RVSupport 仍負責碰撞、登頂與隨車支撐，不改玩家攀爬策略。車門提供實際 leaf 邊界與關閉狀態；不把整個門框當成葉片。

所有攻擊最後經過 boarding.can_attack，掛門攻擊只由掛門流程發出，攀牆途中與抓穩期間禁止結構攻擊。屋頂破壞仍由 UnderfootProbe 與玩家高度授權。車身運動取樣跨短暫地板接觸缺失保持連續，避免重新接觸誤判從靜止加速。RVSupport.capture 在 is_on_floor 成立但缺少滑動碰撞時，用膠囊腳底短射線驗證真實支撐，避免地板吸附造成逐影格漏跟車；支撐拆除仍立即失效。碰撞前保存怪物世界速度，車撞／抓握共用 ClimbMath.point_velocity；高速撞擊先於抓握，並有傷害／重抓冷卻。

MonsterBoardingVisual 僅處理程序生成手臂與原創 PCM 空間音效，透過 attack_landed 接收真正命中的事件，不改碰撞形狀。抓握、模式和導航目標屬暫態，讀檔重新判斷，不改 checkpoint 格式。

[item_detour.gd](enemies/item_detour.gd) 在 RV 外補上固定 Item 的局部繞行，不依賴靜態導航網格重新烘焙。每步先以實際角色碰撞形狀掃掠原方向；遇到未接入 RV 的固定物品時，最多取附近 10 m 的 12 件 Item，沿其包圍盒外角建立 AStar3D 候選點。候選點需有腳下支撐，連線需通過完整碰撞掃掠；路徑每 0.5 秒、目標改變或下一段受阻時重算。物品移除後直路檢查立即恢復原導航方向；無有效路徑時水平移動為零並等待重算，避免沿用舊網格穿過新障礙。實際多物品繞行、移除及封閉等待的歷史專項結果見 [Item 驗收](docs/validation/2026-10-06-unified-items.md)。

MonsterCabinRoute 是目前 4 × 12 m RV 的獨立局部 AStar3D 步行圖，20 cm 網格、實際角色膠囊重疊／掃掠檢查，含對角連線。目標或車輛改變及每 0.65 秒重新規劃；路點存在車輛本地座標，隨轉向／平移轉換。落在設備上時從真實高度檢查離開桌面的水平路段，再由重力落地。近戰終點需視線可及，不單純靠近座位中心；玩家不可及時不把車內設備當替代攻擊目標。RVStructureSlots 提供被拆除後仍存在的破口位置，開門角度至少 70° 且完整膠囊可通過才視為出口。走道封死等待重規劃，車內不使用隨機跳躍脫困。DriverSeat 碰撞拆為座墊／底座與椅背，避免整塊盒子包住乘員而完全阻擋近戰。圖不保存至 checkpoint，也不取代室外 NavigationAgent3D。

CombatTargeting 做一般排序，Monster 觀測候選並執行攻擊；Item 在選敵與實際命中都被排除。腳下攻擊僅接受 UnderfootProbe 實際命中的 RVStructurePanel，且需較低位置的追蹤玩家授權；同 physics tick 共用射線結果，其他攻擊路徑排除同一支撐目標，避免繞過授權。物品仍有碰撞並遮擋攻擊，有路繞行、無路等待重規劃。

一般移動時，已在近戰距離／高度範圍且視線通暢的玩家優先於拆車體結構目標，直接進入 ATTACK；接觸攻擊不能先消耗其共用冷卻。攀車目標更新只選目標，不逐影格覆寫 CHASE，避免阻止攻擊狀態執行。待機取 detection_range、追擊／攻擊取 lose_interest_range。Player 的受傷無敵計時在座位／介面移動鎖之前更新，兩者不會延長無敵。現行正式 Raker 回歸保留 [抓取所有權與清理](tests/test_raker_grab.gd) 及 [移動 RV 攀爬](tests/test_moving_rv_climbing.gd)；其他追擊與近戰專項結果屬歷史驗收。

### RV 外觀與駕駛室原型

預設 RV 更新為 WAYFARER 工業露營車：深綠車殼、奶油白窗框／屋頂、橘色標示、透明有碰撞的玻璃、前後燈與輪圈。側牆分成六片：面向車頭時，右側由前到後為牆／門／牆，左側為牆／牆／牆；後方是一組向外開啟的雙扇大門。每片側牆、側門整組、後門整組固定於槽位並可獨立破壞，屋頂分前／中／後三片；結構配置及維修從平板施工。地板是底盤固定部分，不參與結構施工。

駕駛座綁定座椅、方向盤、儀表台、排檔桿、手煞車與踏板，F 搬移整組。方向盤跟隨底盤轉向，排檔桿／手煞車位置與速度、油電儀表同步車況；操控沿用 B、Space、Z/X/C、R/T。駕駛時背包欄隱藏，底部顯示車況與操作提示，離座恢復。加油孔與電池插槽位於車外維護側。

[模型結構說明](rv/visuals/README.md)；[展示場景](tests/rv_design_workshop.tscn)（F2 外觀、F3 車內、F4 駕駛、F5 輪驅、F6 舊版、F7 控制台）。舊車殼保留在 [rv/legacy/new_rv.tscn](rv/legacy/new_rv.tscn)。

#### 分片結構、槽位與門扇

- `RVStructureSlots` 由底盤持有十一個永久槽：六側面、前、後、三片屋頂，保存各槽設定型態與毀壞狀態，並持有本車唯一施工控制器。`get_equipment()` 只列一般設備，`get_structures()` 與 `structure_changed` 提供結構查詢、重量、介面及外觀刷新。地板沒有結構槽位或平板操作。
- 屋頂型態共用同一施工交易與比例耐久；平板按槽可選型態數量提供變更按鈕，不限制側牆。三片總屋頂重量 150 kg，破壞與附掛釋放獨立；地板固定於底盤，不參與施工。現行 v6 僅保存十一槽；舊地板／單一屋頂格式直接拒絕，不轉換支撐或移除舊資料。
- `RVStructurePanel`（`equipment/rv_panel.gd`）直接繼承凍結 `RigidBody3D`；`RVStructureDefinition` 是獨立 Resource，提供穩定型態 ID、槽型、場景、耐久、重量、施工參數及允許轉換。均不繼承設備類別。沒有 F 放置或 H 維修契約；`take_damage()` 逐片受傷，歸零移除外觀／碰撞／攻擊資格但保留空槽。
- `rv_door.gd` 繼承結構類別；門框和可旋轉門扇碰撞同屬根剛體，共用耐久。E 開關與各葉角度保留，開關預檢完整掃掠路徑，動畫中逐步複查阻擋。怪物門框選敵使用結構契約。
- 設備支撐可為底盤、Item 或 RVStructurePanel；板件毀壞發送 removing，附掛設備停機並以車輛點速度連鎖掉落。地板網格與碰撞屬底盤固定部分，重量包含在固定底盤中，不提供獨立耐久或施工；安裝在地板的物品直接引用底盤支撐。
- `RVStructureConstruction` 提供 begin／rejection_reason／cancel／is_building，平板五頁為 Overview、Energy、Equipment、Crafting、Structure，施工位於 Structure；每槽顯示耐久、附掛設備、型態選單與操作原因。維修 2 Metal Parts／2 秒補 60 HP，重建 6／6 秒滿血，側牆門及普通／左側開孔屋頂互換 2／4 秒保留比例，新門關閉。一車一項，熄火、速度 ≤ 0.5 m/s、有電、操作者 UI 所有權及平板服務有效，且 is_management_active() 為真；受擊、退出 TUI、關閉、掉落、斷電、發動／超速中止該平板的施工，切換分頁不取消。完成前重驗材料、目標、依附與碰撞，通過才扣料提交；不提供主動拆除空槽、施工保存或進度還原。
- 變型須清空直接／間接依附，維修不用；重建／變型以快取候選碰撞檢查全部物理層，排除舊部件與底盤，避免包住角色或物件。平板在 `_ready` 關閉可摧毀旗標並覆寫傷害，不加入怪物可攻擊群組；仍是可搬移、掉落與需供電的設備。
- `test_rv_structure_modules.gd` 覆蓋固定槽、E 門扇、阻擋、獨立破壞、設備掉落、固定地板與保存；施工扣料、中止、比例、重建、依附碰撞與平板操作的歷史專項結果見 [施工驗收](docs/validation/2026-10-05-rv-structure-construction.md)。可見場景為 `rv_structure_playground.tscn`，歷史門測試場保留 E 開關與破壞捷徑。

實測及限制見 [分片牆與門驗收](docs/validation/2026-09-16-rv-structure-doors.md)。

### 完整 RV、引擎與車況

- EngineDefinition（engine_standard／engine_upgraded.tres）集中 450／600 耐久、1.0／1.25 動力、1.0／1.15 引擎油耗及重量；EngineState 只保存 id／model／health，item() 轉為含同 ID 的大型道具記錄。
- 固定 EngineBay 持有唯一安裝狀態。Chassis.exchange_engine／remove_engine 原子轉移同格背包，service_reason 共用停穩／熄火／手煞車／開蓋條件。Chassis.take_damage 轉交引擎，has_working_engine 和 engine_start_reason 統一啟動條件；沒有底盤 HP 或整車毀損旗標。
- RepairOperation 對引擎使用 repair_requirement 契約；鎖住目標、引擎 ID 與維修包 ID，連續 3 秒後再次驗證並消耗道具，+150 耐久。一般設備／輪胎沿用材料路徑。
- VehicleEnergy 依引擎定義計算基礎油耗；只有有效引擎能運轉，並由底盤內建充電功能替插槽電池充電。處理充電、待機、工作後統一支付車燈負載，lamps_powered 為實際供電結果。
- VehicleStatus.read 回傳 8 項圖示／等級／文字；實體 InstrumentCluster 與 TabletUI 讀同一結果，沒有副本數值；RVTerminalPresenter 僅翻譯英文顯示名稱及訊息，不改 domain owner 的原始訊息、交易或狀態。VehicleLights 控制真實 SpotLight3D 與燈罩發光；舊裝飾燈材質不再常亮。駕駛 HUD 沒有行車文字列或駕駛提示；實體時速／轉速錶、油量與電量指針錶、檔位窗、充電燈與車況燈提供行車資訊；`Chassis.engine_rpm()` 為既有車速／檔位／油門的呈現估算，由轉速表與音調共用，不另建動力或保存狀態。見 [儀表說明](rv/visuals/README.md#2026-11-12-實體儀表)。
- chassis.tscn 原生網格與簡單複合碰撞保留舊輪槽和車殼座標。正式 new_rv 預裝完整服務；Item.initial_support 僅設定新場景預設依附（平板→工作台）。讀檔由已保存 support ID 還原，不套預設配置。
- RearRamp 是底盤固定子節點；檢查手煞車、速度、兩扇門角、地面法線與兩端支撐、完整展開路徑。1.4 m 寬斜面碰撞及兩折視覺分開，展開阻止 engine_force 並保持煞車，仍可怠速。收起檢查上方占用；狀態保存 deployed／angle／length。
- DriverSeat 離座以 current_driver 的實際 Shape3D／局部變換和碰撞遮罩搜尋支撐地板。正常受阻保留所有權；破壞、拆除、死亡強制搜索外圈支撐／上方淨空並解除座位。
- DriverSeat 鏡頭局部高度 1.62 m，高於儀表台上緣 1.33 m；調整駕駛姿勢時須保留前方路面視線。預設視角中車頭前 15／25／40 m 路面與不透明網格遮擋的歷史檢查見 [駕駛艙驗收](docs/validation/2026-09-16-rv-cockpit.md)；變更後須另行確認原生畫面。
- EquipmentPlacement 對一般設備放置累積繞面法線的旋轉和切面平移，細調後重新射線確認接觸仍屬原支撐，再用 PlacementRules 驗證。車體結構不進放置流程，V 吸附操作已移除。接觸箭頭與控制提示跟隨預覽清理。
- RVStructurePanel.dependent_names／dependent_summary 沿 mount_support 遍歷本車設備，包含直接與間接依附。PanelWear 由 availability_changed 讀取耐久，以獨立材質疊加連續掉漆／金屬擦傷／玻璃裂紋，滿血恢復來源；EngineAppearance 維持引擎耐久呈現。take_damage 結算後才發 damage_applied，產生最多六組／車的碎片、粉塵與合成聲：一般受擊 2.4 秒，破壞 7 秒內清理。破壞以實體 BoxMesh 分割保留材質／厚度的彎折板片及玻璃，繼承接觸點速度，以外觀射線查詢落地／移動支撐後淡出；不加入物理碰撞體，不改既有支撐、HP 或保存所有權；set_health 的維修／讀檔不重播受擊效果。見 [RV 外觀規則](rv/visuals/README.md)。
- v6 VehicleSnapshot 保存 structures、engine_item、headlights、hatch_open、ramp，拒絕舊版本且不遷移或補發。EngineState.unique_ids 對車輛快照與整份檢查點（含背包／地面／倉庫／POI／分解輸入）驗證引擎唯一性，並驗證模型與道具場景一致。
- CraftingStation 依實際產物根層碰撞檢查出料空間，以產物旋轉後碰撞 AABB 底部計算出料高度。一般物品依空間嘗試原姿與兩軸 90 度平放，選擇有台面支撐的小幅偏移；工作保存固定姿態，預覽與實體共用變換，輪胎可在完整房車頂下平放交付。選姿保留牆頂與機台碰撞，暫時占床的未固定物品不改變下一件姿態；交付仍檢查全部碰撞。完成但阻塞的工作留在佇列，不重複出貨或扣款。PrintedPlayerBody 工作啟動時由 CraftingOutputPlacement 檢查平台站姿淨空，不足則將 crouching 姿勢寫入工作；預覽、交付與保存均沿用同一姿勢，產物留在台面。連蹲姿都受阻時等待清空台面／上方，不改道至地板。
- CraftingPrintVisual 只讀工作進度顯示逐層列印；FabricatorRig 分別控制水平 X／Z 滑軌與 Y 升高，依高度增加立柱並同步獨立碰撞 Shape，沒有模型高度上限。完成／取消時水平兩軸以 0.65m/s 平滑回位，停靠後才以 0.45m/s 下降；偏移成品的加工路徑仍限制在實體滑軌行程內。printed_player 配方產生持久化的 PrintedPlayerBody Item；E 在休眠身體與唯一正式 Player 間交換位置、健康、肢體與體力，背包及控制器所有權不複製。切換前驗證狀態及兩處空間，保存經 ItemState 嚴格驗證；入口與範圍見 [製作台與身體切換驗證](docs/validation/2026-10-11-fabricator-print.md)。

#### 新增驗證入口

駕駛體驗增量：Chassis 集中油門、腳煞車、速度相關轉向上限；road_speed 以物理步實際位移取樣，僅供儀表／聲音，不改變動力學。VehicleMirrors 擁有兩個共享 World3D 的 SubViewport，相機裁掉鏡面專用第 20 層避免遞迴，192×256 並交錯 UPDATE_ONCE 更新；前側板弱參照由 structure_changed 刷新，離座停用、讀檔重連。

EngineHatch／RearRamp 持有 progress、目標與 moving；維修蓋動作前及逐步做碰撞掃掠，受阻維持姿態。坡板先滑出再翻折，動畫期間板面無碰撞，僅完全展開後啟用連續斜面；停穩並拉手煞車即可操作，不檢查後門開度、板上占用或折疊淨空，E 可從當下姿態反向。展開仍檢查中央接地與 30° 可行走坡度，不要求兩側角落支撐。save_block_reason 與 VehicleSnapshot.capture 拒絕非穩定狀態，Checkpoint 顯示具體原因；正式保存仍只寫既有穩定 hatch_open／ramp，不保存過渡動畫。

EngineHatch 以上緣後側固定鉸鏈向外旋轉 105°，用緩入緩出角度同步蓋板、把手碰撞與雙側伸縮支撐桿；障礙檢查沿轉動弧線每 ≤1° 採樣，停止後保留當下姿態。引擎槽標示只在完全開啟時顯示。[本輪動畫與驗證](docs/validation/2026-10-10-rv-engine-hatch.md)。

VehicleAudio 快取原創 PCM stream，每車一個引擎迴圈／最多三個一次性空間音源，操作提交後觸發並有節流；僅引擎視覺子樹可震動。WorkLighting 僅管理引擎維修燈，CabinLighting 跟獨立燈條；製作台不附帶燈或照明負載，Equipment 控制車內及維修燈，Overview 控制頭燈；平板不提供工作燈、儀表亮度或視覺震動控制，亮度與震動沿用保存值或新車預設；VehicleEnergy 支付各類可用燈具的負載。VehicleSnapshot 的必要 comfort 保存燈具請求、亮度與震動並在套用前檢查型別／有限值／範圍；獨立燈條以普通設備保存，已拆除燈條不補回，沒有舊車頂燈遷移。音源來源見 [音效說明](assets/audio/README.md)。

[test_rv_engine](tests/test_rv_engine.gd) 保留預裝、引擎所有權、交換、維修、性能、車燈、保存及製作檢查；終端呈現、坡板與駕駛姿勢需另行驗收。可見入口為 `rv_rebuild_playground.tscn`。

歷史專項測試與實機證據見 [驗收紀錄](docs/validation/2026-09-16-rv-rebuild-engine.md)。該次紀錄使用本機 Godot 4.7.2；目前 CI 也固定至 4.7.2。外掛設備撞擊力矩、極端翻車、怪物群和長途經濟未因此視為完成。

<a id="section-6"></a>

## 6. 已知限制

- 2026-09-22 審查的 A01（搬移未通知依附物）已由 Item 共用 removing／支撐鏈掉落處理；A02–A03 的玩家 UI 重力／RVSupport 及普通動態物件遠距清理限制仍需另查。A04 的 POI 離場取消及安全清理已修正；原重現證據保留於 [架構審查 A01–A04](docs/report/ApocalypseRV_Architecture_Audit_2026-09-22.md)，當時 POI 驗證見[地堡驗證](docs/validation/2026-09-29-bunker-content.md)。
- POI 導航生命週期及車內每隻怪物同步重建路徑的群體成本尚未量測；不代表已重現崩潰或卡頓。
- 設備仍是獨立凍結剛體。重量／重心已彙總，但側撞與大型外掛的碰撞力矩未合併到車體；翻車、偏載、怪物群需專項實測。
- 控制、輪槽與登錄仍共用 Chassis；能源、材料、保存已抽離，後續可按需求再拆控制／掛載服務。
- 配方出料使用產物根層的實際碰撞形狀檢查；新增產品需驗證碰撞配置與出料淨空。
- 簡化載重加總底盤、存活車體結構、已安裝引擎與有效的已安裝設備，並依位置計算重心；電池本體、抽象材料、庫存道具、燃油與鬆散貨物不納入車體質量。插槽與倉庫設備本體仍計重；游離道具保留既有剛體行為。BatteryState.weight 保留供道具物理使用，VehicleSnapshot 載入後以同一 update_load 重算車重，無需存檔遷移。首版檔位不模擬離合器／轉速。
- 保存只支援室外檢查點，沒有多人所有權、室內直接保存或多槽；目前支援往返串流。
- 隨機地堡只使用 16 個當前 content_version=2 廢棄房型，已增加家具、表面破損及暗房；九類複雜設備仍以灰盒等待建模交付。完整地表設施、更多物資／敵人變化與長局平衡仍未製作。本次驗收見 [場景與手電筒](docs/validation/2026-09-29-bunker-art-flashlight.md)。
- 真實輪驅與停車倒車測試通過，但燃油關閉的測試場不是長途資源平衡證據；未宣稱全部玩法與模擬步組合完成驗收。

<a id="section-7"></a>

## 7. 測試與慣例

測試入口、覆蓋範圍與 CI 見[測試指南](tests/README.md)；agent 另見 `godot-tests` skill。

遵循 GDScript tabs、可行時明確型別、snake_case 檔案／函式、PascalCase class、UPPER_SNAKE_CASE 常數；重用 core 契約。新增 POI 必須有有效內容，新增物品需設回收產出，設備需驗證連線／取消／毀損。
