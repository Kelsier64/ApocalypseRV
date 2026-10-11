# 製作台、三軸列印與身體切換（2026-10-11）

## 最終模型與動作

製作台重做為五組 Blender 倒角零件，使用分解機原有的漆面、金屬／粗糙度與法線貼圖。加工平台左右 X 與前後 Z 各有滑軌；Godot 的 Y 為高度軸。整組橫樑與重疊立柱隨加工高度升高，沒有固定高度上限。機柱實體碰撞同步伸展，各設備有獨立 Shape 資源。世界的出料空間檢查仍有效，屋頂等障礙不會被忽略。

`CraftingPrintVisual` 依配方剩餘時間顯示物品底部到頂部，包含發光加工線、層紋及三軸動作。預覽只複製網格，不註冊實體 Item。停電／停用凍結進度；阻塞出料保留完整預覽與高位機架，完成出料或取消後，以每秒 0.45m 慢慢下降收起；立柱與碰撞同步縮回，重複同步或接續較低的列印目標不會瞬移。原先同名支架與立即釋放暫存資源問題已在前輪修正。

## 正式角色製造

平板新增 `Standing Player Body` 配方：20 Metal Parts、10 Electronic Scrap、10 Unrefined Fuel，20 秒、5 電力。產物是原比例約 1.6m 的直立玩家身體，來源為正式十一組玩家網格與 idle 姿勢的靜態烘焙。列印完成後，對著身體按 E 可切換控制，舊身體留在原地，可再次切回。

切換保留唯一的正式 Player 節點、相機與 HUD；位置、健康、肢體及體力／疲勞狀態在兩具身體間交換。背包與手持裝備隨操控者轉移，不在兩具身體間複製。休眠身體不能收進背包，可保存為可信 Item；受傷的休眠身體顯示對應缺肢與傷口。切換前檢查新舊位置碰撞，禁止死亡、駕駛、攀爬、被抓、UI／放置等不適合的狀態。移動載具的接觸點速度與支撐關係一併處理。

## 預覽與操作

```powershell
# 八種配方的模型／動畫展示；八秒展示不改正式配方時間
godot --path . res://tests/crafting_station_playground.tscn
# 正式能源／20秒配方／玩家操作
godot --path . res://tests/printed_player_playground.tscn
```

模型展示：Space 暫停、R 重播、1–8 選配方、左右鍵環繞；`-- --capture` 擷取階段圖到 `.godot/fabricator-preview/`。正式互動場：WASD／滑鼠控制、E 切換、R 製造另一具身體。此測試場會提供材料與電量；正式遊戲須自行取得。`-- --verify` 以真實能源迴圈和 interact 輸入自動驗證切換。

## 驗證與範圍

Godot 4.7.2 統一 runner：13 項測試及 main-scene smoke 通過：`test_crafting_print`、`test_printed_player`、`test_player_carry`、`test_item_services`、`test_item_persistence`、`test_equipment_lifecycle`、`test_rv_checkpoint`、`test_rv_engine`、`test_rv_resource_cycle`、`test_rv_physics_regression`、`test_rv_cockpit`、`test_starting_shelter`、`test_starting_shelter_terrain`。另外 `test_checkpoint_failures` 通過。最終資產改用與分解機相同的 GLB 內嵌貼圖設定；清除舊解出貼圖後，首次匯入遇到舊 UID 快取，完成重新匯入後，兩項製作／角色測試及 Forward+ 階段渲染重跑通過。

新增驗證包含八種配方、真人尺寸十一組靜態網格、6m 立柱伸展、X／Z 獨立行程、停電／取消／讀檔／連續佇列、阻塞後單次出貨、獨立碰撞 Shape、健康／缺肢／體力交換、單一控制器、背包不複製、物品快照還原、切回舊身體、障礙拒絕與載具速度。原生 Forward+／Compatibility 皆能渲染完整列印；原生遊戲回放驗證正式 20 秒製作與 interact 輸入切換。

尚未跑整套 full suite 或長途行車列印。休眠身體採靜態直立姿勢與站立碰撞；腿部缺損者切回控制後才採正式爬行碰撞與動作。無角色 AI、多人連線或噴嘴逐三角形的實際切片／路徑規劃。

## 回位動畫修正

2026-10-11：三項相關測試（test_crafting_print、test_printed_player、test_equipment_lifecycle）重跑通過，驗證中途高度、下降速率、重複 clear、碰撞同步、連續工作改目標與到位不越界。原生 Forward+ 回放另驗證實際一秒後下降約 0.45m，最終停在 0.97m。
