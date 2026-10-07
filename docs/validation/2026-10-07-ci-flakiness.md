# CI 不穩定測試修正 — 2026-10-07

基準 commit：`157d2a7e2f8e2d3b082d8236984d0eb67d10f2b9`。Windows／Godot 4.7.2 stable，統一 runner 的 headless／dummy、固定 60 FPS。測試用獨立 managed checkout 與 `.godot/ci-appdata`，只套用本輪三個程式／測試檔案，避免主工作樹同步進行的普通油桶功能修改影響驗證。

## GitHub 與本機重現

- [同 commit 失敗](https://github.com/Kelsier64/ApocalypseRV/actions/runs/37503578400/job/112406452282) 與 [同 commit 成功](https://github.com/Kelsier64/ApocalypseRV/actions/runs/37503585982/job/112406478777) 確認 `test_outdoor_encounter` 不穩定；五筆 slow 失敗紀錄都落在遠端場址的 `Production monster crosses streamed seam and rotated gate`，並有玩家反覆死亡／重生。
- 未修改的戶外測試本機同樣 FAIL（47.20 秒），重現相同遠端 gate 斷言與死亡／重生。日誌：`.godot/test-logs/20261007-210052-185-selected-42988/`。
- [最新 integration 失敗](https://github.com/Kelsier64/ApocalypseRV/actions/runs/37623611453/job/112799715877) 與前一版 `37620705897` 都包含 `test_barrel_man` 倒數斷言失敗。這是測試沿用舊數值造成的確定性失敗。
- [屍體 playground 的單筆原生崩潰](https://github.com/Kelsier64/ApocalypseRV/actions/runs/37586474238/job/112677645250) 發生在 `CORPSE_RECYCLED`、fixture 清理與 `PASS:` 之後，退出碼 `-1073741819`（Windows access violation）；後續兩次 CI 同測試已通過。尚未取得 native stack，不能據此判定根因。

## 修正

[戶外測試](../../tests/test_outdoor_encounter.gd) 原本以空陣列的 `all()` 判斷初始就緒，且只刪除當下已存在的怪物，漏掉非同步生成的 actor。後續等待遠端背景導航時，近距離 Raker 持續追擊玩家。固定 FPS 等待背景工作仍推進模擬，等待時間依機器負載變動；10000 HP 不能防止抓咬直接斷頭，抓取又會解除 UI 模式，使後續傳送的追逐目標失去原測試狀態。

現在等待預期初始區塊數、生成完成與全部導航就緒，使用既有 TestWait 期限；新生成的環境怪物立即停用、就緒後移除。被測追逐怪物與玩家只在非同步準備期間凍結，傳送與清零速度後恢復。原五個轉彎目標、2700／1500 tick 追逐上限、900 tick 輪驅進入、300 tick gateway 阻擋及 90 tick 煞車採樣、空間門檻全部保留；增加準備後玩家仍存活／未被抓取的斷言與失敗位置診斷。

[油桶人設定](../../enemies/barrel_man_settings.gd) 保留當前 3 m／2 秒玩法數值，以浮點常值避免小數配置被隱含整數型別截斷。[行為測試](../../tests/test_barrel_man.gd) 明確指定 1.5 m／0.5 秒 fixture，保留表面距離邊界、離開後不取消倒數與精確 30 tick 引爆；另驗證當前預設的實際物理倒數。GDD／architecture 同步目前數值，歷史驗收結果不改寫。

沒有加入失敗重試、放寬追逐門檻、縮短模擬時段或忽略原生退出碼。

## 本輪驗證

第一輪六支測試及主場景 smoke 全部 PASS：`test_outdoor_encounter`、`test_barrel_man`、`test_barrel_explosion`、`test_barrel_man_persistence`、`test_barrel_vehicle_contact`、`test_corpse_playground`、`main-scene`；匯入也 PASS，總耗時 83.17 秒。

第一輪之後，以相同統一 runner 連續重跑戶外／油桶人／屍體三項三輪，再單跑屍體 26 輪。包含第一輪的最終結果：

| 檢查 | 本輪結果 |
|---|---|
| `test_outdoor_encounter` | 4／4 PASS；四份日誌均沒有玩家死亡／重生；每次保留全部追逐、輪驅、阻擋與煞車驗證。 |
| `test_barrel_man` | 4／4 PASS；含小數 fixture 與現行預設的倒數。 |
| `test_barrel_explosion`、`test_barrel_man_persistence`、`test_barrel_vehicle_contact` | 各 1／1 PASS。 |
| `test_corpse_playground` | 30／30 PASS，全部退出碼為 0；歷史原生崩潰未重現，尚未修正或宣稱根因已解決。 |
| 正式主場景 smoke | 1／1 PASS，出現 `WORLD_READY_FOR_PLAY`。 |

總計 42 次測試／smoke 執行與一次匯入均 PASS。完整日誌、manifest、results 與彙總保留於主專案 `.godot/ci-diagnostics/local-validation/`，GitHub 來源日誌保留於 `.godot/ci-diagnostics/<job-id>.log`。本機基準失敗與修正後驗證分開保存。中途主工作樹有一輪載入其他同步修改的未完成腳本，已停止該程序；它未列入上表的隔離驗證結果。

沒有宣稱 GitHub 已套用本輪修改或 full suite 通過；本輪未進行原生遊戲視窗操作，玩法預設與追逐／車輛實作未更動。
