# 程式與資產目錄指南

本指南是找檔案、追資源依賴及整理目錄的入口。遊戲操作見 [README](../../README.md)，執行期所有權與資料流見 [architecture](../../architecture.md)。

## 從入口追程式

`project.godot` 指向 `world/test_world.tscn`，並註冊 `rv/checkpoint.gd` 為 Checkpoint autoload。場景中的 `ext_resource` 連結腳本、子場景和資源；GDScript 也會以 `load`／`preload` 或場景路徑載入資源。修改路徑前，先查場景引用與程式中的路徑字串。

| 目錄 | 主要責任 | 入口例子 |
|---|---|---|
| `core/` | 共用契約、支撐、識別碼、存檔場景白名單 | `save_scene_catalog.gd`、`rv_support.gd` |
| `player/` | 玩家移動、攀爬、互動、背包和外觀 | `player.tscn` |
| `enemies/` | 殭屍、Raker、選敵、追擊及攻擊 | `zombie.tscn`、`raker.tscn` |
| `props/` | 地面與背包可搬運物件 | `prop.gd`、道具場景 |
| `rv/` | 底盤、輪胎、車況、能源、檢查點及 RV 視覺 | `new_rv.tscn`、`chassis.tscn` |
| `equipment/` | 可安裝設備、車殼、互動與定義 | `equipment.gd`、各設備場景 |
| `world/` | 主世界、地形串流、POI、建築與室內生成 | `test_world.tscn`、`terrain/`、`instances/` |
| `assets/` | 執行期貼圖、模型、圖示與材質 | 模型旁的 README 與匯入設定 |
| `art_source/` | 可重建資產的 Blender 來源、製作腳本和審核圖 | Raker 各版與玩家動畫來源 |
| `scripts/` | 資產建置、效能量測、回放及統一測試入口 | `test.ps1` |
| `tests/` | `test_*.gd` 自動測試、獨立展示場及測試資產 | `main_scene_smoke.gd` |
| `docs/` | 現行指南、計畫、驗收、研究；`archive/` 保存歷史 | [文件索引](../README.md) |

`world/poi_kit/`、`world/roadside_kit/` 與 `world/roadside_pois/` 是內容製作層；場景可能由定義、生成器或測試場動態載入。`rv/legacy/`、`world/art_sample/` 與 `assets/materials/style_sample/` 是仍有展示或對照用途的資產。獨立的 `tests/*playground.tscn` 不會由主場景引用，但可直接執行，操作見 [展示場指南](playgrounds.md)。

匯入模型用途見 [模型入口](../../assets/models/README.md)，來源與授權資訊有需要時記在各資產 README。建模需求使用 [短 prompt](../modeling/README.md)，不另維護全域清單；舊來源與使用關係可查 [2026-09-29 歷史盤點](../archive/modeling-2026-09-29/inventory.md)。

## 資源與存檔相容

- `res://` 路徑和 Godot UID 都是引用入口；搬移或刪除場景、腳本時要檢查兩者。與仍在使用的腳本／資產成對的 `.gd.uid`／`.import` 檔應保留。
- `SaveSceneCatalog` 會根據存檔中的場景路徑動態載入白名單項目。未在主場景文字中出現，不代表可刪；例如 `equipment/rv_floor.tscn` 仍列於白名單，供舊檔讀取。
- `Checkpoint` 和 `VehicleSnapshot` 在驗證及實例化前，將舊 `fuel_tank`、`material_rack`、`material_bundle` 路徑轉成現行油量、材料及設備資料。舊路徑字串是遷移契約，雖然對應的舊場景已移除，仍要保留並測試。
- `art_source/` 和建置腳本保存可編輯來源；`docs/validation/` 保存當次證據。圖片或模型未被主場景直接引用，也可能是匯入來源、展示場或審核證據。

## 整理與驗證

新增遊戲行為時，將場景放在擁有該行為的模組；共享純邏輯放 `core/`，正式資產放 `assets/`，可重建來源放 `art_source/`。測試與獨立展示場放 `tests/`。文件依 [索引](../README.md) 放入指南、計畫或驗收；歷史紀錄留在 `docs/archive/`。

刪除候選先查 `res://` 路徑、UID、`class_name`、場景的 `ext_resource`、程式中的動態組字路徑、存檔白名單、測試與製作腳本。確認舊存檔會先轉換，再移除已無消費者的檔案。完成後從乾淨匯入開始執行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

Runner 會匯入資源、執行根層 `tests/test_*.gd` 並檢查主場景啟動；Godot 4.7.2 必須可由 PATH 找到，或使用 `-Godot 'C:/path/to/godot.exe'`。日誌在 `.godot/test-logs/`。涉及畫面或物理時，再按 [AGENTS](../../AGENTS.md) 與展示場指南做實機檢查。本次清理範圍與實際檢查另記於 [整理紀錄](../validation/2026-09-28-codebase-cleanup.md)。
