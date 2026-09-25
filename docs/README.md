# 開發文件索引

整理日期：2026-09-22。`docs/` 包含現行指南、計畫、驗收、研究與美術目標；只有 `docs/archive/` 是歷史封存區。本輪架構審查另記 headless 檢查結果，既有驗收紀錄保留當時結果。

## 從哪裡開始

| 需求 | 文件 | 責任 |
|---|---|---|
| 啟動遊戲、查按鍵 | [README](../README.md) | 快速開始與統一驗證入口 |
| 理解玩法、數值與未實作願景 | [GDD](../GDD.md) | 現行遊戲設計 |
| 修改程式、查所有權與資料流 | [architecture](../architecture.md) | 現行實作與限制 |
| 選擇下一項開發工作 | [計畫總覽](plans/README.md) | 狀態、依賴與剩餘工作 |
| 操作展示場、驗收場景 | [遊玩與測試場指南](guides/playgrounds.md) | 命令、快捷鍵與測試設定 |
| 開發約定 | [AGENTS](../AGENTS.md) | 協作與工具指引 |
| 待辦與原始想法 | [todo](../todo)、[todo_prompt](../todo_prompt)、[GDD_add](../GDD_add.md) | 保留原項目、POI 方向與補充提案；實作狀態見 GDD 及計畫總覽 |

## 文件維護規則

- README 保持快速入口；玩法規則與數值放 GDD，技術契約放 architecture，展示場細節放指南。
- 現況與程式不符時核對程式、場景與測試後修正文檔；計畫提案與研究建議不自動成為現有功能。
- 計畫標明已實作、部分實作、待實作或已被取代的範圍，附驗收連結。新增功能按主題併入現行文件，避免在首尾不斷追加日期章節。
- 驗收與審查報告保留當時版本、環境、結果與限制；修正結果另留紀錄，不把歷史測試寫成當前重新通過。
- `docs/archive/` 內文與歷史規格保留原樣。舊相對連結可能失效，以下提供目前位置的直接入口。

## 開發計畫

完整狀態與證據見 [計畫總覽](plans/README.md)。

## 指南

- [隨機地堡製作與保存契約](guides/bunker-interior.md) — 16 模組、自由尺寸擴充、接口與 manifest 保存。

- [Blender 角色與怪物製作規格](guides/character-modeling.md) — 美術方向、尺寸、低模預算、骨架、動畫與 GLB 交付；含玩家全身分件、布娃娃及肢解製作需求，與現有試接限制分開標示。

- [玩家角色建模 AI 委託書](guides/player-model-ai-brief.md) — 依使用者參考圖指定可換色工作服、純白可替換面具、全身骨架、布娃娃及活體斷肢資產的 Blender 交付條件。

- [POI 共用製作與接入規範](guides/poi-authoring.md) — 類型、Resource、場景層級、素材替換及生成／保存責任。

- [遊玩與測試場指南](guides/playgrounds.md) — `guides/playgrounds.md`

## 審查與修正

- [2026-09-22 架構、潛在問題與遺產清理審查](report/ApocalypseRV_Architecture_Audit_2026-09-22.md) — 三個 subagent 分工、重現證據、清理候選、保留邊界及當次驗證；列出的程式問題尚未修正。
- [R01–R07 修正與驗收](report/ApocalypseRV_Fixes_2026-09-18.md) — `report/ApocalypseRV_Fixes_2026-09-18.md`
- [ApocalypseRV 專案審查與修改建議](report/ApocalypseRV_Review_2026-09-18.md) — `report/ApocalypseRV_Review_2026-09-18.md`

## 驗收紀錄

- [隨機軍事地堡](validation/2026-09-24-random-bunker.md) — 16 模組、自由尺寸擴充、三層通行、主世界進出與保存。

