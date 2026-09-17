# ApocalypseRV 架構

## 2026-09-17：局部體積霧（目前正式設定）

桌面渲染改為 Forward+／Vulkan。WorldClock 設定薄全域體積霧與 160–420 m 遠景距離霧；ForestFog 使用獨立外觀 RNG，按地形低處與實際步道路線高度建立 FogVolume，隨 chunk 回收。世界座標 3D 噪聲和柔化邊界控制局部濃淡，霧不參與碰撞、導航或怪物感知，也不改地形生成版本與物資。

RV 車頂的 CabinLighting 持有負密度排霧區，僅在安裝完成且可運作時啟用；獨立 World3D 室內副本不啟用室外體積霧。Compatibility 降級沿用 18–380 m 距離霧，不建立 FogVolume。地表紋理作為污痕資料遮罩採原始取樣，避免 Forward+ 的色彩空間轉換改變材質閾值。驗收見 [局部體積霧](docs/validation/2026-09-17-volumetric-fog.md)。

## 2026-09-17：世界時間與太陽

正式場景持有 WorldClock，集中維護累積遊戲秒數與一天的現實分鐘數，預設 day 1 / 08:00 / 30 分鐘。每幀依 delta 前進，跨日由累積秒數推導；minute_changed 提供日期、時、分，HUD 每遊戲分鐘更新。PROCESS_MODE_PAUSABLE 尊重 SceneTree 暫停，背包／平板與 POI 不暫停世界。

WorldClock 獨佔正式室外 Environment 與 DirectionalLight3D 的光照設定，取代 WorldGenerator 的固定光照。太陽在 +X 升起、-X 落下，06:00／18:00 越過地平線，最高仰角約 58°；光源 basis 與天空 sun_direction 共用同一向量，地平線下光源能量歸零。天空、距離霧與環境填光按太陽高度平滑插值，霧距離不隨時段突然跳動（Forward+ 遠景 160–420 m；Compatibility 18–380 m）。使用自訂陰天天空、低解析 radiance cache、關閉天空反射來源；Forward+ 體積霧見上節，未加入動態天候。

Checkpoint v3 增加可選 clock 字典（elapsed_seconds、day_length_minutes），與生成版本分開。讀取時檢查數字型別、有限值及範圍；prepare_world 在子節點 ready 前恢復，HUD 在 ready 強制刷新。舊 v1/v2/v3 缺欄位沿用 day 1 / 08:00，不改寫來源檔案、不計算離線時間。POI 的 own_world_3d 保留自身照明，戶外時鐘持續流動，返回立即使用目前時段。

`tests/day_night_playground.tscn` 的調時／加速鍵只用於驗收。歷史美術樣板凍結時鐘並明確使用 exponential fog，避免新光照每幀覆寫 A/B 環境。

## 2026-09-17：正式戶外 D 風格

前一輪霧效修正（目前保留為 Compatibility 降級）：原生 Depth 模式，18–380 m、curve 0.65、最大混合量 1，避免近景過早洗灰。天空 horizon_color 使用 source_color，與 Environment.fog_light_color 共用時段色彩（白天 a4aca9）；fog_sky_affect 為 0，天際線由天空本身匹配，高處只有低對比固定雲層。沒有額外全螢幕霧後製或體積霧。

ForestMeshes 使用共用的不透明低模分枝網格與粗葉脈／樹皮材質；ForestScenery 將原有世界座標轉成 48m 格內局部座標，樹／灌叢裁切距離為 340m／160m、遲滯 16m。未改生成 RNG、實例數、樹位或碰撞。這是正式渲染更新，不需要存檔或生成版本升級。

地表 shader 用現有三角形的導數計算平面法線，不改 mesh 頂點或碰撞；只取原泥地貼圖的低頻污痕。天空 shader 的光色由 WorldClock 驅動，配合距離霧與環境填光。OutdoorPresentation 保留約 540p 縮放，但後製不再進行像素格量化或抖色；室內／UI 分離與 F8 偏好沿用原契約。入口材質由外觀專用快取持有，不修改室內共用材質。

## 2026-09-17：可切換美術樣板

`tests/industrial_style_playground.tscn` 繼承既有室外驗收流程，載入正式世界 seed 42。`world/art_sample/` 提供 SampleForest、SampleMaterials、維修廠附加立面，以及固定陰天天空／泥地 shader。替代 MultiMesh 與材質均由樣板持有；A/B 還原當前正式資源。樣板植被依 48m 格子分批，樹／灌叢裁切距離 300m／110m，保留 12m 遲滯。正式版分區後，樣板沿用来源節點變換與 forest_kind metadata，不解析分區名稱為型號。新載入 chunk 只掃直接子節點掛上外觀，沒有全樹每幀遍歷。

RV 牆板的局部 PanelWear source 隨比較切換，保留真實耐久損傷；車內燈繼續使用正式供電判定。新增立面是視覺樣板，正式擴展前還需補上高層量體的物理／攀爬設計及導航驗收。不得把獨立樣板視為已全面替換主世界。

更新：2026-09-16。描述目前程式；玩法與願景見 [GDD](GDD.md)，啟動與驗證見 [README](README.md)。[docs](docs/README.md) 收錄計畫、驗收紀錄與 archive 歷史封存。

## 1. 執行環境與場景

