# 世界生成與串流

世界入口、種子生成、道路與地形、串流、細節層、公路生成與樹木破壞。程式在 [world/](../../world/) 與 [world/terrain/](../../world/terrain/)；場址與室內見 [poi](poi.md)。

## 功能一覽

### 世界入口

| 入口 | 用途／差異 |
|---|---|
| [main_world.tscn](../../world/main_world.tscn) | 正式入口；兩室教學、完整戶外／副本循環與 F6／F9 檢查點 |
| [demo_world.tscn](../../world/demo_world.tscn) | 快速展示；seed 42、小霧、單間車庫、無限材料與燃油，電力正常消耗；啟程後安排一次巨人遭遇，沒有正式檢查點 |
| [cheat_test_world.tscn](../../world/cheat_test_world.tscn) | 現行生成＋單間車庫；預設無限燃油／電力／材料，仍需有效電池；沒有正式檢查點 |
| [test_world.tscn](../../world/test_world.tscn) | 保留的舊測試世界；沒有正式檢查點，配置不代表現行新局 |

正式、Demo 與作弊世界均使用當前生成版本（`WorldProfile.CURRENT_GENERATION`）。外殼內容、Checkpoint、VehicleSnapshot 是各自獨立的版本欄位；保存路徑見 Checkpoint 的 `PATH`，只接受當前正式世界，不遷移舊局。存檔開發目前凍結，新功能狀態不保存（見[存檔凍結](../README.md#系統)）。依據：[WorldProfile](../../world/terrain/world_profile.gd)、[Checkpoint](../../rv/checkpoint.gd)、[VehicleSnapshot](../../rv/vehicle_snapshot.gd)。

### 戶外世界

| 功能 | 現況與範圍 | 主要來源／測試場 |
|---|---|---|
| 種子生成與雙向串流 | 150 m 區塊、道路／地形／內容獨立 RNG、分幀建立、往返重載及載入視野保護 | [generator](../../world/world_generator.gd)、[world field](../../world/terrain/world_field.gd)、[highway](../../tests/highway_playground.tscn) |
| 世界細節層 | 地形特徵（池塘／湖、泥土支線、路旁與野地場景、電塔）、16 層程序化散佈、道路設施；RV 可撞倒標誌／標柱／圍欄並保存 | [features](../../world/terrain/world_features.gd)、[scatter](../../world/scatter/scatter_scenery.gd)、[road details](../../world/terrain/road_details.gd)、[world detail](../../tests/world_detail_playground.tscn) |
| 山路與六類地貌 | 正式；連續彎道、寬窄、升降、草原／懸崖／濕地／山脊／峽谷／森林盆地、分群樹木灌叢與近路遮蔽 | [route](../../world/terrain/terrain_route.gd)、[landforms](../../world/terrain/terrain_landforms.gd) |
| 河川、橋梁與高架 | 正式；河谷／岸坡、全路寬跨河橋、依落差生成橋板／鋼梁／橋墩／護欄；沒有游泳或水流玩法 | [crossings](../../world/terrain/terrain_crossings.gd)、[bridge builder](../../world/terrain/bridge_builder.gd) |
| 路旁與越野 POI 排程 | 正式；路旁區間與越野網格分開安排，避開道路／水域／陡坡及其他場址，局部整地與植被避讓 | [minor sites](../../world/terrain/minor_sites.gd)、[offroad sites](../../world/terrain/offroad_sites.gd) |

| 公路障礙與遭遇 | 正式；開場安全段、後方最多 28 台廢車，公路分開抽取油桶人／普通油桶／廢車／釘帶；廢車不能清除 | [road spawns](../../world/road_spawns.gd)、[rear wreck](../../world/starting_shelter/rear_wreck_layout.gd) |
| 偏行壓迫 | 正式；退後或離路過遠會起霧，事件持續 30 秒後可出現 Slender Speaker；合法探索場址／通道豁免，返回安全範圍後停止遭遇生成並退霧 | [deviation pressure](../../world/deviation_pressure.gd)、[rear pressure](../../tests/rear_pressure_playground.tscn) |
| 樹木碰撞與倒塌 | 正式；RV／巨人撞樹、斷裂倒塌與破壞狀態保存 | [tree impact](../../world/terrain/tree_impact.gd)、[tree playground](../../tests/tree_impact_playground.tscn) |

## 規則與數值

### 生成版本與公路事件

正式新局使用當前生成版本（`WorldProfile.CURRENT_GENERATION`），包含森林、地堡／加油站、路旁與越野 POI、兩室避難所、公路事件、Abandoned Megashelter 及世界細節層。道路、relief／dry-valley／flora 沿用既有獨立 RNG 版本；場址排程及既有 RNG 域沿用 v18，越野候選池保留原權重，另以獨立 2% 機率選擇巨型住宅外殼取代一般候選；巨型住宅另有每 300 m 一帶的獨立候選（`world/terrain/offroad_sites.gd`）。檢查點只接受當前生成版本。

每 150 m 分別抽取釘帶、廢車、油桶人與普通油桶。油桶人與普通油桶各自在中央路面獨立選點。廢車數量 0／1／2／3／4（60%／25%／10%／4%／1%），每台獨立選位置與 0–TAU 朝向，不保證中央 5 m 通道。保留起點 450 m 安全區、場址、接縫及實體重疊避讓；合法候選不足時可少於抽取數量。釘帶沿用既有獨立規則。普通油桶隨 WorldEntities／Item 保存；死亡、遠距清理、拾取、毀損及回訪均不補出。

### 串流與地形

世界大致沿 -Z 延伸，v5 依玩家位置載入前後 chunk，支援回頭；正式 v9 初始後方 2、目前 1、前方 2；共用 profile 保留前方 3。地形採世界座標固定網格，每帶長 150 m、可碰撞區寬 1000 m（`WorldProfile.terrain_half_width` 的兩倍）；道路在其中彎曲，區塊不再跟著轉向。遠處補上低細節景觀地形與距離霧。

當前生成沿用 v14 地形：草原、懸崖、濕地、碎石山脊、台地峽谷與森林盆地，以低模樹群、灌叢和近路山坡圍繞道路。沿路配置電線桿與電線、彎道警告與危險標誌、標柱及部分護欄。路寬約 7.2–19.5 m，連續左右急彎與持續上下坡需減速；開場 450 m 保留平直安全段。正式坡度設定上限維持 12%，沿實際彎路水平弧長累積高度，四種子 12 km 取樣最大 10.8%、山頂約 316–345 m；最緊彎道約 38–49 m 半徑。道路不逆轉 Z 方向，整片路面另做不自交檢查；山路兩側形成上坡岩肩與下坡谷地，普通路緣仍接地。

未能在程式中找到，沿用原文：四種子 12 km 取樣的最大坡度、山頂高度與最緊彎道半徑是量測結果，不是程式常數；程式設定是 `max_grade` 與 `min_turn_radius`。

### 細節層

世界細節讓路程不重複，全部是「視覺＋實體障礙」，不新增物資或敵人：

- **道路本身**：有磨損與補丁的路面、碎石路肩、電線桿與垂落的斷線、急彎前的警告標誌與彎外危險標誌、標柱。標誌只有符號，沒有文字。
- **自然散佈**：依地貌權重分佈的巨石、露頭、樹樁、倒木、碎石、蕨類、蘆葦、高草與幼樹；能擋車的只放在路緣 4.5 m 以外。
- **人類遺跡**：路旁的拋錨車、施工區、公車亭、看板、工具小屋；野地的廢屋、貨櫃堆、伐木場、乾草田、圍欄與拖拉機；部分場景由泥土支線從公路接出，盡頭是廢屋、小聚落、伐木場或貨櫃堆。支線不通往越野 POI。
- **宏觀結構**：池塘與少數大湖（附棧橋）、沿路的高壓電塔與電纜。
- 標誌、標柱與圍欄可被 RV 撞倒，只略減車速；撞倒狀態隨存檔保存。
- 未實作：跨路隧道或天橋（道路兩側 20 m 內一律整平，沒有自然路塹可放隧道，需另行設計）。

## 實作契約

### 公路獨立生成

正式 main_world 與 WorldProfile 使用當前生成版本；道路內容使用目前獨立規劃器。Checkpoint 只接受 shelter 主世界，不再提供舊版本道路規劃或 legacy 存檔身分。

RoadSpawns.plan(field, band) 使用當前純規劃器，分離釘帶、油桶人、普通油桶及廢車的數量／位置 RNG。油桶人 8% 一隻、普通油桶 20% 一個，各自獨立在中央路面選點。廢車 0–4 台機率為 60／25／10／4／1%，逐台獨立選位置及 0–TAU yaw，沒有固定陣形或中央通道保證。前 450 m、安全據點、5 m 接縫距離及實體重疊避讓維持，候選失敗可少於抽取數量。釘帶與廢車屬 chunk，加入導航烘焙；普通油桶為 WorldEntities 動態 Item。

導航 map／region 同步完成後建立道路怪物，加入 WorldEntities 並尊重 skip_actors。generated_bands 防止回訪、死亡、遠距清理及重載補怪；導航尚未發布時拒絕保存，以免漏掉即將生成的怪物。清理按怪物目前位置與戶外串流錨點前後 450 m 判斷，不以出生 chunk 決定；loaded WALK_IN 保護與其他散落物清理維持。正式 profile 設 chunks_ahead=2，與目前帶共覆蓋至多 450 m，避免前方道路怪物立即被遠距清理；自訂更遠載入窗仍按 450 m 規則清理。普通油桶沿用 Item／WorldActorSnapshot 保存及 generated_bands 防補發；重烘焙、拾取、爆炸、清理或重載皆不重新抽取。

### 樹木撞毀

SlenderSpeaker 由 `move_and_slide()` 的實際身體接觸撞毀樹木，使用掃掠前的水平速度及命中 shape index。朝接觸法線內至少 0.1 m/s 的走路／追擊接觸即可觸發；靜止、離開樹幹及垂直落地不觸發。共用 ForestTrunks／路邊樹的破壞、倒塌、導航更新及 destroyed_trees 帳本；已毀樹等待延後停用時不觸發牆面脫困，其他實體仍保留碰撞與脫困。

Chassis 讀取實際物理接觸，以至少 3 m/s 的水平速度、朝接觸法線內至少 0.1 m/s 的接近速度判定撞樹，高速斜擦也能折斷；離開樹幹、低速及垂直落地不觸發。TreeImpact 只處理破壞，Chassis 在補速後按每棵樹真正造成的速度損失結算一次傷害，沿用下方 VehicleImpact 契約及 take_damage 扣引擎耐久。引擎歸零沿用現有停機／維修流程。

底盤快取前一物理步的線／角速度，避免 Jolt 已解算的硬碰撞讓撞擊速度歸零。先處理全部樹木撞擊，再依最後的破壞狀態判定實體阻擋，避免同 shape 的早期擦碰法線留下錯誤阻擋。只補回沿原水平行進方向損失的速度，每棵新毀樹保留 85%；同棵樹的多個接觸只計一次。接觸上限至少 128；已毀 shape 的延後停用期間不重扣傷害，有反向實體阻擋法線或接觸報告達上限時不補速，垂直與角速度仍由物理解算。

ForestTrunks 保留一個共用靜態碰撞體，shape owner 識別單棵樹，延後停用其碰撞並隱藏對應 MultiMesh instance。TreeFall 在 0.75 m 斷裂面留下斷樁，依材質分離木質與葉面，完整木質網格按世界高度切成最長 3.2 m 的 RigidBody3D 斷木，每段 2–4 kg；圓柱碰撞跟隨網格，layer／mask 1、CCD、摩擦 0.08，不排除 RV。斷木起始外觀承接原樹，依車身位置向外側散開並由物理解算傾倒，不留 HingeJoint 或樹冠碰撞。葉面依高度／方位分成實際網格小簇，保留貼圖與頂點色，重力／旋轉落到取樣地面後壓成薄層；預估落點先取樣，接觸時再確認地形，不逐葉逐幀射線。地面射線排除動態物件／角色。原樹接觸尚未清除時，輕量斷木不作為硬牆補速 veto；只剩斷木接觸後不再補速。斷木的真實地面接觸觸發塵土。木材與葉片獨立清理：木材含斷樁在 20–22 秒淡出後移除全部碰撞體，也可存在至少 8 秒、連續離開視野 2 秒後提前回收；葉簇保持不透明，存在至少 6 秒且全部落地後，連續離開視野 2 秒才釋放。逐組網格世界 AABB 檢查目前 Camera3D 六個 frustum 平面，回望各自重設计時，缺相機只阻止視野清理，木材定時回收仍有效；兩組均釋放後移除效果父節點。碎片隨 chunk 卸載釋放，不進 actor 或存檔。舊版路邊活樹／枯樹使用相同撞擊契約。

ForestScenery.build 首次建立森林前 await TreeFall.prepare：獨立 32×32 SubViewport 先建立一棵實際落葉／斷木／粉塵效果，停止處理、凍結剛體並停用碰撞，渲染兩幀後釋放，不播放音效、不寫破壞帳本或觸發導航。共用 Shader、頂點格式及陰影 pipeline 在載入期準備，blocked PCM 音效也預先合成；一次旗標避免串流重複準備。不可變原 mesh 的 surface arrays 快取最多 32 資源；切木只計算世界高度並在原局部座標裁切，葉面共用變換／法線矩陣，減少首次與每次撞擊的網格計算。

WorldGenerator／WorldField 共用 destroyed_trees 帳本，獨立於可淘汰的 forest_cache；森林 ID 使用 band／確定性生成索引，路邊樹使用原始位置。重建前仍消耗原外觀 RNG，存活樹位置與型號不漂移。Checkpoint 要求完整帳本，先驗證再恢復。

木質小樹叢用獨立的 ForestShrubs 複合碰撞體，由 Chassis 接觸觸發同一撞擊判定。被撞毀的實例以 band／候選位置索引記入 destroyed_trees，TreeFall 散開枝葉並揚起塵土。步行與導航沿用原本的通行範圍。

樹木破壞後以 0.35 秒合併導航重烘焙，沿用原 NavigationRegion 並序列化更新；接縫附近的已載入鄰帶一起更新，鄰帶 halo 也排除已毀樹。

### 串流效能

串流效能：地形取樣、網格組裝與導航接縫採約 4ms 的合作式時間預算；單次引擎 mesh／碰撞建構仍不可中斷，並非硬性幀時間上限。導航接縫重用共享頂點取樣；森林碰撞先在場景樹外完整組裝再加入，避免逐棵修改作用中的 compound body。遠距物件清理每 0.5 秒執行，最多延後半秒；載入與場址保護仍每幀檢查。

地形每帶依生成版本寬度建立網格（v4 為 301×51 個頂點，v2／v3 為 151×51），行駛中分批取樣、組裝及安置；導航背景烘焙，無獨立作業執行緒生成場景節點。100 seed、載入順序、坡度、停車、網格／導航接縫及正式玩家搜刮往返的專項結果屬歷史驗收。現行 [串流生成檢查](../../tests/test_streaming_generation.gd) 聚焦分片幾何、森林配置與實體碰撞。`highway_playground.tscn` 提供正式輪驅 5 km 及停車倒出回放。

### 世界流程

WorldGenerator 建立 WorldField／WorldProfile／POISpawner → 正式 v9 初始後 2／目前 1／前 2 個固定網格帶（共用 profile 保留前 3 帶） → 查詢區域／道路／停靠計畫 → 共用整地結果生成地表、路面與碰撞 → 安置靜態內容 → 烘焙導航並生成動態內容。行駛中的建立分多影格執行，完成前不發佈到 active_chunks；一次只有一個建立作業。

串流比較室外玩家或副本錨點 Z，維護前後窗口並可回頭載入。WorldField 以世界座標計算有界道路曲線，WorldProfile 預設生成 `WorldProfile.CURRENT_GENERATION`、路寬 15／10 m、坡度上限 8%、區域長 900 m／過渡 240 m。獨立 RNG 域隔離道路、停靠、地形、外觀、物資及敵人，場址 ID 固定當前格式。Checkpoint 要求完整 profile 與相同的 generation_version，不使用舊版預設。

外部停靠點位置為 index×450±75 m。v4 起始維修廠位於 (335.2,6,-45)，v3 保留 (135,6,-45)，每三點兩個離路入口、一個小補給；v2 保留 (49,0,-45) 近路維修站與原比例。ExplorationSite 以道路局部座標建立左右及前後鏡像模板，檢查完整場址是否落在版本對應碰撞帶內（v4 寬 900 m，v2／v3 寬 450 m），必要時改向另一側；無無限重抽。WorldField.surface 將場址平台、緩坡、步道及保留區整合到共用取樣，公路高度優先。spawn_site 使用同一份 building/road/frame/id/seed，外觀不消耗物資 RNG。四款外觀沿用既有入口及副本。

地形網格使用相鄰取樣圈計算法線，邊界共享世界位置及高度。v4／v3 導航分別涵蓋 900／450 m 寬碰撞帶，cell_size=0.25 m；v2 維持 240 m／0.5 m。使用實體碰撞，排除高 7 cm 的重複瀝青層，補相鄰地形、圍牆與建築碰撞資料；邊界資料由共用計畫提供，不依賴相鄰 chunk 載入順序。v3／v4 高容許 detail 誤差抑制噪音坡面新增的重疊細三角形，可通行輪廓仍由 voxel 決定；v2 保留原設定。非同步烘焙後發佈獨立 NavigationMesh，navigation_ready 等待 region 和 map 真正同步，避免初始空網格。怪物地面高低差仍使用導航；path_height_offset 對齊角色腳底；落地且已到達路徑點水平範圍時，以實際腳下高度推進路徑點，避免簡化網格埋入土坡造成繞圈。未移動的目標不重複重設路徑；移動目標維持 0.25 秒更新間隔。

場址牆段依中心 Z 歸唯一 chunk；整地跨帶查詢同一計畫。玩家位於場址 bounds 或室內 stream_anchor 時，protected_bands 保留並補建停車區、路線及建築的區塊與 halo。ForestScenery 以獨立 RNG 的 8 m 網格抖動形成樹林與可撞毀灌叢，逐列分幀規劃，樹幹簡化碰撞也提供相鄰導航 halo；快取至多 16 個帶。ForestMeshes 快取四款不對稱針葉樹、兩款枯樹與三款灌叢，共九批 MultiMesh；forest_art_variants 獨立亂數只選外觀，不改既有樹位、碰撞與 seed。遠景左右及前方網格只提供視覺。新造景延續分幀建立，build_ms／max_slice_ms 記錄成本。

世界細節分兩層，都只是「視覺＋實體障礙」，不產生物資或敵人：

- **地形特徵層** [WorldFeatures](../../world/terrain/world_features.gd)（`WorldField.features`）：每 300 m 一格，只用未混合的原始地形規劃池塘／湖、泥土支線與盡頭空地、路旁與野地場景地塊、高壓電塔；一格完整擁有其特徵，規劃絕不呼叫 `surface()`。`WorldField.surface()` 經 `apply()` 套用水面、岸邊、路床高度與保留區，另回傳 `occupied`（不含路肩保留）與 `track`（寫入地形頂點色 alpha，供 `terrain_v14.gdshader` 畫泥路）。[FeatureBuilder](../../world/scatter/feature_builder.gd) 把特徵建成節點，遺跡小場景來自 [VignetteKit](../../world/scatter/vignette_kit.gd)。
- **散佈圖層** [ScatterScenery](../../world/scatter/scatter_scenery.gd)：[ScatterCatalog](../../world/scatter/scatter_catalog.gd) 列出規則（[ScatterLayer](../../world/scatter/scatter_layer.gd)），每層有獨立 RNG 流 `scatter_<id>`、各地貌權重與程序化網格（[ScatterMeshes](../../world/scatter/scatter_meshes.gd)）。規劃讀區塊的 [TerrainGrid](../../world/terrain/terrain_grid.gd)，物件貼在玩家看到的三角面上；實體散佈離帶接縫與路緣保留間距，路肩留給 RoadSpawns。

道路細節由 [RoadDetails](../../world/terrain/road_details.gd) 建立：路面著色條（`road_surface.gdshader`）、碎石路肩、電線桿與電線、彎道標誌及標柱，全部是路線的純函數，鄰帶可描述彼此的電線桿。標誌、標柱與圍欄是 [BreakableProps](../../world/scatter/breakable_props.gd)：只在 `TreeImpact.SHRUB_LAYER` 與 RV 碰撞，每個目標以 `vehicle_speed_retained` 決定 RV 撞擊後保留的速度比例，撞倒後以 `roadside:` 鍵寫入 `destroyed_trees` 帳本。樹木仍由 ForestScenery 管，因為倒樹與存檔契約綁在它身上。

室外日夜照明由 WorldClock 控制，Forward+ 使用局部體積霧與遠景距離霧，Compatibility 降級只保留距離霧。GameSettings autoload 管理全域顯示、輸入與音量偏好；Esc SettingsMenu 是設定入口，F8 不再處理顯示。值在載入與寫入時檢查型別、有限值及範圍；缺漏或非法持久化欄位各自回預設。偏好寫入獨立 ConfigFile，不進角色／車輛或 Checkpoint 快照，短時間多次滑桿變更合併保存，關閉選單時 flush，錯誤由 save_completed 與 last_save_error 回報。偏好僅使用目前設定格式，舊顯示設定不遷移。

register_viewport 把 3D 縮放、抗鋸齒與陰影品質套用到主 viewport 及新建立的室內 SubViewport。舊解析度模式維持室外目標高度 540、最高 1，室內原生解析度；手動 50–100% 解析度同時套用室內外。復古色調與解析度分開，亮度／對比／飽和度使用 3D 後製，Canvas UI 保持清晰。品質預設只修改解析度、抗鋸齒、陰影與霧，其他欄位不變，個別品質調整後保留「自訂」來源，即使數值又與預設相同也不自動改回；此來源隨偏好保存，只有明確選取預設或重設顯示頁才切回預設。霧品質只影響體積霧，不改距離霧、WorldClock 天氣或光照；Compatibility 的體積霧控制不可用。視窗模式使用確認倒數，取消或逾時回復原設定；headless 不可驗證原生視窗輸出。

啟動預設全螢幕，已保存的視窗模式仍優先；視窗模式的初始尺寸為 1280×720。GameSettings 在獨立視窗啟動時，若超出螢幕可用區域的 90%，等比例縮小並置中，保留標題列與工作列空間。嵌入編輯器及 headless 不調整原生視窗。`UILayout` 共用血條、快捷列、設定、平板、教學終端與倉庫的 CanvasLayer 縮放：以 1280×720 放大高解析度 UI，小視窗則保留至少 960×540 的邏輯佈局並縮小顯示；寬螢幕保留額外寬度，平板依邏輯寬度切換欄數。每幀只比較目前 viewport 尺寸，變更才更新，因此玩家移入室內 SubViewport 後仍可適應縮放。原生 3D 尺寸與解析度比例獨立。

SettingsMenu 不設定 SceneTree.paused，玩家 settings_open 是額外輸入遮罩。Player、互動射線、DriverSeat 與 Chassis 共同使用 is_gameplay_input_blocked，涵蓋事件與 held-key 輪詢；關閉時記錄仍按住的操作，放開後才恢復。重力、傷害冷卻、車頂支撐、世界時間、敵人與油電照常推進。駕駛期間釋放油門／腳煞車／轉向，不改引擎、gear 或 handbrake。平板與放置擁有各自 Esc 優先權；被抓、死亡、讀檔及 POI 轉場時拒絕設定入口，失去 actor 所有權時關閉。步行／駕駛 FOV 與滑鼠設定從服務即時更新現有及新建立的相機。

設定介面的 bool 控制使用 ButtonGroup 互斥「關／開」按鈕，勾選與背景共同表示狀態，容器不加入焦點輪巡。畫質組合 0 在 UI 命名「遊戲預設」，不改既有偏好欄位或預設值；render_mode 0／1 顯示「依場景自動／自訂比例」。解析度摘要讀玩家所在 viewport 的實際尺寸及 scaling_3d_scale，開啟期間持續更新，避免把尚未使用的儲存比例當成目前畫面，並支援室內與視窗縮放。自動模式隱藏比例滑桿。

`InteriorLayout` 生成版本 3 manifest，新訪隨機目標 30–60 模組、1–3 層，透過完整 socket transform 接合與三維 AABB 排斥擴展；候選／接口耗盡可提早停止。樓梯與新層首房原子安置，普通分類按 Profile 權重抽選，各層共用。`InteriorRoomDefinition` 以 ID＋內容版本解析，場景提供 footprint／clear_height／socket，新增普通尺寸／分類不改生成器。已保存 v3 manifest 原樣讀取，不套新房數目標。

`PoiInterior` 統一組裝、封牆、導航、探索、出生／出口與玩家掉落物保存。未接通 socket 的門框移除，牆板留在自身占地內，避免共享可見面閃爍。導航發布 immutable mesh 並等待 region／map 同步。`BunkerContent` 在初訪用獨立 RNG 配置深處一具 70% 耐久強化引擎，以及上限 2–12 件散落物、1–5 個各含兩件小型物資的補給箱；合法位置不足時不強行達標。敵人生成最多嘗試 `clamp(房間數 / 15, 1, 4)` 個合格房間，每次獨立以 30% 機率從可擴充候選池選出 Raker，因此可沒有敵人，也可有多隻。合格房間避開入口 24 m 房間連接距離及 18 m 空間距離。`BunkerCache` 使用靜態碰撞與分離視覺；玩家長按 E 1 秒，一次領一件，背包拒收不刪物。地圖按實際占用及保存層距繪製 B1–B3，只顯示樓層、房間輪廓、連線與樓梯圖示；2026-11-08 移除常駐房名、房數、目標位置及返回／按鍵說明，探索記錄仍持續更新。

保存實際布局與內容，不依 seed 重抽；`CheckpointSchema` 驗證逐房版本、接口對齊、占用、連通、內容與補給箱快照。剩餘補給品保留 Item 完整狀態與 ID，活 actor 保留位置及生命；既有布局不補抽新物資。新增目錄／修改權重不改變已訪布局，缺失或不支援版本拒絕。Checkpoint 只接受 v6，不再轉換或清除 pre-bunker 舊資料，舊檔保持原樣。原生成器／專用資產已移除。詳見 [地堡契約](../guides/bunker-interior.md)。

PoiInstanceManager 在入口互動後鎖定玩家輸入、建立 own_world_3d 的 SubViewport，完成載入後 reparent 原玩家與 UI。根 CanvasLayer 顯示 viewport texture，輸入轉交子 viewport，視窗縮放同步。室內設定開啟時，根合成層由 20 提升至 60 並隱藏室外 POI 標題；關閉後恢復，避免室外 HUD 蓋住選單。正常退出先保存室內 Item、活怪與補給箱的完整剩餘狀態，再把原玩家移回主世界並檢查返回落點，釋放副本幾何。saved_instances 供同局重返重建相同布局與內容；室外檢查點把這份資料一併寫入磁碟。非活動副本不繼續模擬。轉場有明確狀態與操作序號；離場取消沿共用安全收尾路徑保存室內狀態、恢復控制並清理暫建 viewport。

WorldEntities.same_world 用於群組選敵、碰撞例外及串流清理；怪物每 physics tick 清掉跨世界的快取玩家目標。只有原玩家與背包透過入口轉移；原設備作為背包 Item 可帶進地堡並放置。實例快照共用 Item／Monster，保存室內散落與固定物品，未連接 RV 的原設備不提供車輛服務。

地堡新增 16 個房間內容版本 2，只接受目前內容版本，布局仍為 version 3。新版家具碰撞獨立於 Visuals/Model；封牆沿用所在房間的牆／塗裝材質。BunkerLighting 以保存 seed、room ID 與固定版本字串做 SHA-256 排序，選出四捨五入後 60% 的普通模組熄燈，排除 entry／stairs；不消耗布局或內容 RNG，不增加存檔欄位。舊房間內容版本直接拒絕。

Flashlight 是小型 Item，初始世界以場景實例放在地面。`state.flashlight={charge,on}` 使用獨立欄位，不能混用 RV 的 `state.battery`；VehicleSnapshot 驗證有限 0–100 電量和開關型別，SaveSceneCatalog 明確登錄場景。玩家背包狀態為耗电真值，手持節點只鏡射 Spotlight；在 NORMAL、選取且可見照明時按 100/300 每秒扣電。PlayerGrab 在抓取開始前記錄實際亮燈狀態；原本亮著的手電筒在 GRABBED 期間保持可見、正常耗電，由持物姿勢將燈頭朝向抓取者臉部，解除後恢復一般朝向。切換、丟棄及倉庫移轉在序列化前關燈；模式暫停不耗電。讀檔用原 actor 替換流程清除初始地面實例，不另補發。
