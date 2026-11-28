# 世界生成與串流

戶外世界由種子與規則生成：一條沿 -Z 前進的公路、兩側的地形與森林、沿路的場址與事件。這份文件說明世界入口、生成規則、串流與可破壞的景物。場址內容與室內見 [poi](poi.md)，怪物行為與偏行壓迫見 [enemies](enemies.md)，日夜與天氣見 [environment](environment.md)。

程式在 [world/](../../world/)、[world/terrain/](../../world/terrain/) 與 [world/scatter/](../../world/scatter/)。

## 功能一覽

### 世界入口

| 場景 | 用途 | 與正式世界的差異 |
|---|---|---|
| [main_world.tscn](../../world/main_world.tscn) | 正式入口 | 兩室教學開場、完整戶外與副本循環、F6／F9 檢查點 |
| [demo_world.tscn](../../world/demo_world.tscn) | 快速展示 | 固定種子、單間車庫開場、固定小霧且天氣不變化、無限材料與燃油；開車離開後安排一次 Slender Speaker 遭遇；開場背包有指南針與手電筒 |
| [cheat_test_world.tscn](../../world/cheat_test_world.tscn) | 作弊測試 | 單間車庫開場，無限燃油、電力與材料 |
| [test_world.tscn](../../world/test_world.tscn) | 世界基底場景 | 沒有開場流程，地上直接放了幾件物品；其餘入口都繼承它的腳本 |

四個入口都用 `WorldProfile.CURRENT_GENERATION` 生成。F6／F9 只在正式入口有反應，見 [saves](saves.md)。

### 戶外世界

| 功能 | 範圍 | 來源 | 測試場 |
|---|---|---|---|
| 串流 | 依玩家位置前後載入區塊，可回頭；一次只建一個區塊，分幀進行 | [WorldGenerator](../../world/world_generator.gd)、[ChunkGenerator](../../world/chunk_generator.gd) | [highway](../../tests/playgrounds/highway_playground.tscn) |
| 世界查詢 | 道路、高度、場址與亂數流，全部是種子與世界座標的純函數 | [WorldField](../../world/terrain/world_field.gd)、[WorldProfile](../../world/terrain/world_profile.gd) | |
| 道路 | 連續彎道、寬窄變化、升降 | [TerrainRoute](../../world/terrain/terrain_route.gd) | [highway](../../tests/playgrounds/highway_playground.tscn) |
| 地貌 | 草原、懸崖、濕地、山脊、峽谷、森林盆地 | [TerrainLandforms](../../world/terrain/terrain_landforms.gd) | [terrain](../../tests/playgrounds/terrain_playground.tscn) |
| 河川與橋梁 | 河谷、水面、跨河橋與護欄 | [TerrainCrossings](../../world/terrain/terrain_crossings.gd)、[BridgeBuilder](../../world/terrain/bridge_builder.gd) | [terrain](../../tests/playgrounds/terrain_playground.tscn) |
| 森林 | 樹木、灌叢與可撞毀的樹幹碰撞 | [ForestScenery](../../world/terrain/forest_scenery.gd) | [tree impact](../../tests/playgrounds/tree_impact_playground.tscn) |
| 地形特徵 | 池塘與湖、泥土支線、路旁與野地的遺跡場景、高壓電塔 | [WorldFeatures](../../world/terrain/world_features.gd)、[FeatureBuilder](../../world/scatter/feature_builder.gd) | [world detail](../../tests/playgrounds/world_detail_playground.tscn) |
| 散佈 | 巨石、倒木、樹樁、草、蕨、蘆葦等程序化小物 | [ScatterScenery](../../world/scatter/scatter_scenery.gd)、[ScatterCatalog](../../world/scatter/scatter_catalog.gd) | [world detail](../../tests/playgrounds/world_detail_playground.tscn) |
| 道路設施 | 路面、路肩、電線桿、彎道標誌、標柱、路燈 | [RoadDetails](../../world/terrain/road_details.gd)、[RoadsideStreetlights](../../world/terrain/roadside_streetlights.gd) | [world detail](../../tests/playgrounds/world_detail_playground.tscn) |
| 場址排程 | 主要停靠點、路旁小場址、越野場址、巨型避難所 | `WorldField.stop`、[MinorSites](../../world/terrain/minor_sites.gd)、[OffroadSites](../../world/terrain/offroad_sites.gd) | |
| 公路事件 | 廢車、釘帶、油桶、油桶人 | [RoadSpawns](../../world/road_spawns.gd) | [highway](../../tests/playgrounds/highway_playground.tscn) |
| 起點後方的車群 | 開場後方的固定廢車 | [RearWreckLayout](../../world/starting_shelter/rear_wreck_layout.gd) | [rear pressure](../../tests/playgrounds/rear_pressure_playground.tscn) |
| 撞倒景物 | RV 與 Slender Speaker 撞倒樹、灌叢、標誌、標柱與圍欄 | [TreeImpact](../../world/terrain/tree_impact.gd)、[TreeFall](../../world/terrain/tree_fall.gd)、[BreakableProps](../../world/scatter/breakable_props.gd) | [tree impact](../../tests/playgrounds/tree_impact_playground.tscn) |

