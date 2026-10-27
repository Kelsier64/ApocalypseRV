# POI 共用製作與接入規範

更新：2026-10-27。適用目前 POI；既有資產的視覺組裝例外見末節。此文件是 POI 共用規範，房型接口細節仍由 [房間／家具規格](../../world/poi_kit/README.md) 管理。

## 1. 類型與責任

| 類型 | 空間與入口 | 世界管理者負責 |
|---|---|---|
| `INSTANCE_ENTRANCE` | 室外入口透過 PoiEntrance 進入獨立 World3D；有 ReturnPoint | 副本轉場、返回、安全復原與副本記憶 |
| `WALK_IN` | 室內外同一 World3D，以真實門洞步行；不得含 PoiEntrance／SubViewport | 地形安置、連續導航、物資狀態、串流與保存 |

共用「建築資產＋定義 Resource＋世界場址」三層。資產只包含靜態幾何、家具、功能物件及標記；定義提供製作資料；世界管理者持有每次生成的身分和動態狀態。

## 2. 定義與登錄

每種資產建立一份 [PoiDefinition](../../world/poi_definition.gd) `.tres`，放入 `world/poi_definitions/`，登錄於 [POIConfig.DEFINITIONS](../../world/poi_config.gd)。路徑由定義解析，生成及跨區導航不得自行用類型字串拼接場景檔名。

| 欄位 | 規則 |
|---|---|
| `definition_id` | 唯一、穩定的資產定義 ID；改顯示名稱不改 ID |
| `display_name` | 顯示名稱，可與檔名不同 |
| `kind` | 副本入口或直接探索，兩者有不同驗證要求 |
| `scene_path` | `res://` PackedScene 路徑；集中於定義，以免外觀載入與導航使用不同資產 |
| `content_version` | 資產內容版本，起始為 1；不是檢查點格式或地形生成版本 |
| `placement_modes` | 放置類別旗標 `ROADSIDE`、`OFF_ROAD`；可同時設定，與 `kind` 分開 |
| `building_bounds` | 建築本地 AABB，包含店面、棚架、碰撞與地標等完整占用量體 |
| `site_bounds` | 本地 AABB，包含建築及需要淨空的入口、後院、維修動線；包住 building_bounds |
| `entrance_path`／`return_path` | 副本入口專用，本地 PoiEntrance／Marker3D 路徑 |
| `access_paths` | 可驗證的本地 Marker3D 路徑；直接探索型至少一個，涵蓋主要進出位置 |
| `interior_profile` | 副本入口專用；支援 `bunker`；室內見 [地堡規格](bunker-interior.md) |
| `legacy_visual_layout` | 僅既有四款程序外觀可為 true，新資產必須為 false |
| `enemy_count_range` | WALK_IN 首訪敵人數量範圍，預設 (0,0)；本輪上限 2，需提供足量且位於 site_bounds 內的 EnemySpawns/Marker3D |

放置類別由 `placement_modes` 的 `ROADSIDE`、`OFF_ROAD` 旗標指定，與 `PoiDefinition.kind`（副本入口／直接探索）分開；兩個旗標可同時設定，無須複製定義或場景。四款地堡入口、camp、shed 同時支援兩類；兩款 shelter 僅支援越野，其他四個小型 POI 主題維持路旁。四款地堡入口 路旁位置為距道路中心 49 m 的獨立場址，局部整地只用於建築本體安置。越野候選使用橫向 3 欄、每格 300 × 900 m 的網格，需避開道路、水域、陡坡及既有 POI，按自然地面高度及隨機朝向放置。路旁專用的公路標誌、方向標誌及停車區配置不得套用到越野場址。越野地堡只在建築本地入口局部整地，不改造周遭地形。

場址實例 `site.id` 與 `site.seed` 由世界規劃提供。`POIConfig.instantiate_site(site, include_visuals)` 設定場景實例；需場址幾何的正式生成與鄰帶導航應共用同一份 `site.exterior_plan` 字典，使動態 bounds 與碰撞一致。`definition_id` 識別資產種類，**不是某一棟建築的保存 ID**；同種建築可有許多不同場址 ID。未知明確定義不能默默退回維修站。

Resource 為共用唯讀設定；執行時不得把拾取、門狀態、敵人生命或個別場址 seed 寫回 Resource。驗證工具需要改值時先 duplicate。

