# 副本室內 v2：製作與保存契約

2026-09-22。適用 `maintenance_v2`，承接 [POI 共用規範](poi-authoring.md) 與 [POI 路線圖](../plans/2026-09-15-poi-roadmap.md)。這是可替換正式模型的灰盒內容，不宣稱完成最終室內美術。

## 玩家流程

四款非 legacy 入口的新副本使用 v2。入口接待室 → 挑高機房 → 第一座樓梯 → 二樓控制／勤務區 → 第二座樓梯 → 一樓零件庫。零件庫 E 一次釋出一個標準引擎與兩包引擎維修包；獎勵生成到副本 WorldEntities，需實際拾取和搬運。可從零件庫側 E 解除返程門閂，走地面短路回接待室 EXIT。一般搜刮可隨時沿已走路線撤退。

主路是手工安排的 12 房跨層環路；正式生成以 seed 擴展到總共 50–100 房，添加不同尺寸、旋轉、支路和同區環路。不是每個 seed 都重排整條主路。三個路程區段用 SERVICE／OPERATIONS／RESTRICTED 色標識別；分區與物資深度使用鎖門狀態下的連通圖距離，樓梯邊額外計入通行成本。這是路程近似值，不是逐個家具繞行的精確導航長度。

M 開關已探索地圖，Page Up／Down 切樓層；未到訪房間不顯示。樓梯標記 UP／DOWN，挑高房上方標記 VOID，不代表該處有可行走樓板。探索、目標和門閂狀態重返仍保留。

## 模組契約

| 項目 | v2 規則 |
|---|---|
| 水平尺寸 | 9 m 模組；目前 9×9、18×9、9×18、18×18 m |
| 高度 | 兩層，地板標高 0／6 m；一般淨高 5.5 m，跨層房 11.5 m |
| 樓板 | 0.25 m；樓板頂面為房間原點 Y=0 |
| 門 | 3×3.5 m，底部中央 Marker；local -Z 朝外；樓梯上門 Y=6 |
| 樓梯 | 9×18 m，升高 6 m／水平坡長 12 m；視覺踏步，連續楔形碰撞，上下平台及護欄 |
| 三維占用 | 房間完整矩形 AABB，包括挑高與樓梯所需空間；接合邊界可相貼，內部不可重疊 |
| 房型數 | 11 種：接待、交叉廳、電氣、儲藏、維修、長廊、泵機房、控制、挑高、樓梯、零件庫 |

`InteriorProfile` 的當前驗證限兩層／6 m。第三層、L 形非矩形占用、梯子與電梯尚未提供；不能只修改欄位就視為支援。挑高廳的高處構件是造景，沒有對玩家開放的樓上平台。

`world/instances/catalog/*.tres` 是房型資源表，包含穩定 ID、PackedScene、版本、抽樣權重及用途。尺寸和門 transform 直接從 PoiRoom 場景讀取，不複製另一套門座標。房間場景保留 Visuals、Collision、DoorSockets、Furnishings、LootSpawns、EnemySpawns、Walkway；不得把 GLB 放到 Collision 或讓其持有生成／保存邏輯。

增加支路房型：複製最接近 `.tscn`，保持單位縮放；配置尺寸、接口與家具；新增 `InteriorRoomDefinition` `.tres`，加入 `maintenance_v2.tres` 的 rooms。普通房型可設定正權重加入抽樣，不需修改生成器。主路必需房型的替換涉及路線設計，必須另外改主路並驗收。新資料不在 `_ready()` 抽物資。

原始建置腳本 `scripts/build_interior_v2.py` 僅是首次產生灰盒的來源紀錄，拒絕覆寫已存在的場景。後續直接編輯 `.tscn`，替換 Visuals／Model，保留簡化碰撞及標記；更換機台時尤其注意側門和中央十字動線。

## 生成與執行

`InteriorLayout` 只產生可序列化資料，局部 RNG 可重播。房間沿相容門的完整 transform 接合；先檢查旋轉後三維 AABB，再接受房間。生成重試有上限，無法填滿要求房數時回傳失敗；不能發佈孤立房或悄悄減少房數。已對上的空接口可成環路，不允許跨區支路繞過返程門的鎖定。

`MaintenanceInterior` 組裝場景與封門，依含家具的實體碰撞烘焙導航。等待烘焙、region 更新及 map 查詢真正就緒，才發佈可玩狀態。開捷徑後重新烘焙，角色沿真正樓梯移動，沒有跨樓層傳送或穿板導航連結。

一般物資總上限 36（含入口保證的一罐汽油），每房最多 2 件，按標記機率及路程優先抽取；零件庫另有 3 件一次性目標獎勵。怪物使用另一個 RNG，最多 8 隻，放在主路之外、入口路程超過 35 m 的房間。這是首版遭遇配置，沒有新巡邏 AI 或遭遇導演。6 格背包及大型物品限制沿用正式玩家。

## 保存與相容

- 外部 site ID 和 PoiInstanceManager 世界隔離／返程／串流錨點沿用。四款入口暫時共用 v2；WALK_IN 加油站不受室內改動影響。
- 新快照保存布局版本 2、profile／內容版本 1、seed、房間 ID／種類／三維 transform、帶 socket ID 的連接、目標／門閂／探索紀錄，以及既有 actors。
- 讀取驗證 manifest 與釘選的生成器／內容相符，再使用保存的 manifest；未知版本、錯誤房間、改動 transform 或不合法探索 ID 拒絕，不重抽或默默重置。
- 沒有 layout 的既有 actor-only 快照一律交回原 PoiInterior／MazeLayout，即使入口現已設定 v2。`maintenance_legacy` 新訪仍使用舊版。保留舊房間／生成器，不拿新幾何承接舊物品位置。
- 改房型碰撞、標記或生成規則必須更新內容／生成器版本並保留舊內容或提供明確遷移；不是改同一份 Resource 的 seed。沒有自動把 v1 迷宮改造成 v2 的功能。
- 檢查點格式仍為 v3，室外 F6／F9 保存完整副本記憶；仍不支援副本內直接存檔。回程保存不等於全世界任意散落物永久保存。

## 預覽與驗收

```powershell
godot --path . --log-file .godot/interior-v2.log res://tests/interior_v2_playground.tscn
godot --path . --log-file .godot/interior-v2-100.log res://tests/interior_v2_playground.tscn -- --seed=1800 --rooms=100
godot --path . --log-file .godot/interior-v2-replay.log res://tests/interior_v2_playground.tscn -- --replay
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -TestFilter 'test_interior_*.gd'
```

預設 12 房，用來驗證同一生成器的必要路線。F1 步行、F2 總覽、F3 隱藏視覺天花板、F5 持續輸入回放（重播會先重建測試場），R 重建相同 seed，F8 保存檢視到 `.godot/v2-view.png`，M／Page Up／Down 是正式探索地圖。回放建立一件測試搬運引擎和一隻零傷害殭屍，控制其他敵人，不能當作遭遇平衡驗收。

四個新增 suite 分別檢查：100 seeds 的三維占用／門對接／捷徑；50／75／100 房每條導航及重返；正式玩家搬運與殭屍跨層、E 互動和序列化；舊布局相容及不支援版本復原。完整 runner 保留 120 秒預設，慢機器可明確傳 `-TimeoutSeconds 240`，仍檢查退出碼、錯誤及 PASS 標記。實際執行結果和範圍見 [驗收紀錄](../validation/2026-09-22-interior-v2.md)。
