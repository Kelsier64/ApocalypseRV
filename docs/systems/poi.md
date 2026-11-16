# POI、場址與室內

加油站、路旁與越野場址、軍事地堡、巨型避難所，以及副本轉場。程式在 [world/poi_config.gd](../../world/poi_config.gd)、[world/instances/](../../world/instances/) 與 [world/poi_kit/](../../world/poi_kit/)；製作方式見 [POI 製作](../guides/poi-authoring.md)。

## 功能一覽

| 功能 | 現況與範圍 | 主要來源／測試場 |
|---|---|---|

| 十八套小 POI | 正式；camp／shed／wreck／checkpoint／cargo／rest 各三套，物資與遭遇；camp／shed 同時支援越野 | [roadside POIs](../../world/roadside_pois/README.md)、[minor POI](../../tests/minor_poi_playground.tscn)、[production](../../tests/production_minor_poi_playground.tscn) |
| 加油站與民用避難所 | 正式；NORTHLINE 商店／維修間／後院及兩款廢棄民用／庭院避難所可直接步行探索；加油機目前為造景 | [gas station](../../world/poi_kit/buildings/README.md)、[production gas](../../tests/production_gas_station_playground.tscn)、[POI config](../../world/poi_config.gd) |
| 巨型避難所外觀 | 正式；獨立候選密度、程序生長平面、多種結構／牆面／屋頂／入口細節，維持封閉無窗外觀；可經入口轉入室內 | [外殼指南](../guides/megashelter-exteriors.md)、[megashelter](../../tests/megashelter_playground.tscn)、[world](../../tests/megashelter_world_playground.tscn) |
| 巨型避難所室內 | 正式 v19；獨立單層、通常六至八模組、依外觀面積選房型；少量散物與一箱，無敵人／樓梯／升級引擎；大小出口門共用返回流程，回訪不補貨 | [室內指南](../guides/megashelter-interiors.md)、[interior playground](../../tests/megashelter_interior_playground.tscn) |
| 隨機軍事地堡 | 正式；四種入口、16 房型、目標 30–60 模組及 1–3 層；接口／樓梯空間可能使規模減少；暗房、補給箱、機率 Raker 與強化引擎 | [地堡指南](../guides/bunker-interior.md)、[bunker playground](../../tests/bunker_playground.tscn) |
| 副本轉場與探索地圖 | 正式；入口 E 進獨立 World3D、安全返回、探索圖與切層；外界 RV 油電持續，保存布局／探索／物資／箱子／敵人及玩家丟物 | [instance manager](../../world/instances/poi_instance_manager.gd)、[interior map](../../world/instances/interior_map.gd)、[poi instance](../../tests/poi_instance_playground.tscn) |

## 規則與數值

### POI 類型與加油站

POI 資產共用定義已區分「副本入口型」與「同世界直接探索型」。四款既有入口維持同一室內迷宮與原生成順序；生成 v5 已把加油站加入正式公路：第 1、4、7…號停靠點為同世界直接探索型（起點為第 0 號）。製作與接入流程見 [POI 共用規範](../guides/poi-authoring.md)。

另有獨立 [加油站探索測試場](../../tests/gas_station_playground.tscn)：商店、維修間、後門與加油棚可以在同一個室外世界直接步行探索，放置正式可拾取物資與 RV。加油機仍為停用造景；正式世界可搜刮物資，場址卸載保存剩餘物件，回程及檢查點重讀不重新抽物資。見 [資產規格](../../world/poi_kit/buildings/README.md)。

加油機外觀已使用專案自製 GLB，保留灰盒的碰撞尺寸；測試場 F6 近看、F7 切換灰盒／模型，僅作素材替換驗證，不改燃油玩法。

另見下方〈POI 與場址〉。

### 路旁與越野場址

路旁場址沿道路分布，維持各自的進出空間。越野場址由獨立世界網格抽選，按自然地面高度與隨機朝向配置；不配置公路／方向標誌、車道、停車線、林間步道、迷宮或周界牆。越野地堡只在建築入口局部整地。現行 POI 穩定 ID 使用生成版本與場址座標。