自動測試：[test_streaming_generation.gd](../../tests/test_streaming_generation.gd) 檢查區塊幾何、森林配置與碰撞；[test_world_contracts.gd](../../tests/test_world_contracts.gd) 以純取樣檢查道路、場址與生成契約。

## 規則與數值

數值寫在程式裡，這裡只說規則與它們在哪。

### 世界的形狀

- 世界沿 -Z 無限延伸，切成固定長度的區塊（`WorldProfile.chunk_length`）。可行走的地形寬度是 `terrain_half_width` 的兩倍，更遠只有看得到、走不到的遠景。
- 公路在這個寬度內左右彎曲，但永遠往 -Z 前進，不會折返。
- 起點之後的第一段是平直的安全路段，沒有彎道、坡度與公路事件（`RoadSpawns.SAFE_DISTANCE`）。
- 路寬沿途在窄路與寬路之間變化（`TerrainRoute.width`，由 `narrow_width` 與 `road_width` 決定）；坡度不超過 `max_grade`；彎道不小於 `min_turn_radius`。急彎與長坡需要減速。
- 地貌每隔一段路換一種（`TerrainLandforms.REGION_LENGTH`、`KINDS`）。地貌決定地表顏色、樹木與地被密度、濕度與岩石裸露程度，也決定池塘、支線與遺跡出現的機率。
- 河川橫過公路時有橋。水只是景觀與障礙，沒有游泳或水流玩法。

### 場址出現在哪

| 種類 | 排程 | 來源 |
|---|---|---|
| 開場避難所 | 起點固定一座 | `WorldField.stop(0)` |
| 主要停靠點 | 沿路每隔 `stop_spacing` 一個位置，前後抖動 `stop_jitter`；每三個位置依序是探索入口、加油站、空位 | `WorldField.stop` |
| 路旁小場址 | 每個 `MinorSites.CELL_LENGTH` 區間至多一座，主題與配置各自抽選 | `MinorSites.plan` |
| 廢棄鄉間小站 | 在主要停靠點的空位獨立抽選，避開河谷、相鄰車道及所有既有場址，用獨立場址 ID 記錄初訪與回訪。 | `WorldField._plan_fuel_station` |
| 越野場址 | 離路的網格（`OffroadSites.CELL_LENGTH`、`CELL_WIDTH`、`COLUMNS`），每格先抽有沒有場址，再抽種類 | `OffroadSites.plan` |
| 巨型避難所 | 每個 `MEGASHELTER_CELL_LENGTH` 區間嘗試放一座，地形或其他場址擋住就沒有；另外一般越野場址有 `MEGASHELTER_CHANCE` 的機率換成巨型避難所 | `OffroadSites.plan_megashelter` |

場址會避開道路、河川與橋的引道、過陡的地形，以及其他場址。位置不合格時那個位置就沒有場址，不會無限重抽。各類場址的內容見 [poi](poi.md)。

### 公路事件

每個區塊各自抽一次，四種事件互不影響（`RoadSpawns.plan`）：

| 事件 | 規則 | 常數 |
|---|---|---|
| 廢車 | 0 到 4 台，多數區塊沒有；每台獨立選位置與朝向，可能擋住整條路。廢車不能清除 | `_wreck_count` |
| 釘帶 | 至多一條，橫在路面上 | `STRIP_CHANCE` |
| 油桶 | 至多一個，放在路面中央區域，可以拾取 | `BARREL_CHANCE` |
| 油桶人 | 至多一隻，站在路面中央區域 | `BARREL_MAN_CHANCE` |

- 安全路段、橋上與橋的引道沒有任何公路事件。
- 每個事件最多試 `ATTEMPTS` 次位置；都不合格就不放，所以實際數量可能少於抽到的數量。
- 油桶、油桶人只在第一次到達時生成。拾取、爆炸、死亡或離開後再回來都不會補。
- 起點後方另有一批固定的廢車（至多 `RearWreckLayout.MAX_WRECKS` 台），開局時決定一次，之後不變。
- Slender Speaker 的路段遭遇與偏行壓迫見 [enemies](enemies.md)。

### 景物

景物只有外觀與碰撞，不產生物資或敵人：