目標開發／CI 版本 Godot 4.6.1，Jolt Physics、桌面 Forward+／Vulkan（Compatibility 可降級）。[project.godot](project.godot) 的入口為 [world/test_world.tscn](world/test_world.tscn)。目前沒有網路同步或任務／進度管理器；Checkpoint autoload 提供主世界檢查點。

本機專案已由既有修改標為 4.7，本次 POI、地形與 RV 系統以安裝的 Godot 4.7.2 實測；CI 仍為 4.6.1，尚未驗證兩版結果一致。

```text
TestWorld
├── Player                  玩家、Camera、互動射線、UI
├── WorldEntities           共用動態物件容器
├── WorldGenerator
│   └── chunk               地形、道路、導航、POI 入口建築
├── PoiInstances            同局副本狀態、轉場、串流錨點
│   └── InteriorViewport    獨立 World3D，僅探索時存在
│       └── PoiInterior     房間／走廊／導航／WorldEntities／室內玩家
├── NewRv
│   └── Chassis             VehicleBody3D、油電、材料、耐久
│       ├── Wheel_*         VehicleWheel3D；獨立輪槽 hitbox 常駐底盤
│       └── 座椅／車板／插槽／加油孔／道具箱   已安裝的 Equipment
└── 地面物品、殭屍      主場景測試實例
```

正式 RV 預裝發電機、工作台、分解機、平板與完整駕駛室；引擎、電池和兩包維修包一併備妥，地面不重複散放同款服務設備。

## 2. 模組責任

| 模組 | 檔案 | 邊界 |
|---|---|---|
| 玩家協調 | [player.gd](player/player.gd) | 攝影機、移動、攀爬、生命、座位／UI／放置授權、手持外觀 |
| 玩家背包 | [player_inventory.gd](player/player_inventory.gd) | 6 格、選取、大型限制與消耗，不持有場景節點 |
| 互動 | [player_interact.gd](player/player_interact.gd) | 射線、目標提示與結果、E／F 獨立按鍵狀態、快速事件緩衝、輪胎安裝特例 |
| 放置 | [equipment_placement.gd](player/equipment_placement.gd) | 預覽位置／朝向、確認／取消輸入 |
| 可撿物 | [interactable_item.gd](props/interactable_item.gd) | Prop 剛體、名稱、大型旗標、回收產出與手持配置 |
| RV | [chassis.gd](rv/chassis.gd) | 控制授權、引擎／排檔／手煞車入口、輪槽、耐久、設備登錄與重量／重心 |
| 能源 | [vehicle_energy.gd](rv/vehicle_energy.gd)、[battery_state.gd](rv/battery_state.gd) | 代理有效插槽的 BatteryState、集中物理步調度；燃油屬於底盤 |
| 材料 | [material_storage.gd](rv/material_storage.gd) | 本車存量、容量、原子扣款、溢出保留 |
| 保存 | [checkpoint.gd](rv/checkpoint.gd)、[vehicle_snapshot.gd](rv/vehicle_snapshot.gd) | 版本化磁碟檢查點、車輛／設備／輸入物件關係還原 |
| RV 互動轉接 | [fuel_port.gd](equipment/fuel_port.gd)、[wheel_hitbox.gd](rv/wheel_hitbox.gd) | 加油入口、拆輪 |
| 設備基類 | [equipment.gd](equipment/equipment.gd) | 放置、物理／材質恢復、連線快取、耗電、破壞 |
| 專用設備 | [equipment/](equipment/) | generator 供電、scrapper 回收、tablet_screen/UI 顯示製作、crafting_station 出料、driver_seat 駕駛 |
| 串流 | [world_generator.gd](world/world_generator.gd) | 固定座標區塊窗口、分幀建立、遠景與距離清理 |
| 世界資料 | [world_field.gd](world/terrain/world_field.gd)、[world_profile.gd](world/terrain/world_profile.gd) | 獨立 RNG、三層噪音、區域權重、道路及停靠計畫、共用高度查詢 |
| 地形道路 | [chunk_generator.gd](world/chunk_generator.gd) | 網格、碰撞、路面、停靠設施、裝飾、實際碰撞導航和物資／敵人 |
| 場址計畫 | [exploration_site.gd](world/terrain/exploration_site.gd) | v3／v4 路線、平台、鏡像、窄口、圍牆分段及邊界，共用於整地／生成／導航／串流 |
| 室外顯示 | [outdoor_presentation.gd](world/outdoor_presentation.gd) | 主 viewport 的 3D 縮放、輕微對比、F8 偏好與室內切換；Canvas UI 不縮放 |
| POI 外部 | [poi_config.gd](world/poi_config.gd)、[poi_spawner.gd](world/poi_spawner.gd) | v3 四種外觀、v2 原入口、穩定 ID／返回點與註冊 |
| 副本 | [poi_instance_manager.gd](world/instances/poi_instance_manager.gd)、[poi_interior.gd](world/instances/poi_interior.gd)、[maze_layout.gd](world/instances/maze_layout.gd) | 轉場、隔離世界、拓樸、房間連接、導航、物資／敵人與同局保存 |
| 怪物 | [monster.gd](enemies/monster.gd) | AI、導航、接觸觀測、攀爬、攻擊、車撞傷害、掉落 |
| 選敵 | [combat_targeting.gd](enemies/combat_targeting.gd) | 候選排序，使用 actor 提供的接觸判斷 |

## 3. 共用契約