六種小型路旁 POI 各有三套手工佈局，共 18 套。POI 資產放置類別與資產定義分開，以 `ROADSIDE`、`OFF_ROAD` 旗標表示且可同時設定：四款地堡入口、camp、shed 支援兩類；wreck、checkpoint、cargo、rest 僅 roadside；civilian_shelter 與 courtyard_shelter 為 content v1 的小型荒廢民用混凝土避難所，僅 off_road 且可直接步行探索。路旁 POI 的物資、敵人及場址回訪狀態按原流程保存。歷史 v6 路旁生成規則曾按每 1,200 m 區間規劃，舊 1,000-seed 樣本平均約 1.25 km 一處；該數值不代表越野 POI 的間距或密度。越野網格每格 55% 成為候選，最多 8 次嘗試避開道路、水域、陡坡及其他 POI；候選池原權重為 40% 地堡、10% civilian_shelter、10% courtyard_shelter，其餘為營地或棚屋，另以獨立 2% 機率選擇巨型住宅外殼取代一般候選；巨型住宅另有每 300 m 一帶的獨立候選。場址穩定 ID 依生成版本、seed、row、column 組成。詳見 [小 POI 規格](../../world/roadside_pois/README.md)。

另見下方〈路旁小 POI 與越野場址〉。

### 生成、內容與副本

面向門短按 E。隨機軍事地堡使用 16 個模組（14 個普通變體、入口與樓梯），新訪目標 30–60 個模組、隨機 1–3 層，各層共用房型池。無平面邊界，接口耗盡可少於 30 間；樓梯放不下時保留較少樓層。首批六種尺寸可透過場景與 Resource 擴充，沒有固定必要主路。初訪會依獨立 RNG 在適合房間放置散落零件、補給箱與敵人遭遇，深處另有一具可帶回 RV 使用的強化引擎（70% 耐久）。散落零件目標 2–12 件、補給箱 1–5 個且各有兩件小型物資；合法位置不足時可更少。敵人最多有 `clamp(房間數 / 15, 1, 4)` 次合格房間生成機會，每次獨立以 30% 機率抽取，沒有保底，可有 0、1 或多隻。敵人生成須與入口相距至少 24 m 的房間連接距離及 18 m 空間距離；新訪地堡每個成功敵人名額有 20% 為油桶人，其餘為 Raker；已訪內容按原記錄恢復，不補怪。

M 顯示已探索分層地圖，Page Up／Down 切 B1–B3；沿實體樓梯往返並搬運大型道具。補給箱長按 E 1 秒，每次取得一件；背包已滿時物品留在箱內。HUD 提示強化引擎所在房間與返程方向。返回入口 EXIT 按 E 回室外。存檔保存實際布局、內容、補給箱剩餘物件與存活 actor；新增房型或改權重不重排已訪地堡。不支援的副本資料拒絕載入，不執行舊檢查點遷移。契約見 [地堡指南](../guides/bunker-interior.md)。

室內使用獨立 World3D 與家具碰撞導航，敵人不能跨入口追擊。外部世界繼續模擬，RV 油電和外部威脅不中斷；串流錨點留在進入處。離開時保存剩餘物品、位置、回收產出和存活敵人的生命／位置，卸載模型；同局重返用相同布局與保存狀態重建，不重抽物資、不復活已死亡敵人。F6 室外檢查點可把已訪副本記憶一起保存至磁碟，F9 還原；不支援在副本內直接保存。

公路支援往返串流；玩家在場址或對應副本期間保留場址所需區塊，離開後恢復清理。world_seed 與生成版本固定配置，各系統使用獨立 RNG，不保證戰鬥與動態物理逐影格重播。檢查點要求當前 generation_version、完整 profile 與所有狀態欄位。長局資源平衡、道路事件、分岔及廣域自由探索仍待後續。

