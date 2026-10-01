# 測試執行器與現行測試整理

日期：2026-10-01。環境：Windows 11、Godot 4.7.2 stable、headless/dummy，專案維持 60 Hz／Jolt。基準 commit `99c6b1e23564df6584c101bf77ae9eaf41ce0036`，包含當時既有未提交的起始避難所及其他工作樹修改。下列是本輪執行結果，不沿用歷史驗收作為本次通過證據。

## 更動

- 原本 90 支頂層測試改為 quick 16、integration 32、slow 27、assets 14；正式主世界 readiness/movement 為獨立 smoke。full 與 CI 涵蓋 89 支有效測試及 smoke。分組依本輪量測再調整，full 選取的有效測試範圍相同。
- `test_raker_boarding` 完全繼承與預設 fixture 相同的移動 RV 攀爬情境，列為 retired 並保留直接執行。v2–v6 舊世界／存檔相容性測試仍保留。
- Runner 使用固定 60 fps 模擬排程加速，保留物理 tick、求解器、原本模擬情境及 seed 數量；提供 RealTime 對照。指定測試不額外建立完整主世界。
- 加入清單一致性檢查、List、SkipImport、FailFast、逐支耗時與失敗收集，每次執行保留獨立 JSON／CSV／manifest／日誌。
- 導航 bake/publication、候選世界 retirement 及背景生成使用有期限的條件等待，取代無期限等待與猜測就緒的固定幀數。
- 玩家／怪物外觀測試保留當前骨架、蒙皮、材質、鏡頭、陰影、接地與生命週期契約，移除固定歷史總數與已移除 mantle helper 必須不存在的斷言。
- 匯入／蒙皮／布娃娃 audit 證據移到 `.godot/test-logs/`，不覆寫受版控的歷史 JSON。CI 在隔離 job 分組執行全部覆蓋。

## 本輪量測與驗證

| 執行 | 結果 |
|---|---|
| 原 runner，僅 `test_player_inventory`（含必跑匯入與主世界） | 通過，42.82 秒 |
| 新 runner，預設 quick 16 支（含匯入） | 全部通過，33.52 秒 |
| 新 runner，僅 `test_player_inventory`（含匯入、引擎版本核對及 PowerShell 啟動） | 通過，8.22 秒；runner 階段本身 7.38 秒 |
| 新 runner，單次 full 89 支 + 正式世界 smoke（含匯入） | 全部通過，1,227.90 秒（20 分 28 秒） |
| Runner 自我測試 | Windows PowerShell 5.1 與 pwsh，各 82 項斷言通過 |

快速集日誌：`.godot/test-logs/20261001-190718-308-quick-12052/`。每支約 1.3–2.3 秒，匯入約 5.9 秒。

自我測試使用隔離 fixture 與假引擎，驗證分類／篩選／續跑、清單異常、退出碼／script error／缺 PASS／timeout、憑證診斷例外、繼續收集、FailFast、匯入、RealTime、smoke 專屬標記與輸出報告。假引擎刻意印出的 FAIL/TIMEOUT 是預期案例。

單支測試日誌：`.godot/test-logs/20261001-193039-352-selected-25016/`。完整回歸日誌：`.godot/test-logs/20261001-190930-348-full-32360/`，`results.json` 有 91 筆 PASS（89 支測試、smoke、匯入），零失敗、零超時。正式世界固定 seed 42，等待地形、導航與玩家可操作後驗證移動。

完整模式仍需約 20 分鐘，主要成本包含地形／導航重建及 CPU 掃描，並非全都能透過模擬排程加速。本輪最慢項目為地堡 1,000 seed 掃描（105.92 秒）、起始檢查點（103.65 秒）、手電筒世界存檔（85.25 秒）、戶外外觀整合（76.26 秒）與戶外遭遇（67.13 秒）。快速集與指定測試已避免附帶這些成本。

實時輪驅煞車對照通過：`-TestFilter test_rv_braking.gd -SkipImport -RealTime` 的測試階段 30.25 秒，加速模式為 6.52 秒。兩種排程下五種速度／踏板情境的輸出時間與距離完全一致（列印精度為秒、米小數三位）。實時日誌：`.godot/test-logs/20261001-193059-636-selected-30532/`。這是該組物理情境的對照，未宣稱所有實時排程情境已逐一比較。

`git diff --check` 與本輪更動文件的相對連結檢查通過。

## 範圍

本輪修改測試與執行方式，沒有修改正式遊戲物理或玩法。未進行實機／GPU 畫面操作；headless 不代表手感、輪驅長途、翻車或群怪視覺驗收。GitHub Actions 定義已更新，本機未實際觸發遠端 CI。

操作與維護見 [測試指南](../../tests/README.md)。
