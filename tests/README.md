# 自動測試

從專案根目錄執行 [scripts/test.ps1](../scripts/test.ps1)。預設跑全部 **16 個核心測試 + 正式主世界 smoke**，匯入只做一次。Godot 版本由 [.godot-version](../.godot-version) 固定。

```powershell
# 日常與 CI 使用相同入口
./scripts/test.ps1
# 列出範圍，不啟動引擎
./scripts/test.ps1 -List
# 只跑相關測試；逗號分隔的樣式會合併去重
./scripts/test.ps1 -TestFilter 'test_item_*.gd,test_pistol.gd'
# 相關測試加上正式主世界啟動
./scripts/test.ps1 -TestFilter test_item_player.gd -Smoke
# 只驗證正式世界就緒、設定選單及玩家移動
./scripts/test.ps1 -SmokeOnly
# 同一批修改已匯入、資產沒有變更時省略匯入
./scripts/test.ps1 -TestFilter test_pistol.gd -SkipImport
# runner 自我測試，不需要 Godot
./scripts/test-runner.tests.ps1
```

可用 `-Godot 'C:/Program Files/godot/godot.exe'` 指定引擎。Windows PowerShell 5.1 與 PowerShell Core 均可執行；CI 使用 Core。

## 保留範圍

| 核心測試 | 主要目的 |
|---|---|
| [item_player](test_item_player.gd)、[item_persistence](test_item_persistence.gd) | 正式玩家拾取／放置、物品 ID／所有權及保存 |
| [rv_resource_cycle](test_rv_resource_cycle.gd)、[rv_engine](test_rv_engine.gd) | 回收、製造、燃料、維修、能源、引擎及車載作弊／時間／天氣指令 |
| [rv_structure_modules](test_rv_structure_modules.gd)、[rv_braking](test_rv_braking.gd) | 車體結構／支撐與真實輪胎煞車 |
| [moving_rv_climbing](test_moving_rv_climbing.gd) | 玩家與 Raker 的移動 RV 攀爬 |
| [pistol](test_pistol.gd)、[raker_grab](test_raker_grab.gd)、[barrel_explosion](test_barrel_explosion.gd) | 武器、抓取所有權及爆炸傷害 |
| [slender_speaker_encounter](test_slender_speaker_encounter.gd)、[slender_speaker_acquisition](test_slender_speaker_acquisition.gd) | 巨人遭遇狀態與正式玩家／RV 抓取 |
| [orientation_departure](test_orientation_departure.gd) | 新版接待室、完整維修交易、真實輪驅出庫、封門與讀檔 |
| [checkpoint_failures](test_checkpoint_failures.gd)、[poi_transition_persistence](test_poi_transition_persistence.gd) | 保存失敗處理與副本轉場所有權；Checkpoint v6 只接受地形生成 v14，檢查當前教學／重試入口及舊版拒絕行為 |
| [streaming_generation](test_streaming_generation.gd) | v6 分幀／碰撞一致性、v13／v14 四種子 12 km 路線與地形契約、v14 道路凍結及獨立外觀域、橋面支撐與導航發布 |
| [main_scene_smoke](main_scene_smoke.gd) | 正式主世界可操作、Esc 設定路由與玩家移動 |

新版教學共用旅程放在 [support/orientation_journey.gd](support/orientation_journey.gd)，只由 departure 執行，避免同一批交易重跑。新增頂層 `test_*.gd` 會自動納入預設及 CI；優先擴充既有核心測試，共用 fixture 放在 `support/`。

2026-10-19 精簡移除 196 支測試，另將 1 個重複入口移至 support；原本 213 個入口剩下 16 個。刪除範圍包含已停用的重複攀車測試、早期模型樣板、外觀／骨架專用驗收、舊版教學與舊世界相容性專測，以及大量長時間情境變體。**這些覆蓋已減少**，不是由核心集完整取代。手動 playground 保留；舊存檔相容程式已移除；過去的驗收紀錄只代表當時範圍。量測與取捨見 [本次紀錄](../docs/validation/2026-10-19-test-ci-simplification.md)。

## 執行與 CI

每支測試使用獨立 Godot 程序，避免 autoload／存檔共享污染。固定 `--fixed-fps 60` 解除實時節流；`-RealTime` 可作實時對照，不改物理 Hz、求解器或 time_scale。

Runner 檢查引擎版本、退出碼、非空日誌、錯誤訊息及 `PASS:`；smoke 必須有 `WORLD_READY_FOR_PLAY`。第一項失敗立即停止。每項期限預設 240 秒，可用 `-TimeoutSeconds` 調整；超時會終止該測試與子程序。每次執行在 `.godot/test-logs/` 建立獨立目錄，保存 `results.json`、選取清單、環境／commit／工作樹資訊、耗時及各項日誌。

不再使用 `-Suite`、`-StartAt`、`-FailFast` 或 `suites.json`。指定篩選若有任一樣式沒有匹配，會在啟動引擎前失敗。`-SmokeOnly` 不可與 `-TestFilter` 併用。

[GitHub Actions](../.github/workflows/tests.yml) 只用一個 Windows job：runner 自測、安裝固定 Godot、匯入與執行核心集。main push、PR 及手動觸發；純 Markdown／docs 修改略過，更新同一分支會取消舊執行。job 上限 10 分鐘，失敗才上傳診斷。移除原本 5 個分組 job、重複下載／匯入及雙 shell 自測。

Headless 不驗證 GPU 畫面、手感、極端翻車或群怪；必要時依 [測試場指南](../docs/guides/playgrounds.md) 做相關人工驗收。
