# 開發計畫總覽

存檔只支援當前版本（見 `rv/checkpoint.gd`、`rv/vehicle_snapshot.gd`、`world/terrain/world_profile.gd`）；舊版相容與遷移已移除，各計畫中的退役條款與歷史驗收不代表目前支援。

**核對範圍**：劃分進行中與已封存時，只確認各列所列的檔案與符號存在於程式中，沒有執行測試或遊戲；「未結項目」沿用各計畫原文，沒有逐項重測。依賴某列前，先對照程式與該列的驗收紀錄。以下順序是建議，不是排程承諾。

[文件索引](../README.md) · [遊戲設計](../../GDD.md) · [技術架構](../../architecture.md)

## 進行中

| 計畫 | 狀態 | 剩餘工作 | 驗收依據 |
|---|---|---|---|
| [地形與道路改造](terrain-overhaul.md) | 階段 1–3 已接入，等待使用者檢查實際渲染；階段 4 尚未開始 | 湖泊、水流玩法、RV 長途輪驅與完整串流成本；橋梁的實際輪驅驗收 | [第一個檢查點](../validation/2026-10-20-terrain-stage1.md) · [山路](../validation/2026-10-21-mountain-road.md) |
| [架構重構](architecture-refactor.md) | 盤點完成，測試基準已全綠，擬真操控分支已合回 main，尚未動程式 | 從 main 分片重構；大型變更逐項提案 | 盤點為靜態閱讀，沒有驗收紀錄 |
| [RV 擬真操控、翻車與車損](2026-11-14-rv-handling-rollover.md) | 首版實作，已合回 main，待人工驗收 | 輪胎、傳動、部位車損、乘員與跳車傷害、兩段千斤頂救援的試玩手感與聽感 | [測試與回放紀錄](../validation/2026-11-15-rv-handling-rollover.md) |

## 已封存

下列計畫的實作已在程式中，或已被其他計畫取代，文件移到 `docs/archive/plans/`。未結項目沒有因封存而完成，接手時從這一欄找。

