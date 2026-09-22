# ApocalypseRV 架構、潛在問題與遺產清理審查

日期：2026-09-22。基準 HEAD：`de238c49605ac3b895ab72df7b22065a15bb6b3b`，審查對象為該 commit **加上未提交工作樹**，包含怪物模型、Raker、車內路徑與 runner 的改動。審查期間另一批 Raker 工作更新為 22 段動畫並新增驗收紀錄，本輪保留並同步其最新文件；工作樹未凍結。本文不是只審查 HEAD，也不是對未提交改動的歸因。

本輪只修改文件，未修正玩法程式、刪除資源或建立 commit。既有變更、`todo`、`todo_prompt` 與 `docs/archive/` 原文均保留。

[文件索引](../README.md) · [現行架構](../../architecture.md) · [計畫總覽](../plans/README.md)

## 判斷

目前架構有可用的邊界：共用世界容器、保存場景白名單、載入候選世界、版本化布局，以及設備／能源／材料的責任分離。沒有證據顯示需要全面重寫。主要問題出現在跨模組的生命週期：**輸入鎖定連帶停止物理、設備搬移沒有完整通知支撐關係、雙向串流沿用單向清理，以及轉場取消的保存提交點不一致。**

本輪以最小 headless probe 重現四項狀態缺口，另外列出兩項尚未量測／重現後果的架構風險、三項驗證／製作工具缺口。可清理遺產主要是少量舊包裝資源與失去用途的欄位；舊世界生成、舊副本與存檔轉換仍有現行使用者，應保留。

### 分工與方法

| 審查者 | 獨立範圍 | 交付 |
|---|---|---|
| subagent `core_world_audit` | core、世界串流、檢查點、POI | 回程清理、離場取消、導航退休及相容碼用途 |
| subagent `gameplay_audit` | 玩家、怪物、RV、設備、道具 | UI 物理、設備支撐、群怪導航成本及舊欄位 |
| subagent `tests_legacy_docs_audit` | tests、scripts、CI、文件、舊資產 | 驗證盲區、引用與 UID 核對、文件漂移 |
| 主 agent | 交叉驗證、執行檢查、整合文件 | 核對程式路徑、兩份定向 probe、統一 runner、報告與文件同步 |

所有 subagent 採只讀審查；本任務由主 agent 統一執行測試。另有外部工作在同目錄執行 runner，實際覆寫共用 manifest，見 A09。以下行號定位於本次審查工作樹；未把「沒有直接函式呼叫」自動當作死碼。

## 問題與優先順序

P2 表示有具體影響、建議近期修正；P3 表示維護或驗證完整性改善。風險與實際重現分開標示。

| ID | 優先度／證據 | 問題 | 建議下一步 |
|---|---|---|---|
| A01 | P2／正式 RV 最小重現 | 搬走工作台後平板仍留在原位置、凍結且可運作 | 共用設備搬移通知依附物 |
| A02 | P2／最小重現 | UI 模式跳過重力與隨車更新 | 分離操作鎖定與物理更新 |
| A03 | P2／最小重現 | v5 清理仍只處理正 Z 遠方 actor | 依雙向窗口與所有權清理 |
| A04 | P2／取消分支注入重現 | POI 離場取消保留背包卻沒保存室內 | 將背包與室內狀態提交保持一致 |
| A05 | P2／靜態生命週期風險 | 正常離場未等待導航重烘 | 共用安全釋放流程並測競態 |
| A06 | P2／未量測效能風險 | 每隻怪物同步重建整張車內導航圖 | 先量測群怪，再做快取與重建預算 |
| A07 | P3／靜態確認 | smoke 寫死場景，未讀正式入口設定 | 驗證 `application/run/main_scene` |
| A08 | P3／靜態確認 | 室內生成工具只局部防覆寫 | 寫入前一次檢查全部輸出 |
| A09 | P2／本輪觀察 | 並行 runner 覆寫共用日誌與 manifest | 每次執行使用獨立輸出目錄 |

### A01：一般設備搬移未釋放依附物

來源：[Equipment](../../equipment/equipment.gd) 160–182、200–208、293–311；[RVPanel](../../equipment/rv_panel.gd) 52–57；[正式 RV](../../rv/new_rv.tscn) 96–110。

