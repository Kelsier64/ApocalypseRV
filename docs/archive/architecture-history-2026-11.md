# architecture.md 歷史段落

2026-11-12 從 architecture.md 移出的過時狀態紀錄與重複的測試說明，保留原文供追溯，不代表現況。

（2026-10-25 世界狀態紀錄，已由上方 2026-10-27 v18 摘要更新。）當時正式新局使用生成 v17；地形與植被外觀沿用 v14，沿用兩室教學；舊版存檔不支援，需重新開局。道路 RNG 域為 v13，relief／dry-valley／flora 域沿用 v14；v17 沿用 v15 預設 RNG 域，只擴充越野資產池為 40% 地堡、10% 民用避難所、10% 庭院避難所、40% 營地／棚屋，不重抽既有排程或底層地形串流。道路以水平弧長積分持續爬升／下降，解析曲線導數協助急彎最近點投影；近路接地保留，山體外側另形成山坡與谷地。`TerrainLandforms` 混合草原、懸崖、濕地、山脊、峽谷與盆地、世界噪音及材質；`ForestScenery` 依地貌分群並避開 40° 以上坡面。橋梁按完整路寬與斜向河岸重新判斷跨度、水面低於整段跨河道路；地堡入口改為路旁及越野雙分布，不再生成深林步道場區。導航沿用既有細節簡化及怪物接地推進，普通／巨人烘焙的垂直範圍改由來源幾何推算，避免 150 m 上限裁掉山頂。Checkpoint 為 v7，只接受生成 v17；舊版世界按政策需重新開局。湖泊、水流玩法、長途輪驅與完整串流仍待後續。[分階段計畫](../plans/terrain-overhaul.md) · [地形細化](../validation/2026-10-20-terrain-v14.md) · [山路修正](../validation/2026-10-21-mountain-road.md)。下方歷史段落保留當時契約。

舊九關教學的控制器、Workshop／Service 保存與升級支援已移除。歷史設計與驗收保留於[階段計畫](../plans/starting-tutorial.md)，不屬目前執行契約。

文件核對（2026-10-22）：目前使用生成 v17 及 v7 檢查點；地形與植被外觀沿用 v14。2026-10-09 森林巨人整合屬歷史驗收；各功能細節沿用各自驗收日期。描述目前工作樹實作；已實作不等於全部情境已驗收。本輪架構審查、headless 檢查與當時未修正問題見 [架構與遺產報告](../report/ApocalypseRV_Architecture_Audit_2026-09-22.md)，未進行實機操作驗收。本次檔案清理見 [整理紀錄](../validation/2026-09-28-codebase-cleanup.md)。歷次測試結果保留在 [文件索引](../README.md)，目錄責任見 [程式與資產目錄指南](../guides/codebase.md)，待辦與後續設計見 [計畫總覽](../plans/README.md)。

歷史 v11 主場景契約：該版明確選擇生成 v11，共用 WorldProfile 預設及測試世界保持 v6。v7／v8／v9／v10 的第一個停靠點為固定 WALK_IN 避難所，場址共用整地、植被排除、導航與串流範圍；兩台設備及十五件物資（含手槍與兩盒子彈）只在首訪生成，沿用 WorldEntities／outdoor_sites 的動態物件保存。車庫門由 StartRun 管理 preparing → opening → started → closing → sealed，區塊重建時重新綁定門並套用狀態。ready_for_play 只表示地形／玩家可操作，不等於旅程已開始。整備期間停止時鐘與敵人處理，不跳過敵人生成。

[scripts/test.ps1](../../scripts/test.ps1) 自動發現 tests 根目錄的所有 `test_*.gd`，預設全部執行並加上 [正式主世界 smoke](../../tests/main_scene_smoke.gd)。現行覆蓋聚焦 Item 操作／保存、RV 引擎／煞車／資源循環／結構、移動攀爬、手槍、油桶爆炸、Raker 抓取、Slender Speaker 遭遇／抓取、檢查點失敗恢復、POI 轉場、串流，以及正式新課程交易與駕車離場。orientation departure 共用的旅程 fixture 位於 `tests/support/orientation_journey.gd`，不獨立執行。

舊版本相容性專項、全 seed 掃描、逐姿勢美術與展示場自測已退出自動清單；手動場景仍保留，舊存檔相容分支已移除。歷史驗收結果保持原日期與範圍，不能當作本次通過證據。完整保留清單與命令見 [測試指南](../../tests/README.md)。

以 `-TestFilter` 選取檔名或逗號分隔的樣式時，只跑符合的保留測試；`-Smoke` 可加上主世界檢查，`-SmokeOnly` 只跑 smoke。`-List` 不啟動引擎；同一批已匯入資產可用 `-SkipImport`。每支測試以獨立 Godot 程序執行，固定 60 fps 模擬排程不修改物理 Hz、time_scale 或求解器，`-RealTime` 可作實時對照。等待背景工作使用 `tests/support/test_wait.gd` 的條件與期限，仍保留有意義的物理採樣時段。

Runner 核對引擎版本、程序退出碼、非空日誌、錯誤與 `PASS:`；smoke 另要求 `WORLD_READY_FOR_PLAY`。任一程序失敗或超過期限即停止，避免繼續使用受污染的狀態。版本、工作樹、選取清單、結果與耗時保存於 `.godot/test-logs/` 各次執行目錄。[CI](../../.github/workflows/tests.yml) 使用單一 Windows／pwsh job，期限 10 分鐘，在 main push、PR 或手動啟動；取消同一分支被取代的執行，僅文件變更略過。

文件更動核對連結與來源；程式更動選取最小有意義的測試，必要時執行預設核心集。物理更動另依 [AGENTS.md](../../AGENTS.md) 做互動觀察。Headless 結果不代表原生畫面、長途經濟、極端翻車或怪物群已完成驗收。

## GDD.md 開頭的狀態紀錄

（2026-10-25 世界狀態紀錄，已由上方 v18 摘要更新。）當時正式新局使用世界生成 v17（沿用 v14 地形與植被外觀），並有 40 m 寬的 20 m 接待室＋40 m 維修室。接待室開機並帶走終端後進入第二室，操作指南全部選做；新局引擎完全故障、電池沒電、中段屋頂毀壞，並有部分牆損與左前爆胎。供應充電備用電池、兩包引擎維修包、健康備胎、八件廢料與兩個油桶；沒有電量／燃油保底。原 RV 朝出口前進即感應開門，全車與玩家離場才開始世界模擬。Esc 提供安全復原點重試／略過。只支援當前格式存檔。[教學計畫](../plans/starting-tutorial-two-room.md)。

文件核對（2026-10-22，當時狀態）：使用 v17 新局與 v6 檢查點保存；地形道路 RNG 為 v13，relief／dry-valley／flora RNG 沿用 v14，v17 沿用 v15 的排程及 RNG，新增兩款越野民用避難所。2026-10-09 森林巨人整合屬歷史驗收；獨立測試場不提供正式檢查點。玩家死亡布娃娃與隨機地堡內容依各自驗收紀錄記載；已實作不等於全部情境已驗收。2026-09-22 headless 檢查與後續修正見 [架構審查](../report/ApocalypseRV_Architecture_Audit_2026-09-22.md)及[當時地堡驗證](../validation/2026-09-29-bunker-content.md)。歷次測試結果保留在 [文件索引](../README.md)，待辦與後續設計見 [計畫總覽](../plans/README.md)。
