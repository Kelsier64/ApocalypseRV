# 教學開局全霧修正

2026-10-21，`codex/terrain-overhaul`，基準 `3ae1573`。修正正式新局教學建築完全被霧遮蔽。

開局森林準備會等待 process frames，WorldClock 首次取樣時已完成區帶仍為空，載入保護因此收近至 0.5–1 m。StartRun 的整備階段凍結時鐘與天氣，而原本 WorldClock 只在時鐘運行時更新視覺，造成地景已完成後仍永久保留這個 1 m 上限。

WorldClock 現在於模擬凍結時繼續 `apply_time(delta)`，讓實際相機／已完成地景的視野按既有每真實秒 20 m 恢復；不呼叫時間或天氣推進。仍使用 PROCESS_MODE_INHERIT，因此 SceneTree 真正暫停和停用的讀檔候選世界都停止視覺更新。沒有停用室外霧、改動霧距離設定、室內美術或保存格式。

## 本次驗證

- 原生 Forward+／Vulkan，正式主場景、新局 seed 42、08:00、1280×720、原玩家出生鏡頭。修正前地景完成距離已為 345 m，等待 300 frames 後霧仍是 0.5–1 m，畫面整片灰霧。修正後在 ready 時已有約 11.8–23.6 m 視野，接待室牆面、終端、海報與桌子正常顯示；再等 300 frames 後為 24–73.7 m，持續按真實 delta 恢復。兩次等待期間時鐘與天氣的 capture 完全不變，日誌無腳本錯誤。
- Godot 4.7.2：`test_checkpoint_failures.gd` 24.70 s、`test_streaming_generation.gd` 19.61 s、正式主場景 smoke 8.57 s，全數 PASS、正常退出。命令採 `scripts/test.ps1 -TestFilter 'test_streaming_generation.gd,test_checkpoint_failures.gd' -Smoke -SkipImport`；日誌 `.godot/test-logs/20261021-145746-363-selected-40096/`。
- 新回歸包含凍結模擬時正常 frames 恢復視野、不改時間／天氣、地景缺口即時收近、停用候選世界及真正暫停均不取樣／恢復。主場景 smoke 透過正常 process frames 等待完整的當前天氣／地景上限，保留 Esc 設定與玩家移動檢查。

實際畫面及工具位於 gitignored `.godot/tutorial-fog-review/`，入口 `gallery.md`。本輪未操作完整教學離場或長途輪驅；原有 `project.godot` 修改保留並排除提交。完成此修正後停止供檢查。
