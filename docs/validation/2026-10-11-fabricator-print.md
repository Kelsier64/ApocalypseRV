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

## 房車內完成與互動修正

2026-10-11 正式場景回報重現：房車內平台加上 1.6m 身體會與車頂（例如 RoofMiddle/CollisionRear）重疊；remaining 已為 0，但出料被拒絕，因此全身模型仍是沒有互動的預覽，機架與下一工作也一直等候。

PrintedPlayerBody 在原出料位置沒有完整站立空間時，改尋找機台旁 0.95／1.25m 範圍內的安全地板。驗證地板法向、實體身體及正式玩家肩寬淨空，並以身體碰撞沿地板高度掃掠可通過路徑；不忽略牆、其他物品或其他身體。平台／側邊皆無空間時仍保留已付費工作，顯示清空機台旁地板的原因，清空後只出貨一次。一般物品沿用平台出料規則。完成前先同步最終列印高度，再交付真實身體、清除預覽並慢慢回位；後續工作可繼續。

移除 WorkLighting 動態掛在製作台上的燈條與 SpotLight，同時移除該負載與平板工作燈開關。車內燈條與引擎維修燈保留；舊存檔 work 請求欄位保留相容，但不耗電、不產生燈。

新增 test_fabricator_cabin，保留完整房車屋頂和原製作台座標，覆蓋真人尺寸出料、真實射線 E、第二件製作、下降、阻塞／恢復及不重複扣費。另覆蓋狹窄天窗的可操控玩家淨空；主世界 seed 42 探針確認原先卡住的側邊／後方位置可完成交付。

本輪最終統一 runner：test_fabricator_cabin、test_crafting_print、test_printed_player、test_cabin_light_equipment、test_rv_experience、test_rv_checkpoint、test_rv_resource_cycle、test_rv_engine、test_item_persistence、test_equipment_lifecycle 及主場景 smoke 全部通過。薄牆外終點雖空但通路受阻，以及無地板場景均拒絕交付。原生 Forward+ 主世界 seed 42 保留完整房車，兩次真實 20 秒能源工作、實際 interact 輸入切換、完成後慢降與第二具身體生成全部通過；互動在交付身體旁無遮擋位置驗證。

## 台上蹲姿製作與交付（取代前節地板交付）

依後續需求，移除近旁地板交付。角色工作輪到第一筆時檢查台上站姿淨空；不足就選蹲姿並保存於 job.crouching，列印過程不因碰撞變化任意改姿勢。舊工作沒有該欄位時首次同步會選定，新欄位只接受角色配方的布林值。展示場可用 `-- --crouch` 檢視蹲姿列印。

蹲姿模型沿用正式 crouch_bent idle 的十一組玩家網格，烘焙高度約 1.03m，保持等比例與原材質。PrintedPlayerBody 的姿勢、1.05m 蹲姿碰撞、模型與存檔一起保存；舊五欄身體資料仍以站姿載入。E 切換時交換雙方姿態，控制器以正式蹲姿相機與動作還原，屋頂下不能起身，離台到完整淨空後才站起。缺腿的休眠身體沿用原直立外觀／碰撞限制，切回玩家後仍使用爬行。

完成後身體在原製作台上，機架慢降；下一具需等台面清空。連蹲姿都塞不下或台面占用時維持已付款工作，提示清空台面與上方；不放在地板，不再扣款或重複生成。已更新 cabin 與 printed_player 測試，覆蓋台上蹲姿預覽／實體、真實 E、低頂維持蹲姿、離台站起、占床等待、局部低頂不改道、姿勢交換及舊／新身體快照。

本輪最終統一 runner：test_fabricator_cabin、test_crafting_print、test_printed_player、test_player_crouch、test_player_carry、test_item_persistence、test_rv_checkpoint、test_rv_resource_cycle 八項與主場景 smoke 通過。原生 Forward+ 主世界兩次真實 20 秒列印回放通過：台上蹲姿生成、實際 E 切換維持蹲姿、屋頂阻止起立、實際 move_back 輸入走下台面後站起及第二具台上出料。