`mount_support` 的失效監聽依賴 `removing` 或 `tree_exiting`。基類 `start_placement()` 不發送 `removing`，目前僅 RVPanel 補上。正式平板與工作台是底盤的兄弟節點，平板另外依附工作台；工作台在同底盤重新放置不會離開場景樹，因此兩種失效通知都沒有觸發。

重現：使用正式 `rv/new_rv.tscn`，工作台經 `start_placement()` 與 `confirm_placement()` 移動 2 m。平板位移仍為 **0.000 m**、`mount_support == station`、`freeze == true`、`can_operate() == true`。probe 直接呼叫正式生命週期入口，沒有模擬滑鼠放置與 PlacementRules。

修正方向：將搬移釋放依附物的契約下放到 Equipment，RVPanel 不再重複通知；補一般設備、取消搬移、同車重新放置及多層依附的回歸。既有 [引擎測試](../../tests/test_rv_engine.gd) 34 只確認預設平板依附，[結構測試](../../tests/test_rv_structure_modules.gd) 170–179 只測面板搬移。

### A02：UI 模式鎖住整個玩家物理

來源：[玩家](../../player/player.gd) 413–457、663–676；[RVSupport](../../core/rv_support.gd) 15–35。

`in_ui_mode` 直接從 `_physics_process()` 返回，略過重力、`move_and_slide()` 與支撐追蹤。世界沒有暫停，平板／道具箱也沒有一律要求停車；當車滑動、被撞或腳下支撐消失，玩家仍留在舊世界座標。關閉 UI 後才處理累積位移，超過 RVSupport 的 1.5 m 保護門檻時會直接失去支撐。

重現：正式玩家在無地板的 y=10 處開 UI，60 個物理步後仍為 **10.000000**；關閉後 15 步降至 **9.673334**。這證明 UI 凍結重力，沒有把它冒充移動 RV 的完整實機回放。

修正方向：UI 禁止主動走路、跳躍及攀爬輸入，但保留重力、碰撞與既有支撐更新；轉場鎖定另有明確模式。補「UI＋滑動 RV／支撐拆除」組合測試；目前模式測試和隨車測試各自成立，缺少交集。

### A03：v5 回程的 actor 清理仍單向

來源：[世界串流](../../world/world_generator.gd) 66–72、147–156、166–172。

v5 在窗口兩端都卸載地形，`_despawn_entities_behind()` 卻仍只比較 `actor.z - player_z > distance`。向正 Z 回程時，負 Z 遠方的普通物品／怪物不會清理，即使地形已卸載，仍可能繼續落下與模擬。`generated_bands` 又使回訪不會自動重新生成普通物資。

重現：v5 預設 profile，玩家錨點 z=0、同容器兩個 Node3D 測試替身分別在 +1000／−1000 m；直接呼叫正式清理方法後，正側已排程刪除，負側仍保留。probe 不生成整段公路，也未執行怪物群組分支，驗證的是容器清理條件不對稱。

範圍：walk-in 場址有 `WalkInSites.deactivate()` 保存／釋放及 bounds 保護，不屬於此處「普通 actor」。[加油站回程測試](../../tests/test_outdoor_gas_station.gd) 133–169 已涵蓋場址保存，不能替代場址外測試。

修正方向：v5 依雙向有效窗口／距離清理，先處理場址保存，排除載具與已掛載設備；v2–v4 仍維持既有版本規則。補來回兩方向、場址外鬆散物／敵人及車載物不被誤刪的案例。

### A04：POI 離場取消的保存提交不一致

來源：[副本管理器](../../world/instances/poi_instance_manager.gd) 112–139、170–194。

`leave()` 先等待一幀才保存室內。若這段期間玩家死亡，`_valid_operation()` 走取消流程，把同一玩家與背包搬回戶外並釋放副本，卻未寫入 `saved_instances`。依 `enter()` 的 saved-state 分派推導，首次副本重進會重建原始物資，已訪副本則回到上次狀態；本次拾取物仍在背包，形成進度回退與物資重複的風險。

重現：使用正式玩家與 PoiInstanceManager，直接組裝 manager 的 INDOOR 狀態與空 PoiInterior，向背包注入一個物品；呼叫 `leave()` 後在等待期間注入 HP=0。結果為 FAILED、已回戶外、背包 **1 件**，該副本的保存紀錄仍不存在。這是狀態機故障注入，未執行完整 `enter()`／`build()`／拾取與回訪流程。

