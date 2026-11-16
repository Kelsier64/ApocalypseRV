# 開局與教學基地

兩室教學基地、故障車整備、出庫與啟程，以及展示用的單間車庫。程式在 [world/tutorial_shelter/](../../world/tutorial_shelter/) 與 [world/starting_shelter/](../../world/starting_shelter/)。

## 功能一覽

| 功能 | 現況與範圍 | 主要來源／測試場 |
|---|---|---|
| 兩室教學基地 | 正式；接待室啟動並帶走終端才開內門，倉庫提供可任意順序操作的選做指南 | [controller](../../world/tutorial_shelter/orientation_controller.gd)、[orientation playground](../../tests/orientation_playground.tscn) |
| 故障車整備 | 正式新局有故障引擎、空電池、中段毀壞屋頂、部分牆損與爆胎；倉庫提供備用物資，沒有油電保底 | [workshop](../../world/tutorial_shelter/orientation_workshop.gd)、[opening content](../../world/tutorial_shelter/opening_site_content.gd) |
| 出庫與正式啟程 | 原 RV 朝出口前進即感應開門；玩家及全車離場後才啟動正式世界模擬，不要求做完指南清單 | [StartRun](../../world/starting_shelter/start_run.gd)、[bay gate](../../world/tutorial_shelter/bay_gate.gd) |
| 重試、略過與說明書 | 啟程前 Esc 可安全重試／略過；離場後同一終端成為可搜尋說明書；讀檔不重發物資 | [recovery](../../world/tutorial_shelter/orientation_recovery.gd)、[manual](../../equipment/training_manual.gd) |
| 舊單間車庫 | 工具／展示入口；按鈕啟程，供 Demo、作弊世界及獨立場景使用 | [starting shelter playground](../../tests/starting_shelter_playground.tscn) |

## 實作契約

### 兩室教學流程

目前兩室教學使用 `orientation_shelter`，40 × 60 m 兩室。`OrientationController` 課程 v4、`OrientationWorkshop` v3；外層存檔版本以 [Checkpoint](../../rv/checkpoint.gd) 為準。第一室仍檢查原終端開機及拆下；第二室所有參考均選做，成功交易可任意順序記錄，`step` 只保存單向推進的建議與復原邊界，不授權出口。新局一次性設為原引擎 0 耐久、原電池 0 電量、`roof_1` 毀壞。以獨立的世界種子亂數從前牆、側牆和車門抽兩個受損部位，並從四個輪位抽一個磨損或爆胎的輪胎。終端依保存的目標顯示部位，損壞程度由車輛快照保存。以持久 ID 提供充電備用電池、2 包維修包、備胎、8 件廢料及 2 油桶。取消 v12 電量保底。配置後不因讀檔、返回或查看終端重施故障／補發。只接受 OrientationController v4、OrientationWorkshop v3 的完整欄位與目標；不執行課程或入口快照升級。`OrientationRecovery` 在任意順序交易批次結束且安全時捕獲待建立的建議邊界，已有復原點不被後續同段操作覆蓋；接待室仍不將部分開機冒充原始入口。`capture_world(world,false,true)` 只放寬有效終端閱讀的內部捕獲，所有權分開驗證、禁止遞迴、隔離載入成功後替換且不改手動檔案。感應門只依原 RV 的方向、位置及連續向前至少 0.35 秒／淨前移至少 0.5 m 開啟；停車懸吊微動不授權，未完成的移動觀察不保存，與教學證據、車況或服務狀態無關；普通車輛系統仍限制駕駛。玩家及整車碰撞離場後才恢復時間／天氣／敵人，即使清單未完成仍解鎖原終端說明書。Item v2 的 ID、所有權、開機與內部電量保留。

### 倉庫配置

2026-10-16 倉庫配置：v12 第二室新增可重用靜態貨架、貨箱與棧板，16 件原有 Item 改由分散的出生標記配置；保留舊矮架及碰撞路徑，已保存的物資維持原位置。`WarehouseApproaches` 僅保存設計用接近點，不生成遊戲提示或改變交易判定；貨架燈具屬建築、光源置於 Furnishings。

### 建築收邊

2026-10-16：兩室基地階段四加入獨立靜態建築收邊、舊牆皮、屋架／管線、屋頂機組及兩張實體宣導海報。大型結構網格細分以穩定陰影；滑門移至隔牆外側軌道，避免門片與牆皮交疊，活動碰撞仍不烘焙成永久導航障礙。機組基座、軌梁與碰撞由新版場景持有，不改物品 ID 或教學保存格式。獨立 Demo 與作弊測試場仍可使用單間車庫。

### 教學倉庫的回收物

教學倉庫的 Scrap A–F 使用六件 `props/scavenge_loot/` Item，G／H 保留原廢料；馬達為大型物品。`OpeningSiteContent.ORIENTATION_SALVAGE` 集中角色對應場景，沿用原 ID 與各件固定三份金屬產量。`SaveSceneCatalog` 登錄新場景；Checkpoint 的教學角色驗證只接受原廢料或該角色指定的新物品，保留當前格式已保存的舊外觀，不補發、不升級保存格式。Wrapper 使用獨立基本碰撞，不以生成網格建立物理形狀。詳見[物資製作與整合](../../art_source/scavenge_loot_references/README.md)。

### 起始避難所與世界識別

`WorldProfile.opening_shelter_id()` 決定起始建築、局部整地與開場流程，與戶外生成版本分開。一般 profile 預設選擇兩室 `orientation_shelter`。Demo 在計算出生位置前複製繼承的主世界 profile，只改用按鈕開門的單間車庫。`cheat_test_profile.gd` 也覆寫建築選擇，讓 `cheat_test_world.tscn` 使用當前世界生成，同時保留單間車庫及完整起始 RV。作弊測試場沒有教學或檢查點存讀檔，預設三種資源作弊全開。

起始建築外殼擴為 50 × 45 × 14 m，封閉側翼與主樓使用原生幾何完成立面，僅獨立屋頂設備保留灰盒；中央車庫與活動門接口保留。場址 Resource 的 bounds 同步管理整地／植被排除，側後方土坡依 building_bounds 計算。外殼的靜態盒碰撞以 navigation_solid 標記，ChunkGenerator 將其轉成投影障礙，避免碰撞盒下方留下可走地形；鄰區重建沿用相同標記。

Checkpoint 要求 `world_id=shelter`、當前生成版本與完整 `start_state`；只載入受信任的 `world/main_world.tscn`。StartRun v1 要求 phase 為 preparing／started／sealed、一個 bay gate 布林值與當前兩室教學。門移動期間拒絕保存。恢復開場狀態發生於子節點 ready 前，動態物件完成轉移後重新套用敵人狀態。