路旁小 POI 共六類、18 個 WALK_IN 定義；四款地堡入口 與 camp／shed 定義可同時用於越野類別。生成 v18 的越野場址由橫向 3 欄、每格 300 × 900 m 的網格按每格 55% 候選率、最多 8 次嘗試規劃，候選以 40% 抽 bunker、10% 抽 civilian_shelter、10% 抽 courtyard_shelter、40% 抽 camp／shed；獨立 2% 越野抽選以 `modular_megashelter` 取代該候選的一般 POI，不改上述權重或 55% 候選率；位置、主題、佈局、美術、物資與怪物 RNG 分離。所有戶外消費者透過 `WorldField.sites_near_z()` 或 `stops_in_band()` 查詢；v6 的 `stop(index % 3 == 2)` 回傳空字典，不能再把固定停靠點索引當成完整世界場址清單。詳見 [小 POI 規格](../../world/roadside_pois/README.md)。

**登錄不等於加入生成。** `GENERATION_IDS` 是目前四款副本入口的穩定抽樣順序；加油站透過 WalkInSites 的獨立場址排程加入。場址必須提供已登錄定義，沒有 maintenance_legacy 回退。動態組裝資產以 `site.exterior_plan` 字典作為場景設定來源；消費端不得各自重建外觀或 bounds。新增或重排抽樣池需驗收當前場址安置與保存；不支援的舊存檔可直接重新開局。

## 3. 尺度、座標與場景層級

- 1 unit = 1 m，Y 向上。建築根節點單位縮放，原點在約定的地面位置；新建築主要正面朝 +Z。
- 房間採地板占地中心；自由形狀室外建築可自訂原點，但必須記錄本地占地和入口位置。
- `AccessPoints` 的 local -Z 指向建築外側；`DoorSockets` 仍沿用 local -Z 朝房外的接口契約。
- 不將地堡首批六種尺寸套用到所有室外建築或後續房型。
- 地堡尺寸自由、初始 2.4×2.8 m 門洞及 4.5 m 層距依地堡規格。新自由室外門洞需以正式玩家、預期大型物品及敵人膠囊驗證；不以外觀門寬代替碰撞淨空。

```text
Building
├── Visuals          可替換 mesh／GLB，不含碰撞、物資或遊戲狀態
├── Collision        建築簡化碰撞，屋頂、玻璃與門洞行為明確
├── Furnishings      家具／門／互動設備完整子場景
├── LootSpawns       建築本體的 PoiLootPoint，可留空
├── AccessPoints     直接探索型的主要出入 Marker3D
├── Lights           可選；電源來源與關閉規則另行定義
├── Entrance         僅副本入口型，預設路徑
└── ReturnPoint      僅副本入口型，預設路徑
```

可互動門、家具、設備應各自持有 Visuals、Collision 與功能標記，移動其整個子場景。不要把所有家具碰撞搬到建築根層，也不要把碰撞掛在可替換模型底下。替換 Visuals 不應移除碰撞、入口、物資點或互動腳本。

匯入資產以外層 `.tscn` 包裝：`Visuals/Model` 引用 GLB，其餘遊戲節點留在外層。不改 `.godot/imported`；來源、授權、單位、朝向、縮放及必要重建方式記錄於素材目錄。加油機範例見 [GLB 流程](../../assets/models/gas_station/README.md)。

## 4. 場址、導航與入口

site_bounds 是資產安置需求；WalkInSites 的整地與植被排除讀取這份 AABB，加上外圈步行餘量。修改 Resource bounds 後仍須驗證完整地形與步道整合；沒有舊生成版本的安置分支。

新資產加入正式世界前，必須讓共享場址計畫決定完整 transform、整平範圍、接近路線、避讓與串流保護範圍；地形、視覺放置及導航讀相同計畫。所有入口、後門、棚架、招牌、RV 轉彎和搬運路線都要納入驗收。

直接探索型需要室外到室內的連續碰撞及導航，不得用傳送替代門洞。副本入口型由定義的 entrance_path／return_path 接線，外觀腳本不得自行建立 World3D 或管理返回狀態。所有既有入口指向 `bunker`；不支援的副本資料直接拒絕載入；新增 profile 必須先實作生成及保存支援，未知 profile 在生成時拒絕。

ReturnPoint 的返回朝向由 PoiInstanceManager 依建築朝向計算；AccessPoints 的朝向與實際入口動線一併驗收。

## 5. 物資、版本與保存