- [groups.gd](core/groups.gd)：rv、chassis、equipment、monster_damageable、rv_power_generators、crafting_stations、player、monsters。正式程式用 `Groups.*`，部分測試用原字串釘住契約。
- [item_names.gd](core/item_names.gd)：物品、背包、配方和材料庫名稱常數。
- [rv_connection.gd](core/rv_connection.gd)：由父節點向祖先搜尋；RV 須為 Node3D、屬 rv 群組並提供 `add_item`／`deduct_materials`，避免 Equipment／Chassis 預載循環。
- [climb_math.gd](core/climb_math.gd)：RV 辨識、壁面幾何、附著位移與屋頂轉移共用計算。
- [rv_support.gd](core/rv_support.gd)：記住腳下精確支撐面和 RV transform，補償固定車板缺少的平台速度；支撐刪除、換車或單步位移過大時解除。
- [world_entities.gd](core/world_entities.gd)：建立／重用場景動態容器，場景釋放後可重建。

互動採 `interact(player)`／`interact_hold(player)` 方法契約，受傷目標提供 `take_damage(amount)`。群組與祖先階層錯誤可能造成離線或候選忽略，而非編譯錯誤。

## 4. 狀態與所有權

| 狀態 | 擁有者 | 資料 |
|---|---|---|
| 背包 | PlayerInventory | `{name, is_large, scene_path, state}` 陣列、active_slot；state 保存 ID、condition、scrap_yields、回收結果及電池子型別資料 |
| 玩家模式 | player.gd | NORMAL／PLACING／UI／SEATED／DEAD，由欄位推導優先模式，非完整集中狀態機 |
| 移動 | 各 actor | NORMAL／CLIMBING、附著 RV、前一 transform、接觸寬限、冷卻、RVSupport |
| 怪物意圖 | Monster | WANDER／CHASE／ATTACK、追蹤玩家、攻擊目標 |
| 車輛 | Chassis＋VehicleEnergy＋MaterialStorage | 控制、4 輪槽身分／耐久、引擎耐久代理、電池與材料；相容屬性轉送至專責狀態 |
| 設備 | Equipment | 穩定 ID、EquipmentDefinition、啟用、車輛與支撐、預覽快照、耐久及工作清理 |
| 生產工作 | 各工作站 | 配方 ID、預留材料、剩餘電費／時間、輸入物件所有權、待出料結果 |
| 串流 | WorldGenerator | active_chunks 的 node/index/start_z/end_z、next_band、building、WorldField 和 profile |
| 副本 | PoiInstanceManager／MazeLayout | active_id、saved_instances actor 快照、rooms／edges、局部 RNG |

地形、入口和路旁靜態模組由 chunk 擁有。動態敵人、搜刮物、玩家丟棄品、合成品和死亡掉落使用所屬世界的 WorldEntities。室內與主場景根節點都以 entity_domain metadata 指定自己的容器，避免初始 ready 時 current_scene 尚未設定而落到 SceneTree 根。WorldGenerator 只清理同一 World3D、錨點後方超過 450 m 的動態物件。玩家進副本後，錨點固定在進入前位置。

例外：主場景既有物品仍在根部，拆下輪胎、成品與掉落電池使用 WorldEntities。室內物資和怪物死亡掉落都使用室內容器。

玩家 `enter_*`／`exit_*` 授權 UI、座位與放置，呼叫方須尊重拒絕。DEAD 阻擋輸入／移動；平板和座位在玩家死亡或設備失效時釋放模式。

## 5. 主要流程

### 世界

WorldGenerator 建立 WorldField／WorldProfile／POISpawner → 初始後 2／目前 1／前 3 個固定網格帶 → 查詢區域／道路／停靠計畫 → 共用整地結果生成地表、路面與碰撞 → 安置靜態內容 → 烘焙導航並生成動態內容。行駛中的建立分多影格執行，完成前不發佈到 active_chunks；一次只有一個建立作業。

串流比較室外玩家或副本錨點 Z，仍只向 −Z 推進。WorldField 以世界座標計算有界平面曲線；道路高度取低頻地形需求，按 150 m 高度節點限坡，再 smoothstep 插值。WorldProfile 預設路寬 15／10 m、坡度上限 8%、區域長 900 m／過渡 240 m。seed_for(index, domain) 隔離道路、停靠、外觀、路線、裝飾、loot、敵人和副本亂數，入口 ID 為 v{generation_version}:world_seed:stop:index；重播的是生成配置，不是物理與 AI 時序。檢查點 v3 另存 generation_version（2／3／4），缺省為 2；新 WorldProfile 預設 4。舊檔不改地形與 POI ID。

外部停靠點位置為 index×450±75 m。v4 起始維修廠位於 (335.2,6,-45)，v3 保留 (135,6,-45)，每三點兩個離路入口、一個小補給；v2 保留 (49,0,-45) 近路維修站與原比例。ExplorationSite 以道路局部座標建立左右及前後鏡像模板，檢查完整場址是否落在版本對應碰撞帶內（v4 寬 900 m，v2／v3 寬 450 m），必要時改向另一側；無無限重抽。WorldField.surface 將場址平台、緩坡、步道及保留區整合到共用取樣，公路高度優先。spawn_site 使用同一份 building/road/frame/id/seed，外觀不消耗物資 RNG。四款外觀沿用既有入口及副本。

