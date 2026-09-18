# 開發文件索引

整理日期：2026-09-18。`docs/` 包含現行指南、計畫、驗收、研究與美術目標；只有 `docs/archive/` 是歷史封存區。

## 從哪裡開始

| 需求 | 文件 | 責任 |
|---|---|---|
| 啟動遊戲、查按鍵 | [README](../README.md) | 快速開始與統一驗證入口 |
| 理解玩法、數值與未實作願景 | [GDD](../GDD.md) | 現行遊戲設計 |
| 修改程式、查所有權與資料流 | [architecture](../architecture.md) | 現行實作與限制 |
| 選擇下一項開發工作 | [計畫總覽](plans/README.md) | 狀態、依賴與剩餘工作 |
| 操作展示場、驗收場景 | [遊玩與測試場指南](guides/playgrounds.md) | 命令、快捷鍵與測試設定 |
| 開發約定 | [AGENTS](../AGENTS.md)、[CLAUDE](../CLAUDE.md) | 協作與工具指引 |
| 原始想法 | [todo](../todo)、[todo_for_ai](../todo_for_ai) | 原樣保留，不視為目前完成狀態 |

## 文件維護規則

- README 保持快速入口；玩法規則與數值放 GDD，技術契約放 architecture，展示場細節放指南。
- 現況與程式不符時核對程式、場景與測試後修正文檔；計畫提案與研究建議不自動成為現有功能。
- 計畫標明已實作、部分實作、待實作或已被取代的範圍，附驗收連結。新增功能按主題併入現行文件，避免在首尾不斷追加日期章節。
- 驗收與審查報告保留當時版本、環境、結果與限制；修正結果另留紀錄，不把歷史測試寫成當前重新通過。
- `docs/archive/` 內文與歷史規格保留原樣。舊相對連結可能失效，以下提供目前位置的直接入口。

## 開發計畫

完整狀態與證據見 [計畫總覽](plans/README.md)。

## 指南

- [遊玩與測試場指南](guides/playgrounds.md) — `guides/playgrounds.md`

## 審查與修正

- [R01–R07 修正與驗收](report/ApocalypseRV_Fixes_2026-09-18.md) — `report/ApocalypseRV_Fixes_2026-09-18.md`
- [ApocalypseRV 專案審查與修改建議](report/ApocalypseRV_Review_2026-09-18.md) — `report/ApocalypseRV_Review_2026-09-18.md`

## 驗收紀錄

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
