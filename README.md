# ApocalypseRV

Godot 4.7.2 第一人稱末日公路生存原型：駕駛 RV、搜刮建築、搬運物資、分解製作汽油，並應對會攀車與拆車的殭屍。**目前是單人沙盒**，提供室外檢查點保存，尚無多人、任務、正式勝敗或長局進度；合作生存屬後續願景。

玩家已接入完整 1.60 m 角色模型，低頭可見身體並保留完整影子。死亡會切換布娃娃，第一人稱鏡頭隨倒地下移而不翻滾，兩秒後在附近安全站位恢復控制；固定 60 Hz，布娃娃落地與恢復控制、79 組完整回歸已通過；已加入待機、5 m/s 慢跑與 8 m/s 快跑，含四方向動作與布娃娃交接；跳躍使用上升、下降與落地姿勢；攀爬有抓牆停留、交替攀升、左右橫移與登頂收手，沿用既有移動與登頂操作。最新動作見 [v021 驗收](docs/validation/2026-09-27-player-animations-v021.md)。前階段見 [模型整合](docs/validation/2026-09-27-player-model-integration.md)與[死亡布娃娃驗收](docs/validation/2026-09-27-player-death-integration.md)。

## 文件

- [GDD.md](GDD.md)：遊戲設計、完整玩法、資源數值、目標與未實作願景。
- [architecture.md](architecture.md)：場景、模組契約、資料流、測試範圍與限制。
- [docs 索引](docs/README.md)：開發計畫、驗收紀錄與 archive 歷史文件；現行文件以根目錄版本為準。
- [AGENTS.md](AGENTS.md)：開發約定；[todo](todo) 保留原項目並標記狀態，[todo_prompt](todo_prompt) 保留 POI 規劃方向。
- [遊玩與測試場指南](docs/guides/playgrounds.md)：RV 維護、各展示場命令與快捷鍵。
- [開發計畫總覽](docs/plans/README.md)：各計畫狀態、剩餘工作與驗收依據。
- [程式與資產目錄指南](docs/guides/codebase.md)：目錄責任、資源引用、存檔相容及清理流程。

## 啟動

安裝 Godot 4.7.2，將 godot 加入 PATH，在專案根目錄執行：

```powershell
godot --editor --path .
godot --path .
```

主場景為 `world/test_world.tscn`，使用 60 Hz／Jolt Physics（32／32 次求解），桌面預設 Forward+／Vulkan。開局有完整組裝的 RV、測試物資及殭屍，並生成公路。

戶外已改用林間局部體積霧，會接受太陽與車燈照明；遠處另外保留淡距離霧。更新後須重新啟動遊戲，編輯器需重新載入專案。若顯示卡不支援，可用 `godot --path . --rendering-method gl_compatibility --rendering-driver opengl3`，降級為原距離霧。畫面與測試見 [局部體積霧驗收](docs/validation/2026-09-17-volumetric-fog.md)。

## 怎麼玩

車上已裝齊發電機、分解機、平板與工作台。撿物並丟入分解機，從平板製作汽油罐，到工作台取貨並補油。沿公路路標與步道前往混凝土地堡入口，面向鋼門 E 進入。隨機軍事地堡使用 16 個模組（14 個普通變體、入口與樓梯），目標 10–30 個模組、隨機 1–3 層，各層共用房型池。無平面邊界，接口耗盡可少於 10 間；樓梯放不下時保留較少樓層。首批六種尺寸可透過場景與 Resource 擴充，沒有固定必要主路。本輪只有結構、照明及基本陳設，不生成物資／怪物，也沒有目標或捷徑。 返回 B1 ENTRY 的 EXIT 門 E 回地面；M 顯示已探索地圖，Page Up／Down 切層。室外世界與 RV 油電持續運作，玩家掉落物及探索會保留，回室外 F6 保存。舊 v1／v2 副本紀錄會清除，其餘世界資料保留。見 [地堡指南](docs/guides/bunker-interior.md)。