地形網格使用相鄰取樣圈計算法線，邊界共享世界位置及高度。v4／v3 導航分別涵蓋 900／450 m 寬碰撞帶，cell_size=0.25 m；v2 維持 240 m／0.5 m。使用實體碰撞，排除高 7 cm 的重複瀝青層，補相鄰地形、圍牆與建築碰撞資料；邊界資料由共用計畫提供，不依賴相鄰 chunk 載入順序。v3／v4 高容許 detail 誤差抑制噪音坡面新增的重疊細三角形，可通行輪廓仍由 voxel 決定；v2 保留原設定。非同步烘焙後發佈獨立 NavigationMesh，navigation_ready 等待 region 和 map 真正同步，避免初始空網格。怪物地面高低差仍使用導航；path_height_offset 對齊角色腳底；落地且已到達路徑點水平範圍時，以實際腳下高度推進路徑點，避免簡化網格埋入土坡造成繞圈。未移動的目標不重複重設路徑；移動目標維持 0.25 秒更新間隔。

場址牆段依中心 Z 歸唯一 chunk；整地跨帶查詢同一計畫。玩家位於場址 bounds 或室內 stream_anchor 時，protected_bands 保留並補建停車區、路線及建築的區塊與 halo。ForestScenery 以獨立 RNG 的 8 m 網格抖動形成樹林，逐列分幀規劃，樹幹簡化碰撞也提供相鄰導航 halo；快取至多 16 個帶。ForestMeshes 快取四款不對稱針葉樹、兩款枯樹與三款灌叢，共九批 MultiMesh；forest_art_variants 獨立亂數只選外觀，不改既有樹位、碰撞與 seed。遠景左右及前方網格只提供視覺。新造景延續分幀建立，build_ms／max_slice_ms 記錄成本。

室外日夜照明由 WorldClock 控制，Forward+ 使用局部體積霧與遠景距離霧，Compatibility 降級只保留距離霧。OutdoorPresentation 僅設定主 viewport.scaling_3d_scale（目標高度 540，最高 1），CanvasLayer 0 只套輕微對比，不再進行像素格量化或抖色，遊戲 UI 在較高 layer。F8 偏好寫入 user://display_preferences.cfg，不進角色／車輛快照。偵測 viewport 尺寸與副本 active_id 變化，室內停用、返回恢復。

MazeLayout 使用 10 欄、27 m 中心間距，建立 50–100 個 9 m／18 m 房間。隨機 DFS 產生連通樹，再增加少量鄰接邊形成環路。PoiInterior 放置四門預製場景、封閉閒置門、連接走廊，依實際靜態碰撞（含家具）非同步 bake 導航；動態物資與敵人在 bake 後建立。各房物資點獨立隨機排序，最多成功抽取 4 件。

PoiInstanceManager 在入口互動後鎖定玩家輸入、建立 own_world_3d 的 SubViewport，完成載入後 reparent 原玩家與 UI。根 CanvasLayer 顯示 viewport texture，輸入轉交子 viewport，視窗縮放同步。退出先保存室內 Prop 的場景、位置、回收資料及活怪生命／位置，再把原玩家移回主世界並檢查返回落點，釋放副本幾何。saved_instances 供同局重返重建相同房間與剩餘 actors；室外檢查點把這份資料一併寫入磁碟。非活動副本不繼續模擬。

WorldEntities.same_world 用於群組選敵、碰撞例外及串流清理；怪物每 physics tick 清掉跨世界的快取玩家目標。怪物與物品不穿越入口，只有原玩家與背包轉移。實例快照目前支援 Prop／Monster，未支援搬入副本的任意設備。

### 設備放置與支撐

F 長按 → 玩家授權 → 保存父節點／變換／freeze／碰撞層／速度／材質 → 停止服務 → 共用 PlacementRules 驗證 ghost。驗證使用各碰撞形狀和定義的操作空間，檢查合法支撐、重疊、朝向和支撐循環；確認前重新計算候選。結構板提供可選面中心接點吸附。

確認後分開記錄本車歸屬與 mount_support。設備向本車登錄；支撐 removing/tree_exiting 先停機，再延後解除掛載，帶 RV 點速度落至 WorldEntities。取消還原完整物理快照。UI、駕駛與生產由共用停止入口清理，重複清理不重複退款／退料。

### 能源、道具與生產

BatterySocket 繼承 Equipment 並保存 installed_battery；VehicleEnergy 透過弱參照查詢底盤的有效插槽，Chassis.current_power/max_power 保留代理介面。同車最多接通一顆電池，未接入的背包／倉庫電池不參與供電。搬移開始、支撐脫落或損壞時，插槽將 BatteryState 轉成世界 Prop 並清空自己；掉落點在車體外，繼承車輛點速度。取消搬移不自動收回。

底盤直接保存 current_fuel/max_fuel；FuelPort 只提供加油交易，拆除、損壞或多裝入口均不改變存量／容量。BatterySocket 交換先檢查新電池與舊電池去處，滿背包使用原槽位；沒有有效插槽就沒有隱藏電量。

Chassis 物理步呼叫 VehicleEnergy：扣引擎油耗 → 依本車穩定 ID 呼叫正常發電機 → 電池待機支出 → 工作站 step_work。發電需要引擎運轉；無油停止引擎。發電機開關／門檻不會自動點火；燃油保留只限制發電附加負載。玩家進副本時室外照常模擬。

