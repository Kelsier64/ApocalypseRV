# v8 公路隨機刷新驗證

日期：2026-10-01。規格：[random_spawn.md](../plans/random_spawn.md)。變更：[PR #5](https://github.com/Kelsier64/ApocalypseRV/pull/5)。

## 實作與來源核對

RoadSpawns 純規劃道路釘帶、一般／封路廢車及 Raker；候選率為 15%／25%／35%，封路為廢車候選中的 15%。據點避讓可能留白，因此實際密度低於候選率。三類獨立 RNG，廢車優先解決跨類淨空衝突；輪胎、車體、裂爪模型與碰撞重用原資產。

完整廢車模型範圍含輪胎、保險桿與翹起的引擎蓋，並補償資產內建 -0.2 rad 朝向。一般配置保留中央 5 m 柏油通道；封路使用 3–4 台橫置車，淨空以模型投影檢查，避免彎道 AABB 重疊造成錯誤拒絕。

道路完成後建立 chunk 靜態內容並參與導航烘焙；導航 map／region 發布後才建立 WorldEntities 怪物。skip_actors 與 generated_bands 防止回訪及重載補怪。v8 保存增加導航等待檢查；檢查點格式仍 v3，shelter 接受 v7／v8，legacy 保留 v2–v6。共用 WorldProfile 預設仍為 v6。

## 自動驗證

本次雲端執行環境在 executor registration 時失敗，未執行本機 Godot；改由既有 GitHub Actions Windows runner / Godot 4.7.2 分組驗證。

首輪 commit `1c8119e57ec23d9181c982c4185f9192f08e3ceb`：[push run](https://github.com/Kelsier64/ApocalypseRV/actions/runs/36905268212)、[PR run](https://github.com/Kelsier64/ApocalypseRV/actions/runs/36905273625)。quick 17 支測試（含新規劃測試）及正式世界 smoke 已通過；其餘組待核對。後續修正增加導航前保存拒絕、v7 fixture 世界隔離、死亡測試只統計活怪及跨 World3D 清理檢查，需以最後程式提交的 CI 為準。

新增覆蓋：

- `test_road_spawns`：12 seeds、正序／倒序查詢、舊版本隔離、安全區、接縫、據點、模型淨空、一般通道與封路。
- `test_road_spawn_lifecycle`：導航前禁止道路怪物、就緒回呼一次、靜態重建一致、出生 chunk 卸載仍存活、死亡後不補出、±450 m／WALK_IN／另一 World3D 清理，以及真導航發布。
- `test_road_spawn_checkpoint`：正式主世界 v8 活怪保存／載入、擊殺後保存／载入與原帶重建不復活。
- `test_starting_checkpoint`：新局 v8、三個開場穩定狀態、真 v7 及 legacy v6 檢查點相容。

## 實機與未驗證範圍

未進行 GPU 畫面、輪驅穿越釘帶／廢車、一般通路與封路手感、Raker 追擊／搭車、群怪效能或長局密度觀察。Headless 規劃／導航與保存通過不等同這些情境已驗收。

清理遵循規格：戶外怪物目前位置距串流錨點前後超過 450 m 時移除，loaded WALK_IN 受保護。v8 正式 profile 將 chunks_ahead 對齊為 2，目前帶與前方兩帶共至多 450 m，避免新怪在最遠預載帶立即清除。舊版與自訂 profile 保持原設定；若自訂前方窗超過 450 m，仍不補怪、不休眠保存。實際遇敵節奏仍需實機核對。
