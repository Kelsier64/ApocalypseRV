# 兩室教學基地：新版階段一

日期：2026-10-15。分支 `codex/starting-tutorial`。本輪只交付[新版計畫](../plans/starting-tutorial-two-room.md)的階段一，等待使用者驗收後才繼續。

## 完成內容

- 正式新局 v12：40 m 寬，20 m 接待室＋40 m 維修室，一道內門及封閉出口。第一室只有牆面終端與海報，RV 停在隔牆後的第二室。整地、植被排除、活動門導航與串流邊界使用獨立場址。
- 終端沿用 Item 固定／拆卸／背包／保存流程，具有內部供電。提示 `Press ENTER to boot the system.`，Enter 後六秒分批捲動 TTY 日誌，完成後切換既有 Conditions／Steps／Controls／Manual TUI。
- 原固定座在開機完成前鎖住。必須完成原終端的正常拆卸並收進背包才開內門；掉落拾取、其他終端、取消及背包滿都不算。通過內門後仍可攜帶閱讀。
- 選中背包中的終端後按 T 閱讀；閱讀器直接引用原物品紀錄，沒有新增第二個 Item 所有權。關閉介面不顯示教學條件 HUD。
- Checkpoint 外層仍為 v5。新版課程使用獨立識別與版本，保存開機進度、原物品 ID／所有權及開門狀態；讀檔驗證失敗保留原世界。舊 v11／v7–v10 不轉換為新版課程。

## 自動檢查

Godot 4.7.2，相關檢查全部通過，未執行完整套件：

| 檢查 | 結果／日誌 |
|---|---|
| `test_orientation_controller`、`test_orientation_shelter`、`test_portable_training_terminal` | PASS；`.godot/test-logs/20261015-125523-607-selected-2960/` |
| `test_orientation_checkpoint`，含實際導航連通及串流保護 | PASS；`.godot/test-logs/20261015-125649-427-selected-44424/` |
| `test_inventory_ui`、`test_item_player`、`test_training_checkpoint`、正式主場景 smoke | PASS；`.godot/test-logs/20261015-125316-229-selected-36188/` |
| `test_road_spawns`、`test_road_spawns_v9`、`test_starting_checkpoint` | PASS；`.godot/test-logs/20261015-125214-419-selected-46688/` |
| 舊 `test_training_terminal` | PASS；`.godot/test-logs/terminal-legacy-subagent.log` |
| 舊 v11 `test_tutorial_checkpoint` | PASS；`.godot/test-logs/orientation-legacy-v11-checkpoint.log`；退出時仍有清理資源警告，見限制 |

新增四支測試已分類到 `tests/suites.json`。中途測試修正的失敗日誌保留，不作為通過證據；最後成功路徑如上。

## 原生畫面觀察

以正式 Forward+ 原生遊戲視窗觀察接待室、牆面固定座與海報；修正海報溢出後再查看。專用 `--terminal-review` 只代為開啟原物品介面，沒有推進教學。使用原生 Enter 驗證提示開始輸出開機文字、完成後出現舊 TUI 的帶走條件，Esc 關閉後回到接待室且沒有教學條件 HUD。原生日誌：`.godot/orientation-native.log`、`.godot/orientation-terminal-native.log`，沒有腳本錯誤。

上述不是完整 WASD 自由遊玩；拆卸、跨房、背包閱讀、存讀檔與門開啟由自動測試驗證，仍待使用者操作驗收。建築遠景與整體美術留在最後階段。

## 驗收入口

在 Godot 開啟 [orientation_playground.tscn](../../tests/orientation_playground.tscn) 按 F6，或執行：

```powershell
godot --path . --log-file .godot/orientation-acceptance.log res://tests/orientation_playground.tscn
```

1. 確認出生於無車接待室，只有終端、海報及建築照明。
2. 靠近牆上終端，長按 E 開啟；Enter 前只有 TTY 提示，不能拆下。
3. 按 Enter，等待約六秒日誌，應自動切到舊 TUI，顯示 `Take this terminal with you.`。
4. Esc 關閉，長按 F 拆下同一終端；成功進入背包後內門開啟並保持開啟。
5. 選中終端，按 T 閱讀；再次打開直接進 TUI。進入第二室後仍可閱讀。
6. 離座、關閉介面並等門停妥後，可使用既有 F6／F9 保存與載入，確認終端及開門狀態保留。

僅檢查初始化介面可加 `-- --terminal-review`；正常 F6／新局沒有這個捷徑。

## 限制與保留變更

- 階段二尚未開始：第二室只提供結構和停放 RV，尚未配置故障、回收／製造設備、物資與修車／加油條件。
- 新版感應離場、正式啟程、說明書解鎖、Restart Stage／Skip Tutorial 及完整重試入口快照留在階段三；第一階段不提供這些操作。
- 最終建築美術、全套海報、更多種子／顯示尺寸、正式全流程自由遊玩與完整套件尚未驗收。未執行輪驅離場。
- 舊 v11 checkpoint 測試通過，但退出回報一個 Jolt shape、511 個 ObjectDB instance 和一個 resource 的清理警告；未宣稱此情境無警告。
- 工作樹原有九區美術、`AGENTS.md`、專案設定、貼圖匯入設定與技能刪除等本機變更均保留。本輪提交不包含它們；`tests/suites.json` 僅提交新增四支測試的分類，原有未提交的 journey 分類留在工作樹。
- 只有本機提交，未推送或建立 PR。