- [Raker 固定抓咬視角](validation/2026-09-24-raker-fixed-grab-view.md) — 抓住時抬頭並固定角度，移除向下追嘴與頓挫，嘴部改對準固定視線。
- [Raker 抱頭與快速貼臉咬擊](validation/2026-09-24-raker-bite-contact.md) — 加快伸手與咬合、雙手抓頭、三姿勢嘴部接觸與近距離鏡頭修正。
- [Raker v021 整隻手重建](validation/2026-09-23-raker-v021.md) — 移除舊手、重建掌部與指縫、三節四指、權重、手部 UV 與 41 動畫，整合正式遊戲。
- [Raker v020 四指關節反折](validation/2026-09-23-raker-v020.md) — 修正 Blender bind 網格／骨架及全動畫，保留拇指；6,520 個遊戲手指取樣與 15 組怪物回歸通過。
- [Raker v019 Blender 來源掌向](validation/2026-09-23-raker-v019.md) — 修正來源動畫拇指朝後／掌心外翻，重新烘焙、匯出及關閉執行期修正的來源驗證。
- [Raker 只低頭、掌向與咬後輸入](validation/2026-09-23-raker-neck-hands-input.md) — 取消站立俯身、執行期抓握及真實輸入驗證；來源步態掌向問題由後續 v019 修正。
- [Raker 站立抓咬與即時解除（前次）](validation/2026-09-23-raker-attack-alignment.md) — 前次俯身與掌向方案已由上方修正取代；保留歷史驗收。
- [Raker v018 蹲姿臉向與內藏牙齒](validation/2026-09-23-raker-v018.md) — 實際臉向補償、原生嘴縫、閉嘴藏齒及咬合動畫。

- [Raker v017 貼臉咬擊與口腔](validation/2026-09-23-raker-v017.md) — 30／40° 上抬、前探抓頭、碰撞掃掠、牙齒與咬合衝擊。

- [Raker v016 可動頸部與抓咬掙脫](validation/2026-09-22-raker-v016.md) — 限角追視、三組抓咬動畫、硬控、駕駛滑行與固定種子驗證。

- [輪胎爆胎與低機率路邊釘帶](validation/2026-09-22-tire-puncture.md) — 四輪獨立狀態、16 種組合、維修／保存與世界生成；含解鎖後的爆胎、轉彎支撐與拆頂目視證據。

- [裂爪 Raker：2.18 m 新怪物與 22 段動畫](validation/2026-09-22-raker.md) — 獨立行為、命中時機、低姿態進出 RV、生成／保存及完整回歸。
- [裂爪 v011 外觀接入](validation/2026-09-22-raker-v011.md) — 污垢貼圖、深眼窩與嘴部正式替換及 Raker 回歸。
- [Raker v013 步態與追車狂奔](validation/2026-09-22-raker-v013.md) — 三種步態、18 m/s 上限與追車回歸。
- [Raker v014 姿勢與追車測試場](validation/2026-09-22-raker-v014.md) — 手臂內收、背頸前彎、走跑相位切換與正式輪驅 playground。
- [Raker v015 小幅抬頭與轉向](validation/2026-09-22-raker-v015.md) — 下巴微抬、回頭方向鎖定、移動朝向一致及轉彎回放。
- [裂爪 v012 頭部／軀幹加密](validation/2026-09-22-raker-v012.md) — 16,116 三角面、輪廓平滑、動畫掃描及正式主世界模型驗證。

- [2026-09-22 室內 v2 主世界接入](validation/2026-09-22-interior-v2-main-integration.md) — 正式入口分流、舊副本相容與接入結果。
- [2026-09-22 室內 v2 驗收](validation/2026-09-22-interior-v2.md) — 布局、接口、樓梯、目標與捷徑。

- [怪物 GLB 試接](validation/2026-09-22-monster-model.md) — 模型、骨架、材質、循環播放、受傷與登車實機檢查；包含車內追擊失敗及原外觀對照。

- [車內燈條設備與控制台](validation/2026-09-22-cabin-light-equipment.md) — 獨立拆裝、控制台開關、耗電、保存與舊燈轉換。

- [RV 駕駛體驗](validation/2026-09-22-driving-experience.md) — 油門／轉向、鏡面、機械動畫、音效、可控照明及白天／夜間完整回放；保留人工驗收限制。

- [正式世界加油站](validation/2026-09-20-production-gas-station.md) — v5 場址、回程串流、物資保存與實機輪驅停靠。

