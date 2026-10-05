# 玩家跑步與 Raker 咬擊姿勢修正驗收

日期：2026-10-05。基準提交：`96a1fe37a51560598a064b0c1ac698dde1cd4b26`。Godot 4.7.2 stable（`ed1daf0bf`，Windows）；維持 60 Hz/Jolt 設定，測試 runner 固定 60 fps。

## 問題與修正

基準測試重現三項失敗：`test_player_animation` 的向後慢跑空中相位左腳峰值為 `0.026777368 m`（上限 `0.025 m`）；`test_raker_bite_pose` 固定視角／接觸姿勢檢查失敗；`test_raker_release_input` 在 mode 2 因 `contact_lost`、`blocked:DriverSeat` 失敗。咬擊蹲低肩部後，原本固定向外的手肘路徑會穿過座椅靠背。

玩家布娃娃腳部慣性倍率由 4 調為 6；質量與關節限制不變。Raker 抓取共用有限的手肘避障候選路徑，讓坐姿受害者沿座椅邊緣向上／向外移動；姿勢修改器採用相同碰撞路徑，並在找不到可行手肘路徑時以最多 25° 的鎖骨旋轉避開靠背角落。沒有傳送或骨骼平移。玩家放開時序維持接觸 `0.22 s`、怪物 `RELEASE` `0.35 s`。

另加入姿勢修改完成時的渲染手臂射線取樣、候選路徑全被牆阻擋的案例、掙扎迴圈上限、座椅前置條件，以及動畫記錄中的 `peak_frame`。最新通過行為案例有 9 次取樣。腳部 20 案例修改後峰值為 `0.023322064 m`，最高速度 `9.341959 m/s`。

## 驗證狀態

基準回歸記錄：`.godot/test-logs/20261005-111111-278-selected-12760`，重現上述三項失敗。

修正後篩選回歸分兩次完成：`.godot/test-logs/20261005-112401-169-selected-23480` 通過 11 項生產測試套件；`test_raker_release_input.gd` 另於 `.godot/test-logs/20261005-112543-109-selected-27748` 通過（8.14 秒）。因此 12 項篩選均已覆蓋，但不是單次 12 項執行。放開輸入測試確認負向牆面阻擋與自然咬擊姿勢下 9 次渲染手臂淨空取樣。這些結果不代表完整測試套件或 CI 通過。

原生自動測試 `.godot/test-logs/ci-raker-release-native.log` 使用 Forward+／Vulkan 與 NVIDIA RTX 4060，在實際顯示環境下通過自然咬擊放開、滑鼠水平與垂直視角、移動／駕駛油門、鏡頭恢復後保留輸入，以及牆面阻擋檢查；沒有使用 headless 或固定 FPS。駕駛姿勢手臂淨空取樣 25 次，mode 2 的視角變化為 yaw `-0.17999995`、pitch `-0.05000001`。這是自動化滑鼠輸入測試，並非人工滑鼠操作。

桌面場景觀察另見 `.godot/test-logs/ci-raker-bite-review.log`：測試場暫停於接觸前，切至 F4 外部近景檢查座椅姿勢，恢復後 HUD 顯示 HP 100 降至 50，日誌記錄 `GRAB_RELEASE`／`bitten`。`.godot/climb-playground.log` 的重播除錯記錄顯示玩家與怪物皆完成攀爬，轉彎時怪物仍支撐於車頂；畫面觀察到車頂 `DESTROYED` 後怪物落下。此場景以自動座位旗標安排玩家入座，未觀察到手動 F5 完成。後續 `.godot/test-logs/ci-climb-manual-review.log` 的 F3／F4／R 手動操作發生致命抓取與重複重生，因此不視為完整手動 F5 驗收。上述四份原生紀錄均未見 `SCRIPT ERROR` 或 `ERROR`。未驗收輪驅操控、翻車或人群視覺表現。

最後 5 項測試執行 `.godot/test-logs/20261005-113227-263-selected-5684` 全數通過：屍體 3.81 秒、屍體展示場 2.99 秒、玩家動畫 9.52 秒、Raker 咬擊姿勢 9.00 秒、Raker 放開輸入 7.11 秒，合計 32.49 秒。原先三項失敗案例在此單次執行中一併通過。連同先前分段回歸，本輪共覆蓋 14 個相關測試檔；完整測試套件與 CI 未重跑，不能據此宣稱全套或 CI 通過。

執行命令使用 `scripts/test.ps1 -Godot 'C:/Users/evan4/AppData/Local/Programs/Godot/Godot_console.exe' -SkipImport`，篩選 `test_player_animation.gd`、`test_player_ragdoll_v020.gd`、`test_raker_bite_pose.gd`、`test_raker_release_input.gd`、`test_raker_grab.gd`、`test_raker_grab_vehicle.gd`、`test_raker_attack_alignment.gd`、`test_raker_finger_flexion.gd`、`test_rv_cockpit.gd`、`test_player_dismemberment.gd`、`test_player_death.gd`、`test_moving_rv_climbing.gd`；最後一輪另含 `test_corpse.gd` 與 `test_corpse_playground.gd`。
