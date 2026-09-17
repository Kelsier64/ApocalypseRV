# ApocalypseRV

## 日夜時間

正式世界從第 1 天 **08:00** 開始，現實 **30 分鐘為遊戲一天**。右上角顯示日期／時間；太陽移動、陰影、天空、環境光和霧色同步變化。進入室內時間繼續，SceneTree 暫停才會停止；F6／F9 檢查點保存與恢復時間，舊存檔缺少時間時從第 1 天 08:00 開始。不計算離線時間。

快速觀看四個時段：`godot --path . --log-file .godot/day-night.log res://tests/day_night_playground.tscn`。測試場景 F1 切換清晨／正午／黃昏／夜晚，F12 加速至 1 分鐘一天，Home 停住／繼續；F2 換視角，5 從高處檢查日輪，F11 隱藏測試文字。這些時間快捷鍵只存在於測試場景。

Godot 4.6.1 第一人稱末日公路生存原型：駕駛 RV、搜刮建築、搬運物資、分解製作汽油，並應對會攀車與拆車的殭屍。**目前是單人沙盒**，提供室外檢查點保存，尚無多人、任務、正式勝敗或長局進度；合作生存屬後續願景。

## 文件

- [GDD.md](GDD.md)：遊戲設計、完整玩法、資源數值、目標與未實作願景。
- [architecture.md](architecture.md)：場景、模組契約、資料流、測試範圍與限制。
- [docs 索引](docs/README.md)：開發計畫、驗收紀錄與 archive 歷史文件；現行文件以根目錄版本為準。
- [AGENTS.md](AGENTS.md)：開發約定；原始 [todo](todo) 與 [todo_for_ai](todo_for_ai) 保留作規劃紀錄。

## 啟動

安裝 Godot 4.6.1，將 godot 加入 PATH，在專案根目錄執行：

```powershell
godot --editor --path .
godot --path .
```

主場景為 `world/test_world.tscn`，使用 Jolt Physics，桌面預設 Forward+／Vulkan。開局有完整組裝的 RV、測試物資及殭屍，並生成公路。

戶外已改用林間局部體積霧，會接受太陽與車燈照明；遠處另外保留淡距離霧。更新後須重新啟動遊戲，編輯器需重新載入專案。若顯示卡不支援，可用 `godot --path . --rendering-method gl_compatibility --rendering-driver opengl3`，降級為原距離霧。畫面與測試見 [局部體積霧驗收](docs/validation/2026-09-17-volumetric-fog.md)。

## 怎麼玩

### 工業美術樣板（獨立場景）

正式戶外已採用 [D 低模目標方向](docs/art_targets/outdoor/2026-09-17-d-revision.md)：分叉低模樹冠、簡化泥地、冷霧與固定雲層。F8 切換約 540p 的 3D 渲染／原生解析度，沒有額外像素格或抖色；HUD 保持清楚。驗收見 [正式戶外 D 紀錄](docs/validation/2026-09-17-outdoor-d.md)。後續 [霧效修正](docs/validation/2026-09-17-fog-refinement.md) 保留近景對比，統一天際線與霧色並減弱雲斑。

執行 `godot --path . --log-file .godot/style-sample.log res://tests/industrial_style_playground.tscn`，查看同一 seed 的新舊美術對照。F1 切換樣板／原版、F2 固定視角、F3 正式角色攜引擎走完全程、F4 進入／返回、F6 RV／駕駛室／設備視角、F7 切換測試電量、F8 復古效果、F9 測試牆板損傷、F10 平板、F11 隱藏樣板文字、F5 切換視窗尺寸。這些測試按鍵僅屬樣板，不改正式操作。

