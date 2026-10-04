# 遊玩與測試場指南

正式遊戲操作見 [README](../../README.md)，規則與數值見 [GDD](../../GDD.md)。以下保留各測試場命令、快捷鍵、測試設定與限制；測試場按鍵不等同主世界按鍵。

## 目錄

- [Raker 車撞與布娃娃](#raker-impact)
- [起始避難所車庫](#starting-shelter)
- [RV 能源與維護](#section-1)
- [RV 車殼、駕駛室與門](#section-2)
- [完整 RV 與可替換引擎](#section-3)
- [公路與沿途探索](#section-4)
- [POI 資產與副本](#section-5)
- [日夜時間](#section-6)
- [正式美術與獨立樣板](#section-7)
- [攀爬與怪物測試場](#section-8)
- [加油站室外探索](#gas-station)
- [路邊小 POI](#minor-pois)
- [玩家持物動作](#player-carry)
- [屍體搬運與分解](#corpse-carry)
- [玩家斷肢與受傷爬行](#player-dismemberment)
- [樹木撞毀](#tree-impact)

<a id="corpse-carry"></a>

## 屍體搬運與分解

```powershell
godot --path . --log-file .godot/corpse-playground.log res://tests/corpse_playground.tscn
```

E 拾取軀幹、G 丟棄、WASD 移動。F1 第一人稱、F2 拾取附近屍體（測試捷徑）、F3 旁觀、F4 持續行走轉彎、F5 玩家死亡、F6 分解手持屍體（測試捷徑）、Esc 關閉。加 `-- --replay` 自動開始重播。沿用正式玩家、怪物、屍體物理及分解機；[本輪結果與限制](../validation/2026-10-04-corpse-props.md) 分開記錄自動測試與桌面觀察。

<a id="tree-impact"></a>

## 樹木撞毀

```powershell
godot --path . --log-file .godot/tree-impact-playground.log res://tests/tree_impact_playground.tscn
godot --path . --log-file .godot/tree-impact-playground.log res://tests/tree_impact_playground.tscn -- --replay
godot --path . --log-file .godot/tree-impact-chain.log res://tests/tree_impact_playground.tscn -- --chain
```

F6 自動輪驅撞向前方樹木，撞後繼續供油 2 秒再煞車；F7 重載為 8 排、共 16 棵的連續撞樹回放，R 重設目前模式。W/S 油門／煞車、A/D 轉向、Space 發動並切換手煞車。畫面顯示引擎耐久、撞毀棵數及連撞最低速度；確認車頭推開帶實際碰撞的輕量斷木、撞擊後繼續前進，葉簇落地形成薄層，留在視野內不消失，並有碎木、塵土及斷樁。斷木和斷樁在撞後 20 秒開始淡出，22 秒連同碰撞移除，落葉仍保留；視野外木材可提早回收。旁邊的樹保留外觀及碰撞。日誌 TREE_REPLAY 記錄真實輪驅撞擊速度，TREE_VISUAL 記錄批次實例移除與鄰樹碰撞，TREE_CHAIN_REPLAY 記錄 16 棵連撞結果。回放抵達 65 m 後主動煞車，最後顯示零速屬回放結束。此測試場不包含導航與串流；保存、重建、導航及相機視野清理回歸由 test_tree_impact.gd 驗證。最新結果見 [首次停頓與木材清理](../validation/2026-10-02-tree-impact-preparation.md)，前階段結果見 [落葉與連撞驗證](../validation/2026-10-02-tree-leaves.md)。

<a id="starting-shelter"></a>

## 起始避難所車庫

```powershell
godot --path . --log-file .godot/shelter-playground.log res://tests/starting_shelter_playground.tscn
godot --path . --log-file .godot/shelter-replay.log res://tests/starting_shelter_playground.tscn -- --replay
```

使用正式主場景、RV、物資、地形與開場控制器。F2 從原停車位開始輪驅出發，F3 查看外觀，F4 切換室內全景／玩家視角，F5 查看廢車封路。`--replay` 自動開門、入座並以油門／煞車／轉向駛出車庫、轉入公路，確認門封閉後退出；加上 `--keep-open` 保留結果畫面。`--inspect-exterior` 或 `--inspect-roadblock` 僅選擇初始觀察鏡頭。

回放只在入座時切換玩家模式，行駛期間不設定車輛 transform 或速度、不停用正常油耗。它驗證空載基本 RV 的出發；裝載三種設備與門防夾由 `test_starting_shelter.gd` 驗證，保存、讀檔與舊場景相容由 `test_starting_checkpoint.gd` 驗證。這些不是翻車、超載或大量敵人追車的驗收。

牆體近景：F6 查看入口與側翼窗洞，F7 查看玩家高度的內牆，F9 查看牆腳凹陷與斷面。`--inspect-facade` 以近景開始；另加 `--art-daylight` 只在這個測試場把時間設為 15:00，便於檢查立面光影，不改正式開場時間或天氣。

<a id="player-carry"></a>

## 玩家持物動作

```powershell
godot --path . --log-file .godot/carry-playground.log res://tests/player_carry_playground.tscn
```

F1 切換外部／第一人稱、F2 輪換手電筒／廢鐵／電池／油桶／引擎／空手、F3 原地播放步行、F4 切換抬頭／低頭、F5 手部近景、F6 旋轉近景角度。F3 只供固定機位觀察動畫；正式移動由 `test_player_carry.gd` 使用真實輸入驗證。

一般小物使用右手，大物依背包 `is_large` 使用雙手；持物與移動共用全身骨架。手持副本保留原 hold_rotation／hold_scale，並將最長邊限制在小物 0.18 m、大物 0.50 m（大物寬度另限 0.40 m）；不改地面物品或碰撞。預設抓點從持物網格包圍盒計算，可在 Prop 根節點下加入 `GripRight`／`GripLeft` Marker3D 指定接觸點；手電筒已指定右手握柄位置。既有 hold_position 隨整體包圍盒置中，不再決定鏡頭內的持物位置。

攀爬／攀頂、被抓、就座及設備放置時收起持物，讓原狀態接管手臂。詳細驗收與限制見 [持物驗收](../validation/2026-09-30-player-carry.md)。

手指依骨架實際掌面屈曲，四指具有不同彎曲幅度，拇指朝前輕握。手腕保留移動動畫的局部旋轉，隨前臂自然抬起，不再由持物程式或抓點旋轉手腕。預設抓點位於物體側面的中央高度，油桶兩個表面 Marker3D 也在桶身中段；小型箱體的近節彎曲較放鬆，避免指節插入側面。圓柱物品不能以包圍盒角落作抓點。`GripRight`／`GripLeft` 僅提供位置，旋轉不控制手腕；先前的 `carry_hand_frame` 設定已移除。手臂以固定四次求解重新計算掌心位置，配合這個自然手腕方向。

手電筒使用專用握姿：燈頭維持朝前並跟隨受限俯仰，燈身貼合自然掌面；四指依各自指根位置及指節長度包住圓柱截面，拇指沿燈身向前。每幀從原 hold transform 重新計算，避免燈身貼合偏移累積；手腕仍不覆寫。按 L 可驗證照明開關。

<a id="minor-pois"></a>

## 路邊小 POI

```powershell
godot --path . --log-file .godot/minor-gallery.log res://tests/minor_poi_playground.tscn
godot --path . --log-file .godot/minor-production.log res://tests/production_minor_poi_playground.tscn -- --seed=0 --cell=0 --replay
```

展示場：左右方向鍵切換 18 套佈局、N 換 seed、F1 玩家步行、F2 近景總覽、F7 截圖。WASD／E／G 使用正式玩家操作；怪物暫停 AI 以便檢查。`--capture-all` 逐套輸出 `.godot/minor-captures/00.png` 到 `17.png`，仍保留測試視窗。

正式道路測試場：指定 v6 世界 seed 和小 POI 區間 cell，若該區間留空則尋找下一處。F2 總覽、F3 步行、F5 用正式輪胎物理駛入、倒回公路並換前進檔離場、F7 截圖。沿用正式串流、道路坡度和物資，測試場移除敵人避免干擾車輛測量。回放不代表所有地形或手動操控情境已驗收。

自動檢查：`test_minor_site_generation.gd` 為 1,000 seeds；`test_outdoor_minor_assets.gd` 逐套驗證正式玩家與物資；`test_outdoor_minor_persistence.gd` 驗證正式串流及磁碟保存；`test_outdoor_minor_navigation.gd` 驗證跨區塊公路至搜刮點的導航和步行。效能抽樣：`godot --headless --path . -s res://scripts/profile_minor_streaming.gd`。

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

新世界採生成 v4：建築距公路約 330 m，樹冠與高灌叢包圍步道。既有生成 v2／v3 存檔保留原地形和入口距離；要體驗新版密林與遠距入口，請開新世界。未記錄生成版本時採 v2。Esc 設定中的顯示偏好獨立保存，舊 display_preferences.cfg 會遷移；F8 不再切換顯示。復古色調只影響室外 3D，不降低背包、平板或互動文字解析度。詳見 [密林驗收紀錄](../../docs/validation/2026-09-16-dense-forest.md)。

```powershell
godot --path . --log-file .godot/horror-visible.log res://tests/outdoor_horror_playground.tscn
```

F2 切換公路／停車處／遮蔽步道／入口／回望視角，1–4 換四款外觀，F3 回放正式玩家攜引擎步行，F4 在門前送出 E 互動／從室內返回，F5 切換視窗大小，Esc 開啟正式設定，R 重設。測試場只替換同一位置的入口模型供比較；正式世界依 seed 配置。截圖、效能與驗證範圍見 [室外氛圍驗收](../../docs/validation/2026-09-16-outdoor-horror.md)。

在 WorldGenerator 設定 `world_seed` 可重現整條路線，`-1` 每局另選 seed；`profile` 集中景觀、路寬、坡度、密度和串流設定。此版仍是沿公路向前旅行，遠景不提供可探索碰撞，後方已回收的地形不重建。

```powershell
godot --path . --log-file .godot/highway-visible.log res://tests/highway_playground.tscn
```

F1/F2/F3 預覽草原／林地／岩丘，F6 執行固定 seed 的 5 km 輪驅測試，F7 測停車、倒出及返回公路。回放以正式油門／轉向和 VehicleBody3D 輪胎物理移動；僅起點擺位、測試相機及停用耗油屬測試設定。完成後再次按回放鍵會重載測試場，再按一次啟動。可用 `-- --replay` 或 `-- --parking` 自動執行並退出；headless 測試加 `--fixed-fps 60`。

路旁九種模組提供可編輯場景，見 [roadside kit](../../world/roadside_kit/README.md)。地形驗收與效能紀錄見 [驗收紀錄](../../docs/validation/2026-09-15-highway.md)。

<a id="section-5"></a>

## POI 資產與副本

16 個啟用的 v2 廢棄地堡模組、保留 16 個 v1 定義供舊存檔解析，六種首批尺寸、隨機 1–3 層。普通模組 60% 暗房，外觀／碰撞／門口分層，可在編輯器擴充。[製作規格](bunker-interior.md)。

美術檢查在地堡測試命令最後加 `--art-inspect`，可加 `--inspect-room=hall_03` 選起始房型（該 seed 未生成時回到入口）：測試專用手電筒自動拾取、怪物暫停；F4 轉向房內四角，F6／F7 切到下／上個房間，L 使用正式手電筒開關，F8 存當前房型和開關狀態截圖至 `.godot/bunker-art-*.png`。房間定位僅用於檢視，不能當成步行通過證據；F5 的連續搬運回放獨立驗證通行。正式遊戲仍須在初始世界地面 E 拾取手電筒。

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

正式戶外已採用 [D 低模目標方向](../../docs/art_targets/outdoor/2026-09-17-d-revision.md)：分叉低模樹冠、簡化泥地、冷霧與固定雲層。Esc 設定可選約 540p 的舊室外模式或手動 3D 解析度，另調復古色調；沒有額外像素格或抖色，HUD 保持清楚。驗收見 [正式戶外 D 紀錄](../../docs/validation/2026-09-17-outdoor-d.md)。後續 [霧效修正](../../docs/validation/2026-09-17-fog-refinement.md) 保留近景對比，統一天際線與霧色並減弱雲斑。

執行 `godot --path . --log-file .godot/style-sample.log res://tests/industrial_style_playground.tscn`，查看同一 seed 的新舊美術對照。F1 切換樣板／原版、F2 固定視角、F3 正式角色攜引擎走完全程、F4 進入／返回、F6 RV／駕駛室／設備視角、F7 切換測試電量、F9 測試牆板損傷、F10 平板、F11 隱藏樣板文字、F5 切換視窗尺寸；Esc 開啟正式設定。這些測試按鍵僅屬樣板，不改正式操作。

獨立樣板仍保留前一輪針葉樹、高窗維修廠與 RV 材質實驗；F1 現在對照的是目前正式美術，不是凍結的歷史版本。正式遊玩請使用主場景；正式畫面驗收使用 `res://tests/outdoor_horror_playground.tscn`，F11 隱藏驗收文字。高窗量體與 RV 實驗材質仍未併入正式版。歷史資料見 [視覺研究](../../docs/research/2026-09-17-lethal-company-visual-direction.md) 與 [樣板驗收](../../docs/validation/2026-09-17-style-sample.md)。

室外植物、地面、四款入口與 RV／設備已使用統一的老舊工業材質；生成紋理與完整提示詞見 [材質說明](../../assets/materials/industrial/README.md)。HUD、背包和平板保留操作方式，改為方角暗底及灰白／暗黃配色。新外觀適用新舊存檔，不變更世界位置；舊生成版本仍保留其原植物配置。

室外展示場新增 **F6** 循環 RV 外觀／駕駛室／設備、**F7** 切換測試電池電量、**F9** 切換側牆損傷、**F10** 開啟正式平板介面。正式遊戲不增加這些快捷鍵。RV 車內暖燈由獨立燈條設備、控制台請求與統一電力結算供電；顯示改用 Esc 設定，文字保持清晰。

[美術驗收與截圖](../../docs/validation/2026-09-17-industrial-art.md)

<a id="section-8"></a>

## 攀爬與怪物測試場

### 正式玩家模型

```powershell
godot --path . --log-file .godot/player-model.log res://tests/player_model_playground.tscn
godot --path . --log-file .godot/player-model-replay.log res://tests/player_model_playground.tscn -- --replay --quit-replay
```

載入正式主世界、固定 seed 42 與上午 10 點，使用正式 Player。F1 平視、F2 低頭、F3 外部觀察、F4 連續移動／跳躍／持物／上下車回放、Esc 關閉此測試視窗。第一人稱捕捉滑鼠，外部觀察釋放滑鼠；WASD／Space 使用正式控制器，TEST 骨架動畫不會播放。自動回放截圖輸出 `docs/validation/player-model-integration/`。獨立物理配置仍可使用 `tests/player_ragdoll_v020/playground.tscn`，正式死亡另見下方測試場。見 [整合驗收](../validation/2026-09-27-player-model-integration.md)。

<a id="player-dismemberment"></a>

### 玩家斷肢與受傷爬行

```powershell
godot --path . --log-file .godot/player-dismemberment.log res://tests/player_dismemberment_playground.tscn
godot --path . --log-file .godot/player-dismemberment-replay.log res://tests/player_dismemberment_playground.tscn -- --replay
godot --path . --log-file .godot/player-gore-review.log res://tests/player_dismemberment_playground.tscn -- --replay --gore-review
godot --path . --log-file .godot/player-arm-pov.log res://tests/player_dismemberment_playground.tscn -- --replay --arm-pov
godot --path . --log-file .godot/player-head-pov.log res://tests/player_dismemberment_playground.tscn -- --replay --head-pov
```

載入正式 Player、五切口、受傷爬行與 Raker 咬合流程；`--replay` 自動回放並結束，截圖輸出 `docs/validation/player-dismemberment/`。這裡列的是操作入口，不代表本次已完成目視驗收。

`--gore-review` 另拍頭顱落地後的正反近景，以及三個血泊在明亮／昏暗照明下的畫面，輸出至 `gore-review/after/`；不改變正式遊戲流程。

`--head-pov` 使用正式第一人稱記錄致命咬頭、銜住、落下、地面視角及復活，輸出至 `head-pov/after/`；`--before` 只改用 `before/` 輸出目錄，供在修正前版本建立對照，不會還原舊邏輯。畫面先保留於記憶體，回放完成才寫檔。

`--arm-pov` 記錄第一人稱掙扎、咬合前、斷臂、向外撕扯、掉落與恢復視角，輸出至 `arm-pov/`；初始先看怪物臉部（`00_face`），再於 1.05 秒拍攝掙扎中的 `01_struggle`，咬合前拍攝仍看著怪物臉部的 `01b_before_bite`；接觸後的 `04`／`05` 顯示鏡頭轉向咬手，`07` 顯示恢復視角。加 `--arm-observer` 改拍旁觀對照；加 `--grab-prop` 預先持有廢料，檢查持物時只抬空手，結果存於對應的 `held-prop/` 子目錄。畫面先存在記憶體、結束才寫 PNG，避免寫檔延遲跳過接觸瞬間。

`--replay --prone-review` 從低側面記錄缺左腿、缺右腿、無腿、僅左／右臂可用的匍匐待機與連續移動，每個版本保存五個循環時點，另保存第一人稱眼位，輸出至 `prone/`。此模式清除遮擋接觸點的離體件，先緩存畫面再寫 PNG，用於檢查胸腹、前臂與靴子接地。

| 按鍵 | 功能 |
| --- | --- |
| 1／2／3／4／5 | 依序切頭、左臂、右臂、左腿、右腿；重複切斷拒絕 |
| F1 | 第一人稱／外部觀察 |
| F6 | 60% 掙扎結果的左臂咬擊；左臂已缺失時升級為頭部致死咬擊 |
| F7 | 頭部致死咬擊 |
| F8 | 持續向前移動 3 秒，觀察爬行循環；先切腿才會爬行 |
| R | 重設完整玩家並清除本場斷肢，供下一次檢查 |
| Esc | 關閉此測試視窗 |

WASD／滑鼠沿用正式控制器；缺腿後不能跳躍、衝刺、攀爬或駕駛。請分別檢查一腿／無腿／單臂爬行、兩端封口、第一人稱缺肢同步、斷肢獨立物理、左臂咬後 50 HP 與第二次咬擊升級，以及死亡後安全完整重生。數字切斷是測試快捷鍵；正式 Raker 咬擊只授權左臂與頭部，其他切口不由普通傷害自動觸發。規則與資產契約見 [角色製作規格](character-modeling.md#player-five-cuts)。

### 正式死亡布娃娃

```powershell
godot --path . --log-file .godot/player-death.log res://tests/player_death_playground.tscn
godot --path . --log-file .godot/player-death-replay.log res://tests/player_death_playground.tscn -- --replay --quit-replay
```

使用正式主世界、Player 傷害／死亡／重生與目前 60 Hz／Jolt 32／32；局部慣量／角阻尼配置已通過 60 Hz 落地與恢復專項。F1 第一人稱、F2 外部、F3 致命傷害、F4 站立／空中／座位死亡回放、F5 入座死亡、Esc 關閉。第一人稱隨倒地下移、不翻滾，兩秒後找到安全站位才恢復；被堵住時等待淨空。本輪截圖與 replay.json 存在 `docs/validation/player-death-integration/current-60hz/`，見 [驗收報告](../validation/2026-09-27-player-death-integration.md)。

### 移動 RV 攀爬

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

此追蹤／近戰場景現載入 Raker：藍色方柱標記玩家，黃色小方塊為可受傷設備。玩家生命提高且保持介面移動鎖，可觀察怪物追近後的攻擊。F3 放入牆壁並固定怪物移速，F4 移除牆壁；正式 Raker 回歸以 `test_raker.gd` 為準。[舊追蹤驗收](../../docs/validation/2026-09-16-monster-pursuit.md)記錄的是當時場景。

以下模型預覽現使用 Raker；其他動作與抓咬流程可用下方專用 Raker 測試場。[舊素材設定](../../assets/models/monster/README.md)僅供追溯早期試接。

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
- `F3` 既有步行回放、`F4` 入口互動／離開副本；`Esc` 正式設定，`F11` 隱藏說明。

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

<a id="raker-impact"></a>

## Raker 車撞與布娃娃

```powershell
godot --path . --log-file .godot/raker-impact.log res://tests/raker_impact_playground.tscn -- --replay
```

使用正式輪驅 RV 與 Raker，不預設車速或直接呼叫撞擊。1–4 切換正面存活、受傷目標致命、偏側、輕撞四例；R 重播、Space 開始、F4 近景／全景、F9 暫停／繼續。可加 `--review` 在撞擊後 0.3 秒暫停檢視、`--case=0` 至 `--case=3` 選初始案例。畫面標示目標巡航速度，實際撞擊速度由儀表與日誌回報；致命案例的 Raker 初始為 60 HP。存活起身後暫停該測試目標的 AI，便於檢查；正式遊戲仍恢復追逐。輪驅測試、碰撞層與限制見 [驗收](../validation/2026-10-02-raker-impact-ragdoll.md)。

## Raker 抓咬測試（v016）

`godot --path . res://tests/raker_vehicle_playground.tscn -- --grab-ground --grab-seed=218`

`--grab-cabin`／`--grab-driver` 分別啟動車內步行／行駛駕駛情境，三者擇一。F11 循環三情境、F12 重試，F7 對怪物造成 10 傷害中斷。測試時恢復玩家 100 HP，使用正式 AI、車輪物理、座位、碰撞和抓咬判定；2 秒準備後開始接近。Space 需反覆按下並放開；可觀察 HUD 60% 刻度、鏡頭、張嘴與雙手接觸。F11/F12/F7 在被抓時也可用，僅 playground 開放。

加上 `--grab-slow` 可將整個測試場降至 0.1 倍時間，方便逐步觀察鏡頭、雙手與咬合；抓取仍是 1 秒遊戲時間。正式遊戲與預設測試場均為正常時間。

v017 加上 `--bite-review` 可在咬合前暫停整个場景，檢查貼臉與雙臂接觸；F9 繼續，F12 重試，F11 換情境。正式遊戲不受這個檢查選項影響。

加上 `--grab-wounded` 會透過正式掙扎介面自動補到最低 60% 次數，方便檢查左臂咬擊：完整的 100 HP 玩家在咬合時降至 50 HP 並失去左臂，立即恢復操作、關閉掙扎 HUD；鏡頭在接觸前持續看著怪物，接觸後才短暫轉向手臂再淡回，雙腿仍完整的駕駛留在座位並恢復單臂控制。左臂已缺失時升級為頭部致死咬擊。可搭配 `--bite-review` 在接觸前暫停。日誌 `GRAB_RELEASE reason=bitten` 表示咬合解除，其他取消原因也會記錄。此選項只在 playground 生效。

`godot --path . --log-file .godot/release-input-visible.log --script res://tests/test_raker_release_input.gd` 使用真實視窗自動驗證地面／車內／駕駛咬後控制。測試經正式輸入事件送入鍵盤與滑鼠，確認身體位移、水平及垂直轉向、油門恢復；也覆蓋抓取中滑鼠捕捉遺失。Headless runner 只驗證位移和駕駛，無法驗證作業系統滑鼠捕捉。未達 60% 或剩餘 HP 不足時仍按原規則死亡，等待重生期間不是抓取狀態。


## 玩家正式動作 v021

```powershell
godot --path . --log-file .godot/player-animation.log res://tests/player_animation_playground.tscn -- --replay
```

使用正式玩家與實際輸入回放待機、四方向慢跑／快跑、動作中死亡與重生。去掉 `-- --replay` 可手動 WASD／Shift；F1 低頭第一人稱、F2 外部視角、F3 完整回放、Esc 關閉。相機只屬測試場，沒有寫入正式玩家系統。物理固定沿用專案 60 Hz。證據寫入 `docs/validation/player-animations-v021/`，驗收與限制見 [本輪報告](../validation/2026-09-27-player-animations-v021.md)。

加入 `-- --jump` 使用較近的跳躍觀察鏡頭，Space 手動跳躍；F3 回放站立、慢跑、快跑跳躍並保存上升／下降／落地及低頭畫面至 `docs/validation/player-animations-v021/jump/`。使用 `-- --jump --replay` 自動回放並結束。跳躍高度、速度、耐力及物理 tick 均沿用正式控制器。


### 玩家攀爬動作近照

```powershell
godot --path . --log-file .godot/player-climb-desktop.log res://tests/player_climb_animation_playground.tscn -- --animation-review
```

使用正式玩家與 RV，回放抓牆、攀升、左右橫移、車輛轉彎中的停留與登頂收手。F1 第一人稱、F2 外部視角、F3 重播、Esc 關閉；截圖存到 `docs/validation/player-animations-v021/climb/`。登頂仍由現有控制器直接轉移站位，動畫不改路徑或速度。

雙角色回歸仍用 `rv_climb_playground.tscn -- --replay`，加 `--animation-review` 隱藏藍色標記以觀看正式模型。此測試車體凍結於抬高位置，回放起點設在車壁旁，與 `test_moving_rv_climbing.gd` 一致；手動起點與正式玩家控制器不變。

鏡頭同步複驗可加 `--camera-review`：保存攀爬低頭／平視畫面到 `docs/validation/player-animations-v021/climb-camera/`，保留上一版圖片。

### 玩家駕駛動作

```powershell
godot --path . --log-file .godot/player-driving.log res://tests/player_driving_playground.tscn
```

使用正式玩家與駕駛座，隱藏車殼、凍結車體，檢查坐姿與控制件接觸。F1 回正、F2 左轉、F3 右轉、F4 切換外部／第一人稱／側面、F5 切換踩踏、F6 顯示／隱藏完整車殼。這是姿勢觀察場，不代表已驗證輪驅行駛。自動回歸 `test_rv_cockpit.gd` 檢查方向盤方向與回正、骨架接觸、跟車姿態及座位生命週期。