- [行駛卡頓與漸進煞車](validation/2026-09-22-driving-performance-braking.md) — 導航等待搜尋節制、長距離重心穩定、腳煞車調整與幀時間比較。

- [RV 簡化載重](validation/2026-09-22-simple-vehicle-load.md) — 電池與庫存不計重、保存相容性、輪驅及車頂支撐回歸。

- [日夜與動態天氣](validation/2026-09-20-weather.md) — 天氣、遮雨、保存、40 組回歸與實機觀察。

- [POI 共用定義與規範](validation/2026-09-19-poi-definitions.md) — 兩類 POI、資產登錄、入口分流與舊世界資料相容。

- [加油機 GLB 替換驗證](validation/2026-09-19-fuel-pump-import.md) — 原創外部模型匯入、碰撞保留與灰盒比較。

- [室外加油站探索測試](validation/2026-09-19-gas-station.md) — 同世界商店／維修間／後院、物資與步行驗證。

- [串流 CPU 效能與回歸檢查](validation/2026-09-18-streaming-performance.md) — `validation/2026-09-18-streaming-performance.md`
- [公路地形與沿途探索驗收](validation/2026-09-15-highway.md) — `validation/2026-09-15-highway.md`
- [RV 系統執行與驗收紀錄](validation/2026-09-15-rv-systems.md) — `validation/2026-09-15-rv-systems.md`
- [密林壓迫感與遠距入口：後續驗收](validation/2026-09-16-dense-forest.md) — `validation/2026-09-16-dense-forest.md`
- [怪物相對速度攀車與兩種破壞模式（2026-09-16）](validation/2026-09-16-monster-boarding.md) — `validation/2026-09-16-monster-boarding.md`
- [破口進出與車內追擊（2026-09-16）](validation/2026-09-16-monster-cabin.md) — `validation/2026-09-16-monster-cabin.md`
- [怪物追蹤與近戰修正（2026-09-16）](validation/2026-09-16-monster-pursuit.md) — `validation/2026-09-16-monster-pursuit.md`
- [室外恐怖氛圍與離路物資點驗收](validation/2026-09-16-outdoor-horror.md) — `validation/2026-09-16-outdoor-horror.md`
- [WAYFARER 車體與駕駛室原型](validation/2026-09-16-rv-cockpit.md) — `validation/2026-09-16-rv-cockpit.md`
- [RV 電池與設備互動修正](validation/2026-09-16-rv-interactions.md) — `validation/2026-09-16-rv-interactions.md`
- [RV 完整組裝、新底盤與可替換引擎驗收](validation/2026-09-16-rv-rebuild-engine.md) — `validation/2026-09-16-rv-rebuild-engine.md`
- [RV 底盤共用儲存與設備入口](validation/2026-09-16-rv-shared-storage.md) — `validation/2026-09-16-rv-shared-storage.md`
- [RV 分片車殼、車門與安裝槽驗收（2026-09-16）](validation/2026-09-16-rv-structure-doors.md) — `validation/2026-09-16-rv-structure-doors.md`
- [世界時間、太陽與日夜霧效 — 2026-09-17](validation/2026-09-17-day-night.md) — `validation/2026-09-17-day-night.md`
- [戶外霧效修正 — 2026-09-17](validation/2026-09-17-fog-refinement.md) — `validation/2026-09-17-fog-refinement.md`
- [室外與 RV 工業恐怖美術驗收](validation/2026-09-17-industrial-art.md) — `validation/2026-09-17-industrial-art.md`
- [正式戶外 D 風格驗收](validation/2026-09-17-outdoor-d.md) — `validation/2026-09-17-outdoor-d.md`
- [工業恐怖美術樣板驗收](validation/2026-09-17-style-sample.md) — `validation/2026-09-17-style-sample.md`
- [局部體積霧 — 2026-09-17](validation/2026-09-17-volumetric-fog.md) — `validation/2026-09-17-volumetric-fog.md`

## 設計研究

- [Lethal Company 視覺風格與 ApocalypseRV 差距研究](research/2026-09-17-lethal-company-visual-direction.md) — `research/2026-09-17-lethal-company-visual-direction.md`
- [《Lethal Company》恐怖氛圍設計研究](research/lethal-company-horror-atmosphere.md) — `research/lethal-company-horror-atmosphere.md`