修正方向：區分進場建立失敗與離場取消；後者保留室內或在釋放前提交有效 snapshot，避免只提交背包。補離場死亡／逾時、首次／已訪副本、已拾取道具與目標捷徑狀態。既有 [故障測試](../../tests/test_checkpoint_failures.gd) 152–156 測的是進場死亡。

### A05：正常離場缺少導航重烘的釋放保護

來源：[捷徑重烘](../../world/instances/maintenance_interior.gd) 173–176、217–219；[離場／取消](../../world/instances/poi_instance_manager.gd) 132、196–204。

開啟捷徑可啟動非同步導航重烘。取消轉場已有 `_retire_viewport()` 等待 native bake 完成，正常 `leave()` 卻直接 `queue_free()` viewport。兩條清理路徑的生命週期保護不一致，慢機或重烘中離場可能觸發失效 continuation／資源生命週期錯誤。

目前僅確認缺少保護，**未重現崩潰**。[室內回放](../../tests/interior_v2_replay.gd) 104 主動等待 `rebaking` 完成，迴避了此競態。建議共用取消與安全釋放流程，針對重烘進行中離場／重進測試。

### A06：車內導航的群怪成本沒有預算

來源：[MonsterCabinRoute](../../enemies/monster_cabin_route.gd) 35–40、106–131。

需要車內路徑的追擊怪物約每 0.65 秒，或局部目標移動超過 0.5 m 時，同步重建自己的 AStar3D。每次先掃 15×55＝**825 個位置**，再檢查鄰邊的碰撞與掃掠、尋找起點和近戰視線。多隻怪物在同車重複處理相同靜態幾何；目標持續移動也可能使重建早於固定週期。

這是程式成本分析，沒有量測到的 FPS 結論。現有車內測試主要逐隻驗證行為。建議先量測 1／5／10 隻的重建次數、物理步時間與 p95，再考慮按 RV＋膠囊規格快取靜態圖、以設備修訂失效，另處理動態避障並錯開重建。不要直接快取含其他怪物碰撞的完整結果。

Monster 本體約 1,941 行，Raker 繼承多條共享攀爬／攻擊路徑，亦提高改動耦合。先穩定行為契約與測試，再按地面導航、車內路徑、攀爬和攻擊分工；行數本身不是缺陷，也不是全面重寫理由。

### A07：主場景 smoke 未驗證實際入口設定

來源：[runner](../../scripts/test.ps1) 45；[smoke](../../tests/main_scene_smoke.gd) 7；[專案設定](../../project.godot) 14。

smoke 直接載入 `res://world/test_world.tscn`，未從 `application/run/main_scene` 取得路徑。未來專案入口誤設，測試仍可能通過。目前兩者相同，沒有現存入口錯誤。建議讀取並斷言正式設定入口，再保留目前地形／導航就緒與移動驗證。

### A08：室內產生工具防覆寫不完整

來源：[build_interior_v2.py](../../scripts/build_interior_v2.py) 98–110。

工具逐項檢查房間 `.tscn`，但相應 room `.tres` 及 `maintenance_v2.tres` 直接寫入。部分輸出被移走後重建，可能先覆寫已手動維護的 catalog，再遇到後面的既有場景而中止。建議一次預檢全部輸出，再執行寫入；需要更新資產時另設明確模式。本輪未執行此生成器，也未改動資產。

### A09：runner 的證據目錄不能區隔並行執行

來源：[runner](../../scripts/test.ps1) 4、13、17–18。

所有執行共用 `.godot/test-logs/manifest.txt` 與同名 suite 日誌。本輪一開始 discovery 為 53 組，另一批 Raker 專項執行後，共用 manifest 實際變為 `Tests: 3`；import 與部分同名 suite 日誌也會被後一次執行覆寫。CI 單一 job 通常不會碰到此情境，本機多任務則已發生。

後果不只是少一份歷史：兩個 runner 同時執行同一 suite，會讀到彼此共用的日誌，削弱退出碼與 PASS 標記的對應。不能只拿最後的 manifest 代表本輪 53 組結果。建議 runner 接受獨立 `LogDirectory`／run ID，並保存執行時間與來源狀態；必要時用鎖拒絕共用輸出目錄。

## 遺產處置清單

