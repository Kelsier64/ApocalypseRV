# Esc 設定選單與視訊效果驗收

日期：2026-10-03。環境：Windows、Godot 4.7.2、NVIDIA RTX 5070 Ti；Forward+／Vulkan 1.4.341 及 Compatibility／OpenGL 3.3（驅動 610.62）。本紀錄只列本輪執行結果，沒有宣告 full suite 通過。

## 完成內容

- Esc 開啟四頁設定、釋放滑鼠；Esc 或返回遊戲關閉，世界保持運行。入座及室內使用相同入口。
- 視訊包含視窗確認、垂直同步、幀率、畫質預設、解析度、抗鋸齒、陰影、霧、復古色調及色彩；另有靈敏度、反轉、步行／駕駛 FOV、主音量與分組按鍵說明。
- 正式 F8 接收與現行切換提示移除。解析度與色調獨立；GameSettings 成為 `display_preferences.cfg` 唯一寫入者，支援舊偏好、合併保存、錯誤重試與逐頁重設。
- 輸入遮罩保留重力、支撐、傷害與載具模擬，駕駛操作依既有曲線釋放。關閉後，原本仍按住的操作須放開才可重新使用。
- 室內合成層開設定時提升至 60 並隱藏外層 POI 標題，修正桌面驗收發現的重疊問題。手動畫質修改保留「自訂」來源並保存，即使數值重新等於某個預設。

## Headless 自動檢查

