# 偏行迷霧刷新與出生點後方重整

2026-10-11，Godot 4.7.2 stable，生成版本維持 v10、checkpoint 維持 v5。實作與操作入口見 [README](../../README.md)、[架構](../../architecture.md)。

## 實作

道路最遠進度保留有符號投影，出生入口下限 45 m。回退超過 120 m 或離路緣超過 100 m，持續 3 秒啟動；據點實際占地、出入口及真實步道兩側 12 m 豁免。森林場址整體 AABB 不豁免，非合法森林探索不推進最遠進度。

事件霧在 8 秒增至小霧，30 秒增至中霧；第 8 秒嘗試兩隻 Raker，第 30 秒嘗試一隻 Slender Speaker，此後每 30 秒嘗試兩隻 Raker。恢復門檻 80／70 m、確認 3 秒、退霧 12 秒、刷新冷卻 60 秒。冷卻內重入仍起霧，怪物曝光計時待冷卻結束；退霧重入銜接既有濃度。計時使用真實遊戲秒數，整備、暫停、staging、死亡、抓取、副本及切換期間不推進。

出生 helper 每名額每批最多 24 候選，失败每 2 秒重試；過期 Raker 波次不累積。使用正式碰撞、地面、普通／巨人導航及正常感知；檢查完整模型相機視錐與深度霧遮蔽，面向玩家但不強制 AI 目標。Raker 20–24 m 且滿足實際 3D 偵測，追加上限為同世界存活 8 隻；巨人 120–160 m 並與原刷新共用存在名額。保留原道路、據點、副本及自然天氣刷新。偏行霧只合成显示用天氣，雨量、自然 RNG、保存和原巨人天氣判定不變。

v10 後方使用既有廢車，最多 28 台，各自獨立位置／朝向，預留連續 1.5 m 步行路徑。車群在導航烘焙前建立；保留原植被排除遮罩以維持 band:index 樹木身份。v7–v9 原封路車陣與土堤保留。

可選 `route_pressure` 保存 timing 與 RNG，`rear_wreck_layout` 保存 ID、transform 與通道。缺少記錄的舊 v10 在實際玩家還原後初始化，生成後方配置前避開玩家、RV 和道具占地。新 `RearWrecks` 使用獨立支撐路徑，旧 `Roadblock` 上 Item 的失去支撐走原脫落流程。配置卸載後仍保存；不計離線時間，不刪除既有怪物；不合法的現存欄位及浮空 transform 拒絕載入。

## 當次自動驗證

全部通過，headless／dummy，固定 60 FPS；設定放在忽略追蹤的 `.godot/deviation-appdata`，未改玩家偏好。測試 runner 為 [scripts/test.ps1](../../scripts/test.ps1)，新增測試均已在 [suites.json](../../tests/suites.json) 分類。

- Quick 30 項：`.godot/test-logs/20261011-173627-337-quick-36656/results.json`。
- 相關回歸 12 項：偏行保存、出生、道路保存／生命週期、巨人感知／世界、起始保存／舊封路、串流、世界生成、天氣及主場景 smoke；`.godot/test-logs/20261011-173831-675-selected-16112/results.json`。
- 最後補充測試 3 項：拒絕浮空保存配置、消失的舊支撐 Item 脫落、準備／staging／死亡／抓取／切換／暫停凍結、立即恢復霧、7 隻 Raker 只補 1 隻、後方負區段巨人自然感知及正式玩家穿越；`.godot/test-logs/20261011-174150-752-selected-8112/results.json`。
- 多 seed 純規劃檢查 0／1／42／99 的位置／朝向、貼地、完整占地避讓、連續通道、還原占地排除，以及改動前 v10 森林完整陣列身份一致。讀檔測試涵蓋缺可選欄位、部分波次與 RNG、退霧與冷卻、候選世界不刷新、配置卸載／回訪一致。

最初兩次 sandbox import 因 Godot 設定安全存檔權限失敗；授權引擎存取後 import 通過。早期測試發現 director 內部 `state` 鍵被 Item 身份掃描當作 Item，已改為 `timing`；正式保存回歸通過。

## 實機觀察與範圍

Forward+／Vulkan，NVIDIA RTX 5070 Ti，正式場景測試包裝 [rear_pressure_playground](../../tests/rear_pressure_playground.tscn)，日間晴天、seed 42。以 computer-use 選取遊戲視窗，沒有操作 Godot 編輯器。

- 看到 27 台廢車以不同位置與方向散落，沒有原堆疊封路、碎石 backing 或長翼牆。
- F2 使用正式玩家連續前進，穿過車群到 Z119.7564，導航查詢 66 個路點；`REAR_TRAVERSAL ok=true`。起點擺放屬測試設定，穿越過程使用正常輸入與實際碰撞，沒有逐幀傳送。
- F3 擺放至後方 X35／Z120；日間晴天出現偏行霧，日志 `PRESSURE_START reason=backtrack highwater=45 progress=-120`。Raker 以原 AI 追上、扣血與抓取玩家；觀察到 24 點傷害與正常死亡／復活。

實機日志 `.godot/rear-pressure-gui.log` 保持忽略追蹤。使用者按實體 Escape 停止 computer-use，之後未繼續操作視窗。實機未單獨驗收深林巨人、完整冷卻循環、低畫質切換或所有 seed 的步行穿越；後方與深林巨人、霧合成、冷卻及跨導航接縫由自動測試覆蓋。車輛是否能穿過廢車群依配置決定，本輪沒有宣稱 RV 通行或長局效能通過。