來源：[世界](../../world/world_generator.gd)、[chunk](../../world/chunk_generator.gd)、[POI](../../world/poi_config.gd)、[副本](../../world/instances/)、[資產](../../world/poi_kit/README.md)。

### 內容版本與照明

新訪地堡使用房間內容版本 2：警衛、物資、醫療、寢室、倉儲、維修、指揮、機電與撤離生活區共用原 16 模組接口。牆面剝漆、鏽蝕、滲水、碎屑與故障設備表現重度廢棄；複雜設備先接功能灰盒並附建模 request，精細模型仍待交付。已訪房間內容版本 1 保留原場景及照明。

除入口與樓梯外，60% 普通模組（包含走廊，依實際數量四捨五入）主燈熄滅，燈管也不發光。亮暗分布依保存布局穩定重建，沒有重新抽物資或敵人。熄燈房間沒有環境光，只靠灰階暗部顯示辨識近處輪廓；入口與樓梯保留照明。

### 巨型避難所

越野候選中以獨立抽選出現的大型封閉無窗建築（`modular_megashelter`）：一部分取代該位置的一般 POI，另有每 300 m 一帶的獨立候選。外殼由 seed 逐步生長，不使用固定平面模板。

從入口進入獨立的地面一層：每棟有入口、大廳、三至五個功能房與少量連接空間，通常共六至八個模組；較大建築選較大房型，不增加大量房數。二至四件散放物資與一個補給箱，沒有敵人或升級引擎目標。箱內剩餘物資、拾取／丟物與探索進度隨布局保存，回訪不補貨。

通往勤務樓梯間的鋼門隨機設在接待室以外房間的牆面接口。樓梯間底門依 seed 抽選目的地（地堡 75%、無燈柱廳 25%），離開時可逐層返回原處。細節見[室內指南](../guides/megashelter-interiors.md)與[外殼指南](../guides/megashelter-exteriors.md)。

### 地堡房間與照明

新版地堡房間採重度廢棄軍事設施，包含寢室、醫療、倉儲、維修、指揮與機電空間。入口與樓梯保留照明，其餘模組約 60% 熄燈，回訪維持相同亮暗位置。手電筒在初始世界出生區旁，須自行拾取；切換物品或搬大型引擎時無法照明，剩餘電量會保存。既有地堡使用原房間版本，不重建家具或改燈。

## 實作契約

### POI 資產層與副本驗證

大型場址先分流為 WALK_IN 或副本入口，再建立各自配置；`ExplorationSite.select_side()` 共用既有側向避讓判定，不為加油站或開場據點建立再刪除地堡路線。`WalkInSites` 保管戶外啟用／休眠生命週期，開場終端、固定物資及工作坊 ID 由 `OpeningSiteContent` 提供，僅初訪生成。`PoiInstanceManager` 的正常離場與取消共用 viewport 清理，快照時機及等待原生導航烘焙完成後釋放幾何的規則不變。

`PoiDefinition`（`world/poi_definition.gd`）及 `world/poi_definitions/*.tres` 統一兩類 POI 的 ID、場景、場址範圍、入口路徑及室內 profile。POIConfig.DEFINITIONS 是資產目錄；GENERATION_IDS 是保留原順序的 v3／v4 生成池，兩者分開。POISpawner 與 chunk 鄰帶導航共用 scene_for_site，未知 ID 不退回預設；場址以 definition_id 指定已登錄資產。生成時只為 INSTANCE_ENTRANCE 註冊 PoiInstanceManager；入口與返回路徑由定義傳入 metadata，未使用定義的 caller 保留原節點路徑預設。v5 的 WalkInSites 使用定義 site_bounds 整地、清空植被及保護跨帶場址；戶外保存記錄 content_version，不支援的版本拒絕載入，尚無自動佈局遷移。詳見 [共用規範](../guides/poi-authoring.md)。

