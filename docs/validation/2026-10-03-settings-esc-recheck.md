# Esc 無反應回報重測

日期：2026-10-03。接續 [設定選單驗收](2026-10-03-settings-menu.md)，保留前次結果。本輪使用者回報「按 Esc 沒反應」；當時已停止遊戲，桌面只有原本的 Godot editor，因此不能直接判定當次執行狀態或原因。

## 程式檢查

正式玩家場景有 SettingsMenu 子節點，Esc 使用內建 `ui_cancel`。入口會在初始 `play_ready=false`、Checkpoint 載入、POI 轉場、死亡或被抓時拒絕；平板／儲物 UI 與放置操作有第一個 Esc 的優先權。沒有發現一般遊戲狀態的其他 Esc 攔截器。

先前隔離選單測試以普通 Node3D 作為根，不含正式世界的 `play_ready`，原本 smoke 只驗證就緒與移動。這是本輪補上的覆蓋缺口，沒有把推測原因當成已確認故障。

## 自動檢查

[main_scene_smoke.gd](../../tests/main_scene_smoke.gd) 現在由真實 Esc 事件驗證：載入完成前拒絕、完成後選單顯示且取得焦點、不暫停、再次 Esc 關閉，以及關閉後玩家能移動。偏好保存路徑隔離在 `.godot/test-logs/main-smoke/preferences.cfg`，程序結束前還原原服務狀態。

執行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Suite smoke -SkipImport -FailFast`，結果 1/1 PASS，耗時 14.88 秒。日誌：`.godot/test-logs/20261003-144404-078-smoke-31976/`；PASS 標記包含 `WORLD_READY_FOR_PLAY, production Escape settings routing and player movement`。`git diff --check` 通過。

## 桌面觀察

以 `godot --path . --log-file .godot/settings-esc-repro.log` 啟動正式主遊戲，沿用專案視窗尺寸。在新遊戲視窗觀察到整備區、玩家 HP 100，再送一次 Esc：設定出現、返回按鈕取得焦點，背景設備耐久繼續下降。本輪沒有重現無反應。日誌無 script error。

只關閉本輪新啟動的遊戲視窗，保留原本的 Godot editor。另清除日夜測試場仍殘留的 `F8 resolution` 說明，改為 `Esc settings`；不改該測試場的時間控制。

## 尚未確認

使用者當次是 F5 主遊戲、F6 當前測試場，或其他執行視窗，以及按鍵時是否載入完成，仍待提供。不能將新啟動遊戲通過寫成已解決原回報，也不能斷言是編輯器攔截或舊程序。