Prop 進 HopperArea → Scrapper 取得唯一 processing_owner，保存物理快照並隨機器定位 → 一個處理槽分步付費 → 固定一次回收結果 → MaterialStorage 接受後才刪物。缺電保留進度；滿庫保留完成結果；拆卸／摧毀恢復輸入物理。

RecipeDefinition/RecipeCatalog 定義四個配方。平板只 request_craft，工作站檢查有效性／完整電費並預留材料，進度逐步耗電；取消退材料，已用電不退。完成後檢查出料空間才生成；堵塞保留待出料工作。spawn_item 的即時介面也在完整驗證後扣材料與電費，失敗回復。成品屬於本世界 WorldEntities，繼承 RV 點速度；製作電池初始電量為零。

MaterialStorage 保存底盤數字材料，material_capacity 預設 300；容量不依賴設備，超額只允許消費／退款，不再領出 Material Bundle。底盤 stored_items 保存完整道具記錄，item_capacity 預設 24 格。ItemBox 開啟不耗電的 item_storage_ui；同車箱子共用底盤倉庫，先驗證容量／背包大型限制再轉移，按鈕保留原項目快照以拒絕過期操作。搬移、損壞、斷線與玩家死亡關閉 UI。

### 駕駛、維修與保存

控制仍由 Chassis 集中協調，未另做 VehicleController 類別。引擎狀態與入座分離，方向鍵遙控只可由測試明確啟用。輪槽常駐，即使沒有輪胎仍可射線互動；輪胎 ID／condition 在拆裝間保留。RepairOperation 累計持續瞄準時間，一般設備／輪胎完成才扣 2 Metal Parts 並補 60 HP；引擎另用專用維修包；切換目標、移動車輛、發動引擎或中斷免費取消。

Checkpoint autoload 在主場景攔截 F6/F9。保存限室外 NORMAL 模式、沒有 POI 轉場或地形建立中。Variant 序列化禁用 objects，版本 3；先寫 .tmp、flush，再 rename 至 user://rv_checkpoint.save。讀取先驗證格式、版本、資源、支撐 ID 和循環。

檢查點包括玩家背包／位置／生命、世界 seed／profile／有效 bands、RV、鬆散 actors 與已訪 POI 記憶。主場景 enter_tree 先配置保存的地形範圍，生成時跳過動態物資；ready 建立車輛／設備、接回支撐 ID、電池、輪胎、油料、材料及工作，最後恢復模擬。分解機持有輸入不重複列入室外 actors。版本 1 經記憶體轉換後驗證：車載燃油歸原底盤、舊電池建立插槽；游離油箱燃油及材料包（含背包、世界、POI、分解輸入）歸第一台保存車輛。保留超額材料，必要時提高燃油容量避免遺失，原檔不被讀取覆寫。新存檔保存道具倉庫及底盤容量，電池只存於設備 service。未知版本拒絕；目前沒有室內保存、多槽或未載入室外歷史恢復。

### 攀爬與戰鬥

玩家 W 加 RV 壁面命中，通過法線／高度／頭頂條件開始攀爬。套 RV transform 差並保留碰撞；W 登頂，S／Space 脫離；過大角速度、位移、失去接觸或頂部阻擋會中止。

Monster 結合 NavigationAgent3D、直接追蹤 fallback、卡住監測與高度協助。MonsterBoarding 管理附近入口選擇、掛門／登頂模式、接觸前相對速度抽樣、抓握耐力、恢復和車頂失衡；ClimbMath／RVSupport 仍負責碰撞、登頂與隨車支撐，不改玩家攀爬策略。車門提供實際 leaf 邊界與關閉狀態；不把整個門框當成葉片。

所有攻擊最後經過 boarding.can_attack，掛門攻擊只由掛門流程發出，攀牆途中與抓穩期間禁止結構攻擊。屋頂破壞仍由 UnderfootProbe 與玩家高度授權。車身運動取樣跨短暫地板接觸缺失保持連續，避免重新接觸誤判從靜止加速。RVSupport.capture 在 is_on_floor 成立但缺少滑動碰撞時，用膠囊腳底短射線驗證真實支撐，避免地板吸附造成逐影格漏跟車；支撐拆除仍立即失效。碰撞前保存怪物世界速度，車撞／抓握共用 ClimbMath.point_velocity；高速撞擊先於抓握，並有傷害／重抓冷卻。

MonsterBoardingVisual 僅處理程序生成手臂與原創 PCM 空間音效，透過 attack_landed 接收真正命中的事件，不改碰撞形狀。抓握、模式和導航目標屬暫態，讀檔重新判斷，不改 checkpoint 格式。

MonsterCabinRoute 是目前 4 × 12 m RV 的局部 AStar3D 步行圖，20 cm 網格、實際角色膠囊重疊／掃掠檢查，含對角連線。目標或車輛改變及每 0.65 秒重新規劃；路點存在車輛本地座標，隨轉向／平移轉換。落在設備上時從真實高度檢查離開桌面的水平路段，再由重力落地。近戰終點需視線可及，不單純靠近座位中心；玩家不可及時不把車內設備當替代攻擊目標。RVStructureSlots 提供被拆除後仍存在的破口位置，開門角度至少 70° 且完整膠囊可通過才視為出口。走道封死等待重規劃，車內不使用隨機跳躍脫困。DriverSeat 碰撞拆為座墊／底座與椅背，避免整塊盒子包住乘員而完全阻擋近戰。圖不保存至 checkpoint，也不取代室外 NavigationAgent3D。

