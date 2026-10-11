# Slender Speaker 身體撞毀樹木

日期：2026-10-11；Godot 4.7.2；沿用 `codex/slender-ground-grab-hands`。

## 實作

`SlenderSpeaker._move_swept` 在實際身體掃掠接觸後，用掃掠前的水平速度及命中 shape index 呼叫既有樹木破壞契約。朝法線內至少 0.1 m/s 的走路／追擊接觸會撞毀樹木；靜止、離開及垂直落地不觸發。森林只停用命中的樹幹與 MultiMesh instance，路邊活樹／枯樹也沿用倒塌、導航更新及 destroyed_trees 存檔帳本。其他牆面保留碰撞與脫困。

## 本輪自動檢查

透過 `scripts/test.ps1 -TestFilter 'test_slender_speaker_tree_impact.gd,test_slender_speaker_forest_tracking.gd,test_tree_impact.gd,test_slender_speaker_patrol.gd' -Smoke`，匯入、四支測試及正式主場景啟動全部 PASS，總計 71.71 秒。日誌：`.godot/test-logs/20261011-125802-863-selected-29012/`。

新撞樹測試涵蓋 compound 第二棵樹的 shape 選取、2 m/s 走路撞毀並通過、旁樹保留、重複接觸不重建碎片、靜止／分離／垂直及落地拒絕、路邊活樹／枯樹和牆面阻擋。正式森林回歸維持自主感知／導航，追玩家時有實際樹幹接觸及新增毀樹紀錄，最大單步位移 0.167 m，距玩家縮短至 2.948 m；輪驅 RV 追蹤與巡邏也通過。既有 RV 撞樹測試包含導航、checkpoint 與重建保存。

## 本輪原生畫面

使用 computer-use 選取獨立遊戲視窗，以 Enter 啟動連續走路回放。觀察到兩棵接觸樹倒塌、地面出現碎木／落葉，巨人走過後被牆擋在 z = -20.60 m；未接觸的第三棵樹仍站立。日誌沒有腳本錯誤，檢查後只關閉本次測試視窗。暫時場景放在 gitignored `.godot/` 並於檢查後移除。

此次未跑 full suite；原生畫面使用受控移動回放，自主追擊由正式森林自動回歸覆蓋，不代表所有 seed 或串流中追擊已驗收。