加油站 `fuel_pump.tscn` 以 `Visuals/Model` 實例化 `assets/models/gas_station/fuel_pump.glb`，Collision 保留原三塊 BoxShape3D，模型上的 Godot 文字標籤已移除。GLB 不帶碰撞或行為；來源為 `scripts/build_fuel_pump_glb.py`。測試場 F7 只切換新舊 Visuals，原碰撞物件不重建。

`world/poi_kit/buildings/gas_station.tscn` 是同世界可步行進出的靜態建築資產，分離 Visuals、Collision、Furnishings、LootSpawns、AccessPoints 與 Lights。資產不自行產生物資，也不持有副本管理器；`tests/gas_station_playground.gd` 負責測試地面、導航烘焙、正式玩家／RV 及一次性固定 seed 物資生成，道具進入 WorldEntities。生成 v5 已接入正式串流、場址與檢查點。

`world/poi_kit/` 提供 `PoiRoom`、`PoiDoorSocket`、`PoiFurniture` 與 `PoiLootPoint`、`PoiEntrance`。房間原點在地板中心，接點 local -Z 朝外；`connect_to()` 依完整 transform 接合不同尺寸房間，拒絕不相容接口。Visuals、Collision、Furnishings 與標記彼此獨立。地堡使用 InteriorProfile 登錄的 16 個地堡模組；巨型避難所使用獨立 megashelter catalog，透過 InteriorProfiles 分流；舊副本專用資產與展示場已移除。

物資標記只提供 caller RNG 的抽選契約；初訪地堡由 BunkerContent 使用獨立 RNG 安置內容，BunkerCache 保管未領取物件。入口只發出 entry_requested，由 PoiInstanceManager 管理；場景及 Resource 可在編輯器直接修改。只供舊版房型生成的 `build_bunker_kit.py` 已移除。詳見 [製作規格](../../world/poi_kit/README.md)。

房型接口、跨接縫、seed 掃描、大型搬運及完整室內導航屬歷史專項驗收；現行自動測試保留 [POI 轉場取消與保存](../../tests/test_poi_transition_persistence.gd)。實機觀察與自動檢查分開記錄。

### 路旁小 POI 與越野場址的生成

POI 定義的 `placement_modes` 以 `ROADSIDE`、`OFF_ROAD` 旗標指定放置類別，兩者可並用，且與 `kind`（副本入口／直接探索）分開。`MinorSites` 以獨立 RNG 規劃每 1,200 m 區間的路旁小場址，最多四次候選，避開大型場址與車道；穩定 ID 使用當前生成版本、seed 與道路 cell。六主題各三個 WALK_IN 定義，不重排 POIConfig.GENERATION_IDS。越野場址按橫向 3 欄、每格 300 × 900 m 的網格規劃，每格 55% 成為候選，8 次有界嘗試並避開道路、水域、陡坡及其他 POI；候選 40% 為 bunker、10% 為 civilian_shelter、10% 為 courtyard_shelter、40% 為 camp／shed；另以獨立 2% 機率選取 `modular_megashelter`，取代一般候選而不改原池權重。四款地堡入口 與 camp／shed 支援路旁及越野，兩款 shelter 僅越野，其他四類小型主題僅路旁。四款地堡入口 路旁場址距道路中心 49 m，為獨立位置，局部整地僅用於入口建築安置。越野場址依自然地面高度及隨機朝向配置，只在資產占地及外圈步行餘量局部整地；不生成公路標誌、方向標誌、車道、停車線、林間步道、迷宮或周界牆。穩定 ID 使用生成版本、seed、row、column。

`POIConfig.instantiate_site(site, include_visuals)` 為場景設定提供單一入口；程序外觀及鄰帶導航共用同一個 `site.exterior_plan`，保持碰撞與動態 bounds 一致。`WorldField.sites_near_z` 與 `stops_in_band` 合併大型與小型場址，作為整地、植被、道路裝飾、導航鄰帶幾何、釘帶避讓與 protected_bands 的共用入口；縱向查詢有上限 256 筆的唯讀快取。主題、佈局、位置、美術、物資、敵人各有獨立 RNG。小場景資產的 Visuals 不持有碰撞或 actor 標記，外觀隨機化不改通路。