CombatTargeting 做一般排序，Monster 觀測候選並執行攻擊。腳下設備只能由 UnderfootProbe 實際命中選取，且需較低位置的追蹤玩家授權；同 physics tick 共用射線結果，其他攻擊路徑排除同一支撐目標，避免繞過授權。

一般移動時，已在近戰距離／高度範圍且視線通暢的玩家優先於接觸設備與拆頂目標，直接進入 ATTACK；接觸攻擊不能先消耗其共用冷卻。攀車目標更新只選目標，不逐影格覆寫 CHASE，避免阻止攻擊狀態執行。待機取 detection_range、追擊／攻擊取 lose_interest_range。Player 的受傷無敵計時在座位／介面移動鎖之前更新，兩者不會延長無敵。正式場景回歸見 test_monster_pursuit.gd。

一般移動時，已在近戰距離／高度範圍且視線通暢的玩家優先於接觸設備與拆頂目標，直接進入 ATTACK；接觸攻擊不能先消耗其共用冷卻。攀車目標更新只選目標，不逐影格覆寫 CHASE，避免阻止攻擊狀態執行。待機取 detection_range、追擊／攻擊取 lose_interest_range。Player 的受傷無敵計時在座位／介面移動鎖之前更新，兩者不會延長無敵。正式場景回歸見 test_monster_pursuit.gd。

## 6. 已知限制

- 設備仍是獨立凍結剛體。重量／重心已彙總，但側撞與大型外掛的碰撞力矩未合併到車體；翻車、偏載、怪物群需專項實測。
- 控制、輪槽與登錄仍共用 Chassis；能源、材料、保存已抽離，後續可按需求再拆控制／掛載服務。
- 配方出料以目前產品大小的 0.28 m 球體檢查；新增更大產品前需按實際形狀擴充。
- 車上抽象材料、燃油與鬆散貨物尚未動態計重。首版檔位不模擬離合器／轉速。
- 保存只支援室外檢查點，沒有多人所有權、室內直接保存或多槽；道路仍單向串流。
- 副本目前兩種四門房型和一種外觀，內容多樣性與長局效能仍需擴充驗收。
- 真實輪驅與停車倒車測試通過，但燃油關閉的測試場不是長途資源平衡證據；未宣稱全部玩法與模擬步組合完成驗收。

## 7. 測試與維護

### POI 資產層與副本驗證

`world/poi_kit/` 提供 `PoiRoom`、`PoiDoorSocket`、`PoiFurniture`、`PoiLootPoint` 與 `PoiEntrance`。房間原點在地板中心，接點 local -Z 朝外；`connect_to()` 依完整 transform 接合不同尺寸房間，拒絕不相容接口。Visuals、Collision、Furnishings 與標記彼此獨立。主遊戲使用 maze_utility、maze_hall 四門變體；展示保留原始房型。

物資點只提供使用呼叫者 RNG 的 `roll_scene()`，不在 `_ready` 生成。入口只發出 `entry_requested(player, destination_id)`，主遊戲交由 PoiInstanceManager 管理。獨立資產展示仍只傳送到樣板區。`.tscn` 可直接編輯，首次建立腳本拒絕覆蓋既有輸出。詳見 [製作規格](world/poi_kit/README.md)。

`test_poi_asset_kit.gd` 驗證接點旋轉、物資物理支撐、正式玩家穿越與互動射線入口。`test_poi_instances.gd` 驗證 100 個 seed 的連通性／環路／重現、正式主場景入口、隔離、外部電量、錨點、拾取／掉落／死亡／重返與實際跨房導航。`poi_instance_playground.tscn` 的 F6 回放正式場景入口、連接走廊步行及返回；實機觀察與自動檢查分開記錄。

### 統一驗證

[scripts/test.ps1](scripts/test.ps1) 先 headless import，再執行全部 `tests/test_*.gd`，最後主場景 120 frames；等待實際 Godot process，檢查退出碼、錯誤日誌，測試需有 `PASS:`。CI 為 [tests.yml](.github/workflows/tests.yml)，日誌在 `.godot/test-logs/`。

| 測試 | 關注範圍 |
|---|---|
| [test_player_inventory](tests/test_player_inventory.gd) | 格數、選取、大型限制、消耗 |
| [test_equipment_lifecycle](tests/test_equipment_lifecycle.gd) | 玩家授權、取消、跨 RV 連線、正確車輛供電 |
| [test_combat_targeting](tests/test_combat_targeting.gd) | 獨立選敵策略 |
| [test_monster_navigation](tests/test_monster_navigation.gd) | 導航、高度、碰撞、攀爬和攻擊 gates，尤其腳下射線授權 |
| [test_player_climbing](tests/test_player_climbing.gd) | 攀爬幾何與 helper 契約 |
| [test_player_climbing_runtime](tests/test_player_climbing_runtime.gd) | 玩家 runtime 攀爬 |
| [test_moving_rv_climbing](tests/test_moving_rv_climbing.gd) | 生產場景、移動 RV 攀爬／支撐／拆頂，含物理驅動情境 |
| [test_world_entities](tests/test_world_entities.gd) | chunk 刪除後容器存活、場景重建 |
| [test_rv_systems](tests/test_rv_systems.gd) | 電池交易、能源、正式設備工作／清理、失效授權 |
| [test_rv_extended](tests/test_rv_extended.gd) | 底盤容量、加油孔、維修、輪胎、重量、長停耗電 |
| [test_rv_shared_storage](tests/test_rv_shared_storage.gd) | 掉落電池、共用道具倉庫、滿庫／滿背包、引擎救援、舊檔轉換 |
| [test_rv_checkpoint](tests/test_rv_checkpoint.gd) | 磁碟與主世界重建、電池及生產所有權 |
| [test_rv_resource_cycle](tests/test_rv_resource_cycle.gd) | 搜刮、回收、製作、加油、維修、充電與再出發 |
| [test_rv_physics_regression](tests/test_rv_physics_regression.gd) | 正式 RV 裝載設備穩定性 |
| [test_poi_resources](tests/test_poi_resources.gd) | POI／loot／enemy 資源可載入 |

