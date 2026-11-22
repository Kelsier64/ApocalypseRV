# 自動測試

從專案根目錄執行 [scripts/test.ps1](../scripts/test.ps1)。預設跑全部 **根層 `test_*.gd` 核心測試 + 正式主世界 smoke**，匯入只做一次。Godot 版本由 [.godot-version](../.godot-version) 固定。

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
# 全部跑完再一次列出所有失敗（CI 使用）
./scripts/test.ps1 -KeepGoing
# runner 自我測試，不需要 Godot
./scripts/test-runner.tests.ps1
```

可用 `-Godot 'C:/Program Files/godot/godot.exe'` 指定引擎。Windows PowerShell 5.1 與 PowerShell Core 均可執行；CI 使用 Core。

## 保留範圍

| 核心測試 | 主要目的 |
|---|---|
| [item_player](test_item_player.gd)、[item_persistence](test_item_persistence.gd) | 正式玩家拾取／放置、物品 ID／所有權及保存 |
| [body_recovery](test_body_recovery.gd) | 製造復活、地下設施遺體、佇列、缺料與停工取消 |
| [rv_resource_cycle](test_rv_resource_cycle.gd)、[rv_engine](test_rv_engine.gd) | 回收、製造、燃料、維修、能源、引擎及車載作弊／時間／天氣指令 |
| [promo_world](test_promo_world.gd) | 錄影擺場、錄影面板暫停、自由鏡頭與跟拍的操作權、跟拍不隨目標翻滾、運鏡曲線等速且不倒退、路徑存讀、遭遇、設備與重錄。預設檢查代表鏡頭，完整逐鏡參數見[錄影指南](../docs/guides/promo-capture.md) |
| [rv_structure_modules](test_rv_structure_modules.gd)、[rv_braking](test_rv_braking.gd) | 車體結構／支撐與真實輪胎煞車 |
| [rv_handling](test_rv_handling.gd)、[rv_rollover](test_rv_rollover.gd) | 合成輪胎力、柏油滑移、側坡翻車、屋頂車損與倒置離座 |
| [rv_audio](test_rv_audio.gd) | 音效事件、Sfx 聲源池、冷卻與 POI 世界、亂數隔離、雙向車殼隔音、巴士直六的轉速與負載混音、換檔過程、手煞車與碰撞分層錄音、路噪、怪物腳步表對上步態著地點、玩家腳步的地板分類與步伐、零星環境聲的挑選、間隔與距離、室內聲與嗡聲 |
| [rv_crash_injury](test_rv_crash_injury.gd)、[recovery_jack](test_recovery_jack.gd) | 乘員傷害、事件去重、固定種子斷肢、倒置快照與千斤頂兩段救援 |
| [moving_rv_climbing](test_moving_rv_climbing.gd) | 玩家與 Raker 的移動 RV 攀爬 |
| [pistol](test_pistol.gd)、[raker_grab](test_raker_grab.gd)、[barrel_explosion](test_barrel_explosion.gd) | 武器、抓取所有權及爆炸傷害；Raker 與油桶人何時出聲 |
| [slender_speaker_encounter](test_slender_speaker_encounter.gd)、[slender_speaker_acquisition](test_slender_speaker_acquisition.gd) | 巨人遭遇狀態（含脫離冷卻）、正式玩家／RV 抓取，以及活性情境：巡邏點走不到、目標看得見卻走不到（[夾具](support/slender_speaker_liveness.gd)） |
| [white_apparition](test_white_apparition.gd) | 白影在畫面外現身與換位、追擊與致死接觸、障礙阻擋、依距離扣 SAN、遮蔽與離開視野消失；白影與黑影何時出聲 |
| [orientation_departure](test_orientation_departure.gd) | 新版接待室、完整維修交易、真實輪驅出庫、封門與讀檔 |
| [checkpoint_failures](test_checkpoint_failures.gd)、[poi_transition_persistence](test_poi_transition_persistence.gd) | 保存失敗處理與副本轉場所有權；檢查點只接受當前世界生成（`WorldProfile.CURRENT_GENERATION`），檢查當前教學／重試入口及舊生成版本拒絕行為；巨型避難所固定 seed／面積布局、profile 分流、真實進出、補給箱與丟物回訪不補貨，以及完整檢查點磁碟往返 |
| [streaming_generation](test_streaming_generation.gd) | 當前分幀／碰撞一致性、四種子 12 km 路線與地形契約、急彎及持續升降、固定道路指紋與獨立外觀域、全路寬河橋支撐、山頂跨區塊普通／巨人導航；霧外觀設定、載入視野保護及自然天氣 RNG／保存隔離 |
| [world_contracts](test_world_contracts.gd) | v14 地形、世界細節、野外場址、建物定位、[建築 kit](support/building_kit_contracts.gd)（參考建築無懸空零件、開口檢查、碰撞一致、玩家可穿門與上樓梯）與巨型避難所外殼的取樣契約；從 streaming_generation 拆出，讓兩者各自留在逐測試時限內 |
| [main_scene_smoke](main_scene_smoke.gd) | 正式主世界可操作、教學凍結期間視野恢復且時間／天氣不前進、Esc 設定路由與玩家移動 |

世界細節契約放在 [support/world_detail_contracts.gd](support/world_detail_contracts.gd)，由 world_contracts 執行：特徵格與規劃順序無關、池塘／支線／地塊留在所屬格與帶內並避開 POI 與路肩、地表帶有水位／支線路床／保留區，道路設施與串流順序無關，散佈圖層目錄合法，以及一個真實帶的散佈規劃一致、實體散佈避開水／場址／路肩／接縫、可撞倒物件只碰 RV 並寫入破壞帳本。

巨型避難所室內契約放在 [support/megashelter_interior_contracts.gd](support/megashelter_interior_contracts.gd)，由轉場測試執行；外殼入口、相同碰撞及串流導航仍由 world_contracts 的 [support/megashelter_contracts.gd](support/megashelter_contracts.gd) 檢查。

新版教學共用旅程放在 [support/orientation_journey.gd](support/orientation_journey.gd)，只由 departure 執行，避免同一批交易重跑。新增頂層 `test_*.gd` 會自動納入預設及 CI；優先擴充既有核心測試，共用 fixture 放在 `support/`。

2026-10-19 精簡移除 196 支測試，另將 1 個重複入口移至 support；原本 213 個入口剩下 16 個。刪除範圍包含已停用的重複攀車測試、早期模型樣板、外觀／骨架專用驗收、舊版教學與舊世界相容性專測，以及大量長時間情境變體。**這些覆蓋已減少**，不是由核心集完整取代。手動 playground 保留；舊存檔相容程式已移除；過去的驗收紀錄只代表當時範圍。

## 執行與 CI

每支測試使用獨立 Godot 程序，避免 autoload／存檔共享污染。固定 `--fixed-fps 60` 解除實時節流；`-RealTime` 可作實時對照，不改物理 Hz、求解器或 time_scale。

Runner 檢查引擎版本、退出碼、非空日誌、錯誤訊息及 `PASS:`；smoke 必須有 `WORLD_READY_FOR_PLAY`。預設第一項失敗立即停止；`-KeepGoing` 會跑完全部再列出所有失敗，但匯入失敗或無法終止逾時子程序時仍立即停止。每項期限預設 240 秒，可用 `-TimeoutSeconds` 調整（CI 較慢，使用 480 秒）；超時會終止該測試與子程序。每次執行在 `.godot/test-logs/` 建立獨立目錄，保存 `results.json`、選取清單、環境／commit／工作樹資訊、耗時及各項日誌。

不再使用 `-Suite`、`-StartAt`、`-FailFast` 或 `suites.json`。指定篩選若有任一樣式沒有匹配，會在啟動引擎前失敗。`-SmokeOnly` 不可與 `-TestFilter` 併用。

[GitHub Actions](../.github/workflows/tests.yml) 只用一個 Windows job：runner 自測、安裝固定 Godot、匯入並以 `-KeepGoing -TimeoutSeconds 480` 執行核心集。main push、PR 及手動觸發；純 Markdown／docs 修改略過，更新同一分支會取消舊執行。job 上限 20 分鐘，失敗才上傳診斷。

Headless 不驗證 GPU 畫面、手感、極端翻車或群怪；必要時依 [測試場指南](../docs/guides/playgrounds.md) 做相關人工驗收。手動測試場放在 `tests/playgrounds/`，不會被 runner 選取。
