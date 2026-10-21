# 2026-10-22 路旁與越野 POI

狀態：已完成下列自動檢查與場景渲染檢視；未做完整手動遊玩。

生成版本升至 v15；Checkpoint／VehicleSnapshot 維持 v6，依存檔政策只接受生成 v15，舊世界重新開局。地形與植被外觀沿用 v14；道路 RNG 維持 v13，relief、dry-valley、flora RNG 維持 v14，本輪改動集中於 POI 排程與放置。放置類別與資產定義分開，同一資產可支援 roadside、off_road，亦可只屬其中一類。

越野規劃使用橫向 3 欄、每格 300 × 900 m 的網格，x 範圍 -450 至 450 m。每格以 55% 機率成為候選，最多 8 次嘗試；避開道路、水域、陡坡及其他 POI。候選以 40% 機率選 bunker，其餘為 camp／shed。四款地堡入口、camp、shed 同時支援兩種放置類別；另外四種小型主題只在路旁生成。四款地堡入口 路旁場址位於道路中心 49 m 外，為獨立地點，局部整地只用於建築入口本體。越野場址依自然地面高度及隨機朝向放置，地堡入口使用局部整地，不附帶公路／方向標誌、車道、停車線、林間步道、迷宮或周界牆。

越野場址穩定 ID 由生成版本、seed、row、column 組成。地堡室內沿用 PoiInstanceManager.saved_instances 與 checkpoint 的 `poi` 狀態；戶外營地等沿用 outdoor_sites／WorldActorSnapshot。不新增專用存檔格式。此輪不建造房屋。

## 驗證

Godot 4.7.2，使用正式 [runner](../../scripts/test.ps1) 選取相關測試，未執行全套：

| 檢查 | 結果 |
|---|---|
| test_checkpoint_failures | PASS；v15 保存、還原及舊生成版本拒絕 |
| test_orientation_departure | PASS；開場教學與離場交易 |
| test_poi_transition_persistence | PASS；地堡轉場取消、死亡、逾時與回訪狀態 |
| test_streaming_generation | PASS；既有地形／道路契約，加上公路外場址及跨帶導航 |
| main-scene | PASS；正式新局就緒與可操作檢查 |
| 最後一次 editor import | 無腳本錯誤；相依展示場已改用測試專用步行路點，不重建實體步道 |

新增 [場址契約](../../tests/support/offroad_site_contracts.gd) 取四個 seed、各 12 列 × 3 欄，檢查反向查詢、清除快取後重建、唯一 owning band、雙類別資產資格、地面接合、道路避讓、無車道整地、實際場景驗證、掉落物卸載回訪，以及真實建築旁的跨帶導航。道路保留原 12 km 固定指紋；POI 整地已改變，完整地表改驗查詢順序獨立性。

導航沿用既有高度簡化；測試先在實際烘焙三角形上以 XZ 插值取導航高度，再檢查發布地圖的覆蓋與跨帶路徑，不以物理地面高度的三維最近點偏移誤判缺洞。未放寬路徑端點的水平容差，也未修改遊戲導航參數。

公路外候選排除河道完整谷地影響範圍，避免後續河床整形切掉建築平台。地形合法性仍採有界取樣，不代表所有 seed、物理通行及長途密度已完整驗收。

實際 Compatibility 渲染檢視：seed 42 的 pump 地堡入口（row 4、column 2）及 seed 0 的 camp_2（row 6、column 0），使用正式地形、建築與森林生成，確認局部整地、周邊植被及無導引道路／告示牌。這是靜態場景觀察，沒有操作玩家或驗收搬運返程。截圖與日誌保留於忽略的 `.godot/poi-refactor/`，不納入遊戲資產；暫存渲染及診斷腳本已清理。

測試日誌：`.godot/test-logs/20261022-005537-848-selected-3264/`（保存／教學／轉場），`.godot/test-logs/20261022-010420-206-selected-27096/`（修正後生成與主世界）。