獨立樣板仍保留前一輪針葉樹、高窗維修廠與 RV 材質實驗；F1 現在對照的是目前正式美術，不是凍結的歷史版本。正式遊玩請使用主場景；正式畫面驗收使用 `res://tests/outdoor_horror_playground.tscn`，F11 隱藏驗收文字。高窗量體與 RV 實驗材質仍未併入正式版。歷史資料見 [視覺研究](docs/research/2026-09-17-lethal-company-visual-direction.md) 與 [樣板驗收](docs/validation/2026-09-17-style-sample.md)。

### 正式遊玩

車上已裝齊發電機、分解機、平板與工作台。撿物並丟入分解機，從平板製作汽油罐，到合成站取貨，再對 RV 加油口補油。沿公路辨認建築的煙囪、水塔或天線，在停車灣下車，沿土路與路標穿過窄口前往入口。新世界第一棟維修廠位於 (335.2,6,-45)，停車區在 (33,0,-45)，步行約 97 秒。門前 E 進入 50–100 間房的迷宮，回 R001 的 EXIT 門 E 返回。室外世界與 RV 油電持續運作；同局重返保留搜刮和敵人死亡狀態，回到室外可用 F6 保存。

| 操作 | 按鍵 |
|---|---|
| 步行／視角／跳躍 | WASD／滑鼠／Space |
| RV 攀爬 | 面向車壁持續 W；A/D 橫移；S 或 Space 脫離 |
| 撿物／加油 | 瞄準後短按 E；加油須手持汽油罐 |
| 副本進出 | 門前短按 E；出口在 R001 |
| 入座／開平板／拆裝輪胎 | 長按 E 約 1 秒；裝輪胎需手持 Wheel 瞄準輪槽，停穩並熄火 |
| 移動設備 | 長按 F 約 2 秒，左鍵確認、右鍵取消、R 切換貼面／直立、V 切換結構吸附；自由放置 Q/E 轉 15°、Shift 轉 5°、方向鍵移 5 cm |
| 背包選取／丟棄 | 1–6 或滾輪／G；大型物品鎖定選取 |
| 駕駛 | W 油門、A/D 轉向、S 腳煞車、Space 手煞車、E 離座 |
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

Replay 使用腳本控制車輛運動，整合測試另有物理驅動 RV 情境。Headless 通過仍不能代替鏡頭手感、實際輪驅操控、翻車、怪物群與設備對齊的視覺驗收。新增回歸涵蓋製作交易、電池交換、能源、維修、設備清理、重量及磁碟存讀檔；長途經濟仍需調整。

## RV 能源與維護

發電機是設備，電池是可換的道具。車子行駛或原地怠速，只要引擎運轉且發電機正常，就能耗油替插槽電池充電；熄火停車會慢慢耗電。電池沒電仍可坐進駕駛座按 B 手動發動，或直接換一顆電池。地上或背包中的電池不自動供電。

預設 RV 底盤自帶 300 材料單位、24 格道具倉庫、100 燃油容量，附加油孔、道具箱與已裝滿電電池的插槽設備。平板可啟停引擎、切換設備、調整發電門檻／保留油量、查看材料與排隊製作。駕駛座入座後 B 啟停引擎，沒電也能手動發動；獨立引擎開關已移除。瞄準設備顯示用途、E／F／H 操作與失敗原因。

道具箱 E 開啟不耗電的共用道具倉庫，可存入／取出背包道具，保留電量與耐久；箱子拆除不影響存量或容量。手持汽油罐對已安裝加油孔 E 加油，燃油保存在底盤。材料只有數量，由分解取得、製作與維修消耗，不再領出材料包。

電池插槽可用 F 搬移；開始搬移、脫落或損壞時，電池會成為可拾取的掉落道具，保留電量。取消搬移不會自動收回電池。電池短 E 裝入／交換、長 E 取出至背包；同車只接通一顆，倉庫電池不供電。