「候選」表示引用與載入流程支持清理，**不表示已刪除或已驗證刪除後的專案**。

| 類別 | 檔案／內容 | 證據與處置 |
|---|---|---|
| 第一批：低風險候選，8 檔 | `equipment/fuel_tank.gd`、`.gd.uid`、`fuel_tank_definition.tres`；`material_rack.gd`、`.gd.uid`、`material_rack_definition.tres`；`material_storage_ui.gd`、`.gd.uid` | 舊場景已直接繼承新版 fuel_port／item_box，未使用這些 script／definition；未找到外部路徑或 UID 引用。可在獨立清理變更刪除，再 import＋runner。 |
| 第二批：需驗遷移，5 檔 | `equipment/fuel_tank.tscn`、`material_rack.tscn`；`props/material_bundle.gd`、`.gd.uid`、`.tscn` | 現行 SaveSceneCatalog 不接收舊路徑；Checkpoint 與 VehicleSnapshot 先比較字串並轉換／吸收舊資料，不需實例化舊場景。保留轉換字串與 fixture，移除實體檔後驗 v1／v2 保存。 |
| 小型死碼候選 | `Equipment.get_half_extents()`／`hold_timer`、`WheelHitbox.hold_timer`、`Chassis.EMPTY_GAS_CAN_*`／`_set_fuel()`／`_set_power()` | 目前程式／場景／測試未見引用，archive 仍有歷史說明；可逐組清理並驗互動／能源。不要據此刪同類所有代理介面。 |
| 保留相容程式 | v1／v2 checkpoint migration、v2–v4 generation、PoiInterior／MazeLayout／v1 房型、maintenance_legacy | 舊保存資料仍經正式入口分派到這些實作，有相容測試；要退役必須先決定存檔支援政策。 |
| 保留有用途的對照資產 | `rv/legacy/`、`world/art_sample/`、style_sample 材質、`fuel_pump_graybox.tscn` | 被展示場、A/B 比較或回歸測試引用。可日後集中標示為測試資產，不能直接刪。 |
| 保留製作來源 | `scripts/build_*20260915`、其他 build 腳本 | 是製作來源，maze builder 另繼承 POI builder；檔名帶日期不代表廢棄。 |
| 不以文字搜尋判死 | gas_can／oil_barrel 的 WebP、GLB 及匯入相關檔 | GLB 有內嵌圖像，匯入設定可能生成關聯資源；需要資源依賴與乾淨匯入驗證。 |
| 保留原始想法與歷史 | `todo`、`todo_prompt`、`GDD_add.md`、`docs/archive/` | GDD_add 補提案定位，原文保留；封存紀錄與本輪結果分開。 |

特別反例：`Chassis.install_wheel()` 雖然未被直接呼叫，[PlayerInteract](../../player/player_interact.gd) 149 用 `has_method("install_wheel")` 當能力判斷，不能按「沒有 call site」刪除。

清理批次應保留 [Checkpoint 轉換](../../rv/checkpoint.gd) 355–379、[VehicleSnapshot 轉換](../../rv/vehicle_snapshot.gd) 234–242 及 [共用儲存 fixture](../../tests/test_rv_shared_storage.gd) 118–126。第一、二批合計 13 個實體檔案；不包含仍必要的 migration 字串。

## 文件同步

- GDD 改正「只有 Zombie」與已接入 Raker 的矛盾，將室內 v2 下一步改為主題／自由探索／平衡。Raker 計畫與索引保留其他工作新增的[獨立驗收紀錄](../validation/2026-09-22-raker.md)，其實機與動畫驗收不算本輪重做。
- architecture 補 v2 模組責任、修正 v5 場址保存的描述、區分新舊房型，列出 A01–A06 的缺口，避免將契約理想寫成完全實現。
- docs 索引補本報告及室內 v2 主世界整合驗收，將 v2 指南／驗收移至正確分類；計畫總覽補 Raker 與優先修復項。
- GDD_add 只補定位與現況入口，不刪除原始設計想法。歷史 2026-09-18 報告及既有模型驗收不改寫。

## 本輪驗證

環境：Windows `10.0.26200.0`，Godot `4.7.2.stable.official.ed1daf0bf`，headless／dummy renderer。`godot` 不在本 shell 的 PATH，使用既有安裝絕對路徑；APPDATA 指向專案 `.godot/architecture-audit-20260922/appdata`，隔離使用者存檔及設定。

