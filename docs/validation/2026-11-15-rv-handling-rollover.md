# RV 操控、翻車與救援驗證

2026-11-15，Godot 4.7.2／Jolt。開發分支為 `codex/rv-handling-rollover`，基準 `8f10a952`。規格見 [操控與翻車計畫](../plans/2026-11-14-rv-handling-rollover.md)。

## 自動測試

```powershell
./scripts/test.ps1 -KeepGoing -TimeoutSeconds 480
```

21 支核心測試和 1 項正式主場景檢查全數通過，匯入成功。完整紀錄在 `.godot/test-logs/20261115-011807-617-all-27564/`。

- [操控測試](../../tests/test_rv_handling.gd)以正式 RV 在平地起速 19 m/s 滿舵，量到明顯輪胎滑移與約 3.9° 側傾，未翻車。陡側坡可失去正立姿態。低路肩橫撞使撞擊側兩輪爆胎並越過側躺門檻。
- [翻車測試](../../tests/test_rv_rollover.gd)驗證倒置後車頂承重，撞擊扣屋頂耐久，引擎保持耐久但無法發動，駕駛可短按 E 到車外。毀壞面板後對應底盤碰撞關閉。
- [乘員](../../tests/test_rv_crash_injury.gd)與[跳車](../../tests/test_moving_rv_climbing.gd)測試驗證座位減傷、事故去重、甩飛慣性、固定種子斷肢、低速離車無傷，以及高速落地／撞牆只結算一次。
- [千斤頂測試](../../tests/test_recovery_jack.gd)從倒置快照重建車輛、還原獨立千斤頂，利用實體力完成兩段扶正，再透過工作台製作實體成品。[教學出庫](../../tests/test_orientation_departure.gd)也驗證第二室有一支千斤頂。

## 正式道路回放

```powershell
godot --headless --path . --fixed-fps 60 res://tests/highway_playground.tscn -- --replay --from=70 --to=295
godot --headless --path . --fixed-fps 60 res://tests/highway_playground.tscn -- --parking
godot --headless --path . --fixed-fps 60 res://tests/highway_playground.tscn -- --replay --from=1660 --to=1900
```

固定 seed 42 從 70 m 行駛至 294.6 m 停住。路邊停靠回放完成低速進站、倒出和回到公路。山路從 1660 m 行駛至 1899.3 m 停住，爬升 37.7 m，最大橫向偏差 0.16 m。回放皆使用正式輪胎力，保留地形和路旁碰撞。

## 試玩

F2–F6 五站均通過無頭啟動。已檢視千斤頂在正式材質和倒置 RV 旁的 OpenGL 截圖，保留在 `.godot/recovery-jack-playground.png`。駕駛手感、失衡、鏡頭與音效仍待人工試玩。[測試場操作](../guides/playgrounds.md#rv-操控與翻車救援)
