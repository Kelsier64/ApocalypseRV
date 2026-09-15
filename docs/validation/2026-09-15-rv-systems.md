# RV 系統執行與驗收紀錄

- 執行日期：2026-09-15～16。
- 範圍：[RV 完善計畫](../plans/2026-09-15-rv-systems-roadmap.md) RV-01～05 首版，以及 RV-06 保存與資源循環。
- 環境：Windows，Godot 4.7.2 stable、Jolt、GL Compatibility；NVIDIA RTX 4060 Laptop GPU、AMD Ryzen AI 9 HX 370。目標／CI 4.6.1 尚未交叉驗證。
- 原始日誌位於忽略提交的 .godot/，本文件保留結論、數據與重跑入口。

## 1. 已落地功能

| 範圍 | 實作結果 |
|---|---|
| 設備可靠性 | 共用可運作條件、取消物理快照、搬移停止工作、平板／座位釋放玩家、分解進料退還 |
| 模組安裝 | EquipmentDefinition、穩定 ID、本車登錄、精確支撐與掉落、目標／體積／朝向／操作空間驗證、可選結構接點 |
| 能源 | 引擎啟停、怠速耗油、正常發電機供電、單插槽電池道具、充電門檻／燃油保留、同一步調度 |
| 駕駛維修 | 手煞車、1–4 前進檔／空檔／倒檔、儀表、底盤失效 gate、定向輪槽、磨耗／維修、重量與重心 |
| 設備與生產 | 油箱、材料架、材料包、4 個配方、工作佇列、材料預留、缺電暫停與出口堵塞保留 |
| 保存 | F6/F9 室外檢查點，版本 1，玩家／世界範圍／RV／設備／電池／輪胎／材料／工作／已訪 POI |

使用者確認的電池方向已採用：發電機為 Equipment，電池為 Prop。熄火停車耗電、運轉引擎配合有效發電機充電；可換電池或原地花油充電。沒有油門直接加電或隱藏備用電量。

首版明確取捨：手動啟動不耗電；單插槽，無電池不供一般用電；製作電池初始為空。底盤可以修復，未決定永久報廢結局。油箱各自擁有燃油，材料架只提供本車材料容量，超額材料不刪除。

## 2. 自動驗證

最後一輪統一 runner 退出 0：資源匯入、18 個 tests/test_*.gd 與主場景 120 frames 全部 PASS。測試採正式場景與可觀察狀態，沒有把簡化 stub 的結果當成整體物理驗收。

| 新增測試 | 驗證重點 |
|---|---|
| [test_rv_systems](../../tests/test_rv_systems.gd) | 熄火／怠速發電、停用與搬移、不足完整費用、取消退款、電池 ID／滿背包交換、平板毀損、退料、支撐掉落、底盤失效與座位卸載 |
| [test_rv_extended](../../tests/test_rv_extended.gd) | 負材料拒絕、材料架溢出與存領、拆油箱保留燃油、維修中斷／提交、無電池、輪胎狀況、裝載重量、支撐循環、60 秒充電與 20 分鐘停車 |
| [test_rv_checkpoint](../../tests/test_rv_checkpoint.gd) | 磁碟寫讀、版本拒絕、主世界重建、ID／油電／背包電池／POI 記憶、進行中的製作／分解、輸入物件不複製 |
| [test_rv_resource_cycle](../../tests/test_rv_resource_cycle.gd) | 真實拾取／丟棄油桶 → 回收 → 製作汽油 → 撿取／加油返空罐 → 維修 → 空電池怠速充電 → 入座取得動力 |
| [test_rv_physics_regression](../../tests/test_rv_physics_regression.gd) | 正式 RV 在地面停穩、逐項掛載設備，不產生大幅推飛 |

資源循環測試固定搜刮產出以排除 RNG，不代替探索難度與實際搬運手感；出發檢查正式驅動力，實際輪驅距離由下一節覆蓋。既有攀爬、選敵、背包、POI、世界生成與探索回歸亦納入 runner。