`PoiDefinition.enemy_count_range` 預設為零，非零時驗證 EnemySpawns 中足量且在界內的 Marker3D。WalkInSites 首次載入時抽取物資，貨櫃與棚屋依既有標記和 RNG 生成油桶人，actor 均屬 WorldEntities；加油站既有物資 RNG 不變。越野地堡室內沿用 PoiInstanceManager.saved_instances 與 checkpoint 的 `poi` 狀態；戶外營地等沿用 outdoor_sites／WorldActorSnapshot，不新增專用保存格式。Checkpoint v7 要求 generation_version=19；休眠狀態記錄 definition_id 和 content_version，未知版本拒絕。更多內容與驗收見 [小 POI 規格](../../world/roadside_pois/README.md) 與 。

### 加油站保存

`WalkInSites` 在停靠點 index % 3 == 1 配置 gas_station；index 0 維持維修廠。定義占地加外圈步行餘量參與 WorldField.court_distance，因此地形、植被排除與車道共用同一計畫。建築碰撞參與 chunk 導航及鄰帶補圖。導航 readiness 先確認 region iteration 與有效 bounds，再等 map 上可查詢到鄰近網格；只在 map RID 或同步 iteration 改變時重做最近點搜尋，避免等待期間每個物理步反覆掃描整張戶外導航網格。共用邊界點不必只屬於自己，等待期間重新取得 map，支援檢查點跨 World3D 轉移。

WorldGenerator v5 維護前後載入窗口、場址 pinned bands 及 generated_bands，回程重建不重抽小補給點。加油站初次用獨立 walk_in_loot RNG 讀取標記；靜態資產仍不生物資。卸載 owner band 前，WalkInSites 收集 bounds 內主世界的散落或固定 Item／活怪，保留完整 transform、狀態及速度，釋放活動 actor；回程只還原保存的剩餘物件。搬入後丟下的物品也包含在內，車輛及車上設備／庫存不歸場址。

Checkpoint 要求 outdoor_sites／generated_bands；活動物件只放 actors，休眠場址只放 outdoor_sites，WorldActorSnapshot 共用驗證／建立／捕捉契約。EngineState 的全樹唯一性檢查涵蓋休眠物件。戶外 content_version 不符拒絕還原。加油機尚無燃油交易功能，遠離場址的普通散落物仍沿用既有遠距清理規則。

### 巨型避難所：室內

2026-11-01 巨型避難所室內：生成 v19 將 `modular_megashelter` 接到獨立 World3D 的 `megashelter` profile；外殼內容仍 v7，既有地形／道路及外觀 RNG 域保留。只開放地面一層，入口、大廳、三至五間功能房與少量連接空間通常共六至八個模組，按外部面積選擇模組尺寸。首訪二至四件散物與一個箱子，沒有敵人或升級引擎目標。`InteriorProfiles` 供生成與 Checkpoint 共用分流；保存完整布局、探索、箱子與散物，回訪不補貨。Checkpoint v7／VehicleSnapshot v6 不變，只接受生成 v19，舊局重新開始。本次轉場／保存檢查與 seed 42 實際回放已通過；完整範圍與待驗項目見[室內指南](../guides/megashelter-interiors.md)。

### 巨型避難所：樓梯間與地下通道

巨型避難所地下通道從接待室以外的未連通牆面接口抽選樓梯間入口，檢查門前淨空與導航可達性。巨型避難所、地堡及無燈柱廳的獨立樓梯間共用 `InteriorProfiles.STAIR_DESTINATIONS`，以各自的 seed 抽選底門目的地並保存 `stair_destination`。轉場管理器使用各副本的穩定保存 ID 並記住來時的門，離場時可逐層返回。[室內指南](../guides/megashelter-interiors.md)

### 巨型避難所：生成密度

