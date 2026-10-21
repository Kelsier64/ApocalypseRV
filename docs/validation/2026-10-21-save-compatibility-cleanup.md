# 2026-10-21 舊存檔支援清理

依使用者要求移除舊存檔相容與遷移。現在只接受 Checkpoint／VehicleSnapshot v6、生成 v14、OrientationController v4、OrientationWorkshop v3 與完整終端 v2 狀態。新檢查點路徑為 `user://rv_checkpoint_v6.save`；不掃描舊路徑。本機既有 `rv_checkpoint_v5.save` 已刪除。

清理涵蓋舊生成與導航分支、舊教學控制器／九區場景、地堡 v1 房型與生成器、舊天空／地形／霧 shader、車體地板遷移、終端及玩家欄位補值、舊顯示偏好遷移。保留目前使用的共用美術、車庫展示場與歷史驗收紀錄。展示場改用 v14 地形與獨立車庫 profile。

## 本次驗證

Godot 4.7.2，Windows headless，使用 `scripts/test.ps1 -TestFilter` 選取相關測試；未執行全套。

- `test_checkpoint_failures`：目前格式序列化、教學重試入口、完整欄位與身分驗證、磁碟錯誤、隔離載入與復原。
- `test_orientation_departure`：實際教學交易、原 RV 感應離場、封門及檢查點重載。
- `test_item_persistence`：道具所有權／支撐及列印身體姿勢、體力、缺肢的還原。
- `test_item_player`、`test_rv_engine`、`test_poi_transition_persistence`：新道具建立、車體與服務、地堡轉場保存。
- `test_streaming_generation`：分幀生成、導航、四種子地形／12 km 道路指紋、森林重建與橋梁；現行地形及道路指紋與清理前一致。
- `test_barrel_explosion`、`test_slender_speaker_acquisition`：必要油桶人行為／倒數狀態還原及完整玩家復原資料。
- 正式主場景 smoke：可操作就緒、設定入口及玩家移動。

上述九個測試及主場景 smoke 全部通過。兩個車庫入口 `world/demo_world.tscn`、`tests/starting_shelter_playground.tscn` 另以忽略目錄內的臨時腳本確認 v14 地形、車庫門與啟動完成。

過程修正了身分負向測試資料別名衝突、新建立電池道具的必要欄位，以及串流測試容器缺少現行巨人導航 map。車庫啟動腳本也改為等待展示場延後初始化完成才釋放場景。

日誌位於 `.godot/test-logs/`，車庫啟動日誌為 `.godot/save-cleanup-demo-smoke.log`。未進行桌面畫面、長途輪驅、翻車或群怪驗收；本次沒有替換現行視覺資產。