使用同一 runner、固定 60 Hz 模擬與已完成的資產匯入。命令形式為 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 ... -SkipImport -FailFast`。每次結果均由 runner 檢查程序退出碼、錯誤日誌及 PASS 標記。

| 執行 | 結果 | 秒 | `.godot/test-logs/` 目錄 |
|---|---:|---:|---|
| `-Suite quick` | 18/18 PASS | 23.596 | `20261003-075032-049-quick-32288` |
| 相關玩家／RV／POI／天氣／外觀及 `-Smoke` | 12/12 PASS | 117.752 | `20261003-013733-185-selected-29928` |
| 攀爬動畫、抓咬釋放、上下車、煞車、檢查點 | 5/5 PASS | 30.324 | `20261003-072359-098-selected-32256` |
| 室內合成修正後：設定、POI 保存、選單及 smoke | 4/4 PASS | 20.074 | `20261003-074656-215-selected-28600` |
| 自訂來源保存修正後：設定及選單 | 2/2 PASS | 3.170 | `20261003-075221-261-selected-32092` |

相關批次選取：`test_forest_fog`、`test_interior_compatibility`、`test_moving_rv_climbing`、`test_outdoor_horror`、`test_player_death`、`test_poi_instances`、`test_poi_transition_persistence`、`test_raker_grab`、`test_rv_cockpit`、`test_rv_physics_regression`、`test_world_weather`。補充批次：`test_player_climb_animation`、`test_raker_release_input`、`test_rv_boarding`、`test_rv_braking`、`test_rv_checkpoint`。新測試已登錄 [suites.json](../../tests/suites.json)。

[test_game_settings.gd](../../tests/test_game_settings.gd) 覆蓋缺漏／非法欄位、舊 retro 偏好遷移、預設只修改品質、自訂來源保存、分類重設、0.3 秒合併保存、保存錯誤與重試、全螢幕取消／逾時／確認、主及室內 viewport、原有 atlas 恢復，以及濃霧與 Compatibility 降級。

[test_settings_menu.gd](../../tests/test_settings_menu.gd) 覆蓋事件及逐幀輸入、GUI 焦點、按鍵釋放鎖、真實碰撞下落、時間與傷害持續、相機設定、F8 無效、駕駛滑行與油耗、轉彎車頂跟隨、平板／放置 Esc 優先權、抓咬／死亡關閉、轉場以及室內 M 地圖封鎖／恢復。

最後 headless editor 匯入完成，`.godot/settings-final-import.log` 無 script error；`git diff --check` 通過。

## 原生 GPU／視窗自動檢查

執行 [validate_settings_display.gd](../../scripts/validate_settings_display.gd)，以真實 Windows viewport 擷取影像及像素，不使用 headless 替代渲染。Forward+ 最後結果在 `settings-display/native-final.log`，Compatibility 在 `settings-display/compatibility.log`，兩者均 PASS。

- 1280×720 選單矩形為 `(120,35,1040,650)`，全部位於視窗內；額外 1024×600 檢查也通過捲動與裁切布局。
- 3D 飽和度調整使彩色物件變灰，Canvas 色塊保持原色。室內先處理後合成到主 viewport，像素相同，證明沒有重複調色。
- 真實視窗模式、取消、確認及尺寸／位置恢復通過。自動逾時使用 0.4 秒期限，另驗證正式 15 秒預設；完整 15 秒等待由下方桌面觀察補足。
- Master bus 的增益與 0 音量 mute 狀態通過；這項檢查沒有宣告聽到實際音效。
- Compatibility 原生渲染通過，停用不支援的控制並顯示原因。

目前證據位於 `.godot/test-logs/settings-display/evidence.json`，PNG 包含 `menu-1280x720.png`、`menu-1024x600.png`、`outdoor-baseline.png`、`outdoor-graded.png`、`indoor-graded.png`、`indoor-composited-on-root.png`。同名影像由最後一次原生執行更新；兩種 renderer 的日誌分開保留。

## 桌面操作與觀察

使用安裝的 computer-use skill，先列出視窗，再選取本輪遊戲視窗；沒有操作或關閉原本的 Godot editor。每次操作後刷新桌面畫面。

- 正式主世界 1280×720：Esc 開關、四頁、滑動、畫質下拉、逐頁恢復、鍵盤 Tab／方向鍵、退出確認均可操作；低解析 3D 下 HUD 與選單仍清晰。
- 飽和度 0 時世界變灰，生命紅色及選單琥珀色維持原色。F8 不改畫面，偏好檔時間戳與大小也未改變。
- 全螢幕確認倒數顯示正常，等待正式 15 秒逾時後還原原本視窗尺寸及位置。退出確認的焦點限制於取消／退出，確認後只關閉測試遊戲。
- 主世界開場處於既有整備區時間規則下，因此不把該處畫面作為時鐘前進的人工證據；設備耐久在選單開著時仍下降。時鐘持續由上方自動情境驗證。
- RV 輪驅展示：F5 入座後可開設定，狀態列顯示生命及約 14 km/h；選單期間 B 無法改引擎，車輛繼續滑行至約 2 km/h。關閉後仍入座、引擎開啟、維持原檔位；油量及充電繼續更新。日誌：`.godot/settings-rv-native.log`。
- 攀爬重播：兩個角色爬上轉彎 RV；使用既有 `--seat-after-climb --climb-debug` 模式維持玩家入座後，觀察車頂 HP 下降至 DESTROYED、怪物掉落。日誌：`.godot/climb-playground.log`、`.godot/climb-playground-seated.log`。
- 室內小型 fixture 採用正式 PoiInstanceManager、own World3D 與 SubViewport，Esc 開關及高畫質下拉即時生效；設定開著時外層標題不再重疊，關閉後恢復。日誌：`settings-display/manual-interior-final.log`，另有 `manual-interior-ready.png` 與 `manual-interior-evidence.json`。實際 M 地圖使用正式元件在 headless 測試驗證。
- 主音量滑桿可調至 0 並恢復 100%；未進行人工聽音判斷。所有本輪測試遊戲視窗已關閉。

人工測試前備份原始顯示偏好，結束後還原並核對雜湊相同。設定腳本使用隔離檔；沒有改寫使用者遊戲檢查點。備份及人工測試偏好僅留在忽略的 `.godot/`。

## 覆蓋限制

室內桌面驗收使用小型 fixture，完整程序地堡生成及保存由相關自動測試覆蓋；沒有宣告本輪走遍所有室內房間。攀爬重播的車體運動由腳本驅動，不能代替輪驅操控、翻車或大量敵人壓力測試；輪驅滑行另有上述 RV 桌面觀察及物理回歸。音量證據為 bus 狀態與 GUI，不含聽音驗收。這些限制不混寫成已觀察結果。
