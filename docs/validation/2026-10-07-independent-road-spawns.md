# v9 公路獨立生成

日期：2026-10-07。正式新局 generation_version=9，檢查點格式維持 v5；共用 WorldProfile／legacy fixture 仍為 v6。此紀錄只記本輪驗證；[v8 首版紀錄](2026-10-01-random-road-spawns.md)保持原樣。

## 改動範圍

- 每 150 m Raker 數量 0／1／2／3 機率 65／20／10／5%；每隻獨立選路面／路邊 40／60% 及位置，沒有最小間距。
- 油桶人 8% 一隻、普通油桶 20% 一個，獨立在中央路面選點，不替換 Raker。普通油桶由 WorldEntities／Item 保存，非 chunk 靜態內容。
- 廢車數量 0／1／2／3／4 機率 60／25／10／4／1%，逐台獨立位置與 0–TAU yaw，沒有固定車陣或中央 5 m 通道保證。
- 保留起點前 450 m、場址／接縫／實體重疊避讓與不補發生命週期；v9 額外避開同區段既有護欄。怪物使用各物種實際碰撞半徑的緊密範圍，不套用 v8 的 2 m 群組範圍。既有 v8、v2–v7 世界按原版生成。
- shelter 檢查點支援 v7／v8／v9，生成版本接受 v2–v9，未知 v10 拒絕。

## 本輪檢查

Godot 4.7.2 stable／Windows；專案匯入 PASS。分段執行共 15 支不同測試與正式主場景 smoke，以下最終結果全部 PASS；未執行 full suite。

| 範圍 | 本輪通過項目 |
|---|---|
| 最終道路及相關回歸 | `test_road_spawns_v9`、`test_road_spawns`、`test_road_spawn_lifecycle`、`test_road_spawn_checkpoint`、`test_outdoor_minor_persistence`、`test_tire_handling`、`test_tire_puncture`、`main-scene`；8 項，173.68 秒 |
| 開場、保存、桶與串流 | `test_starting_checkpoint`、`test_starting_roadblock`、`test_starting_shelter_terrain`、`test_starting_shelter`、`test_checkpoint_failures`、`test_barrel_man_persistence`、`test_oil_barrel_vehicle_contact`、`test_streaming_generation`；8 支，於第一輪分段通過 |

最終執行命令：

```powershell
./scripts/test.ps1 -Godot 'C:\Users\evan4\AppData\Local\Programs\Godot\Godot_console.exe' -TestFilter 'test_road_spawns*.gd,test_road_spawn_lifecycle.gd,test_road_spawn_checkpoint.gd,test_tire_*.gd,test_outdoor_minor_persistence.gd' -Smoke -SkipImport
```

最終日誌位於 `.godot/test-logs/20261007-224716-246-selected-43936/`；其餘通過項目位於 `.godot/test-logs/20261007-223053-154-selected-35616/`。第一輪道路兩項失敗及後續診斷不算通過證據，已由最後一輪重新驗證：檢查點 fixture 改以同世界 Chassis 查詢處理 F9 後的節點名稱，油桶落地檢查改以傾斜底面及實際路面高度判斷。

4,096 個平坦隔離 seed 的最終抽樣：Raker 數量分布 `[2699, 808, 393, 196]`，廢車 `[2451, 1026, 408, 166, 45]`；普通油桶 790 次、油桶人 330 次。測試另外驗證全部 16 種廢車／Raker／普通油桶／油桶人有無組合、逐件位置／朝向、相鄰區段可連續出現、近距離位置、實際廢車碰撞、安全區與查詢順序一致。

v8／v9 真實道路生命週期及 F6/F9 檢查涵蓋：導航發布前不生成、同一 callback 不重複生成、兩種怪物與普通油桶正確身份、移動油桶的姿態與 ID 保存、區塊休眠／回訪恢復、油桶爆炸後不保存或補發，以及擊殺／導航重烘焙／讀檔不復活。

## 本輪畫面觀察

使用專案既有 `WorldField`、`ChunkGenerator`、Raker、BarrelMan 與 OilBarrel，在獨立原生 Godot 測試視窗以 Forward+／Vulkan 檢視 seed 42 的 band 158、159；AI 暫停以核對位置。透過已安裝 computer-use API 選取唯一的 review 遊戲視窗，逐次切換相機後重新觀察，最後僅關閉該測試視窗。原生日誌 `.godot/validation/independent-road-v9/native-review.log` 無 script error。

- band 158：三隻各自選點的 Raker、一隻油桶人及一個普通油桶；近看確認路肩 Raker 及中央路面普通油桶的實際外觀與落地。見 [路肩 Raker](independent-road-v9/roadside-rakers.png)、[普通油桶](independent-road-v9/ordinary-barrel.png)。
- band 159：三台不同位置與朝向的廢車，分散在路面／路緣；近看確認車體與地面。見 [獨立廢車位置](independent-road-v9/independent-wrecks.png)。

導航診斷確認 band 158 一個路肩位置的真實地面 Y=8.4107，預定 Raker 根位置 Y=8.8341；最近導航面 Y=11.0530，XZ 距離約 0.71 m。差異來自既有地形導航高度近似，非出生點埋地或缺少實體支撐。v9 驗證使用實際地面支撐、XZ 導航接近程度及連通道路路徑；Monster 的導航移動方向原本即忽略 Y，由物理處理落地。v8 保留原 3D 距離斷言，這次不調整導航烘焙參數。

## 限制與未驗證範圍

安全／碰撞避讓可能減少實際生成數量；抽取機率不代表最終密度。原生觀察只核對位置／外觀，沒有執行這些新區段的輪驅穿越、玩家拾取、追擊或碰撞重播；既有真車撞普通油桶測試於本輪通過，不能替代新分布的遊玩手感。長局密度、連續追車累積、廢車繞行與廣泛 seed 的手動遊玩仍待確認。設計與接入詳見 [公路計畫](../plans/random_spawn.md)、[GDD](../../GDD.md)與 [architecture](../../architecture.md)。
