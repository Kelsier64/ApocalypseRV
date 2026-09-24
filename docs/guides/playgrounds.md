# 遊玩與測試場指南

正式遊戲操作見 [README](../../README.md)，規則與數值見 [GDD](../../GDD.md)。以下保留各測試場命令、快捷鍵、測試設定與限制；測試場按鍵不等同主世界按鍵。

## 目錄

- [RV 能源與維護](#section-1)
- [RV 車殼、駕駛室與門](#section-2)
- [完整 RV 與可替換引擎](#section-3)
- [公路與沿途探索](#section-4)
- [POI 資產與副本](#section-5)
- [日夜時間](#section-6)
- [正式美術與獨立樣板](#section-7)
- [攀爬與怪物測試場](#section-8)
- [加油站室外探索](#gas-station)

<a id="section-1"></a>

## RV 能源與維護

發電機是設備，電池是可換的道具。車子行駛或原地怠速，只要引擎運轉且發電機正常，就能耗油替插槽電池充電；熄火停車會慢慢耗電。電池沒電仍可坐進駕駛座按 B 手動發動，或直接換一顆電池。地上或背包中的電池不自動供電。

預設 RV 底盤自帶 300 材料單位、24 格道具倉庫、100 燃油容量，附加油孔、道具箱與已裝滿電電池的插槽設備。平板可啟停引擎、切換設備、調整發電門檻／保留油量、查看材料與排隊製作。駕駛座入座後 B 啟停引擎，沒電也能手動發動；獨立引擎開關已移除。瞄準設備顯示用途、E／F／H 操作與失敗原因。

道具箱 E 開啟不耗電的共用道具倉庫，可存入／取出背包道具，保留電量與耐久；箱子拆除不影響存量或容量。手持汽油罐對已安裝加油孔 E 加油，燃油保存在底盤。材料只有數量，由分解取得、製作與維修消耗，不再領出材料包。

電池插槽可用 F 搬移；開始搬移、脫落或損壞時，電池會成為可拾取的掉落道具，保留電量。取消搬移不會自動收回電池。電池短 E 裝入／交換、長 E 取出至背包；同車只接通一顆，倉庫電池不供電。

F6 保存到 `user://rv_checkpoint.save`，F9 限室外一般操作狀態使用；完成驗證與重建後才取代目前遊戲，失敗保留原世界。成功保存會將上一份有效檔備份至 `rv_checkpoint.save.bak`。保存包含玩家、車輛、設備、油電、物品、工作與已訪 POI；一次只有一個檢查點，不支援副本內保存。沒有存檔時 F9 顯示提示。版本 3 可轉換 v1／v2 檢查點，舊底盤耐久轉入標準引擎（零血保持故障）；v3 空引擎槽保持空槽，保存頭燈、維修蓋及坡板狀態，不補發設備或重排配置。既有轉換包括：油箱燃油歸底盤，材料包轉成數量；游離油箱與材料包歸第一台保存車輛，原檔不會被載入動作覆寫。

```powershell
godot --path . --log-file .godot/rv-systems-visible.log res://tests/rv_systems_playground.tscn -- --replay
```

此場景用正式 RV／設備回放熄火耗電、原地充電、換電池、製作與輪驅轉彎。F2 引擎、F3 換電池、F4 入座、F5 平板、F6 回放、F7 破壞平板、R 重設。測試場按鍵與主世界 F6 存檔各自獨立。

此次設備／儲存調整見 [新版設計與驗收](../../docs/validation/2026-09-16-rv-shared-storage.md)。執行進度見 [RV 計畫](../../docs/plans/2026-09-15-rv-systems-roadmap.md)，測試與限制見 [RV 驗收紀錄](../../docs/validation/2026-09-15-rv-systems.md)。凍結設備對外掛碰撞的力矩傳遞、極端翻車與怪物群尚未全面驗收。

<a id="section-2"></a>

## RV 車殼、駕駛室與門

預設 RV 更新為 WAYFARER 工業露營車：深綠車殼、奶油白窗框／屋頂、橘色標示、透明有碰撞的玻璃、前後燈與輪圈。側牆分成六片：面向車頭時，右側由前到後為牆／門／牆，左側為牆／牆／牆；後方是一組向外開啟的雙扇大門。每片側牆、側門整組、後門整組可獨立搬移與破壞，屋頂仍為一整片。

駕駛座綁定座椅、方向盤、儀表台、排檔桿、手煞車與踏板，F 搬移整組。方向盤跟隨底盤轉向，排檔桿／手煞車位置與速度、油電儀表同步車況；操控沿用 B、Space、Z/X/C、R/T。駕駛時背包欄隱藏，底部顯示車況與操作提示，離座恢復。加油孔與電池插槽位於車外維護側。

[模型結構說明](../../rv/visuals/README.md)；[展示場景](../../tests/rv_design_workshop.tscn)（F2 外觀、F3 車內、F4 駕駛、F5 輪驅、F6 舊版、F7 控制台）。舊車殼保留在 [rv/legacy/new_rv.tscn](../../rv/legacy/new_rv.tscn)。

短按 E 開關瞄準的門扇，後門兩扇可分別操作；長按 F 搬移整組門框或單片牆。搬移時瞄準底盤空槽，預覽會自動對齊位置與朝向，左鍵安裝、右鍵取消、V 切換自由放置。槽位由底盤保留，不會隨牆片拆除而消失。側牆與側門可互換側面槽位。

綠色表示可裝，紅色會顯示占用、視線或碰撞阻擋原因。開關門會檢查整段路徑，角色或物件進入時停止；再按 E 可反向操作。可移動門扇不允許安裝設備，固定門框可以。搬移或破壞一片牆，只讓附掛在那一片上的設備掉落；取消搬移不會自動收回掉落物。

檢查點保存槽位與門扇角度。舊存檔中位於原廠位置的整片左右牆與後牆會轉換成新模組；已自訂位置的舊牆保留，載入不覆寫原檔。

```powershell
godot --path . --log-file .godot/rv-doors-visible.log res://tests/rv_door_playground.tscn
```

測試場 F2 側門、F3／F4 後門左／右扇、F5 搬移側門、F6 切換障礙箱、F7 搬移後門；E 與滑鼠安裝使用正式互動流程，F5／F7 為測試捷徑。詳見 [驗收紀錄](../../docs/validation/2026-09-16-rv-structure-doors.md)。

<a id="section-3"></a>

## 完整 RV 與可替換引擎

正式車已預裝完整設備和標準引擎，車內保留中央走道，道具箱內有兩包引擎維修包。底盤已改為原生網格車架，車頭下方是固定引擎艙；引擎故障只停止動力，車體、電池、倉庫、煞車和座位仍可用。標準／強化引擎與維修包可從平板製作，強化引擎增加 25% 動力及 15% 引擎油耗。

後方坡板供手持大型道具走上車；展開時禁止起步、仍可怠速發電。離座找不到安全位置時會提示並留在座位。儀表與 HUD 顯示汽車式狀態燈，頭尾燈、煞車燈及倒車燈實際耗電。牆／門／玻璃有三級受損外觀。

```powershell
godot --path . --log-file .godot/rv-rebuild-visible.log res://tests/rv_rebuild_playground.tscn
```

F8 引擎艙（E 開蓋）、F9 後門／坡板、F10 故障燈、F11 夜間、F12 輪驅回放；這些是測試場快捷鍵。
[完整計畫](../../docs/plans/2026-09-16-rv-rebuild-engine.md) · [驗收與截圖](../../docs/validation/2026-09-16-rv-rebuild-engine.md)。

<a id="section-4"></a>

## 公路與沿途探索

室外使用陰天雲層、日夜光照、局部體積霧與灰綠工業配色，配置林帶、土堤、岩石、圍牆和路標。道路有緩起伏、連續彎和 15→10 m 縮窄段；看到 SLOW 請減速。每三個停靠點有兩個離路建築、一個近路小補給。四款入口共用現有室內內容；約 488 m 的密林交錯步道與 1.8 m 窄口允許玩家攜大型物品步行，阻擋 RV 直接開到門口。

新世界採生成 v4：建築距公路約 330 m，樹冠與高灌叢包圍步道。既有生成 v2／v3 存檔保留原地形和入口距離；要體驗新版密林與遠距入口，請開新世界。未記錄生成版本時採 v2。F8 顯示偏好獨立寫入 user://display_preferences.cfg。復古效果只影響室外 3D，不降低背包、平板或互動文字解析度。詳見 [密林驗收紀錄](../../docs/validation/2026-09-16-dense-forest.md)。

```powershell
godot --path . --log-file .godot/horror-visible.log res://tests/outdoor_horror_playground.tscn
```

F2 切換公路／停車處／遮蔽步道／入口／回望視角，1–4 換四款外觀，F3 回放正式玩家攜引擎步行，F4 在門前送出 E 互動／從室內返回，F5 切換視窗大小，F8 切換復古顯示，R 重設。測試場只替換同一位置的入口模型供比較；正式世界依 seed 配置。截圖、效能與驗證範圍見 [室外氛圍驗收](../../docs/validation/2026-09-16-outdoor-horror.md)。

在 WorldGenerator 設定 `world_seed` 可重現整條路線，`-1` 每局另選 seed；`profile` 集中景觀、路寬、坡度、密度和串流設定。此版仍是沿公路向前旅行，遠景不提供可探索碰撞，後方已回收的地形不重建。

```powershell
godot --path . --log-file .godot/highway-visible.log res://tests/highway_playground.tscn
```

F1/F2/F3 預覽草原／林地／岩丘，F6 執行固定 seed 的 5 km 輪驅測試，F7 測停車、倒出及返回公路。回放以正式油門／轉向和 VehicleBody3D 輪胎物理移動；僅起點擺位、測試相機及停用耗油屬測試設定。完成後再次按回放鍵會重載測試場，再按一次啟動。可用 `-- --replay` 或 `-- --parking` 自動執行並退出；headless 測試加 `--fixed-fps 60`。

路旁九種模組提供可編輯場景，見 [roadside kit](../../world/roadside_kit/README.md)。地形驗收與效能紀錄見 [驗收紀錄](../../docs/validation/2026-09-15-highway.md)。

<a id="section-5"></a>

## POI 資產與副本

16 個地堡模組、六種首批尺寸、隨機 1–3 層。外觀／碰撞／門口分層，可在編輯器擴充。[製作規格](bunker-interior.md)。

```powershell
godot --path . --log-file .godot/bunker.log res://tests/bunker_playground.tscn -- --rooms=12 --floors=3 --seed=42
godot --path . --log-file .godot/bunker-main.log res://tests/poi_instance_playground.tscn -- --replay
```

地堡測試場 F1 步行、F2 總覽、F3 掀頂、F5 連續搬運回放、R 重建、F8 截圖；M／Page Up／Down 是正式探索地圖。主世界回放 F6 或 --replay 從入口以 E 進出；F7 查看入口外觀、F8 截圖至 `.godot/bunker-exterior.png`。回放的測試引擎不屬於正式生成。舊資產 workshop／v2 playground 已移除。

<a id="section-6"></a>

## 日夜時間

正式世界從第 1 天 **08:00** 開始，現實 **30 分鐘為遊戲一天**。右上角顯示日期／時間；太陽移動、陰影、天空、環境光和霧色同步變化。進入室內時間繼續，SceneTree 暫停或檢查點載入準備期間停止；F6／F9 檢查點保存與恢復時間，舊存檔缺少時間時從第 1 天 08:00 開始。不計算離線時間。

快速觀看四個時段：`godot --path . --log-file .godot/day-night.log res://tests/day_night_playground.tscn`。測試場景 F1 切換清晨／正午／黃昏／夜晚，F12 加速至 1 分鐘一天，Home 停住／繼續；F2 換視角，5 從高處檢查日輪，F11 隱藏測試文字。這些時間快捷鍵只存在於測試場景。

<a id="section-7"></a>

## 正式美術與獨立樣板

正式戶外已採用 [D 低模目標方向](../../docs/art_targets/outdoor/2026-09-17-d-revision.md)：分叉低模樹冠、簡化泥地、冷霧與固定雲層。F8 切換約 540p 的 3D 渲染／原生解析度，沒有額外像素格或抖色；HUD 保持清楚。驗收見 [正式戶外 D 紀錄](../../docs/validation/2026-09-17-outdoor-d.md)。後續 [霧效修正](../../docs/validation/2026-09-17-fog-refinement.md) 保留近景對比，統一天際線與霧色並減弱雲斑。

執行 `godot --path . --log-file .godot/style-sample.log res://tests/industrial_style_playground.tscn`，查看同一 seed 的新舊美術對照。F1 切換樣板／原版、F2 固定視角、F3 正式角色攜引擎走完全程、F4 進入／返回、F6 RV／駕駛室／設備視角、F7 切換測試電量、F8 復古效果、F9 測試牆板損傷、F10 平板、F11 隱藏樣板文字、F5 切換視窗尺寸。這些測試按鍵僅屬樣板，不改正式操作。

獨立樣板仍保留前一輪針葉樹、高窗維修廠與 RV 材質實驗；F1 現在對照的是目前正式美術，不是凍結的歷史版本。正式遊玩請使用主場景；正式畫面驗收使用 `res://tests/outdoor_horror_playground.tscn`，F11 隱藏驗收文字。高窗量體與 RV 實驗材質仍未併入正式版。歷史資料見 [視覺研究](../../docs/research/2026-09-17-lethal-company-visual-direction.md) 與 [樣板驗收](../../docs/validation/2026-09-17-style-sample.md)。

室外植物、地面、四款入口與 RV／設備已使用統一的老舊工業材質；生成紋理與完整提示詞見 [材質說明](../../assets/materials/industrial/README.md)。HUD、背包和平板保留操作方式，改為方角暗底及灰白／暗黃配色。新外觀適用新舊存檔，不變更世界位置；舊生成版本仍保留其原植物配置。

室外展示場新增 **F6** 循環 RV 外觀／駕駛室／設備、**F7** 切換測試電池電量、**F9** 切換側牆損傷、**F10** 開啟正式平板介面。正式遊戲不增加這些快捷鍵。RV 車內暖燈由獨立燈條設備、控制台請求與統一電力結算供電；F8 仍只切換室外復古效果，文字保持清晰。

[美術驗收與截圖](../../docs/validation/2026-09-17-industrial-art.md)

<a id="section-8"></a>

## 攀爬與怪物測試場

移動 RV 攀爬展示：

```powershell
godot --path . --log-file .godot/climb-playground.log res://tests/rv_climb_playground.tscn -- --replay
```

藍色是玩家，灰白模型是怪物。F2 切換車輛運動、F3 自動攀爬、F4 換攝影機、F5 玩家入座測拆頂、R 重設。去掉 `-- --replay` 可手動 WASD／Space。這些按鍵只用於 playground，與主遊戲 R 的設備模式切換不同。

Replay 使用腳本控制車輛運動，整合測試另有物理驅動 RV 情境。Headless 通過仍不能代替鏡頭手感、實際輪驅操控、翻車、怪物群與設備對齊的視覺驗收。新增回歸涵蓋製作交易、電池交換、能源、維修、設備清理、重量及磁碟存讀檔；長途經濟仍需調整。

怪物依接近位置選擇掛門破門或登頂破頂；抓車使用相對速度，急加速／急煞／轉彎會消耗掛車耐力或打斷車頂攻擊。門打開／拆除後解除掛握，屋頂破壞後失去支撐掉落。

```powershell
godot --path . --log-file .godot/boarding-visible.log res://tests/monster_boarding_playground.tscn
```

測試場同時展示兩種行為，為方便觀察提高門頂耐久及掛門耐力；F6 將門耐久設為一擊可破、F5 屋頂一擊可破、F7 耗盡抓握、F2 切換腳本移動、R 重置。這些是測試設定，正式敵人使用一般耐久。
[驗收紀錄](../../docs/validation/2026-09-16-monster-boarding.md)。

追蹤／近戰回歸場景：

```powershell
godot --path . --log-file .godot/pursuit-visible.log res://tests/monster_pursuit_playground.tscn
```

藍色方柱標記玩家，灰白模型為正式 Zombie，黃色小方塊為可受傷設備。玩家生命提高且保持介面移動鎖，觀察怪物追近後是否持續扣血。F3 放入牆壁並固定怪物移速，F4 移除牆壁；牆存在時玩家不受傷，移除後恢復近戰。[修正與驗收](../../docs/validation/2026-09-16-monster-pursuit.md)。

新怪物模型的近距離預覽沿用上述追擊行為，另有 F6 扣怪物 5 HP、R 重設。目前僅播放 `TEST_InPlace` 循環，正式行走／攻擊／攀爬動畫待補。[素材設定與限制](../../assets/models/monster/README.md)。

```powershell
godot --path . --log-file .godot/monster-model-preview.log res://tests/monster_model_playground.tscn
```

破口進出與車內追擊：

```powershell
godot --path . --log-file .godot/cabin-visible.log res://tests/monster_cabin_playground.tscn
```

開局怪物破側門後追擊駕駛。F3 切換屋頂怪物破頂落入車內，F4 將玩家移到車外觀察怪物追出，R 重設。初始只隱藏屋頂外觀方便觀察，碰撞保留；展示把目標門／屋頂設為 15 HP、玩家設為 10000 HP，攻擊和移動規則沿用正式設定。[驗收紀錄](../../docs/validation/2026-09-16-monster-cabin.md)。

<a id="gas-station"></a>

## 加油站室外探索測試

直接開啟 [gas_station_playground.tscn](../../tests/gas_station_playground.tscn)，或執行 `godot --path . --log-file .godot/gas-station.log res://tests/gas_station_playground.tscn`。
商店、維修間、後門與加油棚同處室外世界，沒有副本入口。WASD／E／G 沿用正式操作；F1 步行、F2 外觀、F3 商店、F4 維修間、F5 步行回放、F8 截圖。詳見 [資產與測試規格](../../world/poi_kit/buildings/README.md)。

加油機已接入自製 GLB。F6 近看加油機，F7 切換灰盒／模型外觀，保留同一套碰撞；本場景的 F6 不保存遊戲。模型說明見 [素材匯入樣板](../../assets/models/gas_station/README.md)。

## 正式世界加油站

`godot --path . --log-file .godot/production-station-visible.log res://tests/production_gas_station_playground.tscn`

繼承主場景，以 v5、seed 42 的正式場址、整地、森林、物資與 RV 啟動。F2 鳥瞰、F3 玩家視角、F5 公路轉入停車區的真實輪驅回放、F7 截圖至 `.godot/production-station.png`。回放只在初始化放置車輛，行駛不改 transform；怪物在此驗收場移除，正常主遊戲維持原生成。原獨立灰盒場仍供素材 A/B。


## 行駛幀時間量測

`godot --path . --log-file .godot/driving-benchmark.log -s res://scripts/benchmark_driving.gd`

使用正式主世界／RV、固定 seed 42、08:00 陰天、1024 × 720，停車取樣 4 秒，再以正式輪胎驅動直行取樣 24 秒。只在此量測程序停用 VSync，輸出平均、P95、P99、最慢幀及 CPU 渲染／GPU 時間；不改玩家偏好。結束自動退出。避免同時執行其他測試；headless 數據不能當作 GPU 幀時間。這是開局短路線量測，不包含長途、所有天氣與全部視角。

加 `-- --no-mirrors` 關閉鏡面作對照。`-- --night-lights` 改為 22:00 停車、開蓋及開啟車內／工作／維修燈，暖機 4 秒後取樣 12 秒；再加 `--lights-off` 作同場景關燈對照。開蓋是效能場的初始化設定。

## 駕駛體驗與完整出車回放

`godot --path . --log-file .godot/driving-experience.log res://tests/driving_experience_playground.tscn`

開局入座；F6 左鏡、F7 右鏡、F1 前方；紅色／藍色障礙分別在車尾左右。F8 引擎艙視角後按 E 開蓋、F9 坡板、F11 夜間並開工作／維修燈、F3 車內視角、F12 正式輪驅回放。照明與儀表亮度統一由控制台操作。測試視角定位只用於觀察，不代表玩家已走到該位置。

正式主世界整趟回放：

```powershell
godot --path . --log-file .godot/trip-day.log -s res://scripts/replay_rv_trip.gd
godot --path . --log-file .godot/trip-night.log -s res://scripts/replay_rv_trip.gd -- --night --stay
```

涵蓋輪驅出車、步行搬運、分解／製作、故障維修與引擎交換、收妥車輛、存讀檔後再出發。`--stay` 保留結果視窗；headless 可加 `--fixed-fps 60`。固定種子、移除怪物、替換引擎／廢料供應與零耐久故障是測試設定；取放、製作與維修呼叫正式服務入口，並非逐一滑鼠瞄準的人工遊玩。存檔使用獨立 `user://driving_trip_validation.save`。結果與限制見[驗收紀錄](../validation/2026-09-22-driving-experience.md)。

## 日夜與天氣驗收

執行 `godot --path . --log-file .godot/weather-visual.log res://tests/weather_playground.tscn`。

- `6` 依序切換陰天、小雨、大雨、小霧、大霧、晴天、大雨加大霧；預設立即切換方便比較。
- `7` 雨勢、`8` 霧量、`9` 晴陰；晴天清空雨霧，增加雨霧會切回陰天。
- `0` 切換自動天氣和時間推進；`F12` 一分鐘一天，`Home` 暫停／恢復時間；自然天氣使用平滑過渡。
- `F1` 黎明／正午／黃昏／夜晚；`F2` 場址視角；`F6` RV／車內／設備；`Backspace` 破壞車頂；`R` 重置。
- `F3` 既有步行回放、`F4` 入口互動／離開副本；`F8` 畫面縮放，`F11` 隱藏說明。

每 5 秒記錄天氣、GPU 粒子提交數、覆蓋範圍、最高射線數及平均幀時間。粒子提交數不是遮擋後實際可見數。切換後至少等待一個完整取樣區間再比較；固定視角測量不代表行車／串流壓力測試。聲音遮蔽在固定視角跟隨驗收攝影機，步行時跟隨玩家。


### 直接檢查新版大範圍雨幕

`godot --path . --log-file .godot/rain-user-review.log res://tests/weather_playground.tscn -- --heavy-rain`

直接以正午大雨開啟，無須等待自然天氣。`6` 切換天氣、`7` 循環雨勢、`F2` 更換戶外視角、`F6` 車外／車內、`Backspace` 破壞車頂。請確認近處密度、遠方樹林和建築前也有雨，轉頭／行走不露出小範圍雨柱，車內能看見窗外雨幕。高度快取首次填充約半秒，傳送到新位置時未知區暫時不顯示雨，避免穿屋頂。

新版由使用者負責目視驗收；自動化只檢查行為與兩種渲染器的編譯／執行紀錄，不使用 Computer Use。

## 裂爪 Raker（2.18 m）

`godot --path . --log-file .godot/raker-visual.log res://tests/raker_playground.tscn`

正式新怪物追擊正式玩家。F6 受傷／打斷攻擊，F7 死亡，Space 移動玩家躲避，F8 輪看 23 段動畫，F9 暫停於片段 60% 位置，R 重設回到 AI。玩家生命提高以便觀察。

### Raker 車輛追逐與步態測試

`godot --path . --log-file .godot/raker-vehicle-playground.log res://tests/raker_vehicle_playground.tscn`

正式輪驅 RV 與新版 Raker，平坦道路長 2.4 km，玩家開始坐在車上；此測試場將玩家 HP 提至 10000、怪物感知／失去興趣距離提高，方便反覆追逐。F2 定速是油門／煞車控制，實際速度受車輛動力限制，不是直接平移車輛；加 `-- --replay` 會自動選擇 36 km/h 目標。

| 按鍵 | 功能 |
| --- | --- |
| W / S、A / D | 油門／煞車、轉向 |
| F1 | 回到車上，手動駕駛 |
| F2 | 定速目標循環 0 / 18 / 36 / 61 / 90 km/h |
| F3 | 停車 |
| F4 | 全景、怪物近景、側面 |
| F5 | 下車測試步行追逐 |
| F6 | 在車後重生怪物，結束預覽並恢復 AI |
| F7 | 10 點受傷，觀察中斷 |
| F8 / F9 | 車旁空地輪看待機／走／跑／狂奔；暫停／續播 |
| F10 | 輪驅 S 型轉彎回放，36 km/h 目標；再次按下停止自動轉向 |
| R | 重設整個場景及車輛 |

畫面顯示車速、怪物速度、步態、動畫與距離。建議先 F2 測低速追上，再選 90 km/h 目標觀察 64.8 km/h 狂奔上限；定速期間 A/D 仍可轉向，怪物貼車後按 F6 可重測。預覽可配合 F4 側面檢查駝背和頸部，F6 返回 AI。啟動時加 `-- --preview` 可直接看待機姿勢，`-- --turns` 直接啟動轉彎回放。無限碰撞地板防止掉出路面，超過道路範圍會自動重設。測試場入口與操作有 [自動回歸](../../tests/test_raker_playground.gd)。

`godot --path . --log-file .godot/raker-climb.log res://tests/rv_climb_playground.tscn -- --replay --raker`

新怪物與玩家攀上移動 RV；F5 入座觸發砸頂、屋頂破壞及墜落。其他快捷鍵沿用 RV 攀爬測試場。

## 多樓層室內 v2


## 輪胎爆胎與釘帶

`godot --path . --log-file .godot/tire-playground.log res://tests/tire_puncture_playground.tscn`

F6 自動油門駛過單側釘帶，7 秒後漸進煞車；也可加 `-- --replay` 自動開始。1–4 分別讓左前／右前／左後／右後爆胎，R 重設。Space 啟動引擎並切換手煞車，W/S 油門／煞車、A/D 修正、Z 倒車、X 前進。使用正式輪驅與爆胎邏輯，畫面顯示各輪耐久和故障位置。這裡的 F6 是測試快捷鍵，正式世界仍為保存。

自動化 `test_tire_handling.gd` 檢查 16 種組合、左右偏移、成對抵銷、前後驅動差異、停車、倒車、反打、高速和真實釘帶先後接觸；`test_tire_puncture.gd` 驗證維修／換胎／保存與確定性生成。驗收及尚未完成的目視檢查見 [爆胎紀錄](../validation/2026-09-22-tire-puncture.md)。

## Raker 抓咬測試（v016）

`godot --path . res://tests/raker_vehicle_playground.tscn -- --grab-ground --grab-seed=218`

`--grab-cabin`／`--grab-driver` 分別啟動車內步行／行駛駕駛情境，三者擇一。F11 循環三情境、F12 重試，F7 對怪物造成 10 傷害中斷。測試時恢復玩家 100 HP，使用正式 AI、車輪物理、座位、碰撞和抓咬判定；2 秒準備後開始接近。Space 需反覆按下並放開；可觀察 HUD 80% 刻度、鏡頭、張嘴與雙手接觸。F11/F12/F7 在被抓時也可用，僅 playground 開放。

加上 `--grab-slow` 可將整個測試場降至 0.1 倍時間，方便逐步觀察鏡頭、雙手與咬合；抓取仍是 2 秒遊戲時間。正式遊戲與預設測試場均為正常時間。

v017 加上 `--bite-review` 可在咬合前暫停整个場景，檢查貼臉與雙臂接觸；F9 繼續，F12 重試，F11 換情境。正式遊戲不受這個檢查選項影響。

加上 `--grab-wounded` 會透過正式掙扎介面自動補到最低 80% 次數，方便檢查非致命咬擊：100 HP 玩家在咬合時降至 50 HP，立即恢復操作、關閉掙扎 HUD；駕駛仍留在座位並恢復控制。可搭配 `--bite-review` 在接觸前暫停。日誌 `GRAB_RELEASE reason=bitten` 表示咬合解除，其他取消原因也會記錄。此選項只在 playground 生效。

`godot --path . --log-file .godot/release-input-visible.log --script res://tests/test_raker_release_input.gd` 使用真實視窗自動驗證地面／車內／駕駛咬後控制。測試經正式輸入事件送入鍵盤與滑鼠，確認身體位移、水平及垂直轉向、油門恢復；也覆蓋抓取中滑鼠捕捉遺失。Headless runner 只驗證位移和駕駛，無法驗證作業系統滑鼠捕捉。未達 80% 或剩餘 HP 不足時仍按原規則死亡，等待重生期間不是抓取狀態。
