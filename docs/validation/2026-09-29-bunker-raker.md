# 地堡 Raker 遭遇與舊怪物移除

2026-09-29，Windows／Godot 4.7.2 stable。依使用者要求，僅使用命令列 headless 測試，沒有 computer use 或人工畫面驗收。

## 變更

- 移除 Zombie 場景、專用 GLB 與匯入設定，正式載入白名單只接受 Raker。共用的 `Monster` 行為和 Raker 使用的視覺傷害效果保留。
- 新訪地堡最多取 `clamp(房間數 / 15, 1, 4)` 個足夠遠的合格房間作遭遇機會；每個機會獨立擲 30%，成功且有安全放置點才生成。目前敵人候選池只有 Raker，池內有權重欄位供未來增加種類。生成數可能為 0、1 或多隻，最多 4 隻。
- 生成只消耗地堡內容專用 RNG；相同 seed／副本 ID 可重現結果。回訪從存檔還原存活怪物，不重擲機率或復活死亡怪物。
- 讀取舊檢查點時，已不在專案中的敵人場景會從主世界、POI 和未載入戶外站點的 actor 清單略過；其他物品、車輛與地堡布局／內容仍受原驗證規則保護並保留。缺失的道具場景仍拒絕讀取。
- 三套只針對舊 Zombie 數值／行為的測試退役；現行 Raker 追擊、車內與攀車行為由 Raker 專用套件驗證。歷史驗收紀錄保留當時結果。

## 驗證

完整命令：

```powershell
$env:APPDATA = Join-Path (Get-Location) '.godot/raker-transition-user'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Godot 'C:\Users\evan4\AppData\Local\Programs\Godot\Godot.exe'
```

Runner 退出碼 0：資產匯入、**81 套 `test_*.gd`** 與主場景 `WORLD_READY_FOR_PLAY` 全部通過。日誌在 `.godot/test-logs/`，`manifest.txt` 記錄測試清單。自動測試改寫的歷史 `skinned_bounds.json` 已還原；沒有把量測產物納入本輪變更。

重點覆蓋：

| 測試 | 覆蓋 |
|---|---|
| `test_bunker_content` | 多個 seed 的零隻、一隻、多隻結果；相同 seed 結果固定；內容、導航與回訪快照 |
| `test_bunker_encounter` | 真實 Raker 在室內發現、追近並傷害玩家；受傷生命與死亡不重生 |
| `test_checkpoint_failures` | 缺失敵人場景從三種位置略過，保留道具與 POI 內容；缺失道具仍拒絕 |
| `test_monster_model`、`test_moving_rv_climbing`、`test_outdoor_encounter` | Raker 模型傷害回饋、RV 攀爬與戶外遭遇 |
| `test_raker*` | Raker 攻擊、抓咬、車內、攀車、動畫及控制回復 |

對現行 `.gd`／`.tscn`／`.tres` 做不分大小寫 Zombie 引用搜尋，結果為零。歷史設計、審查與驗收文件保留當時用語。

## 邊界

- 30% 是每個合格遭遇機會的機率，不保證整座地堡有怪。放置點不足時實際生成量會更低。
- 舊存檔中已刪除場景的怪物會消失；其餘資料保留。人工自由遊玩、主觀難度與畫面表現尚未驗收。
