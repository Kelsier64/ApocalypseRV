# 教學基地階段二驗證

2026-10-13，分支 `codex/starting-tutorial`。階段一已驗收；本次交付階段二，報告後等待使用者驗收。不提前實作下一階段；未跑完整套件。

## 完成內容

- RV 駕駛室左前牆的 `TrainingTerminal extends Item`：英文 Conditions／Steps／Controls／Manual，沿用拾取、背包、固定／拆卸、支撐掉落、供電、回收及保存；不能授權 rvctl 車體施工。首張實體民防海報指向車內終端，沒有按鍵或過關清單。
- `StartRun/Tutorial` 持有指定終端、RV、手電筒 ID 與首關進度。只有玩家實際看見指定終端的 Conditions 頁才算查看；讀檔、拒絕互動、其他頁面及其他 ID 不算。
- 第一關：拾取指定手電筒，實際輪驅依序穿過 Z −372／−342 標記，倒車至少 4 m，整車停在 X ±3.5、Z −371～−353 框內，手煞車及熄火。要求至少三輪接地、低速／低角速度，一秒內水平位置範圍不超過 10 cm，容許既有懸吊微幅抖動。完成後首道門自動開啟並保持開啟；下一道門鎖定。
- 教學維持 preparing，時間、天氣與敵人停止；新局燃油 40，燃油保底 10，有效已装電池電量保底 20。空槽不補電池，保底不算成功交易；關閉終端後沒有教學 HUD。
- `capture_world()`／`load_snapshot()` 沿用隔離驗證後替換。Checkpoint 外層 v5、tutorial v1；入口快照禁止遞迴嵌套，現況及入口分別檢查 ID／所有權。重試恢復精確入口，失敗保留當前世界，不覆寫手動檔。終端遺失後仍可透過 Esc 的 Restart Stage 復原。

## 自動驗證

本階段以下項目全部通過；新增三個測試已分類於 `tests/suites.json`。

| 測試 | 時間 | 日誌組 |
|---|---:|---|
| `test_checkpoint_failures` | 17.68 s | A |
| `test_item_persistence` | 2.83 s | A |
| `test_item_services` | 2.45 s | A |
| `test_settings_menu` | 3.31 s | A |
| `test_tutorial_checkpoint` | 38.14 s | A |
| `test_training_checkpoint` | 25.87 s | B |
| `test_training_driving` | 23.41 s | C |
| `test_training_terminal`（版面修正後） | 3.27 s | D |
| 主場景啟動（最終整合） | 10.28 s | D |

- A：`.godot/test-logs/20261013-101102-986-selected-40532/`。同次首關測試曾暴露問題；表內只列通過項目，修正後結果另列 B／C。
- B：`.godot/test-logs/20261013-101544-395-selected-38312/`。
- C：`.godot/test-logs/20261013-102909-414-selected-43968/`。
- D：`.godot/test-logs/20261013-103519-703-selected-42788/`。

輪驅測試没有設定玩家／RV 位置或速度來通關；前進峰值 1.88 m/s、倒車 1.34 m/s。覆蓋未過第二標記就停車、錯誤終端通知、只有 Steps 頁、空電池槽、手動開門與提早啟程等拒絕情境，以及通關後第二關入口快照。保存測試包括檔案往返、損壞快照、套用失敗、逾時、精確重試、終端遺失後實際 Esc 確認，以及手動檔位元組保持不變。v7 實際恢復及 v7–v10 格式相容由對應測試覆蓋。

重跑首關：`scripts/test.ps1 -TestFilter test_training_driving.gd`；終端及啟動：`scripts/test.ps1 -TestFilter test_training_terminal.gd -Smoke`。本機以 `-Godot` 指定 `C:\Users\evan4\AppData\Local\Programs\Godot\Godot_console.exe`。

## 原生畫面觀察

透過 computer-use／`@oai/sky` 選取專用遊戲視窗，在 Forward+、1280 × 720 檢查海報對比、終端貼牆及避開窗框、條件／步驟／按鍵頁、鎖定 Manual、Esc 關閉後不留下教學頁面。保留目前較暗的基地照明。新增 MeshInstance3D 面數：終端 288、海報架及地面標記 144，共 432，不含文字字形。

審查使用忽略目錄內的固定相機工具，沒有手動駕駛完整首關；輪驅及重試證據來自自動測試。日誌：`.godot/tutorial-stage2/native-review-final.log`。運行中沒有腳本錯誤；關閉審查工具時出現 Jolt／ObjectDB 資源清理警告，來源未定位，正式啟動及輪驅測試未報相同警告。

條件頁底部提示已目視確認；Manual 頁截圖未能確認提示列顯示，仍待使用者確認。另以實際 UI／首關資料做版面座標檢查：Conditions → Steps → Controls → Manual → Conditions 每頁等待 20 幀，提示皆可見、位置 (20,664)、尺寸 1240×40，完整位於 1280×720 視窗內；日誌 `.godot/stage2-terminal-layout.log`。

## 使用者驗收入口

1. 啟動正式 `world/main_world.tscn` 新局；讀出生處左側海報，進 RV 駕駛室，對左前牆終端長按 E 查看 Conditions。確認頁面可讀、Esc 可關閉。
2. **第一關尚未完成時**用 Esc → Restart Stage，確認玩家、RV、終端及物資回到第一關入口、手動檔不變；也可先拆下／遺失終端再重試。
3. 拾取右側供應區手電筒；依 Controls 駕車過 01、02，越過 02 後倒車入框，停穩、手煞車、熄火。預期首道門自動開啟，其他門及公路出口鎖定。
4. 完成首關後終端顯示下一站尚未開放。離座後建立第二關入口；此時 Restart Stage 保留首關完成狀態，恢復已停妥的第二關入口。重玩第一關請開新局。中途關閉終端、停妥及離座後，可用既有 F9／F10 保存與讀取進度。

## 限制與交付

只有第一關可玩。換電池及第 3–9 關、Skip Tutorial、正式啟程與完整可搜尋說明書留待後續階段；Manual 目前鎖定，已完成版本化 Item 狀態及介面基礎。倒車未達完成條件前的累積距離不保存；中途讀檔須重新倒車，已完成條件保留。

九區延長的階段一變更當時依使用者要求未驗證；本次證據涵蓋延長後的首關及保存，不代表全基地再次驗收。全基地延長後的靜態面數尚未量測；20 萬面預算、美術、效能及九關完整實機流程留待階段六。操作手感仍待使用者驗收。

文件與相關連結已核對；提交僅包含本階段內容，保留既有 `AGENTS.md`、`project.godot` 修改。工具與日誌留在忽略目錄；未推送、未建立 PR。