2026-10-28 巨型住宅密度：生成 v18 的 `modular_megashelter`（`Abandoned Megashelter`）增加獨立 300 m 候選帶，每帶最多一棟；最多嘗試三種 footprint、各 64 次位置，無合法位置則略過。一般越野候選維持 55%，原有 2% 大樓抽選及場址保持不變且優先保留；新增大樓完整整地範圍必須避開其他場址、道路及河谷，坡度上限維持 0.65，新增大樓場址地面高差上限為 12 m（原候選仍為 6 m）。四個固定種子共 288 個 150 m 區塊抽樣新增 64 棟，平均每 4.5 區塊一棟；屬平均密度，沒有固定間距保證。新增大樓使用獨立 `megashelter` 身分與 RNG 域，納入相同場址查詢及單一區塊歸屬；道路 RNG 域維持 v15。

### 巨型避難所：外殼組裝

`ModularMegashelter.configure_exterior(plan, include_visuals)` 組裝封閉無窗外觀；室內接入改由上方 v19 摘要及室內指南管理，外殼本身不生成物資或敵人。正式生成與鄰帶導航共用 `site.exterior_plan`，並以 `POIConfig.instantiate_site(site, include_visuals)` 組裝可視場景或碰撞／bounds 幾何。Checkpoint v7、VehicleSnapshot v6，不支援舊生成版本遷移。2026-10-27 初版的自動檢查、seed 6 正式場址輪驅及效能結果屬歷史驗收；完整自由遊玩未完成，正式世界遠景受霧遮擋。本次密度及材質調整的自動契約位於 `tests/support/megashelter_contracts.gd`，未重新做輪驅或自由遊玩驗收。

### 巨型避難所：地面裝飾

2026-10-30 巨型避難所地面裝飾：外殼內容 v7，`MegashelterDetails` 提供低層設備、露筋碎塊及入口遮簷；地面配置使用獨立 RNG，生長／結構／屋頂仍沿用 v5 域。附件錨定接地牆板，實際 bounds 避讓門框及結構，並保留前方接近空間。原生零件進入既有三材質批次，地面排風機已停用；牆面沿用四項改進前的修補位置與剝落變體，獨立 `repair_variant` 選用六種新裝飾模型並檢查避讓，牆面及地面服務鐵件依 seed 與組件 ID 抽選鏽蝕程度。入口鋪面含門檻、排水與破損收邊，同樣合批；碰撞與鄰帶導航仍消費同份 plan。

### 巨型避難所：材質

2026-10-30 巨型住宅材質：三個合併網格的混凝土、剝落預鑄面板與鏽蝕鋼件改由固定種子的連續三維噪音直接生成，不再讀取或隨機拼接 albedo 圖。所有紋路以整棟局部公尺座標取樣，跨模組與轉角延續；外牆原漆使用獨立種子 RNG 連續產生全色相 RGB 色碼，不從固定色票抽選，色相仍隨機，但彩度與明度回到先前灰舊範圍（牆漆 S 0.10–0.16／V 0.50–0.54），混凝土及鋼件同步收窄明暗；混凝土保留礦物灰、鋼件原漆採同色相深灰，污垢與鏽蝕沿用實際材質色。種子另決定老化程度、剝落尺度與形狀、殘漆比例、鏽色及雨痕長度，連續局部受潮場再產生同棟內的差異。近景補骨材、細孔、稀疏裂紋、剝漆底層與鏽殼／鏽坑，氧化色使用獨立噪音。雨痕沿重力方向且跨牆板共用相位，UV2 的實際牆頂／梁與門楣下緣高度調整滴水強度；鏽水跟隨最多四條實際排水管，入口雙管優先。牆腳與水平面積垢，滴水區有黴斑與淡色礦物沉積，次像素噪音及微凹凸依像素足跡漸隱。保留維修蓋板、露筋、缺失風口、封閉背板、三個材質批次及共用碰撞／bounds 流程。正式濾鏡下檢查 legacy 540p 與 low 50% 渲染；噪音增加逐像素運算，不能視為所有 GPU 上都更快。舊圖保留供參考但不再載入，詳見[材質說明](../../assets/materials/megashelter/README.md)。

