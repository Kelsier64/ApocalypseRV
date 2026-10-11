# 製作台模型與逐層成形動畫（2026-10-11）

製作台改為原生 Godot 工業製造機：架高網格床、支架、後方雙柱、導螺桿、掃描滑台與狀態列。保留設備場景與 SpawnMarker，新增床面／後柱碰撞；完整測試 RV 的平板移至前面板，避免占用加工空間。

`CraftingPrintVisual` 只複製配方產物的可見 MeshInstance3D，不把暫存產物加入 SceneTree。各網格的 transform 與材質色彩／貼圖交给列印 shader，以製作台局部高度統一裁切；發光加工線、層紋與滑台位置依工作剩餘時間推進。沿用既有配方時間、材料、能源與出貨交易。完成但阻塞時保留完整預覽，成功出貨後移除；取消、下一個相同配方及存檔恢復依 job ID 同步。手持 presentation_only 不啟動製作。

預覽指令：

```powershell
godot --path . res://tests/crafting_station_playground.tscn
```

Space 暫停，R 重播，1–7 切配方，左右鍵環繞。這是同一套正式模型／視覺控制器的展示場，為方便觀察把展示過程設為八秒；正式遊戲仍使用配方原本的時間。追加 `-- --capture` 可輸出五階段畫面至 gitignored `.godot/fabricator-preview/`。

## 驗證

以 Godot 4.7.2 統一 runner 分段執行，以下 12 項測試與 main-scene smoke 通過：

- `test_crafting_print`：全部七種配方、半成品、停電／停用、取消退款、相同配方連續佇列、阻塞後單次出貨、入樹前恢復、手持隔離、旋轉與位移後的裁切座標。
- `test_item_services`、`test_item_persistence`、`test_equipment_lifecycle`。
- `test_rv_checkpoint`、`test_rv_engine`、`test_rv_resource_cycle`、`test_rv_physics_regression`、`test_rv_cockpit`。
- `test_player_carry`、`test_starting_shelter`、`test_starting_shelter_terrain`。搬運測試新增完整製作台網格皆在場景樹與握持邊界涵蓋整機的檢查。

本輪原生 Forward+ 與 Compatibility 渲染五階段油桶、強化引擎與輪胎，最終日誌無 ERROR；實際視窗確認暫停保持進度及配方切換。另在完整測試 RV 內以真實 request_craft／step_work 取得半成品畫面，確認平板正向、床面淨空及車頂容納機架。

中途發現並修正兩項問題：離樹暫存模型立即 free 的渲染資源錯誤（改為 queue_free），以及支架 sibling 重名造成搬運讀取離樹節點（改唯一名稱）。最終搬運與避難所測試無該錯誤，不修改角色搬運邏輯。

本輪未執行整套 full suite 或長途行車列印實機驗證。進度預覽對目前配方的靜態網格有效；不包含蒙皮動畫、材質特效或實際噴嘴路徑規劃。
