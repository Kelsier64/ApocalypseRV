# 地形改造第一個檢查點

2026-10-20，Godot 4.7.2 stable，分支 `codex/terrain-overhaul`。狀態為「道路基礎完成，地形／橋梁初版接入，等待使用者檢查」。[階段計畫](../plans/terrain-overhaul.md)。

## 本輪檢查

- `test_checkpoint_failures.gd` 通過：v12／v13 接受、v13 磁碟編碼及離樹世界準備往返、教學重試快照版本一致、錯誤身份及未知 v14 拒絕，既有保存失敗與回復案例保留。結果：`.godot/test-logs/20261020-125816-011-selected-7732/`。
- `test_streaming_generation.gd` 通過：保留 v6 分幀／立即生成一致性；四個種子各 12 km、10 m 間隔，檢查前進、有限寬路面無折疊／交疊、彎曲半徑、坡度、左右彎、上下坡、路寬、最近道路投影、確定性、地形落差、河床與乾燥橋頭。另實際生成 v13 過河區塊，檢查水面網格、三處跨輪距的物理橋面支撐及橋面導航發布。
- 正式主世界 smoke 通過：v13 seed 42 就緒、Esc 設定路由及玩家移動。最後兩項結果：`.godot/test-logs/20261020-130224-029-selected-38188/`，共約 19.43 秒。沒有執行全套測試。
- 原生渲染檢查：以同一套 Ground／Road／TerrainCrossings／ForestScenery 建立河谷過橋、山壁道路、山脊及路面視角。這是固定日光檢查場，不含正式天氣、教學建築或 RV 駕駛操作；已分別檢查 Compatibility 與 Forward+。截圖及工具保留在忽略的 `.godot/terrain-review/`。
- `git diff --check` 通過；沒有修改既有四個使用者變更檔案。

第一次地形測試有測試 helper 型別推斷錯誤；修正後通過。第一次 smoke 發現無橋區塊向導航加入空面陣列，已改為僅在非空時加入，最後 smoke 通過。整合審查另修正新版護欄與刷新避讓共用計畫，以及大彎旋轉後深林 POI 的查詢範圍、完整占地及河道避讓。

## 限制與下一步

本輪沒有實際 RV 輪驅連續上下坡／過橋、長途串流或舊存檔遊玩驗收；數值及固定視角不代表駕駛手感通過。起始載入與行車串流的成本需下一階段量測改善。河岸、橋梁及岩壁仍是程序幾何初版；濕地目前表現為低地及河道，未加入游泳、水流作用、落水傷害或水面反射專用系統。更多局部地形變化與美術細化等待使用者檢查後再繼續。

既有未提交變更保持原樣：`.agents/skills/apocalypse-rv-3d-scenes/SKILL.md`、`tests/weather_playground.tscn`、`world/dark_adaptation_profile.tres`、`world/night_vision_curve.tres`。
