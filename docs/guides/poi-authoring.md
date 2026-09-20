# POI 共用製作與接入規範

版本：1，2026-09-19。適用新 POI；既有資產的相容例外見末節。此文件是 POI 共用規範，房型接口細節仍由 [房間／家具規格](../../world/poi_kit/README.md) 管理。

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
| `building_bounds` | 建築本地 AABB，包含店面、棚架、碰撞與地標等完整占用量體 |
| `site_bounds` | 本地 AABB，包含建築及需要淨空的入口、後院、維修動線；包住 building_bounds |
| `entrance_path`／`return_path` | 副本入口專用，本地 PoiEntrance／Marker3D 路徑 |
| `access_paths` | 可驗證的本地 Marker3D 路徑；直接探索型至少一個，涵蓋主要進出位置 |
| `interior_profile` | 副本入口專用；目前只支援 `maintenance_maze_v1` |
| `legacy_visual_layout` | 僅既有四款程序外觀可為 true，新資產必須為 false |

場址實例 `site.id` 與 `site.seed` 由世界規劃提供。`definition_id` 識別資產種類，**不是某一棟建築的保存 ID**；同種建築可有許多不同場址 ID。未知明確定義不能默默退回維修站。

Resource 為共用唯讀設定；執行時不得把拾取、門狀態、敵人生命或個別場址 seed 寫回 Resource。驗證工具需要改值時先 duplicate。

**登錄不等於加入生成。** `GENERATION_IDS` 保留既有 v3／v4 的四款抽樣順序，生成 v5 透過 WalkInSites 的獨立場址排程加入加油站，不改舊池順序。v2 沒有 exterior 的既有場址繼續解析到 `maintenance_legacy`。新增或重排世界抽樣池須另做生成版本、場址安置及保存驗收。

## 3. 尺度、座標與場景層級

- 1 unit = 1 m，Y 向上。建築根節點單位縮放，原點在約定的地面位置；新建築主要正面朝 +Z。
- 房間採地板占地中心；自由形狀室外建築可自訂原點，但必須記錄本地占地和入口位置。
- `AccessPoints` 的 local -Z 指向建築外側；`DoorSockets` 仍沿用 local -Z 朝房外的接口契約。
- 不將 9／18 m 房型尺寸套用到所有室外建築；這些尺寸是既有室內生成器契約。
- 9 m 格網、3 × 3.5 m 門洞及既有室內樓高仍依房型規格。新自由室外門洞需以正式玩家、預期大型物品及敵人膠囊驗證；不以外觀門寬代替碰撞淨空。

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

site_bounds 是**新資產的安置需求**；v5 加油站的場址整地與植被排除會讀取這份 AABB，加上外圈步行餘量。既有 v2／v3／v4 場址繼續使用其固定地形／步道規則，以維持舊世界；不因改了 Resource 的 bounds 就視為完成地形整合。

新資產加入正式世界前，必須讓共享場址計畫決定完整 transform、整平範圍、接近路線、避讓與串流保護範圍；地形、視覺放置及導航讀相同計畫。所有入口、後門、棚架、招牌、RV 轉彎和搬運路線都要納入驗收。

直接探索型需要室外到室內的連續碰撞及導航，不得用傳送替代門洞。副本入口型由定義的 entrance_path／return_path 接線，外觀腳本不得自行建立 World3D 或管理返回狀態。目前所有四款入口仍指向同一室內 profile；新增 profile 必須先實作生成及保存支援，未知 profile 在生成時拒絕。

既有 ReturnPoint 的返回朝向仍由 PoiInstanceManager 依建築朝向計算，以保持舊行為；新 AccessPoints 的朝向規格不倒改既有轉場朝向。

## 5. 物資、版本與保存

- 建築及家具 `_ready()` 不得自行抽物資。PoiLootPoint 只描述候選、機率和標記；由世界／副本擁有者使用獨立 RNG 首次生成。
- 動態道具放入對應 World3D 的 WorldEntities，不以建築視覺樹或可卸載 chunk 持有。
- 物資點 ID 在所屬家具內穩定；不同家具可重用點名，需以穩定家具身分或場景相對路徑區分。已保存的節點路徑改名視為內容變更。
- 保存需要涵蓋已取物品、掉落物、敵人及互動狀態，回訪／卸載重建不得重新補貨。
- 更換同尺寸外觀且不改通路／碰撞／標記，可視為美術替換。移牆、移家具、換生成規則或物資標記則需檢查舊資料位置。
- **增加 content_version 欄位本身不會遷移存檔。** v5 戶外場址已把此欄位寫入檢查點並驗證，不支援的版本拒絕載入；既有世界靠保留舊抽樣與內容維持相容。未來改布局前須保存並解析版本，保留舊內容或提供明確遷移／拒絕策略；不能用相同 seed 假定幾何一定相同。

加油站在正式 v5 場址初訪抽取物資，卸載保存剩餘 actor；已拾取物品不因回訪重生。活動 actor 與休眠 actor 分別保存，避免重複所有權。

## 6. 製作與驗收流程

1. 選定類型，建立獨立 `.tscn` 與 `.tres`，設定身分、場址範圍及入口標記。
2. 先完成灰盒、簡化碰撞和家具動線；執行 `validate()`／`validate_scene()`。
3. 以正式玩家步行所有主要進出口，確認大型物品、物資支撐／拾取、返程及導航。物理可達性由場景測試負責，靜態欄位驗證不能取代。
4. 試換一件 GLB，確認尺寸、朝向、碰撞／物資點保留；提供相同視角比較。
5. 登錄素材目錄後，再獨立完成場址生成、串流、保存與回訪，才加入正式生成池。
6. 更新規格、現況與驗收紀錄。自動檢查、可見觀察、效能和未驗收項目分開記錄。

現有檢查入口：`test_poi_resources.gd` 驗證所有登錄定義及場景；`test_poi_definitions.gd` 驗證類型分流、轉場接線、ID 與 v2／v3／v4 資料相容；加油站行為由 `test_gas_station.gd` 驗證。程式變更依專案規則執行完整 `scripts/test.ps1`。

新增資產後，可先從專案根目錄執行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -TestFilter test_poi_resources.gd`。此入口會先匯入資源，再檢查所有登錄定義；新增定義也須加入 POIConfig.DEFINITIONS。

## 7. 現有資產狀態

| 定義 | 類型／接入 | 相容範圍 |
|---|---|---|
| maintenance_legacy | 副本入口，v2 既有場址 | 原 service_entrance 不變 |
| maintenance／warehouse／pump／research | 副本入口，v3／v4 既有生成池 | 路徑、顯示名稱及順序集中；同一室內 profile |
| gas_station | v5 正式公路及獨立測試場 | 占地整地、回程串流、剩餘物資及檢查點保存 |

四款舊入口仍由 exterior_style.gd 建立 Silhouette，部分附加碰撞嵌於其視覺量體；透過 `legacy_visual_layout` 明確列為例外，這輪不宣稱已完成外觀／碰撞結構重建。新資產不得沿用這個例外。逐棟改成編輯器組裝場景時，須另做視覺、碰撞、導航及舊世界相容驗收後才能移除旗標。

戶外正式整合另由 `test_outdoor_gas_station.gd` 驗證；加油站保存 content_version，若需更動佈局，必須保留舊版資產或提供遷移，不能只增加版本就宣稱相容。
