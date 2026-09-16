# POI 資產樣板與製作規格

這套可編輯的入口建築、房間與家具已接入主遊戲。維修站入口載入 50–100 房迷宮，具有獨立 World3D、家具導航與同局重返保存；舊 POI 場景和生成器已刪除。原始展示場景仍保留，供模型製作時快速檢查。

正式生成使用 `rooms/maze_utility.tscn`（9×9 m／4.5 m 高）與 `rooms/maze_hall.tscn`（18×18 m／6 m 高），兩者都有四向接口，家具避開十字動線。`world/instances/maze_layout.gd` 產生布局，`poi_interior.gd` 接合門口與走廊並封閉未連接門。增加房型需同步擴充模板選擇與占地規則，不能只放進目錄就期待自動加入。

## 先看樣板

生成 v3 的室外入口使用 `exteriors/maintenance.tscn`、`warehouse.tscn`、`pump.tscn`、`research.tscn`，繼承已驗證的 service_entrance 底層，`exterior_style.gd` 加入原生網格輪廓及入口燈。`Entrance`／`ReturnPoint` 保留原契約；四款仍接同一套室內生成。舊生成 v2 繼續使用 service_entrance。新外觀可在 `tests/outdoor_horror_playground.tscn` 按 1–4 比較。

```powershell
godot --path . --log-file .godot/poi-asset-workshop.log res://tests/poi_asset_workshop.tscn
```

| 按鍵 | 功能 |
|---|---|
| F1 | 入口建築：屋頂、雨棚、入口與回程位置 |
| F2 | 小房：貨架、工作桌、櫃子、物資點 |
| F3 | 大房：挑高與多組家具 |
| F4 | 掀頂總覽；只隱藏視覺屋頂，碰撞保留 |
| F5 | 第一人稱：WASD／滑鼠，對門短按 E 進樣板、對物資 E 撿取、G 丟出 |
| F6 | 用正式玩家和持續輸入，自動穿越小房→走廊→大房 |
| M | 顯示門口（青）和物資點（黃） |

Esc 釋放滑鼠後，用 F5 重新進入步行。展示入口只在這個測試場傳送玩家，不是正式副本系統。F5 可返回建築入口，物資僅首次開啟展示時生成，切鏡頭與重進樣板不重抽。

可加 `-- --replay` 自動啟動 F6 路線。通過時日誌有 `PASS: workshop traversal`，不代表家具側路、完整導航、RV 或大型迷宮已驗收。

## 尺寸與座標契約

- 單位：1 Godot unit = 1 m；房間水平格網 9 m。
- 房間原點：占地中心的地板表面，Y=0；+X 東、-Z 北、+Y 上。場景根節點縮放保持 `(1,1,1)`。
- 小房：9×9 m，淨高 4.5 m；大房：18×18 m，淨高 6 m。
- 走廊：占地 9×9 m，內部通道約 3.2 m；統一門洞淨寬 3 m、淨高 3.5 m。
- 牆厚 0.24 m，地板在 Y=0 下方，門口無門檻。邊界上的牆中心對齊格網，連接模組的兩側牆可能重合；未來生成器可去重共用牆。
- 通行保留中央至少 2.2 m 路線；家具擺放不得進入門口及 Walkway 所標示的主路。
- 家具原點：底部占地中心，朝向 -Z；正面展示／取物側為 +Z。家具 footprint 表示占用包圍盒，保持原始比例。
- 門口 Marker3D 在門洞底部中央，local -Z 朝房外，Y 軸朝上；interface_type 和 opening 相符才能連接。
- 拼接使用接點 transform，支援 90 度轉向，不以房間固定寬度推算下一間位置。

## 可以直接編輯的場景

| 類別 | 場景 |
|---|---|
| 入口外觀 | [service_entrance.tscn](exteriors/service_entrance.tscn) |
| 小房 | [utility_small.tscn](rooms/utility_small.tscn) |
| 走廊 | [service_corridor.tscn](rooms/service_corridor.tscn) |
| 大房 | [maintenance_hall.tscn](rooms/maintenance_hall.tscn) |
| 貨架 | [shelf.tscn](furniture/shelf.tscn) |
| 工作桌 | [workbench.tscn](furniture/workbench.tscn) |
| 開放櫃 | [cabinet.tscn](furniture/cabinet.tscn) |

小房與大房使用相同家具 PackedScene 的實例；編輯家具來源場景，引用它的房間一起更新。當前是單組手工配置，之後可在保持主動線的前提下製作多組陳設變體。

## 房間與家具層級

```text
Room (PoiRoom: room_id, size_cells, clear_height, category)
├── Visuals          可替換的牆、地、頂、燈、標示
├── Collision        獨立 StaticBody3D／簡化 BoxShape3D
├── DoorSockets      PoiDoorSocket：穩定 ID、接口、尺寸
├── Furnishings      共用家具場景實例
├── LootSpawns       房間本身的物資點，可留空
├── EnemySpawns      敵人候選 Marker3D，樣板不自動生敵
└── Walkway          主路檢查標記，不是已烘焙導航

Furniture (PoiFurniture: furniture_id, footprint)
├── Visuals
├── Collision
└── LootSpawns       PoiLootPoint：ID、category、機率、候選 PackedScene
```

