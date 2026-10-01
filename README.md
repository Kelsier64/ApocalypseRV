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

主場景為 `world/main_world.tscn`，使用 60 Hz／Jolt Physics（32／32 次求解），桌面預設 Forward+／Vulkan。玩家出生於半地下避難所車庫，RV 已可駕駛，發電機、工作台及分解機須自行搬上車。整備時時間與敵人停止，門旁 E 按鈕開門並開始旅程；RV 與玩家離開後車庫永久關閉，未帶走物資無法再取回。公路後方由廢棄車陣封死。原 `world/test_world.tscn` 保留為測試場與舊存檔入口。

戶外已改用林間局部體積霧，會接受太陽與車燈照明；遠處另外保留淡距離霧。更新後須重新啟動遊戲，編輯器需重新載入專案。若顯示卡不支援，可用 `godot --path . --rendering-method gl_compatibility --rendering-driver opengl3`，降級為原距離霧。畫面與測試見 [局部體積霧驗收](docs/validation/2026-09-17-volumetric-fog.md)。

正式新局使用生成 v8，沿公路獨立抽取釘帶、一般／封路廢車及 Raker；起點前 450 m 保持安全。一般廢車保留中央通道，偶發車陣會封路；本版沒有廢車清除或撞毀樹木功能。靜態內容回訪按原位重建，怪物死亡或超出戶外前後約 450 m 後不補出。v2–v7 存檔保留原世界規則，檢查點仍 v3。規則與驗收見 [公路隨機刷新](docs/plans/random_spawn.md)。

## 怎麼玩

先在車庫把需要的發電機、分解機與工作台搬上車，平板已預裝。撿物並丟入分解機，從平板製作汽油罐，到工作台取貨並補油。沿公路路標與步道前往混凝土地堡入口，面向鋼門 E 進入。新訪軍事地堡以 16 個房型模組為池，目標 30–60 個模組、隨機 1–3 層；接口耗盡可能提早停止，樓梯放不下時保留較少樓層。探索時可短按 E 拾取散落零件、長按 E 1 秒從補給箱每次取出一件物資，並留意深處可能出現的 Raker：每個合格生成機會獨立以 30% 機率抽取，因此一座地堡可能沒有、只有一隻或有多隻。深入地堡可帶回一具耐久 70% 的強化引擎；HUD 會提示所在房間與返程。返回 B1 ENTRY 的 EXIT 門 E 回地面；M 顯示已探索地圖，Page Up／Down 切層。室外世界與 RV 油電持續運作，剩餘物資、補給箱、存活怪物及探索會保留，回室外 F6 保存。已訪舊 v3 地堡維持原布局與內容，不會補抽新物資；舊 v1／v2 副本紀錄會清除，其餘世界資料保留。見 [地堡指南](docs/guides/bunker-interior.md)與[先前內容驗證](docs/validation/2026-09-29-bunker-content.md)。

| 操作 | 按鍵 |
|---|---|
| 步行／衝刺／視角／跳躍 | WASD／左 Shift／滑鼠／Space；衝刺與跳躍消耗耐力，休息後恢復 |
| RV 攀爬 | 面向車壁持續 W；A/D 橫移；S 或 Space 脫離 |
| 撿物／加油 | 瞄準後短按 E；加油須手持汽油罐 |
| 副本進出 | 入口鋼門前短按 E；返回 B1 ENTRY 的 EXIT 門短按 E |
| 入座／開平板／拆裝輪胎 | 長按 E 約 1 秒；裝輪胎需手持 Wheel 瞄準輪槽，停穩並熄火 |
| 移動設備 | 長按 F 約 2 秒，左鍵確認、右鍵取消、R 切換貼面／直立、V 切換結構吸附；自由放置 Q/E 轉 15°、Shift 轉 5°、方向鍵移 5 cm |
| 背包選取／丟棄 | 1–6 或滾輪／G；大型物品鎖定選取 |
| 手電筒 | 出生區地面 E 拾取；選取手持後 L 開關，滿電累計照明 5 分鐘，暫無充電 |
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

新版地堡房間採重度廢棄軍事設施，包含寢室、醫療、倉儲、維修、指揮與機電空間。入口與樓梯保留照明，其餘模組約 60% 熄燈，回訪維持相同亮暗位置。手電筒在初始世界出生區旁，須自行拾取；切換物品或搬大型引擎時無法照明，剩餘電量會保存。既有地堡使用原房間版本，不重建家具或改燈。

## 驗證

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1
# 完整回歸，包含正式主世界啟動
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -Suite full
# 開發中只跑相關測試；不額外建立主世界
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -TestFilter 'test_bunker_*.gd,test_interior_*.gd'
```

預設執行 `quick` 快速行為集；`-Suite integration`、`slow`、`assets` 分別執行整合、長情境與資產驗收，`smoke` 只驗證正式世界就緒及移動，`full` 執行全部有效測試與 smoke。CI 分組執行全部覆蓋。`-TestFilter` 覆蓋分組選擇，支援逗號分隔樣式、去重與排序；需要同時啟動主世界時加 `-Smoke`。

Runner 核對 `.godot-version`，共用一次匯入，使用固定 60 fps 模擬時間解除 headless 的實時節流，保留專案 60 Hz 物理與求解器設定。`-List` 不啟動引擎；`-SkipImport` 適用於已匯入且資產沒有變更的工作樹；`-RealTime` 可對照實時排程；`-StartAt test_name` 從指定測試接續。每次執行獨立保存 `manifest.txt`、`results.json`、`timings.csv` 與日誌到 `.godot/test-logs/`，失敗後繼續收集結果（`-FailFast` 可提前停止）。完整說明與新增測試規則見 [測試指南](tests/README.md)；可用 `-Godot 'C:/path/to/godot.exe'` 指定引擎。

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