F6 保存到 `user://rv_checkpoint.save`，F9 載入會取代目前遊戲狀態。保存包含玩家、車輛、設備、油電、物品、工作與已訪 POI；一次只有一個檢查點，不支援副本內保存。沒有存檔時 F9 顯示提示。版本 3 可轉換 v1／v2 檢查點，舊底盤耐久轉入標準引擎（零血保持故障）；v3 空引擎槽保持空槽，保存頭燈、維修蓋及坡板狀態，不補發設備或重排配置。既有轉換包括：油箱燃油歸底盤，材料包轉成數量；游離油箱與材料包歸第一台保存車輛，原檔不會被載入動作覆寫。

```powershell
godot --path . --log-file .godot/rv-systems-visible.log res://tests/rv_systems_playground.tscn -- --replay
```

此場景用正式 RV／設備回放熄火耗電、原地充電、換電池、製作與輪驅轉彎。F2 引擎、F3 換電池、F4 入座、F5 平板、F6 回放、F7 破壞平板、R 重設。測試場按鍵與主世界 F6 存檔各自獨立。

此次設備／儲存調整見 [新版設計與驗收](docs/validation/2026-09-16-rv-shared-storage.md)。執行進度見 [RV 計畫](docs/plans/2026-09-15-rv-systems-roadmap.md)，測試與限制見 [RV 驗收紀錄](docs/validation/2026-09-15-rv-systems.md)。凍結設備對外掛碰撞的力矩傳遞、極端翻車與怪物群尚未全面驗收。

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

按 F6 開始，或命令加 `-- --replay`。回放只在測試場提供起點傳送與自動步行；其餘使用正式主場景、玩家和副本流程。2026-09-15 使用本機 Godot 4.7.2 驗證，CI 仍設定為 4.6.1，未宣稱跨版本驗證。副本目前兩種房型；室外檢查點包含已訪副本狀態，暫不支援在副本內直接保存。

## 公路與沿途探索

室外使用陰天雲層、日夜光照、局部體積霧與灰綠工業配色，配置林帶、土堤、岩石、圍牆和路標。道路有緩起伏、連續彎和 15→10 m 縮窄段；看到 SLOW 請減速。每三個停靠點有兩個離路建築、一個近路小補給。四款入口共用現有室內內容；約 488 m 的密林交錯步道與 1.8 m 窄口允許玩家攜大型物品步行，阻擋 RV 直接開到門口。

新世界採生成 v4：建築距公路約 330 m，樹冠與高灌叢包圍步道。既有生成 v2／v3 存檔保留原地形和入口距離；要體驗新版密林與遠距入口，請開新世界。未記錄生成版本時採 v2。F8 顯示偏好獨立寫入 user://display_preferences.cfg。復古效果只影響室外 3D，不降低背包、平板或互動文字解析度。詳見 [密林驗收紀錄](docs/validation/2026-09-16-dense-forest.md)。

```powershell
godot --path . --log-file .godot/horror-visible.log res://tests/outdoor_horror_playground.tscn
```

F2 切換公路／停車處／遮蔽步道／入口／回望視角，1–4 換四款外觀，F3 回放正式玩家攜引擎步行，F4 在門前送出 E 互動／從室內返回，F5 切換視窗大小，F8 切換復古顯示，R 重設。測試場只替換同一位置的入口模型供比較；正式世界依 seed 配置。截圖、效能與驗證範圍見 [室外氛圍驗收](docs/validation/2026-09-16-outdoor-horror.md)。

在 WorldGenerator 設定 `world_seed` 可重現整條路線，`-1` 每局另選 seed；`profile` 集中景觀、路寬、坡度、密度和串流設定。此版仍是沿公路向前旅行，遠景不提供可探索碰撞，後方已回收的地形不重建。

```powershell
godot --path . --log-file .godot/highway-visible.log res://tests/highway_playground.tscn
```

F1/F2/F3 預覽草原／林地／岩丘，F6 執行固定 seed 的 5 km 輪驅測試，F7 測停車、倒出及返回公路。回放以正式油門／轉向和 VehicleBody3D 輪胎物理移動；僅起點擺位、測試相機及停用耗油屬測試設定。完成後再次按回放鍵會重載測試場，再按一次啟動。可用 `-- --replay` 或 `-- --parking` 自動執行並退出；headless 測試加 `--fixed-fps 60`。