- 建築及家具 `_ready()` 不得自行抽物資。PoiLootPoint 只描述候選、機率和標記；由世界／副本擁有者使用獨立 RNG 首次生成。
- 動態道具放入對應 World3D 的 WorldEntities，不以建築視覺樹或可卸載 chunk 持有。
- 物資點 ID 在所屬家具內穩定；不同家具可重用點名，需以穩定家具身分或場景相對路徑區分。已保存的節點路徑改名視為內容變更。
- 保存需要涵蓋已取物品、掉落物、敵人及互動狀態，回訪／卸載重建不得重新補貨。
- 更換同尺寸外觀且不改通路／碰撞／標記，可視為美術替換。移牆、移家具、換生成規則或物資標記則需驗證當前資料；不相容時要求重新開局。
- `content_version` 由戶外場址寫入檢查點並驗證；不支援的版本拒絕載入。改布局不需保留舊內容或提供遷移；不能用相同 seed 假定幾何一定相同。

加油站在正式 v5 場址初訪抽取物資，卸載保存剩餘 actor；已拾取物品不因回訪重生。活動 actor 與休眠 actor 分別保存，避免重複所有權。

## 6. 製作與驗收流程

1. 選定類型，建立獨立 `.tscn` 與 `.tres`，設定身分、場址範圍及入口標記。
2. 先完成灰盒、簡化碰撞和家具動線；執行 `validate()`／`validate_scene()`。
3. 以正式玩家步行所有主要進出口，確認大型物品、物資支撐／拾取、返程及導航。物理可達性由場景測試負責，靜態欄位驗證不能取代。
4. 替換外觀時確認尺寸、朝向、碰撞／物資點保留；提供相同視角比較。
5. 登錄素材目錄後，再獨立完成場址生成、串流、保存與回訪，才加入正式生成池。
6. 更新規格、現況與驗收紀錄。自動檢查、可見觀察、效能和未驗收項目分開記錄。

登錄定義、ID、類型分流與舊版場址的專項自測已退出核心清單。新增或修改 POI 時，仍須執行定義的 `validate()`／`validate_scene()` 並按上列步驟實際走查；現行自動範圍見 [測試指南](../../tests/README.md)。

轉場或保存邏輯變更，可從專案根目錄執行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -TestFilter test_poi_transition_persistence.gd`；此測試聚焦轉場取消與保存，不能代替新場景的定義、通路或導航檢查。新增定義也須加入 POIConfig.DEFINITIONS。

## 7. 現有資產狀態

| 定義 | 類型／接入 | 當前用途 |
|---|---|---|
| maintenance／warehouse／pump／research | 目前副本入口生成池 | 路徑、顯示名稱及順序集中；同一室內 profile |
| gas_station | 正式公路及獨立測試場 | 占地整地、回程串流、剩餘物資及檢查點保存 |
| civilian_shelter | WALK_IN、僅 OFF_ROAD、內容 v1 | 荒廢小型民用避難所；沿用戶外場址物資、串流與保存 |
| courtyard_shelter | WALK_IN、僅 OFF_ROAD、內容 v1 | L 形庭院變體；沿用戶外場址物資、串流與保存 |

既有入口由 exterior_style.gd 在 Visuals/BunkerFacade 建立簡單軍事立面，沿用 service_entrance 的入口／返回點與原占地；外观附加量體不帶碰撞。既有定義的 legacy_visual_layout 旗標暫保留，尚未全面改成編輯器組裝資產；新資產不得沿用此例外。

戶外整合的歷史結果見 [正式加油站驗收](../validation/2026-09-20-production-gas-station.md)，僅代表當時範圍。加油站保存 content_version；更動佈局時驗證當前版本，不維護舊版資產或存檔遷移。


Abandoned Megashelter 使用專用模組規劃器與 `modular_megashelter` definition，依 `OFF_ROAD` 以獨立 2% 機率替換越野候選。`site.exterior_plan` 保存一次生成的規劃；正式視覺／碰撞呼叫 `POIConfig.instantiate_site(site, true)`，鄰帶導航呼叫 `POIConfig.instantiate_site(site, false)`，兩者共用 `modules`、`collision_boxes`、`building_bounds`、`site_bounds` 和 `access_point`。該資產不建立室內 profile、物資或敵人。生成 v18 契約及驗證見 [巨型住宅驗證](../validation/2026-10-27-modular-megashelter.md)。