重跑：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Godot 'C:/Users/evan4/AppData/Local/Programs/Godot/Godot_console.exe'
```

本機一般 sandbox 啟動 Godot 可能輸出 Failed to read the root certificate store；runner 原有規則單獨允許此環境訊息，不忽略 GDScript、物理或其他錯誤。

## 3. 實際輪驅量測

[highway_playground](../../tests/highway_playground.gd) 已改用新引擎、檔位、油門及手煞車入口，未保留舊版以 S 直接倒車的路徑。

| 測試 | 結果 |
|---|---|
| seed 42，正式輪胎 5 km | PASS；模擬 414.4 秒，最大側向偏差 0.32 m、傾斜 4.5° |
| 最終 5 km 效能 | frame p95 4.53 ms、p99 9.37 ms、max 40.02 ms；222.6 MiB，結束時 5 個 chunks |
| 停靠、倒出、返回道路 | PASS；模擬 64.4 秒、傾斜 4.0°；p95 1.80 ms、p99 8.76 ms、max 30.05 ms，185.5 MiB |

上述為 headless 固定 60 模擬步、實際 VehicleBody3D 輪驅；frame 時間不是可見遊戲 FPS。測試場關閉燃油消耗，因此不能作長途能源平衡證據。日誌為 .godot/rv-highway-final.log、.godot/rv-highway-parking.log。

```powershell
godot --headless --path . --fixed-fps 60 --log-file .godot/rv-highway-final.log res://tests/highway_playground.tscn -- --replay
godot --headless --path . --fixed-fps 60 --log-file .godot/rv-highway-parking.log res://tests/highway_playground.tscn -- --parking
```

## 4. 實機觀察

依 computer-use 技能，以實際列出的遊戲視窗操作；未操作 Godot 編輯器。以下與自動測試分開記錄。

### RV 系統回放

開啟 [rv_systems_playground](../../tests/rv_systems_playground.tscn) 可見視窗：

- 車輛停車穩定；回放輸出熄火電量下降、怠速電量上升。
- 換入電池時精確為 75；汽油工作完成；隨後使用真正油門／轉向完成左右轉彎，回放測得約 3.74 m/s。
- 熄火拉手煞車後回到低速停車狀態。
- F5 開啟平板：可讀油電、供需、輪胎、設備狀況；滾動可見充電門檻 80%、保留油量 5、工作與材料領取按鈕。
- Esc 關閉恢復原畫面；F4 入座顯示速度／檔位／手煞車／引擎／油電／車況儀表。
- 在入座狀態關閉本次視窗，進程退出 0，最終日誌沒有腳本錯誤。

日誌：.godot/rv-systems-visible-final.log。檢查排版和可見狀態，未逐個按鈕完成全部人工操作組合。

### 移動 RV 攀爬

使用 [rv_climb_playground](../../tests/rv_climb_playground.tscn) 的 --replay，觀察藍色玩家與紅色怪物在車頂，隨轉彎 RV 保持支撐。F5 入座後觀察屋頂 HP 變為 DESTROYED，怪物失去頂板支撐落到較低位置。

日誌：.godot/rv-climb-validation.log。這是腳本車輛運動展示；不能用它單獨代替輪驅、翻車或群怪測試。

## 5. 本次發現並處理的問題

- 測試場先加入車輛物理世界再移動底盤，曾造成初始巨大衝量；改為加入前完成起始擺位。正式存檔還原也先設定物件變換再加入場景，並統一預裝設備碰撞例外。
- 入座狀態卸載世界時，玩家可能已退出樹，座位再存取全域座標會報錯；加入有效／inside_tree 判斷，覆蓋卸載回歸及實機關閉。
- 存檔測試在新世界還有待執行操作時同步 free，曾在退出階段引擎崩潰；改以 queue_free 在影格結束卸載，再等待影格清理，完整 runner 確認退出。
- 零耐久保留殘骸停止成為可攻擊候選；修好再加入群組。
- 無效成品／設備實例在轉型失敗時清理，避免資源洩漏。

## 6. 完成範圍與未測限制

首版功能已落地，**不宣稱整份計畫所有物理與長途平衡目標均驗收完畢**：

1. 裝載重量／重心已計算，設備仍是獨立凍結碰撞體；大型外掛側撞力矩未重建，極端偏載、屋頂重載、翻車、群怪需專項驗證。
2. 長途資源供給、不同油門／工作負載／搜刮時間／敵人壓力沒有完成平衡；20 分鐘停車測試只證明按規則耗至零。
3. 存檔限主世界室外 NORMAL 狀態；不支援副本內直接保存、多槽、舊版本遷移、已清理室外區域永久回訪。
4. 控制與輪槽仍由 Chassis 協調；能源、材料、保存已抽出，未為每個提案職責強制建立新類別。
5. 燃油量、抽象材料、鬆散貨物不動態計重；手排不模擬離合器／RPM。新增大型成品需擴充出料形狀驗證。
6. 安裝驗證已加入碰撞形狀與操作區域；複雜傾斜配置、支撐連鎖、所有下車空間受困情境仍需擴大實機驗證。

計畫的勾選、現況 GDD／architecture／README 已同步，原始 todo 和使用者既有 todo_for_ai 修改保留。