| 操作 | 按鍵 |
|---|---|
| 步行／衝刺／視角／跳躍 | WASD／左 Shift／滑鼠／Space；衝刺與跳躍消耗耐力，休息後恢復 |
| RV 攀爬 | 面向車壁持續 W；A/D 橫移；S 或 Space 脫離 |
| 撿物／加油 | 瞄準後短按 E；加油須手持汽油罐 |
| 副本進出 | 門前短按 E；新版出口在接待室，舊版在 R001 |
| 入座／開平板／拆裝輪胎 | 長按 E 約 1 秒；裝輪胎需手持 Wheel 瞄準輪槽，停穩並熄火 |
| 移動設備 | 長按 F 約 2 秒，左鍵確認、右鍵取消、R 切換貼面／直立、V 切換結構吸附；自由放置 Q/E 轉 15°、Shift 轉 5°、方向鍵移 5 cm |
| 背包選取／丟棄 | 1–6 或滾輪／G；大型物品鎖定選取 |
| 駕駛 | W 油門、A/D 轉向、S 漸進腳煞車、Space 手煞車、E 離座 |
| 引擎／車燈／排檔 | B 啟停、L 頭燈；Z 倒檔、X 空檔、C 一檔、R 升檔、T 降檔 |
| 車內照明／儀表 | 統一由控制台（平板）控制車內／工作／維修燈、儀表亮度及視覺震動；車內燈條可長按 F 拆裝 |
| 電池 | 手持電池對插槽短按 E 交換；長按 E 取出 |
| 引擎更換 | 車頭 E 開維修蓋；停穩、熄火、手煞車後，手持引擎短 E 交換，長 E 取出 |
| 引擎維修 | 手持引擎維修包，瞄準艙內引擎 H 3 秒，消耗一包補 150 耐久 |
| 其他維修 | 熄火停穩，瞄準設備／輪槽 H 2 秒花 2 金屬補 60 HP |
| 後坡板 | 後方控制柄 E；展開需停穩、手煞車、雙扇後門全開及合適地面；上面無人／物才可收起 |
| 保存／載入 | 主世界 F6／F9；保存須在室外離座、結束互動且地形建立完成 |
| 復古顯示 | F8；保存偏好，HUD 維持清晰。進室內暫停效果，回室外恢復 |
| 平板關閉 | Esc 或 UI 關閉按鈕 |
| 釋放滑鼠 | 一般輸入中按 Esc；沒有暫停選單 |

正式遊戲已移除方向鍵遙控。沒有玩家武器輸入；撞擊敵人依 RV 速度及方向計算。玩家死亡約 2 秒後原地恢復滿血。起步先 B 發動、C 選一檔、Space 放開手煞車，再踩 W。離座不會改變手煞車或引擎狀態；停車需自行拉起手煞車。完整規則和限制見 [GDD](GDD.md)。

車重只計底盤、裝上的引擎與設備，安裝位置影響重心；電池本體、素材、庫存道具與燃油不增加車輛載重。

油門與腳煞車逐步建立力道，高速時限制轉向角度。左右後照鏡可查看車側及後方，只在駕駛視角更新。維修蓋和兩折坡板會播放完整動作，遇阻停止；坡板未收妥禁止行駛，維修蓋／坡板未到穩定姿態時不能保存。照明、儀表亮度及視覺震動設定隨檢查點保存。

## 驗證

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
```

Runner 先核對 `.godot-version`，列出頂層 `tests/test_*.gd`（零測試即失敗），匯入資源並執行全部測試，再等待正式主場景地形、導航與玩家就緒並驗證移動；檢查退出碼、錯誤日誌與測試 `PASS:`。版本、commit、OS 和測試清單保存於 `manifest.txt`。日誌在 `.godot/test-logs/`，可用 `-Godot 'C:/path/to/godot.exe'` 指定執行檔。GitHub Actions 使用同一入口。

測試場操作見 [指南](docs/guides/playgrounds.md)，歷次結果見 [文件索引](docs/README.md)。Headless 通過不代替實機手感、GPU 畫面、翻車、怪物群或長途經濟驗收。

## 程式位置

`player/` 玩家與互動、`enemies/` AI／選敵、`props/` 可撿物、`rv/` 底盤輪胎、`equipment/` 設備、`world/` 串流／POI／建築、`core/` 共用契約、`tests/` 行為測試及展示。目錄與資產來源見 [程式與資產目錄指南](docs/guides/codebase.md)；執行期契約見 [架構](architecture.md)。

## 室外加油站測試

`godot --path . --log-file .godot/gas-station.log res://tests/gas_station_playground.tscn`

可直接步行進入商店、維修間與後院，同世界探索，無副本轉場。F1 步行、F2 外觀、F3 商店、F4 維修間、F5 步行回放；E 拾取。詳見 [加油站規格](world/poi_kit/buildings/README.md)。

新世界生成 v6 保留 NORTHLINE 加油站，並加入六種主題、共 18 套路邊小 POI，每處 2–4 件物資及 0–2 隻怪物，位置不規律分布。可回頭探索，剩餘場內物資與存活怪物隨串流及 F6/F9 檢查點保存；舊 v2–v5 存檔保留原世界，需開新局看新版小 POI。加油機目前是造景，燃料從物資搜刮取得。

小 POI 展示場：`godot --path . res://tests/minor_poi_playground.tscn`。左右鍵切換佈局、N 換 seed、F1 步行、F2 總覽。正式道路驗收與完整控制見 [測試指南](docs/guides/playgrounds.md#minor-pois)。

日夜與動態天氣：陰晴、大小雨與霧可自動轉換，屋頂遮雨、天氣進度隨檢查點保存。[天氣驗收操作](docs/guides/playgrounds.md#日夜與天氣驗收)。

副本 v2 的房型、接口、保存和預覽命令見 [室內製作規格](docs/guides/interior-v2.md)。