路旁九種模組提供可編輯場景，見 [roadside kit](world/roadside_kit/README.md)。地形驗收與效能紀錄見 [驗收紀錄](docs/validation/2026-09-15-highway.md)。

## 程式位置

`player/` 玩家與互動、`enemies/` AI／選敵、`props/` 可撿物、`rv/` 底盤輪胎、`equipment/` 設備、`world/` 串流／POI／建築、`core/` 共用契約、`tests/` 行為測試及展示。完整對照見 [架構](architecture.md)。


## RV 外觀與駕駛室原型（2026-09-16）

預設 RV 更新為 WAYFARER 工業露營車：深綠車殼、奶油白窗框／屋頂、橘色標示、透明有碰撞的玻璃、前後燈與輪圈。側牆分成六片：面向車頭時，右側由前到後為牆／門／牆，左側為牆／牆／牆；後方是一組向外開啟的雙扇大門。每片側牆、側門整組、後門整組可獨立搬移與破壞，屋頂仍為一整片。

駕駛座綁定座椅、方向盤、儀表台、排檔桿、手煞車與踏板，F 搬移整組。方向盤跟隨底盤轉向，排檔桿／手煞車位置與速度、油電儀表同步車況；操控沿用 B、Space、Z/X/C、R/T。駕駛時背包欄隱藏，底部顯示車況與操作提示，離座恢復。加油孔與電池插槽位於車外維護側。

[模型結構說明](rv/visuals/README.md)；[展示場景](tests/rv_design_workshop.tscn)（F2 外觀、F3 車內、F4 駕駛、F5 輪驅、F6 舊版、F7 控制台）。舊車殼保留在 [rv/legacy/new_rv.tscn](rv/legacy/new_rv.tscn)。

## RV 分片車殼與門（2026-09-16）

短按 E 開關瞄準的門扇，後門兩扇可分別操作；長按 F 搬移整組門框或單片牆。搬移時瞄準底盤空槽，預覽會自動對齊位置與朝向，左鍵安裝、右鍵取消、V 切換自由放置。槽位由底盤保留，不會隨牆片拆除而消失。側牆與側門可互換側面槽位。

綠色表示可裝，紅色會顯示占用、視線或碰撞阻擋原因。開關門會檢查整段路徑，角色或物件進入時停止；再按 E 可反向操作。可移動門扇不允許安裝設備，固定門框可以。搬移或破壞一片牆，只讓附掛在那一片上的設備掉落；取消搬移不會自動收回掉落物。

檢查點保存槽位與門扇角度。舊存檔中位於原廠位置的整片左右牆與後牆會轉換成新模組；已自訂位置的舊牆保留，載入不覆寫原檔。

```powershell
godot --path . --log-file .godot/rv-doors-visible.log res://tests/rv_door_playground.tscn
```

測試場 F2 側門、F3／F4 後門左／右扇、F5 搬移側門、F6 切換障礙箱、F7 搬移後門；E 與滑鼠安裝使用正式互動流程，F5／F7 為測試捷徑。詳見 [驗收紀錄](docs/validation/2026-09-16-rv-structure-doors.md)。

## 完整 RV、新底盤與可替換引擎

正式車已預裝完整設備和標準引擎，車內保留中央走道，道具箱內有兩包引擎維修包。底盤已改為原生網格車架，車頭下方是固定引擎艙；引擎故障只停止動力，車體、電池、倉庫、煞車和座位仍可用。標準／強化引擎與維修包可從平板製作，強化引擎增加 25% 動力及 15% 引擎油耗。

後方坡板供手持大型道具走上車；展開時禁止起步、仍可怠速發電。離座找不到安全位置時會提示並留在座位。儀表與 HUD 顯示汽車式狀態燈，頭尾燈、煞車燈及倒車燈實際耗電。牆／門／玻璃有三級受損外觀。

