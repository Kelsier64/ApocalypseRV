# 自動測試與 CI 精簡

日期：2026-10-19。分支 `codex/simplify-tests-ci`，基準 `origin/main` 的 `70dfc58`。使用者明確同意只留約 16 個核心測試，刪減舊版相容性、舊教學及外觀專用回歸。既有 `project.godot` 未提交修改保留並排除本次提交。

## 更動與覆蓋取捨

- 213 個頂層入口（212 個有效、1 個 retired）降為 16 個：刪除 196 支腳本及 UID；另將 `test_orientation_workshop_journey` 移至 `tests/support/orientation_journey.gd`，只由 departure 執行。移除未再引用的兩個 helper 與地堡擴充測試 fixture。
- 移除 `suites.json` 與 quick／integration／slow／assets／full 分組；自動發現頂層 `test_*.gd`。預設跑全部核心集及正式世界 smoke。
- 保留引擎版本檢查、一次匯入、程序隔離、固定 60 fps、退出碼／錯誤／非空日誌／PASS／專屬 smoke 標記與逾時子程序清理。第一項失敗立即停止。
- 移除 StartAt／FailFast 選項與重複的 manifest／CSV 輸出；每次獨立保存 JSON、環境／選取資訊、耗時與日誌。新增 `-SmokeOnly`；指定測試仍可用 `-TestFilter`、`-Smoke`、`-SkipImport`。
- CI 由 5 個 Windows job 改為 1 個，下載與匯入各一次，自測只用 Core。main push、PR、手動可觸發；文件修改略過，同分支新執行取消舊執行，失敗才上傳日誌。job 上限由各組 30 分鐘改為單組 10 分鐘。

保留核心範圍見 [測試指南](../../tests/README.md)。刪除的並非全屬無效測試：早期獨立模型樣板、重複攀車入口屬過時／重複；舊教學、舊世界相容性、種子掃描、動畫幾何、長時間追擊及多情境物理仍有價值，本次依授權退出自動覆蓋。遊戲相容程式與手動 playground 保留，不能用核心集宣稱上述情境仍已完整回歸。

## 本輪實測

Windows、Godot `4.7.2.stable.official.ed1daf0bf`（`C:/Program Files/godot/godot.exe`），headless／固定 60 fps。未改物理、time_scale、遊戲場景或玩法。

| 檢查 | 結果 |
|---|---|
| 精簡前原版 quick：50 支，含匯入 | 50/50 PASS，127.35 秒 |
| 精簡後預設：16 支 + 正式世界 smoke，含匯入 | 17/17 PASS，81.62 秒 |
| Runner 隔離自測 | Windows PowerShell 5.1、Core 各 41 項斷言 PASS，包含真實子程序逾時清除 |
| 靜態與獨立審查 | diff 空白檢查通過；保留程式沒有指向已刪資源的引用，現行文件沒有新增指向已刪檔案的失效連結 |

本機新預設比原 quick 約快 **1.56 倍**，兩者覆蓋不同：新預設同時跑完整維修出庫、保存失敗處理與正式主世界。這不是原 full／CI 與新 CI 的同環境比較。

原 quick 日誌：`.godot/test-logs/20261019-114329-848-quick-38856/`。新預設：`.godot/test-logs/20261019-114746-892-all-32056/`。新版出庫 14.52 秒、保存失敗處理 11.94 秒，是保留集最慢的兩項。所有結果同時要求 PASS 與正常退出，沒有忽略原生崩潰。

## CI 工作量估算

使用 [2026-10-18 最近成功的 main CI](https://github.com/Kelsier64/ApocalypseRV/actions/runs/39124232038) 原始 JSON 計時（基準 `c839009`），不是本輪新 CI 實測：

| 舊分組 | 測試數（不含匯入） | Runner 耗時 |
|---|---:|---:|
| quick | 50 | 148.27 秒 |
| integration | 106 | 1,492.77 秒 |
| slow | 37 | 898.59 秒 |
| assets | 19 | 159.21 秒 |
| smoke | 1 | 34.41 秒 |
| 合計 | 213 | 2,733.24 秒 |

五個 job 當時平行執行，實際最慢 job 約 **25 分 32 秒**；上表合計是測試工作量，不能當作使用者等待時間。

同一份舊 CI 的 16 個保留測試與 smoke 合計 117.08 秒，加上舊 CI 五次匯入的平均一次成本 31.93 秒，估算新單一 runner 約 **149.01 秒**，工作量約縮小 **18.34 倍**。估算不含 checkout、下載 Godot、自測及排隊，亦未反映分組 CPU 競爭差異。新版實際雲端總耗時須在批准推送後量測。

舊 CI 原始報告下載至 gitignored 的 `.godot/test-pruning/ci-before/`；本輪不提交完整日誌或工具輸出。

## 驗證限制

未進行原生視窗／GPU 或人工遊戲操作；本次只改測試與 CI。尚未推送或觸發新版遠端 CI。main 分支保護與 ruleset 的唯讀檢查未發現舊 job 名稱的必過規則。

文件掃描另發現 architecture 與文件索引共 31 處既有歷史驗收連結，在本機原已缺檔；本次保留原文，未將它們算成通過。
