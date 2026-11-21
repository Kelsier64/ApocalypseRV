# POI、場址與室內

公路沿線與野地裡可以搜刮的地點：加油站、路旁小場址、民用避難所、軍事地堡與巨型避難所。這份文件說明每種場址有什麼、怎麼進出室內，以及它們的生成與保存契約。場址出現在哪裡見 [world](world.md#場址出現在哪)，開場的兩座建築見 [opening](opening.md)，新增一個 POI 的步驟見 [POI 製作](../guides/poi-authoring.md)。

## 功能一覽

| 功能 | 範圍 | 來源 | 測試場 |
|---|---|---|---|
| POI 定義 | 每個 POI 一份資源：場景、類型、可放的位置、佔地、入口 | [PoiDefinition](../../world/poi_definition.gd)、[POIConfig](../../world/poi_config.gd)、`world/poi_definitions/` | |
| 場址生成 | 檢查定義與場景後放進世界，副本入口另外向轉場管理器登記 | [POISpawner](../../world/poi_spawner.gd) | |
| 可步行場址 | 直接走進去的建築：首次到訪抽物資，離開後保存剩下的東西 | [WalkInSites](../../world/terrain/walk_in_sites.gd) | |
| 加油站 | 雙面油價牌與雙翼雨棚標出站址。前院後方左側是商店、右側是維修間，可帶走汽油罐。 | [建築說明](../../world/poi_kit/buildings/README.md) | [gas_station](../../tests/playgrounds/gas_station_playground.tscn)、[production](../../tests/playgrounds/production_gas_station_playground.tscn) |
| Mile End 鄉間小站 | 折板棚下有一座停用的機械油泵。可從店前穿到卸貨後院。 | [小站場景](../../world/roadside_pois/mile_end/station.tscn) | [mile_end](../../tests/playgrounds/mile_end_playground.tscn) |
| 路旁小場址 | 六種主題各三套配置 | [MinorSites](../../world/terrain/minor_sites.gd)、[資產說明](../../world/roadside_pois/README.md) | [minor_poi](../../tests/playgrounds/minor_poi_playground.tscn)、[production](../../tests/playgrounds/production_minor_poi_playground.tscn) |
| 副本轉場 | 從入口進入獨立的室內世界、切換相連的室內、返回戶外 | [PoiInstanceManager](../../world/instances/poi_instance_manager.gd) | [poi_instance](../../tests/playgrounds/poi_instance_playground.tscn) |
| 室內組裝 | 依配置擺房間、封牆、烘導航、放內容、保存與還原 | [PoiInterior](../../world/instances/poi_interior.gd)、[InteriorLayout](../../world/instances/interior_layout.gd)、[InteriorProfiles](../../world/instances/interior_profiles.gd) | |
| 隨機軍事地堡 | 多層房間迷宮，有物資、補給箱、怪物與一具強化引擎 | [BunkerContent](../../world/instances/bunker_content.gd)、[BunkerCache](../../world/instances/bunker_cache.gd)、[BunkerLighting](../../world/instances/bunker_lighting.gd)、[地堡指南](../guides/bunker-interior.md) | [bunker](../../tests/playgrounds/bunker_playground.tscn) |
| 勤務樓梯與無燈柱廳 | 室內的側門通往樓梯間，再往下接到另一座副本 | [bunker_stair_access.gd](../../world/instances/bunker_stair_access.gd)、`InteriorProfiles.STAIR_DESTINATIONS` | |
| 巨型避難所外殼 | 由種子生長出來的封閉無窗大樓 | [MegashelterPlan](../../world/megashelter/megashelter_plan.gd)、[ModularMegashelter](../../world/megashelter/modular_megashelter.gd)、[外殼指南](../guides/megashelter-exteriors.md) | [megashelter](../../tests/playgrounds/megashelter_playground.tscn)、[world](../../tests/playgrounds/megashelter_world_playground.tscn)、[viewer](../../tests/playgrounds/megashelter_viewer.tscn) |
| 巨型避難所室內 | 地面一層的小型公共避難所 | [MegashelterInteriorLayout](../../world/instances/megashelter_interior_layout.gd)、[MegashelterInteriorContent](../../world/instances/megashelter_interior_content.gd)、[室內指南](../guides/megashelter-interiors.md) | [interior](../../tests/playgrounds/megashelter_interior_playground.tscn) |
| 探索地圖 | 室內按 M 顯示走過的房間 | [interior_map.gd](../../world/instances/interior_map.gd) | |
| 房型套件 | 房間、門接口、家具、物資點與入口的共用元件 | [world/poi_kit/](../../world/poi_kit/README.md) | |

自動測試：[test_poi_transition_persistence.gd](../../tests/test_poi_transition_persistence.gd) 涵蓋轉場、取消、保存、巨型避難所室內與樓梯串接；[test_world_contracts.gd](../../tests/test_world_contracts.gd) 涵蓋越野場址與巨型避難所外殼的生成契約；[test_checkpoint_failures.gd](../../tests/test_checkpoint_failures.gd) 涵蓋地堡與巨型避難所的存讀。

## 規則與數值

### 兩種 POI

- **可步行場址**（`WALK_IN`）：建築就在戶外世界裡，直接走進去搜刮。
- **副本入口**（`INSTANCE_ENTRANCE`）：戶外只有外殼與一扇門，按 E 進入另一個獨立的室內世界。

| 場址 | 定義 ID | 類型 | 出現位置 | 內容 |
|---|---|---|---|---|
| 地堡入口 | `maintenance`、`warehouse`、`pump`、`research` | 副本入口 | 路旁的主要停靠點、野地 | 四種外觀，裡面都是隨機軍事地堡 |
| 加油站 | `gas_station` | 可步行 | 路旁的主要停靠點 | 商店、維修間、後院與加油棚裡的物資 |
| 廢棄鄉間小站 | `mile_end` | 可步行 | 公路空檔 | 店面寬深、棚距、封板與家具隨站址種子變化。雜貨架、工具桌與行軍床各有對應物資；後門卸貨處另抽汽油罐。 |
| 路旁小場址 | `roadside_<主題>_<0–2>`，主題為 `wreck`、`camp`、`shed`、`checkpoint`、`cargo`、`rest` | 可步行 | 路旁；`camp` 與 `shed` 也出現在野地 | 少量物資；`cargo` 與 `shed` 可能藏著油桶人 |
| 民用避難所 | `civilian_shelter`、`courtyard_shelter` | 可步行 | 只在野地 | 荒廢的小型混凝土避難所與物資 |
| 巨型避難所 | `modular_megashelter` | 副本入口 | 只在野地 | 地面一層的公共避難所，可往下通到地堡 |

野地的一般場址抽中後，種類的比例寫在 `OffroadSites._plan_site`：四成是地堡入口，兩成是民用避難所（兩款各半），四成是營地或棚屋。巨型避難所另外排程。

野地的場址依自然地面的高度與隨機朝向擺放，只在建築佔地與外圈的步行空間整地，沒有車道、標誌或圍牆。路旁的場址面向道路，前方留出停車的空地。

### 可步行場址

- 第一次靠近時，場址依建築裡的物資點抽出物資。之後不再補貨。
- `cargo` 與 `shed` 場址會多放一個油桶當掩護，並依定義的 `enemy_count_range` 抽出零到兩個位置，每個位置有 `BarrelManSettings.MINOR_CHANCE` 的機率是油桶人，否則是空的。Mile End 小站在店側或後院抽一個候選位置，沿用相同機率，也有一個普通油桶。場址的怪物刷新規則待重新設計，見 [GDD 第 9 節](../../GDD.md#section-9)。
- 玩家離開、場址所在的區塊卸載時，場址範圍內所有的物品與活著的怪物會被收起來，包含玩家帶來丟下的東西。回來時原樣放回。車輛與車上的東西不算場址的。
- 加油機是造景，沒有加油功能。可拾取的汽油罐照一般物品的規則使用。

### 進出副本

- 面向入口的門按 E。載入期間玩家不能操作，畫面顯示 `Preparing <名稱>...`。
- 玩家在室內時，戶外世界照常運作：RV 繼續耗油耗電，外面的威脅不會暫停。區塊串流以入口位置為中心。
- 室內只聽得到室內的聲音。每種室內有自己的殘響：地堡像小房間，樓梯間像走廊，無燈柱廳與巨型避難所像大廳。
- 室內是另一個世界，怪物不會跨過門追出來或追進去。黑影在室內的遭遇見 [enemies](enemies.md#白影與黑影)。
- 在室內入口處的 EXIT 按 E 回到戶外，出現在建築門前；門前被擋住時往外找最近的空位。
- 按 M 開關地圖，Page Up／Page Down 切換樓層。地圖只畫出走過的房間、房間之間的連線與樓梯。
- 再次進入同一個副本時，房間配置、剩下的物資、補給箱的內容、活著的怪物與玩家留下的東西都和離開時一樣。不補貨，死掉的怪物不復活。
- 在室內不能用 F6 存檔，見 [saves](saves.md#什麼時候能存能讀)。

### 隨機軍事地堡

- **規模**：新地堡抽一個目標房間數與樓層數，範圍在 `world/instances/catalog/bunker.tres` 的 `min_rooms`、`max_rooms`、`max_floors`。房間從入口沿著門接口往外長，接口用完或樓梯放不下時，實際規模會比目標小。
- **房型**：入口、樓梯，以及通道、走廊、小、中、大、廳六類普通房間；各類被抽中的比重在同一個檔案的 `group_weights`。
- **強化引擎**：一具耐久七成的強化引擎放在離入口最遠、放得下的房間。它是大型物品，要徒手搬回 RV。
- **物資**：散落的零件與補給箱的數量隨房間數增加，算式在 `BunkerContent.populate`。每個補給箱有兩件物資。放得下的位置不夠時會比較少。
- **補給箱**：長按 E 一秒取出一件。背包滿了物品就留在箱裡。
- **怪物**：依房間數取得一到四次機會，每次有 `BunkerContent.ENCOUNTER_CHANCE` 的機率生成一隻，所以可能一隻都沒有。生成位置要離入口夠遠（沿房間連線與直線距離各有下限）。生成的怪物有 `BarrelManSettings.BUNKER_CHANCE` 的機率是油桶人，其餘是 Raker。
- **照明**：入口與樓梯有燈，其餘房間有 `BunkerLighting.DARK_FRACTION` 的比例熄燈。室內沒有環境光，熄燈的房間要靠手電筒。哪些房間熄燈由種子決定，回訪不變。

### 勤務樓梯與無燈柱廳

- 巨型避難所的地面層會有一扇勤務鋼門；地堡有三分之一的機會有一扇。門開在普通房間沒有接上的牆面接口，找不到合格的位置時就沒有門。
- 門後是樓梯間，往下走兩段折返梯，底部的門通往另一座副本：地堡或無燈柱廳，比重在 `InteriorProfiles.STAIR_DESTINATIONS`。目的地由種子決定，回訪不變。
- 無燈柱廳是一座沒有燈的大型柱廳，不放物資，也不生成地堡的怪物。遠端還有一扇門通往下一座樓梯間，所以往下的路沒有固定的盡頭。
- 回程沿原路一層一層走回去，每扇門都回到當初進來的位置。每座副本各自保存。

### 巨型避難所

- **外殼**：封閉無窗的大樓，量體由種子一步步長出來，沒有固定的平面範本。外殼本身沒有物資與怪物。規格見[外殼指南](../guides/megashelter-exteriors.md)，材質見[材質說明](../../assets/materials/megashelter/README.md)。
- **室內配置**：接待室、大廳、勤務走道，加上三到五間功能房（寢室、醫療、倉儲、食堂、勤務、衛生之中抽選）。外殼面積越大，功能房越多；面積夠大時改用大尺寸的房型。算式在 `MegashelterInteriorLayout.generate`。
- **內容**：一個補給箱（一件食物、一件零件）與二到四件散落的物資（食物與零件交替）。沒有怪物，也沒有強化引擎。
- **照明**：功能房有 `MegashelterInteriorLighting.DARK_FRACTION` 的比例熄燈，接待室、大廳與走道保持照明。
- **出口**：接待室的大門與小門都能離開。

### 還沒做的

- 加油機的加油或交易功能。
- 巨型避難所地面層以外的樓層。

## 實作契約

### 定義與生成

- 每個 POI 是一份 `PoiDefinition` 資源，登錄在 `POIConfig.DEFINITIONS`。`kind` 決定是可步行還是副本入口，`placement_modes` 決定能放在路旁、野地或兩者，兩個欄位互不相干。
- `POIConfig.GENERATION_IDS` 是地堡入口的抽選順序。改動順序會讓既有種子抽到不同的入口。
- `POISpawner.spawn_site` 遇到以下情況會警告並放棄，不會退回預設場景：未登錄的 ID、定義不支援這個放置類別、`PoiDefinition.validate` 或 `validate_scene` 有錯誤、副本入口指定了未登錄的室內 profile。
- `validate_scene` 要求場景有 `Visuals`、`Collision`、`Furnishings`、`LootSpawns` 四層，`Visuals` 底下不能有碰撞或物資點。可步行場址不能含入口或 `SubViewport`；副本入口必須有 `PoiEntrance` 與返回點。
- 只有副本入口會向 `PoiInstanceManager` 登記。副本的保存 ID 是場址的穩定 ID（生成版本、種子與場址座標）。
- `POIConfig.instantiate_site(site, include_visuals)` 是建立外觀的唯一入口。區塊本身與相鄰區塊的導航都呼叫它，所以碰撞與範圍一定相同。巨型避難所在這裡套用 `site.exterior_plan`。

### 可步行場址的生命週期

- `WalkInSites.activate` 在場址的區塊載入時執行。沒有紀錄的場址抽物資並寫入 `WorldGenerator.outdoor_sites`；有紀錄的場址只還原保存的物件。
- 物資、怪物數量與怪物種類各用自己的亂數流，路旁主要場址、路旁小場址與野地場址的 domain 也分開（見 `activate` 裡的 `rng_for` 呼叫）。
- `WalkInSites.deactivate` 在區塊卸載時執行，以場址的 `bounds` 判斷歸屬，用 `WorldActorSnapshot` 收起物件。
- 開場的兩座建築由 `OpeningSiteContent.populate` 放固定的內容，不走物資點。
- `outdoor_sites` 的每筆紀錄帶有 `definition_id` 與 `content_version`。存檔裡的版本與定義不同時，整份存檔被拒絕（`WalkInSites.validation_error`）。
- 定義的 `enemy_count_range` 只在 `cargo` 與 `shed` 場址生效（`WalkInSites._barrel_site`）。其他定義填了數值也不會生成怪物。

### 副本轉場

- `PoiInstanceManager` 有五個狀態（`State`），每次轉場取一個遞增的操作序號。等待期間序號變了，舊的流程就自己結束。
- 進入時建立一個 `own_world_3d` 的 `SubViewport`，在裡面組裝 `PoiInterior`。組裝完成才把玩家節點搬進去；戶外世界的節點都不動。
- 室內畫面透過根視窗的 `TextureRect` 顯示，輸入轉送進子視窗。室內開啟設定選單時，合成層會提高到選單之上的層級。
- 在相連的室內之間切換時，先保存目前的室內，並留著它的畫面，直到下一個室內準備好。來時的路記在 `_route_stack`，離開時逐層取回。
- 轉場超過 `transition_timeout_ms`、玩家死亡或組裝失敗時走 `cancel_transition`：已經進到室內的話先保存室內狀態，把玩家放回戶外，清掉暫建的視窗。
- 離開時先等一幀讓拾取與死亡結算，再拍快照寫入 `saved_instances`。釋放室內之前會等導航烘焙結束。
- 子副本的保存 ID 由上層的 ID 加後綴組成（見 `enter_link` 與 `_stair_child_id`）。改動後綴會讓已探索的子副本對不上。

### 室內組裝

`PoiInterior.build` 依序做：檢查 profile 與保存資料 → 取得配置 → 擺房間、套用照明、封住沒用到的門接口 → 建立出口 → 烘焙導航 → 開連通門 → 放內容或還原補給箱 → 還原物品與怪物 → 檢查內容走得到 → 啟動怪物。任何一步失敗就回傳失敗，轉場取消。

- **配置**：保存過的配置原樣使用，絕不重抽；新增房型或改比重不會改變到訪過的副本。`InteriorLayout.validate` 檢查房型版本、樓層、重疊、門接口對齊與連通，不合格的配置被拒絕。
- **房型**：以 ID 加 `content_version` 解析。門接口的位置只取自房間場景裡的標記。新增普通房型只要加場景與資源，不用改生成器。
- **profile**：`InteriorProfiles.get_profile` 只認登錄過的 ID，存檔無法指定任意資源。樓梯間與無燈柱廳是被動 profile，不放內容。
- **導航**：烘焙來源是靜態碰撞。烘完後發布一份不再變動的網格，等導航區域與地圖都同步，再確認每個房間都能從入口走到。放了補給箱之後重烘一次。
- **內容的亂數**：配置、內容、怪物種類、熄燈房間與勤務門位置各用自己的種子，都從配置的種子衍生。熄燈房間與勤務門用雜湊排序決定，不消耗亂數，也不佔存檔欄位。
- **內容只放一次**：有保存資料的副本只還原，不呼叫 `populate`；空的副本回訪時仍然是空的。
- **物件歸屬**：室內的物品與怪物掛在室內自己的 `WorldEntities` 底下。只有玩家與背包會跨世界移動。
- **勤務門**：門位要有站立淨空，而且從入口走得到。找不到合格的門位時不放門，室內照常可以進入（`_add_stair_access`、`bunker_stair_access.gd`）。巨型避難所的門位每次進入時重新計算，地堡的門位存在配置的 `stair_access`。

### 存檔

F6 把 `PoiInstanceManager.saved_instances` 存進檢查點的 `poi` 欄位，把 `WorldGenerator.outdoor_sites` 存進 `outdoor_sites` 欄位。`CheckpointSchema.poi_error` 依 `layout.profile` 檢查每座副本的配置、探索紀錄、內容與補給箱。存檔的整體規則見 [saves](saves.md)。