```powershell
$env:APPDATA = Join-Path $PWD '.godot/architecture-audit-20260922/appdata'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Godot 'C:/Users/evan4/AppData/Local/Programs/Godot/Godot_console.exe'
```

| 檢查 | 本輪結果 |
|---|---|
| 完整 runner：import、53 組 test、主場景 smoke | 本輪程序回報全部 PASS，退出碼 0；共享 manifest／部分日誌被外部 Raker 專項覆寫，不能當成單一凍結版本的隔離執行紀錄，見 A09 |
| 獨立目錄補驗 Raker：import、3 組 test、主場景 smoke | 全部 PASS，退出碼 0；使用暫存 runner 副本，只改專案根路徑解析與日誌輸出目錄，保留正式驗證邏輯，涵蓋最新 22 段動畫版本 |
| `behavior_probe.gd` | 通過重現判斷：A02 UI 重力凍結、A03 清理不對稱 |
| `lifecycle_probe.gd` | 通過重現判斷：A01 平板遺留、A04 取消未保存；首次 probe 因暫存腳本型別推導錯誤未執行，補明確 bool 型別後重跑成功 |
| 文件相對連結與 diff 格式 | 非封存 Markdown 70 份、634 個本機連結，路徑全部存在；`git diff --check` 通過。未驗 anchors 或外部 URL |

定向 probe 的 PASS 表示**成功重現問題**，不是該功能正確。probe 腳本、日誌留在 `.godot/architecture-audit-20260922/`，不納入提交；正式 suite 日誌為 `.godot/test-logs/`。補驗的獨立日誌與 manifest 位於 `.godot/architecture-audit-20260922/raker-verification/`。runner 依既有規則排除 Windows 沙箱的 root certificate store 診斷，沒有排除腳本錯誤。

本輪沒有桌面互動、Forward+ GPU 畫面、聲音聽感、實際輪驅長途、翻車或群怪效能驗收。headless 下 `ForestFog.supported()` 不啟用 Forward+，部分體積霧／排霧斷言會跳過；不能把 suite PASS 解讀為雨幕、鏡面或 shader 畫面已驗證。

## 建議修正批次與完成條件

1. **生命週期與狀態一致性**：修 A01–A04，各補對應的失敗情境回歸，再跑統一 runner；物理與支撐修正另依 AGENTS 做實機攀爬／拆頂檢查。
2. **轉場與效能**：統一 A05 的導航釋放流程，量測 A06 的 1／5／10 怪；以量測決定快取或分幀，不先大規模拆 Monster。
3. **小批遺產清理**：先刪 8 個未被使用的包裝 script／definition，再驗 5 個舊資源檔可否退役，保留 migration、測試 fixture、對照場及原始 todo。
4. **驗證與製作工具**：修 A07–A09，保存本輪與後續結果的分界。主場景自動通過、文件同步、實機驗收各自記錄。

已列出的問題在本輪均未修正；這份報告供下一批實作與審查使用。

## 後續補充：測試 runner 是否有多餘內容

2026-09-22 後續核對。再次由三個 subagent 分別檢查 runner／CI、玩家與怪物 suites、世界與 POI suites；主 agent 核對涵蓋範圍並量測短測試的固定成本。本節未修改 runner、未刪除測試，也未重新執行前節的全部 53 組。

**有可精簡項目，但正式 runner 只有一份。** [scripts/test.ps1](../../scripts/test.ps1) 由 [CI](../../.github/workflows/tests.yml) 呼叫，預設頂層發現 53 個 `test_*.gd`。最後的 `main_scene_smoke.gd` 不符合該搜尋模式，並未在同一次呼叫中執行兩遍。

