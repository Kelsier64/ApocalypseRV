# ApocalypseRV

Godot 4.7.2 第一人稱末日公路生存原型：駕駛 RV、搜刮建築、搬運物資、分解製作汽油，並應對會攀車與拆車的殭屍。**目前是單人沙盒**，提供室外檢查點保存，尚無多人、任務、正式勝敗或長局進度；合作生存屬後續願景。

## 文件

- [GDD.md](GDD.md)：遊戲設計、完整玩法、資源數值、目標與未實作願景。
- [architecture.md](architecture.md)：場景、模組契約、資料流、測試範圍與限制。
- [docs 索引](docs/README.md)：開發計畫、驗收紀錄與 archive 歷史文件；現行文件以根目錄版本為準。
- [AGENTS.md](AGENTS.md)：開發約定；原始 [todo](todo) 與 [todo_prompt](todo_prompt) 保留作規劃紀錄。
- [遊玩與測試場指南](docs/guides/playgrounds.md)：RV 維護、各展示場命令與快捷鍵。
- [開發計畫總覽](docs/plans/README.md)：各計畫狀態、剩餘工作與驗收依據。

## 啟動

安裝 Godot 4.7.2，將 godot 加入 PATH，在專案根目錄執行：

```powershell
godot --editor --path .
godot --path .
```

主場景為 `world/test_world.tscn`，使用 Jolt Physics，桌面預設 Forward+／Vulkan。開局有完整組裝的 RV、測試物資及殭屍，並生成公路。

戶外已改用林間局部體積霧，會接受太陽與車燈照明；遠處另外保留淡距離霧。更新後須重新啟動遊戲，編輯器需重新載入專案。若顯示卡不支援，可用 `godot --path . --rendering-method gl_compatibility --rendering-driver opengl3`，降級為原距離霧。畫面與測試見 [局部體積霧驗收](docs/validation/2026-09-17-volumetric-fog.md)。

## 怎麼玩

車上已裝齊發電機、分解機、平板與工作台。撿物並丟入分解機，從平板製作汽油罐，到合成站取貨，再對 RV 加油口補油。沿公路辨認建築的煙囪、水塔或天線，在停車灣下車，沿土路與路標穿過窄口前往入口。新世界第一棟維修廠位於 (335.2,6,-45)，停車區在 (33,0,-45)，步行約 97 秒。門前 E 進入 50–100 房、兩層的 v2 副本；經兩座樓梯到零件庫取得引擎與維修包，從內側開通返程捷徑，回接待室 EXIT 門 E 返回。M 顯示已探索地圖，Page Up／Down 切樓層。既有已訪副本保留原迷宮。室外世界與 RV 油電持續運作；同局重返保留搜刮和敵人死亡狀態，回到室外可用 F6 保存。

| 操作 | 按鍵 |
|---|---|
| 步行／視角／跳躍 | WASD／滑鼠／Space |
| RV 攀爬 | 面向車壁持續 W；A/D 橫移；S 或 Space 脫離 |
| 撿物／加油 | 瞄準後短按 E；加油須手持汽油罐 |
| 副本進出 | 門前短按 E；新版出口在接待室，舊版在 R001 |
| 入座／開平板／拆裝輪胎 | 長按 E 約 1 秒；裝輪胎需手持 Wheel 瞄準輪槽，停穩並熄火 |
| 移動設備 | 長按 F 約 2 秒，左鍵確認、右鍵取消、R 切換貼面／直立、V 切換結構吸附；自由放置 Q/E 轉 15°、Shift 轉 5°、方向鍵移 5 cm |
| 背包選取／丟棄 | 1–6 或滾輪／G；大型物品鎖定選取 |
| 駕駛 | W 油門、A/D 轉向、S 漸進腳煞車、Space 手煞車、E 離座 |
| 引擎／車燈／排檔 | B 啟停、L 頭燈；Z 倒檔、X 空檔、C 一檔、R 升檔、T 降檔 |
| 電池 | 手持電池對插槽短按 E 交換；長按 E 取出 |
| 引擎更換 | 車頭 E 開維修蓋；停穩、熄火、手煞車後，手持引擎短 E 交換，長 E 取出 |
| 引擎維修 | 手持引擎維修包，瞄準艙內引擎 H 3 秒，消耗一包補 150 耐久 |
| 其他維修 | 熄火停穩，瞄準設備／輪槽 H 2 秒花 2 金屬補 60 HP |
| 後坡板 | 後方控制柄 E；展開需停穩、手煞車、雙扇後門全開及合適地面；上面無人／物才可收起 |
| 保存／載入 | 主世界 F6／F9；保存須在室外離座、結束互動且地形建立完成 |
| 復古顯示 | F8；保存偏好，HUD 維持清晰。進室內暫停效果，回室外恢復 |
| 平板關閉 | Esc 或 UI 關閉按鈕 |
| 釋放滑鼠 | 一般輸入中按 Esc；沒有暫停選單 |

正式遊戲已移除方向鍵遙控。沒有玩家武器輸入；撞擊敵人依 RV 速度及方向計算。玩家死亡約 2 秒後原地恢復滿血。起步先 B 發動、C 選一檔、Space 放開手煞車，再踩 W。離座自動拉手煞車，但引擎持續運轉。完整規則和限制見 [GDD](GDD.md)。

車重只計底盤、裝上的引擎與設備，安裝位置影響重心；電池本體、素材、庫存道具與燃油不增加車輛載重。

## 驗證

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

Runner 先核對 `.godot-version`，列出頂層 `tests/test_*.gd`（零測試即失敗），匯入資源並執行全部測試，再等待正式主場景地形、導航與玩家就緒並驗證移動；檢查退出碼、錯誤日誌與測試 `PASS:`。版本、commit、OS 和測試清單保存於 `manifest.txt`。日誌在 `.godot/test-logs/`，可用 `-Godot 'C:/path/to/godot.exe'` 指定執行檔。GitHub Actions 使用同一入口。

測試場操作見 [指南](docs/guides/playgrounds.md)，歷次結果見 [文件索引](docs/README.md)。Headless 通過不代替實機手感、GPU 畫面、翻車、怪物群或長途經濟驗收。

## 程式位置

`player/` 玩家與互動、`enemies/` AI／選敵、`props/` 可撿物、`rv/` 底盤輪胎、`equipment/` 設備、`world/` 串流／POI／建築、`core/` 共用契約、`tests/` 行為測試及展示。完整對照見 [架構](architecture.md)。

## 室外加油站測試

`godot --path . --log-file .godot/gas-station.log res://tests/gas_station_playground.tscn`

可直接步行進入商店、維修間與後院，同世界探索，無副本轉場。F1 步行、F2 外觀、F3 商店、F4 維修間、F5 步行回放；E 拾取。詳見 [加油站規格](world/poi_kit/buildings/README.md)。

新世界生成 v5 已包含可直接探索的 NORTHLINE 加油站：起始維修廠之後的下一個停靠點（距世界起點沿路約 375–525 m），沿路找 GAS / SERVICE 標誌。可回頭探索，剩餘場內物資隨串流及 F6/F9 檢查點保存；舊 v2–v4 存檔保留原世界，需開新局看新建築。加油機目前是造景，燃料從物資搜刮取得。

日夜與動態天氣：陰晴、大小雨與霧可自動轉換，屋頂遮雨、天氣進度隨檢查點保存。[天氣驗收操作](docs/guides/playgrounds.md#日夜與天氣驗收)。

副本 v2 的房型、接口、保存和預覽命令見 [室內製作規格](docs/guides/interior-v2.md)。
