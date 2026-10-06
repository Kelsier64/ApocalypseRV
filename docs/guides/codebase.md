# 程式與資產目錄指南

本指南是找檔案、追資源依賴及整理目錄的入口。遊戲操作見 [README](../../README.md)，執行期所有權與資料流見 [architecture](../../architecture.md)。

## 從入口追程式

`project.godot` 指向 `world/main_world.tscn`（`test_world.tscn` 保留為 legacy 測試場），並註冊 `rv/checkpoint.gd` 為 Checkpoint autoload。場景中的 `ext_resource` 連結腳本、子場景和資源；GDScript 也會以 `load`／`preload` 或場景路徑載入資源。修改路徑前，先查場景引用與程式中的路徑字串。

| 目錄 | 主要責任 | 入口例子 |
|---|---|---|
| `core/` | 共用契約、支撐、識別碼、存檔場景白名單 | `save_scene_catalog.gd`、`rv_support.gd` |
| `player/` | 玩家移動、攀爬、互動、背包和外觀 | `player.tscn` |
| `enemies/` | Raker、共用怪物行為、選敵、追擊及攻擊 | `raker.tscn`、`monster.gd` |
| `props/` | 共用 Item 基類與地面／背包物品 | `item.gd`、道具場景 |
| `rv/` | 底盤、輪胎、車況、能源、檢查點及 RV 視覺 | `new_rv.tscn`、`chassis.tscn` |
| `equipment/` | 原設備的 Item 功能腳本、場景，以及獨立車殼結構 | `generator.gd`、`scrapper.gd`、各場景 |
| `world/` | 主世界、地形串流、POI、建築與室內生成 | `main_world.tscn`、`starting_shelter/`、`terrain/`、`instances/` |
| `assets/` | 執行期貼圖、模型、圖示與材質 | 模型旁的 README 與匯入設定 |
| `art_source/` | 可重建資產的 Blender 來源、製作腳本和審核圖 | Raker 各版與玩家動畫來源 |
| `scripts/` | 資產建置、效能量測、回放及統一測試入口 | `test.ps1` |
| `tests/` | `test_*.gd` 自動測試、獨立展示場及測試資產 | `main_scene_smoke.gd` |
| `docs/` | 現行指南、計畫、驗收、研究；`archive/` 保存歷史 | [文件索引](../README.md) |

`world/poi_kit/`、`world/roadside_kit/` 與 `world/roadside_pois/` 是內容製作層；場景可能由定義、生成器或測試場動態載入。`rv/legacy/`、`world/art_sample/` 與 `assets/materials/style_sample/` 是仍有展示或對照用途的資產。獨立的 `tests/*playground.tscn` 不會由主場景引用，但可直接執行，操作見 [展示場指南](playgrounds.md)。

匯入模型用途見 [模型入口](../../assets/models/README.md)，來源與授權資訊有需要時記在各資產 README。建模需求使用 [短 prompt](../modeling/README.md)，不另維護全域清單；舊來源與使用關係可查 [2026-09-29 歷史盤點](../archive/modeling-2026-09-29/inventory.md)。

## 資源與存檔相容

- `res://` 路徑和 Godot UID 都是引用入口；搬移或刪除場景、腳本時要檢查兩者。與仍在使用的腳本／資產成對的 `.gd.uid`／`.import` 檔應保留。
- `SaveSceneCatalog` 根據存檔場景路徑載入白名單中的一般設備與道具；車體結構從 `RVStructureSlots` 的型態目錄建立。`equipment/rv_floor.tscn` 是正式地板結構，由固定地板槽擁有，不是可搬移設備。
- `props/item.gd` 是唯一可搬運基類；`core/item_definition.gd` 集中物品定義，`core/item_state.gd` 驗證所有所有權領域的狀態，`core/item_mount.gd` 管理固定支撐與掉落。原 Prop／Equipment 基類已移除，不再按這兩種類型分流背包、回收或世界保存。
- `Checkpoint` 和 `VehicleSnapshot` 僅接受 v5，預設 `user://rv_checkpoint_v5.save`；v1–v4 拒絕並提示重新開局，不轉換舊油箱、材料架、材料包或長牆，也不改寫舊存檔／備份。結構、耐久、破口及門角度獨立保存；Item 支撐明確區分底盤、Item ID、結構槽位與靜態場景錨點。
- 結構目錄包含普通 `rv_ceiling` 與左側開孔 `rv_ceiling_hatch`，都能裝入 `roof_0`／`roof_1`／`roof_2`；總布局十二槽，屋頂每片 50 kg／120 HP。Snapshot 版本為 v5，舊版（包含早期十槽／單片屋頂）資料拒絕載入，不自動轉換。
- `art_source/` 和建置腳本保存可編輯來源；`docs/validation/` 保存當次證據。圖片或模型未被主場景直接引用，也可能是匯入來源、展示場或審核證據。

## 整理與驗證

新增遊戲行為時，將場景放在擁有該行為的模組；共享純邏輯放 `core/`，正式資產放 `assets/`，可重建來源放 `art_source/`。測試與獨立展示場放 `tests/`。文件依 [索引](../README.md) 放入指南、計畫或驗收；歷史紀錄留在 `docs/archive/`。

刪除候選先查 `res://` 路徑、UID、`class_name`、場景的 `ext_resource`、程式中的動態組字路徑、存檔白名單、結構型態目錄、測試與製作腳本。確認現行存檔與仍使用中的測試場沒有消費者，再移除無用檔案；歷史文件保留。完成後從乾淨匯入開始執行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Suite full
```

Runner 的 `full` 會匯入資源、執行全部有效的根層測試並檢查正式主場景啟動；預設命令只跑快速行為集，詳細選擇與分類見 [測試指南](../../tests/README.md)。Godot 4.7.2 必須可由 PATH 找到，或使用 `-Godot 'C:/path/to/godot.exe'`。日誌在 `.godot/test-logs/`。涉及畫面或物理時，再按 [AGENTS](../../AGENTS.md) 與展示場指南做實機檢查。本次清理範圍與實際檢查另記於 [整理紀錄](../validation/2026-09-28-codebase-cleanup.md)。