| 項目 | 判斷與證據 | 建議 |
|---|---|---|
| [test_player_climbing_runtime.gd](../../tests/test_player_climbing_runtime.gd) | 8–30 行只有腳本載入、new、`_abort_climb` 存在與兩個舊 mantle 方法不存在的檢查；沒有 runtime 場景或物理。已被 [test_player_climbing.gd](../../tests/test_player_climbing.gd) 19–25、107–125 涵蓋。 | 可移除這個 suite 與 `.uid`，或改為尚缺的 UI／支撐 runtime 案例。清理後同步架構測試表。 |
| Raker 登車繼承整套玩家案例 | [test_raker_boarding.gd](../../tests/test_raker_boarding.gd) 1–5 只替換 monster_scene 後呼叫父類；[test_moving_rv_climbing.gd](../../tests/test_moving_rv_climbing.gd) 31–72 的玩家登頂／隨車、127–145 的玩家分支、147–167 的座位／頭頂碰撞因此跑兩次。第一段甚至尚未建立怪物。 | 拆分玩家案例與按怪物種類執行的案例，玩家部分只跑一次；保留兩種怪物登車／拆頂／掉落。需明確初始化與重置 RV，不能直接跳過造成隱藏相依。 |
| [test_poi_resources.gd](../../tests/test_poi_resources.gd) 與 [test_poi_definitions.gd](../../tests/test_poi_definitions.gd) | 兩者均驗目前六個 POI 的載入／實例化／場景契約；definitions 經 POISpawner 執行 validate／載入／validate_scene。resources 獨有完整 catalog 遍歷與重複 ID 檢查，不能直接丟棄。 | 先將 definitions 的寫死 ID 陣列改成遍歷 DEFINITIONS，保留 ID 唯一性，再移除 resources suite；可省一個程序及一輪六場景實例化。同步 POI 製作指南入口。 |
| 每次 filter 都做 import＋smoke | runner 37、45 行不受 TestFilter 影響。連續分批呼叫會重複這兩步，即使只測背包。 | 優先支援多組 filter 合併去重，單次匯入／smoke；本機快速模式可選擇略過已確認不需重做的階段，但完整 CI 保留。 |
| `.godot` 的 runner 副本 | `run-model-remaining.ps1`、`poi-v2-integration/scripts/test.ps1`、`architecture-audit-20260922/isolated-test.ps1` 都不在正式 discovery 中，也未受 Git 追蹤。舊續跑副本已漏新 Raker fixed-fps 名單。 | 加正式 LogDirectory／多 filter 或續跑選項後停止複製。它們可作暫存清理候選，但刪除不會加速正式 runner；仍需保留本輪證據時先不刪。 |

不能按名稱相似刪除：Zombie／Raker cabin 分別驗障礙繞路／移動車內追擊，以及低姿態入艙／離艙站立；世界生成、分幀一致性、場址規格及實際玩家搬運各有獨有斷言。RV 煞車、操控、掛載物理與完整資源循環也不是同一案例。`main_scene_smoke` 保留正式 profile 的就緒與移動檢查；版本核對、零測試拒絕、timeout、退出碼、錯誤掃描、PASS 和 manifest 各自防止不同的假通過。

若移除重複的 climbing runtime suite，並將 POI resources 併入 definitions，套件可從 **53 組降至 51 組**，前提是保留上述獨有斷言。Raker 玩家案例去重可另外減少步數；沒有量測這三項的實際節省時間，不宣稱大幅加速完整回歸。

### 後續量測與邊界

使用同一 Godot 4.7.2、headless、正式 runner 相同的引擎參數，依序執行 import、`test_player_inventory.gd`、`main_scene_smoke.gd`；日誌與 APPDATA 獨立放在 `.godot/runner-redundancy-audit/`。三步退出碼皆 0、無腳本錯誤，後兩步包含 PASS；root certificate store 診斷沿用相同精確排除規則。

| 階段 | 單次實測 |
|---|---:|
| 匯入 | 8.393 秒 |
| 背包測試 | 1.851 秒 |
| 主場景 smoke | 22.045 秒 |
| 匯入＋smoke | 30.438 秒 |

這是既有匯入快取、隔離 APPDATA 的單次樣本；包含程序啟動／結束成本，不代表多次平均、CI 時間或所有測試的比例。它支持「短測試分次呼叫有可觀重複成本」，不支持直接刪除完整驗證的匯入或 smoke。

建議精簡順序：先去掉重複 climbing suite、合併 POI 契約檢查，再分離 Raker 的玩家案例；runner 增加多 filter 與獨立日誌，保持單一入口與完整覆蓋。

本節文件核對：非封存 Markdown 70 份、642 個本機連結路徑有效，`git diff --check` 通過；未驗 anchors 或外部 URL。前節的 53 組執行結果仍屬前一輪，不視為這次重跑。
