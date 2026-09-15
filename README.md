# ApocalypseRV

Godot 4.6.1 第一人稱末日公路生存原型：駕駛 RV、搜刮建築、搬運物資、分解製作汽油，並應對會攀車與拆車的殭屍。**目前是單人沙盒**，尚無多人、存檔、任務、正式勝敗或長局進度；合作生存屬後續願景。

## 文件

- [GDD.md](GDD.md)：遊戲設計、完整玩法、資源數值、目標與未實作願景。
- [architecture.md](architecture.md)：場景、模組契約、資料流、測試範圍與限制。
- [docs 索引](docs/README.md)：待實作計畫、驗收紀錄與 archive 歷史文件；現行文件以根目錄版本為準。
- [AGENTS.md](AGENTS.md)：開發約定；原始 [todo](todo) 與 [todo_for_ai](todo_for_ai) 保留作規劃紀錄。

## 啟動

安裝 Godot 4.6.1，將 godot 加入 PATH，在專案根目錄執行：

```powershell
godot --editor --path .
godot --path .
```

主場景為 `world/test_world.tscn`，使用 Jolt Physics 與 GL Compatibility。開局有 RV、地面設備、測試物資及殭屍，並生成公路。

## 怎麼玩

先把地面的發電機、分解機、平板與合成站裝到 RV，撿物並丟入分解機，從平板製作汽油罐，到合成站取貨，再對 RV 加油口補油。沿公路找維修站，門前按 E 進入 50–100 間房的迷宮搜刮，回 R001 的 EXIT 門按 E 返回。第一棟在起點前方約 45 m、公路右側。室外世界與 RV 油電持續運作；同局重返保留搜刮和敵人死亡狀態。現階段目標是自行完成並維持資源循環。

| 操作 | 按鍵 |
|---|---|
| 步行／視角／跳躍 | WASD／滑鼠／Space |
| RV 攀爬 | 面向車壁持續 W；A/D 橫移；S 或 Space 脫離 |
| 撿物／加油 | 瞄準後短按 E；加油須手持汽油罐 |
| 副本進出 | 門前短按 E；出口在 R001 |
| 入座／開平板／拆裝輪胎 | 長按 E 約 1 秒；裝輪胎需手持 Wheel 瞄準底盤 |
| 移動設備 | 長按 F 約 2 秒，左鍵確認、右鍵取消、R 切換貼面／直立 |
| 背包選取／丟棄 | 1–6 或滾輪／G；大型物品鎖定選取 |
| 駕駛 | W 前進、A/D 轉向、S 或 Space 煞車／倒車、E 離座 |
| 平板關閉 | 點 UI 關閉按鈕 |
| 釋放滑鼠 | 一般輸入中按 Esc；沒有暫停選單 |

方向鍵是仍保留的 RV 開發遙控。沒有玩家武器輸入；撞擊敵人依 RV 速度及方向計算。玩家死亡約 2 秒後原地恢復滿血。Space 駕駛時走煞車／倒車邏輯，沒有獨立手煞車。完整規則和限制見 [GDD](GDD.md)。

## 驗證

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

Runner 匯入資源，執行全部 `tests/test_*.gd`，再跑主場景 120 frames；檢查退出碼、錯誤日誌與測試 `PASS:`。日誌在 `.godot/test-logs/`，可用 `-Godot 'C:/path/to/godot.exe'` 指定執行檔。GitHub Actions 使用同一入口。

移動 RV 攀爬展示：

```powershell
godot --path . --log-file .godot/climb-playground.log res://tests/rv_climb_playground.tscn -- --replay
```

藍色是玩家，紅色是怪物。F2 切換車輛運動、F3 自動攀爬、F4 換攝影機、F5 玩家入座測拆頂、R 重設。去掉 `-- --replay` 可手動 WASD／Space。這些按鍵只用於 playground，與主遊戲 R 的設備模式切換不同。

Replay 使用腳本控制車輛運動，整合測試另有物理驅動 RV 情境。Headless 通過仍不能代替鏡頭手感、實際輪驅操控、翻車、怪物群與設備對齊的視覺驗收。現有測試也未完整涵蓋資源經濟與平板製作交易。

## POI 資產樣板

入口建築、小房（9×9 m）、大房（18×18 m）、走廊及貨架／工作桌／櫃子已提供可編輯 `.tscn`。外觀、碰撞、門口與物資點分層，正式模型可以逐步替換灰盒。[製作規格與場景索引](world/poi_kit/README.md)。

```powershell
godot --path . --log-file .godot/poi-asset-workshop.log res://tests/poi_asset_workshop.tscn
```

F1–F4 查看建築／房間／掀頂，F5 步行並以 E 使用入口，F6 自動測試入口與穿越，M 顯示標記。這個場景保留作資產檢查。主遊戲已使用新入口、四門小房／大廳及獨立副本，舊 POI 已刪除。

正式場景進出與連接走廊的操作回放：

```powershell
godot --path . --log-file .godot/poi-replay.log res://tests/poi_instance_playground.tscn
```

按 F6 開始，或命令加 `-- --replay`。回放只在測試場提供起點傳送與自動步行；其餘使用正式主場景、玩家和副本流程。2026-09-15 使用本機 Godot 4.7.2 驗證，CI 仍設定為 4.6.1，未宣稱跨版本驗證。副本目前兩種房型，沒有跨局存檔。

## 公路與沿途探索

世界現在交替生成草原、稀疏林地與岩丘，配置植被、岩石、路標、電線桿、護欄及廢棄設施。道路有緩起伏、連續彎和 15→10 m 的縮窄段；看到 SLOW 標誌請提早減速。每 300–600 m 一個停靠點，小型點提供少量物資，維修站入口通往副本。停車區和展寬支道已與地形一起整平。

在 WorldGenerator 設定 `world_seed` 可重現整條路線，`-1` 每局另選 seed；`profile` 集中景觀、路寬、坡度、密度和串流設定。此版仍是沿公路向前旅行，遠景不提供可探索碰撞，後方已回收的地形不重建。

```powershell
godot --path . --log-file .godot/highway-visible.log res://tests/highway_playground.tscn
```

F1/F2/F3 預覽草原／林地／岩丘，F6 執行固定 seed 的 5 km 輪驅測試，F7 測停車、倒出及返回公路。回放以正式油門／轉向和 VehicleBody3D 輪胎物理移動；僅起點擺位、測試相機及停用耗油屬測試設定。完成後再次按回放鍵會重載測試場，再按一次啟動。可用 `-- --replay` 或 `-- --parking` 自動執行並退出；headless 測試加 `--fixed-fps 60`。

路旁九種模組提供可編輯場景，見 [roadside kit](world/roadside_kit/README.md)。地形驗收與效能紀錄見 [驗收紀錄](docs/validation/2026-09-15-highway.md)。

## 程式位置

`player/` 玩家與互動、`enemies/` AI／選敵、`props/` 可撿物、`rv/` 底盤輪胎、`equipment/` 設備、`world/` 串流／POI／建築、`core/` 共用契約、`tests/` 行為測試及展示。完整對照見 [架構](architecture.md)。
