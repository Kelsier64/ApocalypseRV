# ApocalypseRV 架構

更新：2026-09-15。描述目前程式；玩法與願景見 [GDD](GDD.md)，啟動與驗證見 [README](README.md)。[docs](docs/README.md) 收錄計畫、驗收紀錄與 archive 歷史封存。

## 1. 執行環境與場景

目標開發／CI 版本 Godot 4.6.1，Jolt Physics、GL Compatibility renderer。[project.godot](project.godot) 的入口為 [world/test_world.tscn](world/test_world.tscn)。目前沒有網路同步、存檔服務或任務／進度管理器。

本機專案已由既有修改標為 4.7，本次 POI 和地形以安裝的 Godot 4.7.2 實測；CI 仍為 4.6.1，尚未驗證兩版結果一致。

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
│       ├── Wheel_*         執行時 VehicleWheel3D 與互動 hitbox
│       └── 座椅／車板       固定的 Equipment
└── 地面設備、物品、殭屍      主場景測試實例
```

發電、分解、合成與平板設備起初在場景地面，須放置到車上才能連線；引用設備場景不等於開局已有完整生產鏈。

## 2. 模組責任

| 模組 | 檔案 | 邊界 |
|---|---|---|
| 玩家協調 | [player.gd](player/player.gd) | 攝影機、移動、攀爬、生命、座位／UI／放置授權、手持外觀 |
| 玩家背包 | [player_inventory.gd](player/player_inventory.gd) | 6 格、選取、大型限制與消耗，不持有場景節點 |
| 互動 | [player_interact.gd](player/player_interact.gd) | 射線、E 短長按、F 搬運、輪胎安裝特例 |
| 放置 | [equipment_placement.gd](player/equipment_placement.gd) | 預覽位置／朝向、確認／取消輸入 |
| 可撿物 | [interactable_item.gd](props/interactable_item.gd) | Prop 剛體、名稱、大型旗標、回收產出與手持配置 |
| RV | [chassis.gd](rv/chassis.gd) | 驅動、油電、材料字典、輪槽、底盤耐久 |
| RV 互動轉接 | [fuel_filler.gd](rv/fuel_filler.gd)、[wheel_hitbox.gd](rv/wheel_hitbox.gd) | 加油入口、拆輪 |
| 設備基類 | [equipment.gd](equipment/equipment.gd) | 放置、物理／材質恢復、連線快取、耗電、破壞 |
| 專用設備 | [equipment/](equipment/) | generator 供電、scrapper 回收、tablet_screen/UI 顯示製作、crafting_station 出料、driver_seat 駕駛 |
| 串流 | [world_generator.gd](world/world_generator.gd) | 固定座標區塊窗口、分幀建立、遠景與距離清理 |
| 世界資料 | [world_field.gd](world/terrain/world_field.gd)、[world_profile.gd](world/terrain/world_profile.gd) | 獨立 RNG、三層噪音、區域權重、道路及停靠計畫、共用高度查詢 |
| 地形道路 | [chunk_generator.gd](world/chunk_generator.gd) | 網格、碰撞、路面、停靠設施、裝飾、實際碰撞導航和物資／敵人 |
| POI 外部 | [poi_config.gd](world/poi_config.gd)、[poi_spawner.gd](world/poi_spawner.gd) | 單一維修站內容表、朝向公路、註冊入口 |
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
| 背包 | PlayerInventory | `{name, is_large, scene_path, state}` 陣列、active_slot；state 保留 scrap_yields |
| 玩家模式 | player.gd | NORMAL／PLACING／UI／SEATED／DEAD，由欄位推導優先模式，非完整集中狀態機 |
| 移動 | 各 actor | NORMAL／CLIMBING、附著 RV、前一 transform、接觸寬限、冷卻、RVSupport |
| 怪物意圖 | Monster | WANDER／CHASE／ATTACK、追蹤玩家、攻擊目標 |
| 車輛 | Chassis | 油電、材料 Dictionary、4 輪槽、耐久／毀損旗標 |
| 設備 | Equipment | 原父節點／transform、預覽、材質、碰撞例外、連線快取、耐久 |
| 串流 | WorldGenerator | active_chunks 的 node/index/start_z/end_z、next_band、building、WorldField 和 profile |
| 副本 | PoiInstanceManager／MazeLayout | active_id、saved_instances actor 快照、rooms／edges、局部 RNG |

地形、入口和路旁靜態模組由 chunk 擁有。動態敵人、搜刮物、玩家丟棄品、合成品和死亡掉落使用所屬世界的 WorldEntities。室內與主場景根節點都以 entity_domain metadata 指定自己的容器，避免初始 ready 時 current_scene 尚未設定而落到 SceneTree 根。WorldGenerator 只清理同一 World3D、錨點後方超過 450 m 的動態物件。玩家進副本後，錨點固定在進入前位置。

例外：主場景既有物品仍在根部，拆下輪胎由 wheel_hitbox.gd 加到 chassis 的父節點，不受容器直接子節點清理。室內物資和怪物死亡掉落都使用室內容器。

玩家 `enter_*`／`exit_*` 授權 UI、座位與放置，呼叫方須尊重拒絕。DEAD 尚未完整封鎖輸入／移動；enum 存在不等於所有分支已覆蓋。

## 5. 主要流程

### 世界

WorldGenerator 建立 WorldField／WorldProfile／POISpawner → 初始後 2／目前 1／前 3 個固定網格帶 → 查詢區域／道路／停靠計畫 → 共用整地結果生成地表、路面與碰撞 → 安置靜態內容 → 烘焙導航並生成動態內容。行駛中的建立分多影格執行，完成前不發佈到 active_chunks；一次只有一個建立作業。

串流比較室外玩家或副本錨點 Z，仍只向 −Z 推進。WorldField 以世界座標計算有界平面曲線；道路高度取低頻地形需求，按 150 m 高度節點限坡，再 smoothstep 插值。WorldProfile 預設路寬 15／10 m、坡度上限 8%、區域長 900 m／過渡 240 m。seed_for(index, domain) 隔離道路、停靠、裝飾、loot、敵人和副本亂數，入口 ID 為 v2:world_seed:stop:index；重播的是生成配置，不是物理與 AI 時序。

外部停靠點以 450±75 m 的位置間隔配置，起始維修站固定在 (49,0,-45)，其餘每三點兩個小型搜刮點和一個入口。spawn_site 接受完整 building/road/frame 變換、穩定 id 和副本 seed。停車、建築平台及展寬支道以同一地表查詢整平，公路範圍維持道路高度。固定曲線與充足整地範圍保證預設模板可安置，沒有另加無界重抽候選。九種路旁場景位於 world/roadside_kit，首次生成腳本拒絕覆蓋既有美術。

地形網格使用相鄰取樣圈計算法線，邊界共享世界位置及高度。導航以實際靜態碰撞烘焙，排除僅高 7 cm 的重複瀝青層，補上相鄰地形資料避免 agent radius 蝕刻造成斷路；細節誤差設定為 2 voxel，避免噪音坡面重疊細三角形。植被小叢使用 MultiMesh；大物件有簡化碰撞及顯示距離。遠景左右及前方使用低細節網格，只提供視覺。舊 world/building 沒有恢復。

MazeLayout 使用 10 欄、27 m 中心間距，建立 50–100 個 9 m／18 m 房間。隨機 DFS 產生連通樹，再增加少量鄰接邊形成環路。PoiInterior 放置四門預製場景、封閉閒置門、連接走廊，依實際靜態碰撞（含家具）非同步 bake 導航；動態物資與敵人在 bake 後建立。各房物資點獨立隨機排序，最多成功抽取 4 件。

PoiInstanceManager 在入口互動後鎖定玩家輸入、建立 own_world_3d 的 SubViewport，完成載入後 reparent 原玩家與 UI。根 CanvasLayer 顯示 viewport texture，輸入轉交子 viewport，視窗縮放同步。退出先保存室內 Prop 的場景、位置、回收資料及活怪生命／位置，再把原玩家移回主世界並檢查返回落點，釋放副本幾何。saved_instances 只保存本局記憶體資料，重返重建同 seed 房間並還原剩餘 actors，沒有跨局存檔。非活動副本不繼續模擬。

WorldEntities.same_world 用於群組選敵、碰撞例外及串流清理；怪物每 physics tick 清掉跨世界的快取玩家目標。怪物與物品不穿越入口，只有原玩家與背包轉移。實例快照目前支援 Prop／Monster，未支援搬入副本的任意設備。

### 設備放置

F 長按 → 玩家授權 → 記錄原父節點與位置，凍結碰撞、套 ghost 材質 → 射線預覽貼面／直立朝向 → 確認時找命中物 RV 祖先，掛到 RV；非 RV 則掛命中物 → 刷新碰撞例外和連線。

取消恢復原父節點與 local transform。連線快取每次驗證祖先和 RV 契約；早期查無結果不永久快取，外部 reparent 可重新解析。沒有距離供電或接線網路。

目前可放判斷主要是射線命中，沒有完整體積重疊或 props／怪物黑名單。取消恢復固定物理設定，不是完整還原原始自由剛體狀態。

### 油電與生產

Prop 進 HopperArea → Scrapper 凍結、耗電處理 → 抽 scrap_yields → `Chassis.add_item` → `inventory_changed` 更新平板。

平板開啟扣電 → 解析 RV → 顯示油電材料 → 查配方與同車 crafting_stations → 扣材料 → 合成站載入場景、扣電 → WorldEntities 生出實物。

油電集中在 Chassis，發出 `fuel_changed`／`power_changed`；平板換車重新連訊號。Generator 每 physics tick 主動補自己 RV 的電，底盤不逐幀掃發電機群組。Scrapper 在 `_process` 按 delta 處理。

### 攀爬與戰鬥

玩家 W 加 RV 壁面命中，通過法線／高度／頭頂條件開始攀爬。套 RV transform 差並保留碰撞；W 登頂，S／Space 脫離；過大角速度、位移、失去接觸或頂部阻擋會中止。

Monster 結合 NavigationAgent3D、直接追蹤 fallback、卡住監測與高度協助。攀爬時判斷目標是否仍在同車，登頂後由 RVSupport 維持支撐。車撞傷害依接近方向與速度門檻。

CombatTargeting 做一般排序，Monster 觀測候選並執行攻擊。腳下設備只能由 UnderfootProbe 實際命中選取，且需較低位置的追蹤玩家授權；同 physics tick 共用射線結果，其他攻擊路徑排除同一支撐目標，避免繞過授權。

## 6. 已知限制

- 製作非原子交易：tablet_ui 先扣材料，忽略 spawn_item 失敗，沒有退款；最低可用電力不等於出料費足夠。
- 副本只有兩種四門房型和一種外觀；布局雖有 50–100 間，獨特房型、美術變體及長局效能仍需擴充驗收。
- 底盤毀損後 physics／入座入口未全面封鎖重啟，未形成終局。
- 玩家死亡、平板設備毀損和放置生命週期仍需完整情境驗收，不能只由部分測試推論正確。
- 外部生成和清理假設單向旅行；副本有同局重返，但缺跨局存檔、外部回訪還原及多人所有權。
- 極端翻車、群體攀爬及放置重疊尚未完整驗收；長途輪驅只驗證固定 seed 測試路線，不能推論所有車輛負載和駕駛方式。

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
| [test_poi_resources](tests/test_poi_resources.gd) | POI／loot／enemy 資源可載入 |

以上描述測試範圍，不代表本次已執行。文件更動檢查連結與來源；程式更動執行適用測試及統一 runner。物理更動另須依 [AGENTS.md](AGENTS.md) 做互動視覺檢查。資源交易、長途經濟、極端翻車和怪物群仍是測試缺口。

遵循 GDScript tabs、可行時明確型別、snake_case 檔案／函式、PascalCase class、UPPER_SNAKE_CASE 常數；重用 core 契約。新增 POI 必須有有效內容，新增物品需設回收產出，設備需驗證連線／取消／毀損。

地形預設每帶 151×51 個頂點，行駛中分批取樣、組裝及安置；導航背景烘焙，無獨立作業執行緒生成場景節點。`test_world_generation.gd` 驗證 100 seed、載入順序、坡度、停車與實際網格／導航接縫；`test_roadside_exploration.gd` 使用正式玩家從停車區走到物資、以 E 拾取再返回。`highway_playground.tscn` 提供正式輪驅 5 km 及停車倒出回放。量測、測試環境與限制見 [驗收紀錄](docs/validation/2026-09-15-highway.md)。