```powershell
godot --path . --log-file .godot/rv-rebuild-visible.log res://tests/rv_rebuild_playground.tscn
```

F8 引擎艙（E 開蓋）、F9 後門／坡板、F10 故障燈、F11 夜間、F12 輪驅回放；這些是測試場快捷鍵。
[完整計畫](docs/plans/2026-09-16-rv-rebuild-engine.md) · [驗收與截圖](docs/validation/2026-09-16-rv-rebuild-engine.md)。

## 怪物掛門與登頂（2026-09-16）

怪物依接近位置選擇掛門破門或登頂破頂；抓車使用相對速度，急加速／急煞／轉彎會消耗掛車耐力或打斷車頂攻擊。門打開／拆除後解除掛握，屋頂破壞後失去支撐掉落。

```powershell
godot --path . --log-file .godot/boarding-visible.log res://tests/monster_boarding_playground.tscn
```

測試場同時展示兩種行為，為方便觀察提高門頂耐久及掛門耐力；F6 將門耐久設為一擊可破、F5 屋頂一擊可破、F7 耗盡抓握、F2 切換腳本移動、R 重置。這些是測試設定，正式敵人使用一般耐久。
[驗收紀錄](docs/validation/2026-09-16-monster-boarding.md)。

追蹤／近戰回歸場景：

```powershell
godot --path . --log-file .godot/pursuit-visible.log res://tests/monster_pursuit_playground.tscn
```

藍色方柱標記玩家，紅色為正式 Zombie，黃色小方塊為可受傷設備。玩家生命提高且保持介面移動鎖，觀察怪物追近後是否持續扣血。F3 放入牆壁並固定怪物移速，F4 移除牆壁；牆存在時玩家不受傷，移除後恢復近戰。[修正與驗收](docs/validation/2026-09-16-monster-pursuit.md)。

破口進出與車內追擊：

```powershell
godot --path . --log-file .godot/cabin-visible.log res://tests/monster_cabin_playground.tscn
```

開局怪物破側門後追擊駕駛。F3 切換屋頂怪物破頂落入車內，F4 將玩家移到車外觀察怪物追出，R 重設。初始只隱藏屋頂外觀方便觀察，碰撞保留；展示把目標門／屋頂設為 15 HP、玩家設為 10000 HP，攻擊和移動規則沿用正式設定。[驗收紀錄](docs/validation/2026-09-16-monster-cabin.md)。

追蹤／近戰回歸場景：

```powershell
godot --path . --log-file .godot/pursuit-visible.log res://tests/monster_pursuit_playground.tscn
```

藍色方柱標記玩家，紅色為正式 Zombie，黃色小方塊為可受傷設備。玩家生命提高且保持介面移動鎖，觀察怪物追近後是否持續扣血。F3 放入牆壁並固定怪物移速，F4 移除牆壁；牆存在時玩家不受傷，移除後恢復近戰。[修正與驗收](docs/validation/2026-09-16-monster-pursuit.md)。

## 工業恐怖外觀（2026-09-17）

室外植物、地面、四款入口與 RV／設備已使用統一的老舊工業材質；生成紋理與完整提示詞見 [材質說明](assets/materials/industrial/README.md)。HUD、背包和平板保留操作方式，改為方角暗底及灰白／暗黃配色。新外觀適用新舊存檔，不變更世界位置；舊生成版本仍保留其原植物配置。

室外展示場新增 **F6** 循環 RV 外觀／駕駛室／設備、**F7** 切換測試電池電量、**F9** 切換側牆損傷、**F10** 開啟正式平板介面。正式遊戲不增加這些快捷鍵。RV 車內暖燈隨車頂與既有待機供電；F8 仍只切换室外復古效果，文字保持清晰。

[美術驗收與截圖](docs/validation/2026-09-17-industrial-art.md)
