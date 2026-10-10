# Slender Speaker v10 整合與 PR 驗證

2026-10-09。正式新局使用生成 v10，沿用 v9 道路規則，新增 15 m 森林巨人；舊存檔保持原生成版本，checkpoint 格式維持 v5。

## 行為與保存

- 音箱朝向的視線感知與實體遮擋；追擊最高 60 km/h，加速度 2.5 m/s²，轉彎減速，接近 RV 時漸減並維持約 4 m 跟車距離。
- 砸擊及收手持續走跑；1.8 秒蓄力、最後 0.5 秒鎖定落點，每擊只摧毀第一片真正接觸的車板，支撐設備依原系統掉落。
- 雙手接觸才取得玩家唯一控制權；舉起路徑受阻便取消。1.4 秒舉起、0.6 秒停留、0.4 秒合攏，沿用斷肢、死亡、屍體及復活；背包身份保持。抓取／處刑期間拒絕保存，移除或世界切換釋放玩家與音樂。
- v10 在前 1500 m 外，每 1500 m 以 25% 機率規劃森林候選；距道路邊緣 40–100 m、距玩家至少 160 m，同世界最多一隻。使用獨立巨人導航 map，失敗及已處理區段由 checkpoint 記錄，回訪不補刷。

## 交付範圍

保留正式模型／六張貼圖、音效、Godot 必要匯入設定與腳本、敵人控制器、世界／玩家整合、七項自動回歸及一個實際行為 playground。建模／音樂生成腳本、Blender 原始檔及備份、早期靜態模型、截圖／影片、過程驗收與純外觀展示場留在本機；這些不是執行本版所需的檔案。

[模型契約](../../assets/models/slender_speaker/README.md) · [測試分組](../../tests/suites.json) · [重播操作](../guides/playgrounds.md#slender-speaker-runtime)

## 本次整理驗證

只含 Git 暫存交付檔案的乾淨副本 `.godot/pr-packaging/checkout/`，使用 Godot 4.7.2 與統一 runner 執行：

```powershell
./scripts/test.ps1 -Godot 'C:/Users/evan4/AppData/Local/Programs/Godot/Godot.exe' -TestFilter 'test_slender_speaker_*.gd,test_road_spawns.gd,test_road_spawns_v9.gd,test_starting_checkpoint.gd,test_road_spawn_checkpoint.gd,test_rv_checkpoint.gd,test_checkpoint_failures.gd,test_raker_grab.gd,test_raker_grab_vehicle.gd,test_player_dismemberment.gd,test_corpse.gd,test_flashlight_grab.gd' -Smoke
```

匯入、18 項回歸與正式 main-scene smoke 全部通過，總耗時 303.91 秒。涵蓋七項巨人測試、道路 v8/v9 相容與保存、起始／RV checkpoint、Raker 抓取、玩家斷肢、屍體與手電筒抓取。森林導航／讀檔回訪測試 134.85 秒、起始 checkpoint 49.52 秒、主場景 17.90 秒。結果在本機 `.godot/pr-packaging/checkout/.godot/test-logs/20261009-134901-151-selected-30732/`，不提交日誌。

首次沙箱匯入因 Godot 使用者設定目錄不可寫而停止，未執行回歸；以正常使用者目錄權限重跑後，匯入與上述檢查全部通過。

核對 79 個交付檔、161 個明確 `res://` 引用及 462 個 Markdown 相對連結；依賴齊全，`res://arbitrary.tscn` 為刻意拒絕任意場景的負向測試。暫存總大小約 46.82 MiB，沒有建模／生成腳本、原始 Blender 檔、截圖、影片或日誌。`git diff --cached --check` 通過。沒有執行本版完整 full suite 或新的桌面實機操作。

## 既有紀錄與限制

本機既有驗收包含原生第一人稱處刑、輪驅追車、砸車與正式森林日夜／霧檢查；原始日誌、截圖及影片留在本機，未作為本次重跑結果。較早 full suite 曾有兩項舊道路測試把 v10 視為未知版本，之後已將未來版本反例改為 v11；該歷史 full 不能當作目前版本全套通過。

本次 PR 整理不重新做桌面實機觀察。手部部分角度仍有指排投影重疊與肩肘稜角；自然長途遇敵、翻車及密集群怪不在本次驗證範圍。
