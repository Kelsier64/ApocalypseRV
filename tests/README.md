# 自動測試

從專案根目錄執行 [scripts/test.ps1](../scripts/test.ps1)。Godot 版本由 [.godot-version](../.godot-version) 固定。

```powershell
# 日常行為檢查，預設 quick
./scripts/test.ps1
# 不啟動引擎，列出選取範圍
./scripts/test.ps1 -Suite full -List
# 全部有效回歸及正式主世界啟動
./scripts/test.ps1 -Suite full
# 僅選相關測試；若需要主世界就緒檢查，加 -Smoke
./scripts/test.ps1 -TestFilter 'test_bunker_*.gd,test_interior_*.gd'
# 同一批程式修改的後續執行，資產未變且已匯入時可省略匯入
./scripts/test.ps1 -TestFilter test_player_inventory.gd -SkipImport
# 只驗證正式世界地形、導航、玩家就緒與移動
./scripts/test.ps1 -Suite smoke
# 不需 Godot 的 runner 自我測試
./scripts/test-runner.tests.ps1
```

## 分組與覆蓋

Item 統一流程新增 `test_item_player.gd`（quick）：正式玩家驗證背包／手臂拒收不拆支撐、F 長按拾取與短按抑制、獨立預覽、取消／G、確認後消耗、角色重疊及失效支撐鏈拒絕、拆牆掉落後重新拾取，以及新物品／空油桶的完整狀態與 ID 保存。目前預覽操作會暫時隱藏手持模型，物品保留在背包，取消後恢復顯示；觀察與測試須分別檢查顯示和所有權。`test_item_services.gd` 覆蓋共用物品、服務／回收與怪物免傷；`test_item_persistence.gd`（integration）覆蓋 v5 與跨領域狀態；`test_item_navigation.gd`（integration）以實際怪物碰撞驗證多件固定 Item 的繞行、移除後恢復直路，以及封閉障礙無路時等待。實機入口 `item_playground.tscn` 見 [Item 測試場](../docs/guides/playgrounds.md#unified-item)。完整套件、smoke 與實機結果見 [本輪驗證紀錄](../docs/validation/2026-10-06-unified-items.md)，各階段結果保留當時的顯示行為。

車體改版由 `test_rv_structure_modules`、`test_structure_construction`、`test_rv_structure_snapshot` 與既有車輛、支撐、登車及存檔測試共同覆蓋。平板滑鼠操作與拆穿地板的原生觀察見 [2026-10-05 驗證紀錄](../docs/validation/2026-10-05-rv-structure-construction.md)；互動場景為 `rv_structure_playground.tscn`，操作見 [測試場指南](../docs/guides/playgrounds.md)。

[suites.json](suites.json) 是完整清單，每支頂層 `test_*.gd` 必須恰好分類一次。新增測試、遺漏分類、重複分類或不存在的檔案都會讓 runner 在引擎啟動前失敗。

| 分組 | 範圍 |
|---|---|
| `quick` | 隔離的背包、耐力、互動、攀爬契約、能源／資源交易、起始場址等行為 |
| `integration` | 有限情境的物理、導航、設備、POI 轉場、保存與世界重建 |
| `slow` | 多 seed 掃描、完整步行路線、反覆重建、長時間車輛情境 |
| `assets` | 匯入、蒙皮、骨架姿勢、外觀與資產規範驗收 |
| `smoke` | [main_scene_smoke.gd](main_scene_smoke.gd) 的正式世界就緒與移動 |
| `full` | 所有有效分組及 smoke；排除有原因記錄的重複項 |

`test_raker_boarding` 與 `test_moving_rv_climbing` 的預設 Raker 情境完全相同，因此清單記錄為 retired，保留檔案供舊命令直接執行，也可明確以 `-TestFilter` 選取。舊 v2–v6 地形與 legacy 世界 fixture 仍保留回歸；其保存改用 v5 檢查點，不代表接受舊版檢查點。`test_main_world_monsters` 的名稱保留，但其內容明確標示 legacy v5 fixture。正式 v8 主世界由 smoke 與 starting 系列涵蓋。

每支測試仍使用獨立 Godot 程序。本機不平行跑會共享磁碟 checkpoint 或全域服務的測試。GitHub Actions 以五個獨立 job 跑 quick、integration、slow、assets、smoke，涵蓋與 full 相同的有效測試；一組失敗不取消其他組。

## 執行與診斷

Runner 核對引擎版本，先匯入一次，再用 `--fixed-fps 60` 執行 headless 測試。這會解除實時等待並保持固定模擬步長；不縮短物理情境、減少 seed、調高物理 Hz 或改 `Engine.time_scale`。`-RealTime` 停用此選項，適合對照實時排程。資產匯入本身不使用加速。

每個程序都檢查退出碼、非空日誌、錯誤訊息與 `PASS:`；smoke 必須有 `WORLD_READY_FOR_PLAY` 標記。預設逐支跑完以收集所有失敗，最後以非零狀態結束；`-FailFast` 可在第一個失敗後停止。匯入失敗則立即停止後續測試。

`-TimeoutSeconds` 是每個程序的上限，預設 240 秒。超時會終止該測試與其子程序並記錄 `TIMEOUT`；若子程序清理失敗，停止後續測試並保留原因，避免殘留程序污染下一項。`-StartAt test_name` 從選取清單中的指定名稱接續；它不代表前面的測試已通過。`-TestFilter` 覆蓋分組，逗號分隔的樣式會合併、去重、按名稱排序；每個樣式均須選到測試。`-Suite full -TestFilter ...` 也只跑符合樣式的測試，需要 smoke 時明確加 `-Smoke`。

每次執行建立 `.godot/test-logs/<時間>-<分組>-<PID>/`，包含環境與工作樹清單 `manifest.txt`、結果及錯誤原因 `results.json`、耗時 `timings.csv` 與各支日誌，並在終端列出最慢五項。選取清單與實際結果分開記錄，可看出 FailFast 後未執行項目。資產測試的 JSON 證據位於 `.godot/test-logs/player_import_v020/`、`player_animation_skin/`、`player_ragdoll_v020/`，供最新一次檢查使用，不覆寫 `docs/validation/` 的歷史紀錄。

## 維護

優先驗證可觀察行為與公共契約。固定舊版三角形數、節點總數、某個歷史 helper 必須不存在等斷言，只有在它仍代表目前契約時才保留。資產來源與數值驗收留在 assets；相容性要求保留明確版本與 fixture。

等待非同步導航、生成或候選世界回收時，使用 [support/test_wait.gd](support/test_wait.gd) 的條件與期限，失敗要說明未就緒的工作。真實移動、穩定性、耗電或傷害情境仍保留原本模擬時段；不要把有意義的物理採樣全部改成「成功就提早停止」。純資料檢查不要建立完整主世界。

Headless 與實機觀察分開記錄；車輛或攀爬行為變更仍遵循 [AGENTS.md](../AGENTS.md) 的互動驗收要求。歷次結果見 [文件索引](../docs/README.md)，本輪改版與耗時見 [2026-10-01 驗證紀錄](../docs/validation/2026-10-01-test-runner.md)。

## 設定與原生顯示驗證

`test_game_settings.gd` 屬 quick，驗證偏好遷移、範圍、畫質預設、viewport 套用與保存；`test_settings_menu.gd` 屬 integration，驗證真實輸入、持續物理、傷害、入座、攀爬支撐及室內路由。

GPU 後製與視窗尺寸另用有期限的原生驗證腳本，不列入 headless suites。腳本使用隔離偏好檔，結束時恢復視窗與設定；輸出放在 `.godot/test-logs/settings-display/`。

```powershell
godot --path . --resolution 1280x720 --log-file .godot/test-logs/settings-display/native.log --script res://scripts/validate_settings_display.gd
godot --path . --resolution 1280x720 --rendering-method gl_compatibility --log-file .godot/test-logs/settings-display/compatibility.log --script res://scripts/validate_settings_display.gd
```

加上 `-- --manual-interior` 可開啟採用正式 PoiInstanceManager 的小型室內 fixture，提供 180 秒手動 Esc／GUI 驗收。此模式不宣告自動檢查通過；自動 GPU 證據、桌面操作與未驗證情境分別見 [設定選單驗收](../docs/validation/2026-10-03-settings-menu.md)。


## 大型物品與攀爬

`test_player_climbing.gd` 與 `test_player_inventory.gd`（quick）覆蓋 active_item.is_large、空手／小物、移除後恢復及玩家拒絕車壁的 gate。`test_player_large_item_climbing.gd`（integration）使用正式玩家與 RV，覆蓋 HUD 不重刷、世界拾取／倉庫取出時安全脫離、消耗／存入／丟棄後恢復、拒收不影響既有攀爬、物品 ID／狀態與平台速度交接。

```powershell
./scripts/test.ps1 -TestFilter 'test_player_climbing.gd,test_player_inventory.gd,test_player_large_item_climbing.gd,test_moving_rv_climbing.gd,test_player_carry.gd,test_rv_shared_storage.gd' -Smoke
```

2026-10-04 `855a17e` 的相關 quick／integration 回歸及正式世界 smoke 已在 CI 通過；整體 CI 仍有既存失敗與戶外測試不一致，不能宣稱 full suite 通過。上述命令可供重跑，完整證據見 [本輪紀錄](../docs/validation/2026-10-04-issues-8-17.md)。2026-10-04 該輪沒有本機引擎執行或原生視窗／實機觀察。實機需依 AGENTS 驗證持大型物品貼牆 W 的提示節制、丟棄／存入後攀爬恢復，以及移動／轉彎車身上拾取大型物品時不瞬移且物品仍可丟棄。原有登頂、拆頂與怪物攀爬仍須回歸。

## 可搬移 RV 梯子

`test_rv_ladders.gd`（quick）使用正式側門梯、車內梯及三片屋頂碰撞，覆蓋兩種模式的自由貼牆放置、連續瞄準與 5 cm 細移、地板／天花板／活動門扇拒絕、上下梯、關門阻擋、封住開口、移動車輛、搬移／取消、毀壞、實際牆面支撐失效與 v5 保存。大型物品與動畫測試使用真實梯子，怪物仍沿用車壁。當次執行結果與原生觀察見 [貼牆梯子重做驗收](../docs/validation/2026-10-05-rv-wall-ladders.md)。
