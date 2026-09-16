# ApocalypseRV 架構

更新：2026-09-16。描述目前程式；玩法與願景見 [GDD](GDD.md)，啟動與驗證見 [README](README.md)。[docs](docs/README.md) 收錄計畫、驗收紀錄與 archive 歷史封存。

## 1. 執行環境與場景

目標開發／CI 版本 Godot 4.6.1，Jolt Physics、GL Compatibility renderer。[project.godot](project.godot) 的入口為 [world/test_world.tscn](world/test_world.tscn)。目前沒有網路同步或任務／進度管理器；Checkpoint autoload 提供主世界檢查點。

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
└── 地面設備、物品、殭屍      主場景測試實例
```

發電、分解、合成與平板設備起初在場景地面，須放置到車上才能連線；引用設備場景不等於開局已有完整生產鏈。

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
| 背包 | PlayerInventory | `{name, is_large, scene_path, state}` 陣列、active_slot；state 保存 ID、condition、scrap_yields、回收結果及電池子型別資料 |
| 玩家模式 | player.gd | NORMAL／PLACING／UI／SEATED／DEAD，由欄位推導優先模式，非完整集中狀態機 |
| 移動 | 各 actor | NORMAL／CLIMBING、附著 RV、前一 transform、接觸寬限、冷卻、RVSupport |
| 怪物意圖 | Monster | WANDER／CHASE／ATTACK、追蹤玩家、攻擊目標 |
| 車輛 | Chassis＋VehicleEnergy＋MaterialStorage | 控制、4 輪槽身分／耐久、底盤耐久、電池與材料；相容屬性轉送至專責狀態 |
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

串流比較室外玩家或副本錨點 Z，仍只向 −Z 推進。WorldField 以世界座標計算有界平面曲線；道路高度取低頻地形需求，按 150 m 高度節點限坡，再 smoothstep 插值。WorldProfile 預設路寬 15／10 m、坡度上限 8%、區域長 900 m／過渡 240 m。seed_for(index, domain) 隔離道路、停靠、裝飾、loot、敵人和副本亂數，入口 ID 為 v2:world_seed:stop:index；重播的是生成配置，不是物理與 AI 時序。

外部停靠點以 450±75 m 的位置間隔配置，起始維修站固定在 (49,0,-45)，其餘每三點兩個小型搜刮點和一個入口。spawn_site 接受完整 building/road/frame 變換、穩定 id 和副本 seed。停車、建築平台及展寬支道以同一地表查詢整平，公路範圍維持道路高度。固定曲線與充足整地範圍保證預設模板可安置，沒有另加無界重抽候選。九種路旁場景位於 world/roadside_kit，首次生成腳本拒絕覆蓋既有美術。

地形網格使用相鄰取樣圈計算法線，邊界共享世界位置及高度。導航以實際靜態碰撞烘焙，排除僅高 7 cm 的重複瀝青層，補上相鄰地形資料避免 agent radius 蝕刻造成斷路；細節誤差設定為 2 voxel，避免噪音坡面重疊細三角形。植被小叢使用 MultiMesh；大物件有簡化碰撞及顯示距離。遠景左右及前方使用低細節網格，只提供視覺。舊 world/building 沒有恢復。

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

控制仍由 Chassis 集中協調，未另做 VehicleController 類別。引擎狀態與入座分離，方向鍵遙控只可由測試明確啟用。輪槽常駐，即使沒有輪胎仍可射線互動；輪胎 ID／condition 在拆裝間保留。RepairOperation 累計持續瞄準時間，完成才扣 2 Metal Parts 並補 60 HP；切換目標、移動車輛、發動引擎或中斷免費取消。

Checkpoint autoload 在主場景攔截 F6/F9。保存限室外 NORMAL 模式、沒有 POI 轉場或地形建立中。Variant 序列化禁用 objects，版本 2；先寫 .tmp、flush，再 rename 至 user://rv_checkpoint.save。讀取先驗證格式、版本、資源、支撐 ID 和循環。

檢查點包括玩家背包／位置／生命、世界 seed／profile／有效 bands、RV、鬆散 actors 與已訪 POI 記憶。主場景 enter_tree 先配置保存的地形範圍，生成時跳過動態物資；ready 建立車輛／設備、接回支撐 ID、電池、輪胎、油料、材料及工作，最後恢復模擬。分解機持有輸入不重複列入室外 actors。版本 1 經記憶體轉換後驗證：車載燃油歸原底盤、舊電池建立插槽；游離油箱燃油及材料包（含背包、世界、POI、分解輸入）歸第一台保存車輛。保留超額材料，必要時提高燃油容量避免遺失，原檔不被讀取覆寫。新存檔保存道具倉庫及底盤容量，電池只存於設備 service。未知版本拒絕；目前沒有室內保存、多槽或未載入室外歷史恢復。

### 攀爬與戰鬥

玩家 W 加 RV 壁面命中，通過法線／高度／頭頂條件開始攀爬。套 RV transform 差並保留碰撞；W 登頂，S／Space 脫離；過大角速度、位移、失去接觸或頂部阻擋會中止。

Monster 結合 NavigationAgent3D、直接追蹤 fallback、卡住監測與高度協助。攀爬時判斷目標是否仍在同車，登頂後由 RVSupport 維持支撐。車撞傷害依接近方向與速度門檻。

CombatTargeting 做一般排序，Monster 觀測候選並執行攻擊。腳下設備只能由 UnderfootProbe 實際命中選取，且需較低位置的追蹤玩家授權；同 physics tick 共用射線結果，其他攻擊路徑排除同一支撐目標，避免繞過授權。

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
- snapshot v2 增加可選 service.mount_slot／door_angles，校驗槽型、重複占用、固定變換與有限角度。載入會冪等轉換原廠位置的舊長牆，重連其設備到對應分片；自訂舊牆保持原狀，游離設備不占槽。
- `test_rv_structure_modules.gd` 驗證拆裝、取消、傾斜底盤、阻擋、動態夾阻後反向開啟、依附掉落、獨立破壞、雙扇互動、保存與舊檔轉換。新增視覺測試場 `rv_door_playground.tscn`。

實測及限制見 [分片牆與門驗收](docs/validation/2026-09-16-rv-structure-doors.md)。