| 計畫 | 封存原因與程式依據 | 未結項目 | 驗收依據 |
|---|---|---|---|
| [Abandoned Megashelter（灰井住宅城）](../archive/plans/abandoned-megablock.md) | 外殼已實作；計畫寫的「不提供可玩室內」已被室內接入取代（`world/instances/interior_profiles.gd` 的 `megashelter`、`megashelter_stairwell`） | 完整自由遊玩與最終美術確認 | [外觀指南](../guides/megashelter-exteriors.md) · [室內指南](../guides/megashelter-interiors.md) · [外觀驗證](../validation/2026-10-30-megashelter-facade-refinement.md) |
| [新版兩室教學](../archive/plans/starting-tutorial-two-room.md) | 四個階段都已實作（流程：`world/tutorial_shelter/orientation_controller.gd`、`orientation_workshop.gd`、`tests/test_orientation_departure.gd`；階段四建築：`world/orientation_shelter/building_finish.tscn`、`building_details.tscn`） | 階段四的建築美術等待使用者驗收 | [階段三](../validation/2026-10-15-orientation-stage3.md) · [階段四](../validation/2026-10-16-orientation-stage4.md) |
| [教學基地（舊九關）](../archive/plans/starting-tutorial.md) | 已移除，由新版兩室教學取代（`WorldProfile` 的開局場址為 `orientation_shelter`） | 無 | [階段一紀錄](../validation/2026-10-11-tutorial-stage1.md) |
| [公路隨機刷新](../archive/plans/random_spawn.md) | 獨立數量、選點與朝向已實作（`world/road_spawns.gd`） | 新分布的手動輪驅穿越、追擊、玩家拾取及車撞爆炸觀察 | [獨立生成紀錄](../validation/2026-10-07-independent-road-spawns.md) |
| [裂爪 Raker](../archive/plans/2026-09-22-raker.md) | 首版已完成並驗收，`enemies/raker.tscn` 是正式敵人 | 地形腳掌 IK、極端翻車及群怪效能屬擴充 | [驗收](../validation/2026-09-22-raker.md) · [模型與動畫說明](../../assets/models/raker/README.md) |
| [隨機地堡重作](../archive/plans/2026-09-24-random-bunker.md) | 結構已驗收，初版內容已接入（`world/instances/interior_profiles.gd` 的 `bunker`） | 長局平衡、自由遊玩和效能驗收 | [契約](../guides/bunker-interior.md) · [結構驗收](../validation/2026-09-24-random-bunker.md) · [內容驗證](../validation/2026-09-29-bunker-content.md) |
| [RV 系統路線圖](../archive/plans/2026-09-15-rv-systems-roadmap.md) | 首版已實作；能源設計已由引擎內建充電取代（`rv/vehicle_energy.gd`） | 長途經濟的廣泛量測與數值調整；極端載重、外掛力矩與怪物群 | [RV 系統](../validation/2026-09-15-rv-systems.md) · [共用儲存](../validation/2026-09-16-rv-shared-storage.md) |
| [完整 RV 與引擎](../archive/plans/2026-09-16-rv-rebuild-engine.md) | 已接入正式場景（`rv/engine_bay.gd`、`rv/rear_ramp.gd`） | 無 | [RV 重建](../validation/2026-09-16-rv-rebuild-engine.md) |
| [RV 駕駛體驗](../archive/plans/2026-09-16-rv-driving-experience.md) | 階段 1–3 已實作，後續由[擬真操控計畫](2026-11-14-rv-handling-rollover.md)接續 | 一般操作、UI 瞄準與音效聽感的人工驗收 | [驗收](../validation/2026-09-22-driving-experience.md) · [煞車與效能](../validation/2026-09-22-driving-performance-braking.md) · [簡化載重](../validation/2026-09-22-simple-vehicle-load.md) |
| [室外恐怖氛圍](../archive/plans/2026-09-16-outdoor-horror.md) | 首版已實作（`world/world_weather.gd`、`world/world_clock.gd`、`world/terrain/walk_in_sites.gd`），原規格多處被後續生成版本取代 | 天氣生存效果（淋濕、體溫、感知、抓地）與室內美術 | [密林](../validation/2026-09-16-dense-forest.md) · [D](../validation/2026-09-17-outdoor-d.md) · [體積霧](../validation/2026-09-17-volumetric-fog.md) · [小 POI](../validation/2026-09-26-minor-pois.md) · [天氣](../validation/2026-09-20-weather.md) |
| [局內指令系統](../archive/plans/command.md) | 時間、天氣與作弊指令改在車載終端實作（`equipment/terminal_commands.gd` 的 `time`、`weather`、`cheat`）；計畫的獨立控制台與 `DebugCommands` autoload 不存在（`project.godot` 只註冊 `GameSettings`、`Checkpoint`） | 計畫列出的 `spawn`、`list`、`freeze` 與 `camera thirdperson` 不在程式中 | [終端作弊、時間與天氣](../validation/2026-10-19-terminal-cheats.md) |

## 建議接續順序

接續先收斂 [架構審查 A01–A03](../report/ApocalypseRV_Architecture_Audit_2026-09-22.md) 的設備依附、UI 物理與回程 actor 清理；A04 的 POI 離場取消已由本輪修正。導航生命週期與群怪效能另列待驗證。審查列出的舊檔候選已按 [整理紀錄](../validation/2026-09-28-codebase-cleanup.md) 處理，存檔遷移已移除，歷史紀錄保留。

