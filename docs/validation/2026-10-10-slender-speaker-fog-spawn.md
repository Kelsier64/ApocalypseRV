# Slender Speaker 正式世界霧天生成（2026-10-10）

## 本次變更

正式 `main_world.tscn` 原本已選用 v10，包含森林候選、獨立巨人導航、WorldEntities 與 v5 checkpoint。本次在唯一生成入口 `WorldGenerator._spawn_giant_segments()` 加入天氣限制，沿用現有正式場景與模型。

- 只讀所屬世界的 `WorldClock.weather.sample().z`，達 `WorldWeather.FOG_LIGHT`（0.5）才允許生成。小霧、中霧、大霧都符合；晴天、無霧陰天、單純下雨不符合。缺少時鐘時不生成。
- 依過渡中的實際霧量，不只看天氣目標。渲染品質、常駐遠景霧與林間 FogVolume 不決定生成。
- 天氣判斷位於區段記錄提交之後；無霧略過的區段在起霧、導航重建、回程或讀檔後都不補刷。
- 霧散後不刪除已有巨人，原有遠距清理仍適用；已有巨人可在無霧存檔中正常還原。無新增存檔欄位，不升級舊生成版本。
- 保留前 1,500 m 安全區、每 1,500 m 獨立 25% 候選、道路外 40–100 m 森林、距玩家至少 160 m、導航就緒及同世界最多一隻。

## 驗證

執行 `scripts/test.ps1 -Godot 'C:/Users/evan4/AppData/Local/Programs/Godot/Godot_console.exe' -Suite full`。Godot 4.7.2，固定 60 FPS；本輪約 1,179 秒。153 項回歸（含主場景）中 151 PASS、2 FAIL，另資產匯入 PASS；結果檔共 154 筆，152 PASS／2 FAIL。整體 runner 退出碼 1，不能報為完整通過。

新增 quick `test_slender_speaker_fog_spawn` PASS；擴充 integration `test_slender_speaker_world` PASS，涵蓋真實森林生成、無霧略過、起霧不補刷、實際 checkpoint 還原與區塊回訪。`test_slender_speaker_spawns`、`test_world_weather`、`test_world_clock`、正式主場景啟動均 PASS。完整拆頂抬升、跨艙伸手、輪驅追車、設備阻擋、底盤傷害、玩家死亡／斷肢與 Raker 抓咬回歸亦 PASS。

日誌目錄：`.godot/test-logs/20261010-132931-357-full-28996/`。[完整結果](images/slender-speaker-fog-spawn/results.json) · [霧門檻](images/slender-speaker-fog-spawn/fog-gate-test.log) · [正式世界保存／回訪](images/slender-speaker-fog-spawn/test_slender_speaker_world.log) · [主場景啟動](images/slender-speaker-fog-spawn/main-scene.log)。本次新增測試已登錄 `tests/suites.json`；相關檔案 `git diff --check` 通過。

### 本輪發現的既有行為失敗

這兩個 fixture 直接建立巨人與 RV，沒有 `WorldGenerator` 或 `WorldClock`，不經過此次修改的生成入口。本輪未修改它們的 AI、斷言或時間限制；不能將完整套件報為全綠。[車內移動失敗日誌](images/slender-speaker-fog-spawn/cabin-movement-failure.log) · [右後角失敗日誌](images/slender-speaker-fog-spawn/corners-failure.log)。

- `test_slender_speaker_cabin_movement`：前後／橫向連續移動均未出手抓取，遮擋案例亦未到達可抓狀態。日誌中拆頂後只剩 340 個移動 tick，少於規定的 480 tick，且沒有進入靜止恢復時段；這顯示 40 秒總預算不足以完整執行測試，尚不能據此排除其他 AI 問題。
- `test_slender_speaker_playground_corners`：RIGHT_REAR、RIGHT_REAR_WALK 在 60 秒內遮蔽屋頂仍完整，可見玩家與抓取次數皆為 0，未到達 HOLD。其餘三個角落到達 HOLD。右後走動依賴先拆頂，因此也未執行；日誌不足以確定屋頂選擇或手部接觸的根因，不能單純歸因於時間預算。

上述兩項失敗已在同日後續工作修正：右後角使用屋頂轉向的進入／退出緩衝，車內移動分開自主拆頂與移動／恢復測試期限。原失敗日誌保留當時結果，後續重現、修改及重跑見[車內移動及右後角修正](2026-10-10-slender-speaker-cabin-corner-fix.md)。本文件的完整套件 151 PASS／2 FAIL 仍是霧天生成當時那一輪的結果。

## 原生觀察

Forward+ 原生視窗使用正式世界、seed 42、實際候選與導航，載入生成區段及相鄰森林。觀察程式只控制區塊載入、天氣、玩家觀察錨點及鏡頭；巨人由正式生成入口建立，未直接放置巨人或改變候選機率。不是從起始車庫一路自然駕駛至遭遇的紀錄。

- 區段 11／band 114：無霧，提交區段後巨人數量為 0；立刻改大霧仍是 0。
- 區段 16／band 168：小霧，成功於 `(-23.79563, -9.108641, -25344.21)` 生成 1 隻。
- 切換大霧：原生畫面中同一巨人與遠景被霧遮蔽；再轉無霧，原有巨人數量仍是 1。
- 透過 computer-use 查看原生視窗，巨人持續在森林巡遊。已關閉本次驗證視窗；沒有操作使用者原本的 Runtime 或 Godot 編輯器。
- 最終原生日誌無 script error。此次沒有重做真實輪驅追車或長時間效能量測；本次修改只限制新生成，不更動追擊／攻擊控制器。

[小霧](images/slender-speaker-fog-spawn/light-fog.png) · [大霧](images/slender-speaker-fog-spawn/heavy-fog.png) · [霧散](images/slender-speaker-fog-spawn/fog-cleared.png) · [原生日誌](images/slender-speaker-fog-spawn/native.log) · [觀察程式](images/slender-speaker-fog-spawn/capture-source.gd.txt)
