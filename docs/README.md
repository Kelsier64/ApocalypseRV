# 開發文件索引

| 需求 | 文件 | 責任 |
|---|---|---|
| 啟動遊戲、查按鍵 | [README](../README.md) | 快速開始與統一驗證入口 |
| 理解玩法、數值與未實作願景 | [GDD](../GDD.md) | 現行遊戲設計 |
| 修改程式、查所有權與資料流 | [architecture](../architecture.md) | 現行實作與限制 |
| 找程式、資產來源與清理邊界 | [程式與資產目錄指南](guides/codebase.md) | 目錄責任、引用、存檔相容及驗證 |
| 選擇下一項開發工作 | [計畫總覽](plans/README.md) | 狀態、依賴與剩餘工作 |
| 操作展示場、驗收場景 | [遊玩與測試場指南](guides/playgrounds.md) | 命令、快捷鍵與測試設定 |
| 執行與維護自動測試 | [測試指南](../tests/README.md) | 核心測試、覆蓋範圍與 CI |
| 開發約定 | [AGENTS](../AGENTS.md) | 所有 coding agent 共用的規則與工具 |
| 實作細節、功能契約 | [功能實作契約](guides/feature-contracts.md) | 從 architecture 移出的各功能細節 |
| 查當時的驗收結果 | [驗收紀錄索引](validation/README.md) | 依日期列出的歷史紀錄 |

## 文件分類

| 位置 | 內容 |
|---|---|
| 根目錄 `README.md`、`GDD.md`、`architecture.md` | 現行入口、設計與架構 |
| `guides/` | 各領域的工作方式與實作契約 |
| `plans/` | 進行中的計畫與狀態 |
| `validation/`、`report/` | 有日期的歷史紀錄，不代表現況 |
| `archive/` | 封存，內容保持原樣 |

現況以程式為準；寫作與放置規則見 `docs-maintenance` skill。

## 開發計畫

狀態與證據見[計畫總覽](plans/README.md)。

## 指南

- [Raker 資產建置入口](guides/asset-builds.md)
- [隨機軍事地堡：房型製作與保存契約](guides/bunker-interior.md)
- [可動 3D 角色製作與接入規格](guides/character-modeling.md)
- [程式與資產目錄指南](guides/codebase.md)
- [功能實作契約](guides/feature-contracts.md)
- [目前功能總覽](guides/features.md)
- [單圖 → 3D → 減面 → 驗收操作指南](guides/image-to-3d-workflow.md)
- [舊室內 v2 規格已被取代](guides/interior-v2.md)
- [廢棄巨型住宅外殼：室外外殼製作指南](guides/megashelter-exteriors.md)
- [巨型避難所室內](guides/megashelter-interiors.md)
- [灰階暗部顯示與曲線](guides/night-vision.md)
- [遊玩與測試場指南](guides/playgrounds.md)
- [POI 共用製作與接入規範](guides/poi-authoring.md)
- [白影遭遇](guides/white-apparition.md)

## 審查報告

- [2026-09-22 架構、潛在問題與遺產清理審查](report/ApocalypseRV_Architecture_Audit_2026-09-22.md) — 保留當時重現證據；A04 離場保存已由下方地堡內容更新修正，A01–A03 仍待處理。
- [R01–R07 修正與驗收](report/ApocalypseRV_Fixes_2026-09-18.md) — `report/ApocalypseRV_Fixes_2026-09-18.md`
- [ApocalypseRV 專案審查與修改建議](report/ApocalypseRV_Review_2026-09-18.md) — `report/ApocalypseRV_Review_2026-09-18.md`

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

- [建模 prompt](modeling/README.md) — 簡單物件直接做；複雜物件用灰盒與一份 [短 prompt](modeling/TEMPLATE.md)，不另維護進度清單。
- [2026-09-29 資產盤點與來源快照](archive/modeling-2026-09-29/inventory.md) — 歷史參考，不再日常更新；[來源說明](archive/modeling-2026-09-29/asset-provenance.md)。

- [Original industrial horror materials](../assets/materials/industrial/README.md) — `assets/materials/industrial/README.md`
- [正式戶外 D 風格素材](../assets/materials/outdoor/README.md) — `assets/materials/outdoor/README.md`
- [Concrete wall albedo](../assets/materials/poi_kit/README.md) — `assets/materials/poi_kit/README.md`
- [工業美術樣板材質](../assets/materials/style_sample/README.md) — `assets/materials/style_sample/README.md`
- [WAYFARER RV 模型原型](../rv/visuals/README.md) — `rv/visuals/README.md`
- [POI 資產樣板與製作規格](../world/poi_kit/README.md) — `world/poi_kit/README.md`
- [路旁資產模組](../world/roadside_kit/README.md) — `world/roadside_kit/README.md`