物資點的 Y 是物品**原點**，不是底面。現有標記為 0.3 m 廢鐵方塊預留落下空間；加入不同大小／原點物品前，先在展示場驗證會不會穿板、掉出或無法拾取。`category` 目前只是分類 metadata，抽樣使用候選場景陣列等權重，未接總額度系統。

`PoiLootPoint.roll_scene(rng)` 只回傳選中場景，不生成物件、不使用全域亂數。單純開房間不會刷新物資。正式副本在首次進入時以獨立 RNG 排序標記、依機率抽取，每房最多 4 件；家具點是廢鐵，新增地面 FuelSupply／OilSupply 點分別提供汽油罐／油桶。離開保存剩餘 actors，再進入直接恢復，不重新抽樣。家具同名物資點由各自的實例路徑區分。

入口的 `Entrance` 節點提供 `interact(player)` 和 `entry_requested(player, destination_id)`，由外部管理器決定轉場；外觀、碰撞、入口、ReturnPoint 分開。不要把副本狀態或載入邏輯寫入美術模型。

## 換正式模型的流程

1. 複製最接近的房間／家具 `.tscn`，設定新的穩定 ID。已用於保存狀態的 ID 不隨外觀更名。
2. 在 Godot 用灰盒調尺寸與動線；門口按格網邊界擺，保持尺寸和朝外方向。
3. 在外部建模工具以同單位、原點與朝向製作模型，匯入 GLB。將 GLB 實例放在 Visuals 下，替換對應灰盒視覺節點。
4. 保留 Collision、DoorSockets、LootSpawns 等功能層；需要調碰撞時使用簡化形狀，不對每個視覺細節生成碰撞。
5. 家具移動時一起移動整個實例，讓碰撞與物資點保持一致。不要單獨拉伸 Visuals 來改房間尺寸。
6. 執行下列驗證，再在展示場確認實際門寬、鏡頭高度、拾物可達性與家具動線。

牆面共用 [concrete.tres](materials/concrete.tres)，使用 triplanar 貼圖減少灰盒 UV 拉伸，設定約每 2 m 重複。正式模型可換成自訂 UV 材質，但不改功能層。材質目前只有生成的 albedo，沒有虛構 normal／roughness 貼圖；表面粗糙度使用常數。

## 驗證與生成器保護

```powershell
godot --headless --path . -s res://tests/test_poi_asset_kit.gd
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

測試驗證樣板 metadata、不同尺寸和轉向接合、錯接口拒絕、家具物資落點支撐、正式玩家穿越、視覺層獨立以及入口模式授權。新增房型時把它加入測試清單；測試不取代完整室內導航和大量隨機布局驗收。

[build_poi_kit_20260915.gd](../../scripts/build_poi_kit_20260915.gd) 是首次建立場景的來源紀錄，輸出檔存在時拒絕覆寫。交付後直接編輯 `.tscn`；若需要新的大量生成腳本，另開新檔和輸出路徑，不重跑來覆蓋手工場景。

## 本次驗證紀錄（2026-09-15）

- 引擎：本機 Godot 4.7.2／GL Compatibility，未改既有 4.7 專案設定；CI 的 4.6.1 尚未另測。
- 自動化：最終統一 runner 的匯入、11 個測試套件和主場景 120 frames 全數通過。副本測試涵蓋 100 個 seed 的拓樸、正式入口、獨立世界、外部電量、串流錨點、物品／敵人保存，以及 96 房副本的每條連接導航。原有移動 RV 拆頂測試曾一次非固定失敗，單獨重跑通過，保留紀錄。
- 額外重播：headless `--fixed-fps 60 --quit-after 800` 搭配展示場 `-- --replay`，入口與穿越皆通過。
- Computer Use 實際觀察：資產展示的入口外觀、小房、大房、掀頂；正式場景 F6 回放從路旁入口進入 96 房副本，持續步行穿越連接走廊再回入口按 E 返回，畫面顯示 PASS。互動日誌無 SCRIPT ERROR／ERROR／FAIL；室外 RV 持續受到殭屍攻擊。測試遊戲視窗已關閉，編輯器保留。
- 未驗收：每個隨機 seed 的完整實機探索、100 房上限的長時間效能、群體殭屍實戰、全部家具繞行路線、正式模型外觀、所有材質接縫及 4.6.1 相容性。
- 日誌：`.godot/test-logs/`、`.godot/poi-visible.log`、`.godot/climb-recheck.log`，另保留先前資產展示日誌。Headless 的系統憑證讀取訊息依原測試 runner 規則排除，沒有排除腳本或其他錯誤。

