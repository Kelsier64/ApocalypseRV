# 2026-09-28 程式庫與文件整理

## 範圍與依據

依 [2026-09-22 架構審查的遺產候選](../report/ApocalypseRV_Architecture_Audit_2026-09-22.md) 重新核對目前工作樹的場景、腳本、`res://` 路徑、UID、存檔白名單及測試 fixture。清理只涵蓋能確認已無執行期或製作用途的檔案；歷史審查仍保留當時的原始判斷。

| 處理 | 檔案／內容 | 依據 |
|---|---|---|
| 移除舊服務設備，共 10 檔 | `equipment/fuel_tank.gd`、`.gd.uid`、`.tscn`、`fuel_tank_definition.tres`；`material_rack.gd`、`.gd.uid`、`.tscn`、`material_rack_definition.tres`；`material_storage_ui.gd`、`.gd.uid` | 現行服務場景是 `fuel_port` 與 `item_box`；舊設備沒有場景或程式消費者。 |
| 移除舊材料包，共 3 檔 | `props/material_bundle.gd`、`.gd.uid`、`.tscn` | 新資料只保存材料數量；舊包路徑在載入時先轉換。 |
| 移除重複底盤外觀，1 檔 | `rv/visuals/chassis_trim.tscn` | 無場景或腳本實例；正式 `rv/chassis.tscn` 已有底板、接縫與保險桿。 |
| 移除死碼 | `Equipment.get_half_extents`／`hold_timer`、`WheelHitbox.hold_timer`、`Chassis.EMPTY_GAS_CAN_*`／`_set_fuel`／`_set_power` | 全專案引用檢查沒有呼叫點；相關現行方法及訊號保留。 |

`rv/checkpoint.gd`、`rv/vehicle_snapshot.gd` 的舊路徑字串和 `tests/test_rv_shared_storage.gd` fixture 保留；它們是 v1／v2 資料轉換契約。`equipment/rv_floor.tscn` 仍在 `SaveSceneCatalog` 白名單中，繼續保留。獨立展示場、動態組字載入的 roadside kit、GLB 匯入資產、`art_source/` 製作來源、原始 `todo` 和 `docs/archive/` 沒有納入刪除。

## 文件更新

新增 [程式與資產目錄指南](../guides/codebase.md)，把目錄責任、動態資源路徑、存檔相容與清理檢查集中在一處。同步更新根目錄 [README](../../README.md)、[GDD](../../GDD.md)、[architecture](../../architecture.md)、[開發計畫](../plans/README.md)、[文件索引](../README.md) 及 [RV 視覺說明](../../rv/visuals/README.md)。新世界生成版本現為 v6；檢查點格式仍是 v3。歷史驗收的結果沒有改寫為本次測試結果。

## 本次檢查

| 檢查 | 結果 |
|---|---|
| 追蹤的 `.tscn`／`.tres` 中 `ext_resource path="res://…"` 檔案存在性 | 缺失 0 |
| 程式與場景的字面 `res://` 路徑（排除遷移字串、故意不存在的測試路徑及輸出路徑） | 意外缺失 0 |
| 已刪 `.gd.uid` 的 UID 是否仍在作用中的 Godot 文字資源中引用 | 引用 0 |
| 非 `docs/archive/` 的 112 份 Markdown 相對連結 | 缺失 0 |
| `git diff --check` | 通過 |
| `scripts/test.ps1` 完整匯入、測試與主場景啟動 | 無法執行：本機找不到 Godot 執行檔，`godot` 不在 PATH |

上述靜態檢查不能代替 Godot 匯入、v1／v2 保存轉換測試或實機操作。取得 Godot 4.7.2 後，從根目錄執行 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Godot 'C:/path/to/godot.exe'`；畫面與物理場景另按 [AGENTS](../../AGENTS.md) 驗收。