| 順序 | 可交付範圍 | 完成判準 |
|---|---|---|
| 1：架構問題收斂 | 修正 A01–A03，逐項補正式入口的回歸與保存檢查 | 記錄重現、修正及回歸結果；A04 歷史問題與本輪修正分開記錄 |
| 2：地堡內容與探索收益 | 在已接入的初版搜刮、撤退、物資及遭遇上調整收益與節奏 | 更多 seed、一般遊玩、長局收益、敵人密度與效能驗收 |
| 3：駕駛與安裝問題收斂 | 複查 todo 的方向盤左右、電池槽／設備預設方向、加油孔尺寸與角落閃爍；補一般操作、音效與夜間視角 | 回報有重現／結案證據；受控回放與自由遊玩手感分開記錄 |
| 持續驗收 | RV-06 長途油電／材料平衡，POI-07 載入／重返／記憶體量測，群體敵人與物理專項 | 保留真實油耗與工作成本；結果區分自動回歸、實機觀察、量測與未測範圍 |

若下一輪優先增加可玩的內容，可接第 2 項；地堡初版內容與 18 套室外小 POI 已接入，地堡的長局收益與遭遇節奏仍待調整和驗收。

## todo 核對與仍待收斂事項

封存的 [todo](../archive/todo) 保留每個原始項目與順序，以及當時的完成／部分／待複查標記；[todo_prompt](../archive/todo_prompt) 保留 POI 三種類型與未來模型接入方向。確定完成的引擎維修、底盤模型重作、車門窗戶、車撞怪物傷害、戶外遮蔽與互動結果提示，不再列為從零開發工作。

- 「移除發電機」已完成：改為引擎內建充電，設定與存檔規則見根目錄 GDD／architecture。
- 「撞車受損」與「撞車車損」是同一待辦；怪物被撞扣血已完成，不代表 RV 撞牆會扣耐久。碰撞傷害需定義受損對象、門檻與冷卻；外掛設備仍是獨立凍結剛體，力矩傳遞另需實測。
- 拿重物禁止攀爬已接入：依 active_item.is_large 靜默拒絕（設計已決定不另外提示），攀爬中取得大型物品安全脫離並保留平台速度／物品狀態；相關 quick／integration 回歸與正式世界 smoke 已在 `855a17e` CI 通過；整體 CI 仍有既存失敗及戶外測試不一致，實機操作尚待驗證，詳見 [本輪紀錄](../validation/2026-10-04-issues-8-17.md)。
- 一般座位、出生點建築、丟物手感尚未完成。分解機活體肢解與回收已接入，見 [活體分解驗收](../validation/2026-10-10-scrapper-living.md)。玩家死亡布娃娃與安全重生已接入；原始 todo 中「先不做」保留為歷史想法，現況以 [死亡驗收](../validation/2026-09-27-player-death-integration.md) 為準。
- 天氣視聽已完成；淋濕、體溫、感知、抓地、雷電、積水及濕地材質未實作，雨霧呈現參數也尚未統一成單一設定資源。
- 怪物已能破門／拆頂，車內主動拆設備或拆出路線未做；敵人群體與遭遇節奏不因既有近戰修正而結案。

## 接續工作方式

1. 先核對根目錄現況、相關程式與本計畫的未勾選項目；混合「已完成基礎＋尚未完成擴充」的工作應拆開追蹤。
2. 依上方建議選一批，先界定該批驗收範圍。POI 接續隨機地堡收益與遭遇平衡，RV 接續一般操作驗收；未選中的擴充繼續留待辦。
3. 完成後記錄自動測試、實機觀察與未驗證範圍，再更新計畫狀態及 GDD／architecture。歷史報告不因新程式而改寫為新結果。

勾選只代表該項列出的範圍；「已實作」「已有驗收紀錄」「全情境驗收完成」不可互換。存檔格式（`rv/checkpoint.gd` 的 `VERSION`）與地形生成版本（`WorldProfile.CURRENT_GENERATION`）是不同欄位；只接受當前版本。往返串流不等於全世界所有散落物永久保存。

2026-09-24：室內方向已由 [隨機地堡](../archive/plans/2026-09-24-random-bunker.md) 取代；v2 驗收保留為歷史結果。
