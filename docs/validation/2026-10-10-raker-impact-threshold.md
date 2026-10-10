# Raker 車撞倒地門檻調整

存活 Raker 的相對法向接近速度門檻由 6 提高至 9 m/s（32.4 km/h），以 `vehicle_knockdown_min_approach_speed` 調整。低於門檻的有效撞擊維持 0.55 秒擊退；致命撞擊仍進入死亡布娃娃。相對速度包含 Raker 自己的迎面速度，並非單看車速；傷害、冷卻及攀車共用判定沿用既有行為。

## 本輪自動檢查

Godot 4.7.2，使用 `scripts/test.ps1 -Godot <本機 Godot> -TestFilter ...`。

- `test_monster_navigation`、`test_vehicle_impact` 通過；日誌 `.godot/test-logs/20261010-201345-318-selected-38144/`。該次 Raker 測試未通過：舊強撞 fixture 實際接近速度約 8.98 m/s，低於新門檻。
- 強撞 fixture 改用目標 12 m/s 與較長加速距離後，`test_raker_ragdoll -SkipImport` 通過，26.98 秒；日誌 `.godot/test-logs/20261010-201444-505-selected-49500/`。正式行為程式未在這兩次執行之間改動。
- 直接接觸涵蓋慢車 3 m/s 與迎面跑動 3.4 m/s 合成 6.4、8.99／9.0 邊界，以及低速致命撞擊；驗證傷害與通知次數。
- 五個真實輪驅案例：正面／偏側強撞約 10.86 m/s 法向接近速度，倒地後起身；致命撞擊保持死亡布娃娃；低速約 3.75、中速約 7.42 m/s 全程未請求布娃娃。保留關節、復原、重複接觸、支撐例外與保存回歸。

## 本輪原生畫面

使用 computer-use 選取測試視窗，逐次操作並刷新畫面。

- `raker_impact_playground --case=4 --review`：實際撞擊車速約 26.65 km/h，HP 103，記錄 `ragdoll=false`；觀察保持站姿的擊退。
- `--case=0 --review`：實際撞擊車速約 38.86 km/h，HP 86，記錄 `ragdoll=true`；繼續回放後觀察倒地，隨後恢復站立。
- 原生日誌保存在 `.godot/raker-threshold-visual.log`、`.godot/raker-threshold-high-visual.log`，未見腳本錯誤。
- `rv_climb_playground --replay --climb-debug`：玩家與 Raker 攀上車頂，持續轉彎時保持車上支撐；按 F5 入座後觀察屋頂 `DESTROYED (1/3)`，Raker 從車頂落至底盤支撐。日誌 `.godot/raker-threshold-climb-visual.log` 未見腳本錯誤；該回放以腳本移動車身，不作為輪驅操控證據。

本輪未跑 full suite；上述撞擊畫面使用正式輪驅與靜止 Raker 目標，迎面跑動組合由直接相對接觸測試覆蓋。翻車、群體碰撞與所有場地未在本輪驗收。
