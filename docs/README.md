# 文件索引

現況以程式為準。文件只寫程式讀不出來的事：設計意圖、跨檔案的規則、製作流程，以及還沒做的事。

## 依需求找文件

| 需求 | 文件 |
|---|---|
| 啟動、按鍵、終端指令 | [README](../README.md) |
| 設計意圖、玩家會遇到的規則、未實作方向 | [GDD](../GDD.md) |
| 模組責任、狀態所有權、共用契約、已知限制 | [architecture](../architecture.md) |
| 某個系統目前的功能、數值與實作 | 下方[系統](#系統) |
| 怎麼製作或操作某樣東西 | 下方[指南](#指南) |
| 進行中的工作、待人工驗收、待辦 | [計畫總覽](plans/README.md) |
| 還沒修的 bug、崩潰、不穩定的測試 | [已知問題](../ISSUES.md) |
| 自動測試的範圍與命令 | [tests/README](../tests/README.md) |
| agent 的專案規則 | [CLAUDE.md](../CLAUDE.md)、[AGENTS.md](../AGENTS.md) |

## 系統

每個系統一份，結構相同：功能一覽、規則與數值、實作契約。改某個系統前先讀對應的那一份。

| 文件 | 範圍 |
|---|---|
| [opening](systems/opening.md) | 兩室教學基地、故障車整備、出庫與啟程 |
| [player](systems/player.md) | 移動、體力、生命與死亡、斷肢、飢餓、SAN、列印身體 |
| [items](systems/items.md) | Item 契約、背包、固定放置與支撐、倉庫、手持物 |
| [rv](systems/rv.md) | 底盤、駕駛、輪胎、引擎、車殼、施工、車損 |
| [economy](systems/economy.md) | 燃油、電力、材料、分解、製作、配方、車載平板 |
| [world](systems/world.md) | 世界入口、生成、道路與地形、串流、細節層、公路生成 |
| [poi](systems/poi.md) | 加油站、路旁與越野場址、地堡、巨型避難所、副本轉場 |
| [enemies](systems/enemies.md) | Raker、油桶人、Slender Speaker、白影、攀車與選敵、偏行壓迫 |
| [environment](systems/environment.md) | 日夜、天氣、霧、暗部顯示、美術方向、HUD 與設定 |
| [saves](systems/saves.md) | F6／F9 檢查點的範圍、驗證與凍結政策 |

這些文件大多已經逐段對照程式改寫。`player`、`rv`、`enemies` 三份還是由舊文件合併而成的版本，段落裡仍有當時的日期與版本號，會跟著架構重構一起改寫。內容與程式不符時以程式為準，並直接改掉那一段。還沒改寫的清單在[計畫總覽](plans/README.md#待辦)。

## 指南

| 指南 | 用途 |
|---|---|
| [程式與資產目錄](guides/codebase.md) | 目錄責任、引用方式、整理與刪除前的檢查 |
| [測試場](guides/playgrounds.md) | 各測試場的用途、情境與啟動命令 |
| [宣傳影片錄影](guides/promo-capture.md) | 錄影面板、即時錄影與自動演出、自由鏡頭、跟拍、運鏡路徑、各鏡頭分組 |
| [POI 製作](guides/poi-authoring.md) | 房間、家具、入口的製作與接入規範 |
| [建築 kit](guides/building-kit.md) | 共用建築零件、材質色盤、建築製作關卡與多角度審查圖 |
| [地堡房型](guides/bunker-interior.md) | 軍事地堡房型的製作與保存契約 |
| [巨型避難所外殼](guides/megashelter-exteriors.md) | 程序化外殼的零件與生成規則 |
| [巨型避難所室內](guides/megashelter-interiors.md) | 室內模組、轉場與保存 |
| [角色建模](guides/character-modeling.md) | 可動角色的製作與接入規格 |
| [單圖轉 3D](guides/image-to-3d-workflow.md) | 工具、交付規則與模型需求的寫法 |
| [暗部顯示](guides/night-vision.md) | 灰階暗部曲線的欄位與調整方式 |

## 計畫

[計畫總覽](plans/README.md)列出進行中的計畫、已實作但還沒人工驗收的項目，以及待辦。每個進行中的計畫一份檔案。

## 參考資料

`reference/` 放設計時對照用的材料，不描述現況。

| 位置 | 內容 |
|---|---|
| [reference/research/](reference/research/lethal-company-horror-atmosphere.md) | Lethal Company 的恐怖氛圍與視覺方向研究 |
| [reference/art_targets/outdoor/](reference/art_targets/outdoor/README.md) | 戶外美術目標圖與生成提示；正式採用 D 方向 |
| [reference/art/](reference/art/modular-megashelter/README.md) | 巨型避難所的美術基準與早期概念圖 |
| `reference/ref_picture/` | 使用者提供的風格參考圖 |
| `reference/mockups/` | 介面草稿 |

## 寫在程式旁邊的說明

資產的來源、製作參數與匯入設定寫在資產旁的 README（`assets/`、`art_source/`、`world/` 下各資料夾）。這類說明只談那個資料夾裡的東西。

## 文件規則

- **一件事只寫在一個地方。** 設計意圖在 GDD，跨模組的結構在 architecture，單一系統的行為在 `systems/`，做法在 `guides/`，還沒完成的事在 `plans/`，還沒修的 bug 在 [ISSUES.md](../ISSUES.md)。其他地方用連結，不重抄。
- **只寫現況。** 事實改變時直接改掉舊句子，不加日期註記，不寫「本輪」「這次」。
- **不留歷史。** 之後用不到的文件直接刪除，歷史在 git。沒有封存資料夾，也不寫逐次的驗收紀錄。
- **設計一定要寫回文件。** 討論中定案的新設計或改動，在同一個變更裡更新 GDD 與對應的系統文件。
- **驗證結果寫在 commit 或 PR。** 已實作但還沒人工驗收的項目，列在[計畫總覽](plans/README.md#待人工驗收)。
- **會變的數字不寫死。** 版本、測試數、檔案數寫出處（常數或檔案），不寫數值。

agent 的操作步驟在 `docs-maintenance` skill。
