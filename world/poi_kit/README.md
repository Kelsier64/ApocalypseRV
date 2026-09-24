# POI 資產與地堡房型

現行室內是 16 模組隨機軍事地堡；尺寸、接口、版本、新增房型與預覽流程以 [地堡契約](../../docs/guides/bunker-interior.md) 為準。室外類型／場址以 [共用規範](../../docs/guides/poi-authoring.md) 為準。

- 房間：`rooms/bunker/`，場景提供 footprint、clear_height 與完整接口。
- 房型資源：`world/instances/catalog/bunker/`，Profile：`world/instances/catalog/bunker.tres`。
- 基本外觀：`materials/bunker/`，混凝土貼圖沿用 `assets/materials/poi_kit/` 原有素材。
- 室外入口：`exteriors/service_entrance.tscn` 及四款繼承場景，沿用場址、入口、返回點，加入簡單軍事立面。
- 共用家具：`furniture/shelf.tscn`、`workbench.tscn`、`cabinet.tscn` 與 fuel_pump 仍供加油站使用，不隨舊副本移除。

房間保留 Visuals／Collision／DoorSockets／Furnishings／Walkway。家具保留 Visuals／Collision／LootSpawns，原點在底部占地中心；PoiLootPoint 只描述呼叫者 RNG 抽選，不能自行生成內容。地堡本輪不抽物資或敵人。

原 v1／v2 房間與舊 workshop 已移除。新測試場為 `tests/bunker_playground.tscn`；當前驗收见 [地堡驗收](../../docs/validation/2026-09-24-random-bunker.md)。下方原始紀錄只代表當時版本，不代表新地堡的驗收結果。

## 本次驗證紀錄（2026-09-15）

- 引擎：本機 Godot 4.7.2／GL Compatibility，未改既有 4.7 專案設定；CI 的 4.6.1 尚未另測。
- 自動化：最終統一 runner 的匯入、11 個測試套件和主場景 120 frames 全數通過。副本測試涵蓋 100 個 seed 的拓樸、正式入口、獨立世界、外部電量、串流錨點、物品／敵人保存，以及 96 房副本的每條連接導航。原有移動 RV 拆頂測試曾一次非固定失敗，單獨重跑通過，保留紀錄。
- 額外重播：headless `--fixed-fps 60 --quit-after 800` 搭配展示場 `-- --replay`，入口與穿越皆通過。
- Computer Use 實際觀察：資產展示的入口外觀、小房、大房、掀頂；正式場景 F6 回放從路旁入口進入 96 房副本，持續步行穿越連接走廊再回入口按 E 返回，畫面顯示 PASS。互動日誌無 SCRIPT ERROR／ERROR／FAIL；室外 RV 持續受到殭屍攻擊。測試遊戲視窗已關閉，編輯器保留。
- 未驗收：每個隨機 seed 的完整實機探索、100 房上限的長時間效能、群體殭屍實戰、全部家具繞行路線、正式模型外觀、所有材質接縫及 4.6.1 相容性。
- 日誌：`.godot/test-logs/`、`.godot/poi-visible.log`、`.godot/climb-recheck.log`，另保留先前資產展示日誌。Headless 的系統憑證讀取訊息依原測試 runner 規則排除，沒有排除腳本或其他錯誤。