### 室內生成、副本轉場與地堡內容

`InteriorLayout` 生成版本 3 manifest，新訪隨機目標 30–60 模組、1–3 層，透過完整 socket transform 接合與三維 AABB 排斥擴展；候選／接口耗盡可提早停止。樓梯與新層首房原子安置，普通分類按 Profile 權重抽選，各層共用。`InteriorRoomDefinition` 以 ID＋內容版本解析，場景提供 footprint／clear_height／socket，新增普通尺寸／分類不改生成器。已保存 v3 manifest 原樣讀取，不套新房數目標。

`PoiInterior` 統一組裝、封牆、導航、探索、出生／出口與玩家掉落物保存。未接通 socket 的門框移除，牆板留在自身占地內，避免共享可見面閃爍。導航發布 immutable mesh 並等待 region／map 同步。`BunkerContent` 在初訪用獨立 RNG 配置深處一具 70% 耐久強化引擎，以及上限 2–12 件散落物、1–5 個各含兩件小型物資的補給箱；合法位置不足時不強行達標。敵人生成最多嘗試 `clamp(房間數 / 15, 1, 4)` 個合格房間，每次獨立以 30% 機率從可擴充候選池選出 Raker，因此可沒有敵人，也可有多隻。合格房間避開入口 24 m 房間連接距離及 18 m 空間距離。`BunkerCache` 使用靜態碰撞與分離視覺；玩家長按 E 1 秒，一次領一件，背包拒收不刪物。地圖按實際占用及保存層距繪製 B1–B3，只顯示樓層、房間輪廓、連線與樓梯圖示；2026-11-08 移除常駐房名、房數、目標位置及返回／按鍵說明，探索記錄仍持續更新。

保存實際布局與內容，不依 seed 重抽；`CheckpointSchema` 驗證逐房版本、接口對齊、占用、連通、內容與補給箱快照。剩餘補給品保留 Item 完整狀態與 ID，活 actor 保留位置及生命；既有布局不補抽新物資。新增目錄／修改權重不改變已訪布局，缺失或不支援版本拒絕。Checkpoint 只接受 v6，不再轉換或清除 pre-bunker 舊資料，舊檔保持原樣。原生成器／專用資產已移除。詳見 [地堡契約](../guides/bunker-interior.md)。

PoiInstanceManager 在入口互動後鎖定玩家輸入、建立 own_world_3d 的 SubViewport，完成載入後 reparent 原玩家與 UI。根 CanvasLayer 顯示 viewport texture，輸入轉交子 viewport，視窗縮放同步。室內設定開啟時，根合成層由 20 提升至 60 並隱藏室外 POI 標題；關閉後恢復，避免室外 HUD 蓋住選單。正常退出先保存室內 Item、活怪與補給箱的完整剩餘狀態，再把原玩家移回主世界並檢查返回落點，釋放副本幾何。saved_instances 供同局重返重建相同布局與內容；室外檢查點把這份資料一併寫入磁碟。非活動副本不繼續模擬。轉場有明確狀態與操作序號；離場取消沿共用安全收尾路徑保存室內狀態、恢復控制並清理暫建 viewport。

WorldEntities.same_world 用於群組選敵、碰撞例外及串流清理；怪物每 physics tick 清掉跨世界的快取玩家目標。只有原玩家與背包透過入口轉移；原設備作為背包 Item 可帶進地堡並放置。實例快照共用 Item／Monster，保存室內散落與固定物品，未連接 RV 的原設備不提供車輛服務。

地堡新增 16 個房間內容版本 2，只接受目前內容版本，布局仍為 version 3。新版家具碰撞獨立於 Visuals/Model；封牆沿用所在房間的牆／塗裝材質。BunkerLighting 以保存 seed、room ID 與固定版本字串做 SHA-256 排序，選出四捨五入後 60% 的普通模組熄燈，排除 entry／stairs；不消耗布局或內容 RNG，不增加存檔欄位。舊房間內容版本直接拒絕。