本次改版見 [共用儲存驗收](docs/validation/2026-09-16-rv-shared-storage.md)。先前執行結果見 [RV 驗收紀錄](docs/validation/2026-09-15-rv-systems.md)。文件更動檢查連結與來源；程式更動執行適用測試及統一 runner。物理更動另須依 [AGENTS.md](AGENTS.md) 做互動視覺檢查。資源交易、能源與保存已有正式場景回歸；長途經濟、極端翻車和怪物群仍需擴大驗收。

遵循 GDScript tabs、可行時明確型別、snake_case 檔案／函式、PascalCase class、UPPER_SNAKE_CASE 常數；重用 core 契約。新增 POI 必須有有效內容，新增物品需設回收產出，設備需驗證連線／取消／毀損。

地形預設每帶 151×51 個頂點，行駛中分批取樣、組裝及安置；導航背景烘焙，無獨立作業執行緒生成場景節點。`test_world_generation.gd` 驗證 100 seed、載入順序、坡度、停車與實際網格／導航接縫；`test_roadside_exploration.gd` 使用正式玩家從停車區走到物資、以 E 拾取再返回。`highway_playground.tscn` 提供正式輪驅 5 km 及停車倒出回放。量測、測試環境與限制見 [驗收紀錄](docs/validation/2026-09-15-highway.md)。


## RV 外觀與駕駛室原型（2026-09-16）

預設 RV 更新為 WAYFARER 工業露營車：深綠車殼、奶油白窗框／屋頂、橘色標示、透明有碰撞的玻璃、前後燈與輪圈。側牆分成六片：面向車頭時，右側由前到後為牆／門／牆，左側為牆／牆／牆；後方是一組向外開啟的雙扇大門。每片側牆、側門整組、後門整組可獨立搬移與破壞，屋頂仍為一整片。

駕駛座綁定座椅、方向盤、儀表台、排檔桿、手煞車與踏板，F 搬移整組。方向盤跟隨底盤轉向，排檔桿／手煞車位置與速度、油電儀表同步車況；操控沿用 B、Space、Z/X/C、R/T。駕駛時背包欄隱藏，底部顯示車況與操作提示，離座恢復。加油孔與電池插槽位於車外維護側。

[模型結構說明](rv/visuals/README.md)；[展示場景](tests/rv_design_workshop.tscn)（F2 外觀、F3 車內、F4 駕駛、F5 輪驅、F6 舊版、F7 控制台）。舊車殼保留在 [rv/legacy/new_rv.tscn](rv/legacy/new_rv.tscn)。

### 分片結構、槽位與門扇

- `rv/structure_slots.gd` 由底盤持有九個永久槽：六側面、前、後、頂。以射線與槽位平面求交，空槽不依賴牆面碰撞；槽位預覽僅在搬移時顯示。
- `rv_panel.gd` 保存 `structure_kind`／`mount_slot`，安裝在底盤座標，鄰片互不支撐；搬移時發送 removing，釋放真正附掛於該片的設備。
- `rv_door.gd` 沿用 Equipment 所有權：門框、可旋轉門扇碰撞都屬同一根剛體，傷害、維修、F、保存只處理一組。葉片視覺與碰撞同步；開關預檢完整掃掠路徑，動畫中逐步複查動態阻擋。
- `EquipmentPlacement` 優先選相容槽位並自動旋轉；`PlacementRules.rejection_reason` 共用實際碰撞檢查和玩家提示。V 仍可回到自由貼面／直立放置。
- snapshot 沿用 v2 的可選 service.mount_slot／door_angles，校驗槽型、重複占用、固定變換與有限角度。載入會冪等轉換原廠位置的舊長牆，重連其設備到對應分片；自訂舊牆保持原狀，游離設備不占槽。
- `test_rv_structure_modules.gd` 驗證拆裝、取消、傾斜底盤、阻擋、動態夾阻後反向開啟、依附掉落、獨立破壞、雙扇互動、保存與舊檔轉換。新增視覺測試場 `rv_door_playground.tscn`。

實測及限制見 [分片牆與門驗收](docs/validation/2026-09-16-rv-structure-doors.md)。

## 完整 RV、引擎與車況（2026-09-16）

