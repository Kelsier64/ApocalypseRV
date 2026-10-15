# 兩室教學基地：新版階段二

日期：2026-10-15。沿用 `codex/starting-tutorial`。階段一已通過使用者驗收；本輪完成[階段二](../plans/starting-tutorial-two-room.md)，停止等待驗收，不開始階段三。

## 完成內容

- 第二室放置可搬運分解機、製造台、兩件廢料、油桶與健康備胎；材料架有實體支撐，全部物資位於中央 8 m 車道之外。第一室仍無車、無額外補給。
- 原 RV 初始零燃油，兩片指定側牆各損失 60 耐久，左前輪爆胎，引擎保持健康。配置保存後不因讀檔或查看終端再次施加故障或補發物資。
- 同一攜帶式終端沿用舊 TUI，依序提供「安裝設備 → 回收 → 製造並拾取 → 修牆與換胎 → 加油」的條件、步驟與按鍵參考。沒有新增教學 HUD。
- 使用原生成功交易與指定 ID：兩台設備必須固定於原 RV 且可運作；三件回收物實際入庫；汽油罐出料且被拾取；兩片牆透過 rvctl Repair 完工；原爆胎拆下且指定健康備胎裝入同一輪槽；製造出的汽油罐真正加油並回傳空罐。
- 回收固定取得 8 Metal Parts、10 Unrefined Fuel；製造耗用 2 Metal Parts、5 Unrefined Fuel，兩片牆各耗用 2 Metal Parts，留下 2 Metal Parts。新局不額外贈送引擎維修包。
- 準備期僅對有效已安裝電池維持至少 20 電量，不補空槽、不補燃油。完成紀錄與當前可用狀態分開檢查，設備停用或修復後再受損會顯示未就緒。
- Checkpoint 外層 v5 不變，兩室課程升至 v2、工作坊子狀態 v1。第一階段 v1 存檔第一次升級時配置本次演練，保留原車／終端 ID、燃油與既有較低耐久；之後載入 v2 不再配置。失敗載入保留當前世界。

## 自動驗證

Godot 4.7.2。九項相關檢查的最後結果均通過；未執行完整套件。

| 項目 | 結果與日誌 |
|---|---|
| `test_orientation_workshop`、`test_orientation_workshop_journey`，含資產匯入 | PASS、exit 0；`.godot/test-logs/20261015-141851-092-selected-48172/` |
| `test_orientation_controller`、`test_orientation_shelter`、`test_portable_training_terminal`、`test_training_workshop_schema`、正式主場景 smoke | 各項 PASS；`.godot/test-logs/20261015-141636-673-selected-50520/`；該批次中工作坊單元測試先前的退出失敗已由上列最終重跑取代 |
| 擴充 `test_orientation_checkpoint` | PASS、exit 0，無腳本錯誤；`.godot/test-logs/orientation-stage2-checkpoint.log` |
| 舊 v11 `test_training_checkpoint` | PASS；`.godot/test-logs/20261015-142110-928-selected-49420/` |

原生交易測試覆蓋取消放置／回收／列印／施工不計分，錯誤 RV／材料 ID、非指定輪胎、非製造出的汽油罐不計分，滿油拒絕時不消耗罐；確認原生出料、修牆、換胎及空罐回傳。輪驅檢查在第二室內行駛超過 0.5 m，原生獨立執行紀錄為 1.619 m，兩台機器保持固定且可運作。

測試中的機器安裝點（RV 本地座標）為分解機 `(1.25, 0.512, -2.2)`、製造台 `(-1.0, 0.512, 1.425)`；實際放置碰撞與汽油出料已驗證。這是可行參考位置，不強制玩家只能裝在這兩點。

保存測試覆蓋 v1 首次升級、較低耐久與原燃油保留、v2 再載入不重複發放／破壞、材料與修復狀態保留，以及終端跨固定座／背包所有權；錯誤類型與重複 ID 拒絕載入。新增兩支測試分類在 `tests/suites.json` 的 integration。

中途發現並修正混合型別驗證陣列錯誤；測試也修正了牆板最大耐久為 120 的假設與物理穩定期間的正常微量輪胎磨耗。早期失敗日誌保留，不作為通過證據。

## 原生畫面觀察與限制

使用正式 Forward+ 視窗的 `--workshop-review` 檢視相機查看故障 RV、分解機、製造台、油桶、廢料架、屋架及淨空；確認材料置於架面、設備放在地面，中央車道可辨識。日誌 `.godot/orientation-stage2-native.log` 無腳本錯誤。檢視相機不完成教學，也不改正常新局出生點。

原生交易／短距離輪驅屬自動測試，會控制玩家位置、瞄準與服務經過時間；不代表已完成手動 WASD 搬運全流程、長距離駕駛或所有顯示尺寸的驗收。整體建築美術及效能優化仍留待後續階段。

## 使用者驗收入口

開啟 [orientation_playground.tscn](../../tests/orientation_playground.tscn) 按 F6，或：

```powershell
godot --path . --log-file .godot/orientation-stage2-acceptance.log res://tests/orientation_playground.tscn
```

1. 完成第一室開機與拆下終端，通過內門。選中終端按 T，應看到設備安裝說明。
2. 將第二室兩側機器拾取並固定到 RV；確認入口、走道、進料與出料區可用。
3. 回收架上的兩件廢料與旁邊油桶，確認實際入庫 8 金屬、10 原油材料。
4. 用原 RV 的 rvctl Crafting 製造 Gasoline Can，等待出料並拾取。
5. 用 rvctl Structure 的 Repair 修復 `left_0`、`right_0`；至左前輪槽長按 E 拆下舊胎，拿西側地面的健康備胎長按 E 安裝。三項可自由排序。
6. 選中剛製造的汽油罐，在加油口按 E，確認燃油增加且取得空罐，終端顯示完成紀錄。
7. 可在第二室內停妥／熄火後關閉介面，再使用既有 F6／F9 保存、載入，確認物資不重發、故障不重置、終端仍可攜帶閱讀。

出口仍保持關閉；感應開門、正式啟程、說明書解鎖、重試／略過與完整復原屬第三階段，尚未實作。不得將本輪驗收當成整個新版教學完成。

## 提交與保留

只提交本輪已驗證的場景、課程、保存、測試與文件。原有九區美術、專案設定、貼圖匯入、`AGENTS.md` 及技能刪除等本機變更保留；測試清單只提交新增兩支分類，原有未提交的 journey 分類留在工作樹。未推送或建立 PR。