- **道路**：有磨損與補丁的路面、碎石路肩、電線桿與電線、急彎前的警告標誌、彎道外側的危險標誌、標柱。標誌只有符號，沒有文字。
- **自然散佈**：巨石、露頭、樹樁、倒木、碎石、蕨類、蘆葦、高草與幼樹，依地貌分佈。
- **人類遺跡**：路旁的拋錨車、施工區、公車亭、看板、工具小屋；野地的廢屋、貨櫃堆、伐木場、乾草田、圍欄與拖拉機。部分由泥土支線從公路接出，盡頭是廢屋、小聚落、伐木場或貨櫃堆。支線不通往越野場址。
- **大型結構**：池塘、少數大湖、沿路的高壓電塔與電纜。

### 撞倒景物

- RV 以夠快的速度（`TreeImpact.MIN_SPEED`）正面或斜向撞上樹幹，樹會折斷倒下，RV 保留大部分速度（`SPEED_RETAINED`）並依實際損失的速度受損。低速、擦過後離開、或從上方落下都不會撞斷。
- 灌叢、標誌、標柱與圍欄同樣可以撞倒，損失的速度比樹少（各自的 `vehicle_speed_retained`）。
- Slender Speaker 走路或追擊時碰到樹也會撞倒。
- 現行版本會保存撞倒的森林樹木、灌木與路旁設施。倒下的斷木與落葉是暫時的效果，一段時間後消失。森林樹木改為僅在本次遊玩保留倒樹狀態的施工與驗收見[世界生成重構計畫](../plans/world-generation-overhaul.md#倒樹與檢查點)。

### 還沒做的

- 游泳、水流與湖泊玩法。
- 跨路的隧道與天橋。道路兩側會被整平，沒有自然路塹可以放隧道。

## 實作契約

### 同一個種子生成同一個世界

- `WorldField` 的所有查詢都是種子與世界座標的純函數，不讀已載入的節點，也不用全域亂數。區塊以任何順序載入，結果都一樣。
- 每種內容用自己的亂數流：`WorldField.rng_for(id, domain)`。新增一種內容時要取新的 domain 名稱，不能借用別人的亂數流，否則會改動既有內容的位置。
- `seed_for` 把最近幾個生成版本對應到同一組亂數（見函數內的註解），所以升版不會移動既有的場址與事件。domain 名稱裡的版本字樣（例如 `road_v9_`）只是亂數流的名字，不是版本分支。
- 程式只生成 `WorldProfile.CURRENT_GENERATION` 這一個版本，沒有舊版本的生成路徑。

### 串流

- `WorldGenerator._process` 以玩家位置算出目前的區塊，維持後方 `chunks_behind`、前方 `chunks_ahead` 的範圍。玩家在 POI 室內時改用 `PoiInstanceManager.stream_anchor`。正式世界的範圍寫在 [main_world.tscn](../../world/main_world.tscn) 的 profile 資源裡。
- 一次只建一個區塊（`building`），先補離玩家最近的缺口。區塊建完才加進 `active_chunks`。
- 玩家站在某個場址範圍內時，`protected_bands` 會保留並補建那個場址佔用的區塊，即使它們已經在串流範圍外。
- 區塊的導航還在烘焙時不會被卸載（`retire_band`）。
- 區塊卸載時，位在它上面的物品（含固定在它的靜態物上的物品）收進 `dormant_items`，區塊重新載入時還原。落在玩家後方超出範圍的零散物品同樣收起來，其他非物品的動態物件直接移除。
- 怪物依目前位置判斷：距離串流錨點超過 `RoadSpawns.SAFE_DISTANCE` 就移除，不看它在哪個區塊出生。這項清理每 0.5 秒跑一次。
- 已載入的可步行場址（`walk_in`）裡的怪物與物品不受上述清理影響。
- 遠景地形（`_refresh_horizon`）從預載視窗的最前緣往外生成，開車載入更前面的區塊時再往前推。遠景沒有碰撞。

### 區塊的建立順序

`ChunkGenerator.generate` 依序做：地表與碰撞 → 路面 → 河川與橋 → 路燈 → 公路事件的靜態部分（廢車、釘帶）→ 場址外觀 → 地形特徵 → 森林 → 散佈 → 導航 → 場址的物資 → 霧。

- 行駛中的建立是分幀的：每個時間片用完 `SLICE_BUDGET_USEC` 就讓出一幀。單次的網格或碰撞建構不能中斷，所以這是目標，不是幀時間上限。
- 每個區塊印出 `build_ms` 與 `max_slice_ms`，`WorldGenerator.generation_times` 留最近的紀錄。
- `WorldField.surface(x, z)` 是地形的唯一來源：它把道路、場址平台、河道與地形特徵混進同一次取樣。地表網格、碰撞、導航與物件擺放都讀它，所以相鄰區塊的邊界一定對得上。

### 只生成一次的東西

- `generated_bands` 記錄已經到過的區塊。回到這些區塊時，`skip_actors` 會跳過場址物資與公路怪物的生成。
- 公路怪物與油桶在導航發布之後才生成（`_spawn_road_monsters`），每個區塊只做一次，導航重烘焙不會再生成。
- 油桶的 ID 由生成版本、種子、區塊與序號組成，所以存檔與重載認得同一個油桶。
- 導航還沒發布時不能存檔，否則會存下「已到過」卻漏掉即將生成的怪物，見 [saves](saves.md)。
- 讀檔還原期間（`restoring_entities`）所有區塊都跳過動態內容，改由存檔還原。

### 導航

- 每個區塊烘焙兩張導航網格：一般怪物用的，以及 Slender Speaker 專用的（獨立的導航地圖 `giant_navigation_map`）。兩張都發布後 `navigation_ready` 才成立。
- 烘焙來源是靜態碰撞，並補上相鄰區塊接縫附近的樹木、橋與場址障礙。這些資料來自共用的生成計畫，不依賴鄰區塊是否已載入。
- 可撞毀的灌叢與輕型景物在 `TreeImpact.SHRUB_LAYER`，不進導航烘焙；RV 另外把這一層加進自己的碰撞遮罩。
- 樹被撞倒後，該區塊在短暫延遲後重烘焙（`request_navigation_rebuild`），接縫附近的鄰區塊一起更新。

### 地形特徵與散佈

- **地形特徵**（`WorldField.features`）以固定大小的格子規劃（`WorldFeatures.CELL`），一格完整擁有自己的特徵。規劃只能讀未混合的原始地形，**不能呼叫 `WorldField.surface()`**，因為 `surface()` 反過來要讀特徵的結果。
- `WorldFeatures.apply` 把水面、岸邊、支線路床與保留區套進 `surface()`。泥土支線的範圍寫進地形頂點色，由地形 shader 畫出來。
- [FeatureBuilder](../../world/scatter/feature_builder.gd) 把特徵建成節點，遺跡小場景來自 [VignetteKit](../../world/scatter/vignette_kit.gd)。
- **散佈**的每一層是 [ScatterCatalog](../../world/scatter/scatter_catalog.gd) 裡的一條規則（[ScatterLayer](../../world/scatter/scatter_layer.gd)），有自己的亂數流、各地貌的權重與程序化網格（[ScatterMeshes](../../world/scatter/scatter_meshes.gd)）。新增一種散佈物只要加一條規則。
- 散佈讀區塊的 [TerrainGrid](../../world/terrain/terrain_grid.gd)，把物件貼在實際的三角面上。有碰撞的散佈物與區塊接縫、路緣保持距離；路肩留給公路事件。
- 道路設施全部是路線的純函數（[RoadDetails](../../world/terrain/road_details.gd)），所以區塊可以算出鄰區塊的電線桿位置，把電線接過去。

### 撞倒景物

- 判定在 `TreeImpact.hit`：讀 RV 實際的物理接觸，要求水平速度與朝向接觸面的接近速度都夠大，而且接觸面不是朝上或朝下。
- 可撞倒的目標實作 `vehicle_tree_impact` 與 `vehicle_tree_is_broken`。樹幹是 [ForestScenery](../../world/terrain/forest_scenery.gd) 的共用碰撞體，用 shape 索引認單棵樹；輕型景物是 [BreakableProps](../../world/scatter/breakable_props.gd)，只和 RV 碰撞。
- RV 的處理在 [rv/chassis.gd](../../rv/chassis.gd)：先處理所有撞倒，再判斷剩下的接觸是否真的擋住車；被撞倒的目標不算阻擋。每個新撞倒的目標只結算一次速度損失與傷害，同一目標的多個接觸不重複計算。車損規則見 [rv](rv.md)。
- 撞倒狀態記在 `WorldGenerator.destroyed_trees`，`WorldField` 共用同一份。鍵的格式由 `TreeImpact.forest_id`、`shrub_id`、`roadside_id` 產生：樹與灌叢用區塊與生成索引，路旁景物用位置。
- 這份帳本獨立於可淘汰的森林快取（`WorldField.forest_cache`）。森林的位置計畫不看帳本，建立節點時才跳過已撞倒的樹，所以沒被撞倒的樹位置與外型不變。
- 存檔保存整份帳本，讀檔時先驗證（`TreeImpact.valid_ledger`）。
- 倒下的效果由 [TreeFall](../../world/terrain/tree_fall.gd) 產生：留下斷樁，樹幹切成帶物理的斷木，葉面散成小簇落地。碎片過一段時間、或離開視野後回收（尺寸與時間見 `TreeFall` 開頭的常數），隨區塊卸載釋放，不進存檔。
- 第一次建立森林前，`TreeFall.prepare` 會先在畫面外跑一次完整的倒樹效果，讓 shader 與音效在載入期準備好，避免第一次撞樹時卡頓。