- EngineDefinition（engine_standard／engine_upgraded.tres）集中 450／600 耐久、1.0／1.25 動力、1.0／1.15 引擎油耗及重量；EngineState 只保存 id／model／health，item() 轉為含同 ID 的大型道具記錄。
- 固定 EngineBay 持有唯一安裝狀態。Chassis.exchange_engine／remove_engine 原子轉移同格背包，service_reason 共用停穩／熄火／手煞車／開蓋條件。Chassis.take_damage 轉交引擎，has_working_engine 和 engine_start_reason 統一啟動條件；沒有底盤 HP 或整車毀損旗標。
- RepairOperation 對引擎使用 repair_requirement 契約；鎖住目標、引擎 ID 與維修包 ID，連續 3 秒後再次驗證並消耗道具，+150 耐久。一般設備／輪胎沿用材料路徑。
- VehicleEnergy 依引擎定義計算基礎油耗；只有有效引擎能運轉，發電仍由獨立設備提供。處理充電、待機、工作後統一支付車燈負載，lamps_powered 為實際供電結果。
- VehicleStatus.read 回傳 8 項圖示／等級／文字；CockpitVisual、VehicleDashboard、TabletUI 讀同一結果，沒有副本數值。VehicleLights 控制真實 SpotLight3D 與燈罩發光；舊裝飾燈材質不再常亮。
- chassis.tscn 原生網格與簡單複合碰撞保留舊輪槽和車殼座標。正式 new_rv 預裝完整服務；Equipment.initial_support 僅設定新場景預設依附（平板→工作台）。讀檔由已保存 support ID 還原，不套預設配置。
- RearRamp 是底盤固定子節點；檢查手煞車、速度、兩扇門角、地面法線與兩端支撐、完整展開路徑。1.4 m 寬斜面碰撞及兩折視覺分開，展開阻止 engine_force 並保持煞車，仍可怠速。收起檢查上方占用；狀態保存 deployed／angle／length。
- DriverSeat 離座以 current_driver 的實際 Shape3D／局部變換和碰撞遮罩搜尋支撐地板。正常受阻保留所有權；破壞、拆除、死亡強制搜索外圈支撐／上方淨空並解除座位。
- EquipmentPlacement 對自由放置累積繞面法線的旋轉和切面平移，細調後重新射線確認接觸仍屬原支撐，再用 PlacementRules 驗證。結構槽維持固定姿態。接觸箭頭與控制提示跟隨預覽清理。
- RVPanel.dependency_summary 沿 mount_support 遍歷本車設備，區分直接與間接依附。PanelWear／EngineAppearance 只讀耐久，複製材質實現磨損／玻璃裂紋，絕不改變碰撞或狀態所有權。
- v3 VehicleSnapshot 保存 engine_item、headlights、hatch_open、ramp。v1／v2 沿用結構／儲存轉換，再以車輛 ID 衍生穩定標準引擎 ID、舊 HP 轉入；v3 不重新遷移或補發。EngineState.unique_ids 對車輛快照與整份檢查點（含背包／地面／倉庫／POI／分解輸入）驗證引擎唯一性，並驗證模型與道具場景一致。
- CraftingStation 依實際產物根層碰撞檢查出料空間，大型引擎使用較高出料位置；完成但阻塞的工作留在佇列，不重複出貨或扣款。

### 新增驗證入口

| 測試 | 覆蓋 |
|---|---|
| test_rv_engine.gd | 預裝、引擎所有權、滿背包交換、大型道具、故障服務、維修、性能差、車燈、v2／v3 與實際引擎製作 |
| test_rv_boarding.gd | 正式角色攜引擎走坡板／走道，展開阻擋／占用／坡度、驅動互鎖、安全離座與自由放置 |
| test_rv_checkpoint.gd | 磁碟往返：安裝／背包／倉庫／地面引擎 ID、型號、耐久，以及拒絕跨所有權重複 |
| rv_rebuild_playground.tscn | 可見引擎艙／坡板／汽車儀表／夜間車燈／真實輪驅回放 |

完整測試與實機證據見 [驗收紀錄](docs/validation/2026-09-16-rv-rebuild-engine.md)。本機 Godot 4.7.2；CI 目標仍 4.6.1。外掛設備撞擊力矩、極端翻車、怪物群和長途經濟未因此視為完成。

## 工業恐怖美術（2026-09-17）

- `IndustrialArt` 快取室外 StandardMaterial3D 與 256px 程序材質；兩張原創生成紋理位於 `assets/materials/industrial/`，Godot 匯入限制為 512px、使用 mipmap。室外建築以 mesh override 改外觀，不能修改室內共用的 POI 材質資源。
- RV 的共享掉漆材質維持 StandardMaterial3D；PanelWear／EngineAppearance 使用 detail multiply 疊加損傷，保留原本貼圖。健康狀態仍是老舊外觀，損傷／修復由原耐久資料驅動。
- CabinLighting 附在車頂 Equipment，兩盞暖色燈使用既有待機供電狀態，不建立新電池／存檔／控制開關。屋頂失效、搬移、拆離或無電時熄滅；既有待機耗電涵蓋其常駐照明。
- IndustrialTheme 統一背包、生命、駕駛 HUD、平板及道具箱配色、方角框線、按鈕焦點。保留原字體與中文 fallback、資訊布局、互動及原生 UI 解析度。
- 本輪不改生成版本、地形／導航／碰撞或存檔格式；副本的 3D 材質與照明不在範圍內。驗證見 `docs/validation/2026-09-17-industrial-art.md`。