## 美術目標

- [D：低模與低解析度修正版](art_targets/outdoor/2026-09-17-d-revision.md) — `art_targets/outdoor/2026-09-17-d-revision.md`
- [戶外目標圖：實際生成提示](art_targets/outdoor/2026-09-17-prompts.md) — `art_targets/outdoor/2026-09-17-prompts.md`
- [戶外 gameplay 美術目標圖](art_targets/outdoor/README.md) — `art_targets/outdoor/README.md`

## 歷史封存

- [Climbing and Combat Behavior](archive/2026-09-14/design/climbing-and-combat-behavior.md) — `archive/2026-09-14/design/climbing-and-combat-behavior.md`
- [Player Interaction Flow](archive/2026-09-14/design/player-interaction-flow.md) — `archive/2026-09-14/design/player-interaction-flow.md`
- [RV Equipment Interactions Design](archive/2026-09-14/design/rv-equipment-interactions.md) — `archive/2026-09-14/design/rv-equipment-interactions.md`
- [RV Power and Crafting Design](archive/2026-09-14/design/rv-power-and-crafting.md) — `archive/2026-09-14/design/rv-power-and-crafting.md`
- [World Generation and POI Pipeline](archive/2026-09-14/design/world-generation-and-pois.md) — `archive/2026-09-14/design/world-generation-and-pois.md`
- [World Generation Procedural Buildings](archive/2026-09-14/design/world-generation-procedural-buildings.md) — `archive/2026-09-14/design/world-generation-procedural-buildings.md`
- [ApocalypseRV - 遊戲設計企劃書（GDD）](archive/GDD.md) — `archive/GDD.md`
- [docs 已封存](archive/README.md) — `archive/README.md`
- [Architecture](archive/architecture.md) — `archive/architecture.md`
- [Monster AI Module Contract](archive/modules/monster-ai.md) — `archive/modules/monster-ai.md`
- [Player Traversal and Interaction Module Contract](archive/modules/player-traversal-and-interaction.md) — `archive/modules/player-traversal-and-interaction.md`
- [RV Systems Equipment Module Contract](archive/modules/rv-systems-equipment.md) — `archive/modules/rv-systems-equipment.md`
- [RV Systems Module Contract](archive/modules/rv-systems.md) — `archive/modules/rv-systems.md`
- [World Generation POI System Contract](archive/modules/world-generation-poi-system.md) — `archive/modules/world-generation-poi-system.md`
- [World Generation Procedural Building Module Contract](archive/modules/world-generation-procedural-building.md) — `archive/modules/world-generation-procedural-building.md`
- [World Generation Module Contract](archive/modules/world-generation.md) — `archive/modules/world-generation.md`
- [Monster Underfoot Raycast Single-Path Implementation Plan](archive/superpowers/plans/2026-04-09-monster-underfoot-raycast-single-path.md) — `archive/superpowers/plans/2026-04-09-monster-underfoot-raycast-single-path.md`
- [Monster Underfoot Attack Redesign (Raycast Single Path)](archive/superpowers/specs/2026-04-09-monster-underfoot-raycast-single-path-design.md) — `archive/superpowers/specs/2026-04-09-monster-underfoot-raycast-single-path-design.md`

## 資產與製作規格

- [Original industrial horror materials](../assets/materials/industrial/README.md) — `assets/materials/industrial/README.md`
- [正式戶外 D 風格素材](../assets/materials/outdoor/README.md) — `assets/materials/outdoor/README.md`
- [Concrete wall albedo](../assets/materials/poi_kit/README.md) — `assets/materials/poi_kit/README.md`
- [工業美術樣板材質](../assets/materials/style_sample/README.md) — `assets/materials/style_sample/README.md`
- [WAYFARER RV 模型原型](../rv/visuals/README.md) — `rv/visuals/README.md`
- [POI 資產樣板與製作規格](../world/poi_kit/README.md) — `world/poi_kit/README.md`
- [路旁資產模組](../world/roadside_kit/README.md) — `world/roadside_kit/README.md`
