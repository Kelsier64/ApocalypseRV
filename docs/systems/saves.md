# 存檔

F6／F9 室外檢查點的範圍、驗證與政策。存檔開發凍結到專案後期；版本以 [rv/checkpoint.gd](../../rv/checkpoint.gd) 與 [rv/vehicle_snapshot.gd](../../rv/vehicle_snapshot.gd) 的 `VERSION` 為準。

## 功能一覽

| 功能 | 現況與範圍 | 主要來源／入口 |
|---|---|---|
| 室外檢查點 | 正式主世界 F6／F9；保存完整玩家／RV／教學／時間天氣／場址／副本狀態，上一份有效檔備份為 `.bak`；要求室外離座及穩定狀態 | [Checkpoint](../../rv/checkpoint.gd)、[schema](../../core/checkpoint_schema.gd) |
| 狀態與所有權驗證 | 場景白名單、唯一 ID、支撐鏈／物品狀態／室內 profile 驗證，錯誤／不相容資料拒絕載入；不是多槽永久世界保存 | [save catalog](../../core/save_scene_catalog.gd)、[world entities](../../core/world_entities.gd)、[profiles](../../world/instances/interior_profiles.gd) |

## 規則與數值

### 存檔範圍

存檔版本與預設路徑以 `rv/checkpoint.gd`（`VERSION`、`PATH`）及 `rv/vehicle_snapshot.gd`（`VERSION`）為準，上一份有效檔備份為同名 `.bak`。存檔開發目前凍結，留到專案後期重做；後加入的功能狀態不保存。只支援當前生成版本、`shelter` 主世界與兩室教學；所有玩家身體、體力、蹲姿、車輛充電／舒適設定及輪胎物品欄位必須齊全。獨立保存十一槽型態、耐久／毀壞與門角度，先還原結構再接回設備；驗證唯一性、值域與支撐關係。缺口和空引擎槽保持空缺，不補發設備或維修包。舊版檢查點與舊路徑不再支援，不提供遷移。

現行為十一槽布局；十二槽地板與早期單片屋頂資料拒絕載入。

政策見下方〈更新政策與凍結〉。

### 檢查點檔案

F6 寫入 Checkpoint 的 `PATH`（[rv/checkpoint.gd](../../rv/checkpoint.gd)），上一份有效檔保存為同名 `.bak`。版本以 Checkpoint 與 [VehicleSnapshot](../../rv/vehicle_snapshot.gd) 的 `VERSION` 為準，只接受當前生成版本的正式世界及完整玩家／車輛／教學狀態。保存十一槽型態、耐久、破口、門角度與 Item 支撐關係；施工或放置預覽期間禁止保存。舊版存檔不遷移、不偵測或讀取舊路徑；需要重新開局。存檔開發目前凍結，後加入的功能狀態不保存，讀檔後回到初始值。

## 實作契約

### 更新政策與凍結

**存檔更新政策（2026-10-27）**：更新造成舊存檔不相容時直接重新開局，不維護相容分支、資料遷移或專門適配。只接受當前版本：Checkpoint 與 VehicleSnapshot 的 `VERSION`、當前生成版本（`WorldProfile.CURRENT_GENERATION`）及當前教學狀態格式；不偵測舊存檔路徑。歷史驗收紀錄保留原日期與範圍。

**存檔凍結（2026-11-15）**：存檔開發暫停，留到專案後期整體重做。現有 F6／F9 保存內容與測試維持可用；新功能不接入存檔、不新增必要欄位、不升 Checkpoint 版本，讀檔後新狀態回到初始值。唯一例外是新 Item／Monster 場景仍須登錄 [`SaveSceneCatalog`](../../core/save_scene_catalog.gd)：教學「Restart this stage」與步驟恢復同樣透過 `Checkpoint.capture_world`／`load_snapshot` 在記憶體中拍攝與還原快照，未登錄的場景會讓整份快照被拒絕。
