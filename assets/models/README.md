# 匯入模型入口

目前執行期引用的模型在 `gas_station/`、`monster/`、`raker/`、`player_test_v020/` 與 `player_animations_v021/`；尺度、匯入、用途及需要保留的來源／授權資訊記在各資產自己的 README，不另維護全域 manifest。

- `player_test_v020/player_export_test_v020.glb` 雖帶 `test` 名稱，仍是正式玩家外觀；`player_animations_v021/player_animations_v021.glb` 只供執行期擷取動畫，並不替換 v020 的 mesh、材質或骨架 rest pose。
- `monster/monster_export_test.glb` 仍由 Zombie actor 使用，支援舊存檔還原與測試；新戶外生成使用 Raker。未確認 Zombie 目前有室內自然生成路徑。
- `raker/raker.glb` 是正式 v021 外觀。v009–v020 的製作版本保留在 `art_source/monster_refined_vNNN/`，不是額外的執行期模型。
- 原 `assets/gas_can.glb`、`assets/oil_barrel.glb` 及配套貼圖／匯入設定已收存到 `art_source/retired_props/2026-09-29/`；道具場景路徑保留並改用 Godot 原生灰盒。

需要追查舊資料時，可看 [2026-09-29 來源快照](../../docs/archive/modeling-2026-09-29/asset-provenance.md)，內容不代表目前狀態；不得由檔名中的 `test` 或目前沒有主場景文字引用推定可刪除。
