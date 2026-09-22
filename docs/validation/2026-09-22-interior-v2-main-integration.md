# 室內 v2 主世界整合（2026-09-22）

將 `codex/poi-interior-v2` 的功能提交 `140f9b1` 與規格提交 `a9a44b2` fast-forward 至 `main`。主工作區既有的駕駛功能與文件改動仍保留為未提交內容，沒有混入這兩筆 POI 提交。

## 整合範圍

主場景仍是 `world/test_world.tscn`。maintenance、warehouse、pump、research 四款非 legacy 入口首次造訪時使用 maintenance_v2，無須改成測試場才能進入。已造訪的 actor-only 舊副本繼續使用 v1 幾何；不搬移或重置舊物品。重新啟動遊戲後生效，既有執行中的場景不視為已熱更新。

八份重疊文件／測試腳本先備份並逐段整合，再接入提交。測試 runner 同時保留駕駛的 fixed-fps 名單與 interior_traversal；其他 57 個既有修改或未追蹤檔案在整合前後以 SHA-256 核對一致。沒有提交既有 todo 或駕駛草稿。

## 本輪驗證

Godot 4.7.2、Windows、headless/dummy；驗證對象為主工作區，包含既有未提交的駕駛改動，不是純淨 `a9a44b2` checkout。APPDATA 指向 `.godot/poi-v2-integration/test-user`，保留正常遊玩的存檔。使用正式 `scripts/test.ps1`、每項 240 秒限制。

- `test_interior_*.gd`：四組通過，包含布局、50／75／100 房導航、實際搬運上下樓、保存與舊副本相容。
- `test_poi_*.gd`：四組通過。正式主世界入口以 E 進入 seed 4026586570 的 83 房 v2，返回後再次進入，物資／敵人保存和導航通過。
- `test_checkpoint_failures.gd`：通過磁碟錯誤、第二車輛復原、世界切換與 POI 失敗復原。
- `test_rv_checkpoint.gd`：通過磁碟還原、電池及正式物件所有權。
- 本輪文件的 274 個本地連結檢查通過，`git diff --check` 通過。

驗證期間工作區另有 RV 燈條／空調修改持續寫入，首次最後一批 main-scene 因尚未匯入的新 `CabinLightStrip` 類別而失敗；這些變更不屬於 POI 整合，也沒有回退或代改。重新執行 runner 的 import 後，檢查點與主場景啟動／玩家移動均通過，runner 結束碼為 0。上述 57 檔一致性是整合當下的比較，不代表其他工作在此後停止修改。

原始日誌位於 `.godot/test-logs/`。本輪沒有重跑全部 45 組，也沒有新增桌面實機觀察；上輪完整覆蓋、GPU 畫面及限制見 [室內 v2 驗收](2026-09-22-interior-v2.md)。
