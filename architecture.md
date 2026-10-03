# ApocalypseRV 架構

文件核對：2026-10-02 整合正式 v8 公路隨機內容與樹木撞毀；各功能細節沿用各自驗收日期。描述目前工作樹實作；已實作不等於全部情境已驗收。本輪架構審查、headless 檢查與當時未修正問題見 [架構與遺產報告](docs/report/ApocalypseRV_Architecture_Audit_2026-09-22.md)，未進行實機操作驗收。本次檔案清理見 [整理紀錄](docs/validation/2026-09-28-codebase-cleanup.md)。歷次測試結果保留在 [文件索引](docs/README.md)，目錄責任見 [程式與資產目錄指南](docs/guides/codebase.md)，待辦與後續設計見 [計畫總覽](docs/plans/README.md)。

[啟動與操作](README.md) · [遊戲設計](GDD.md) · [技術架構](architecture.md)

## 目錄

- [1. 執行環境與場景](#section-1)
- [2. 模組責任](#section-2)
- [3. 共用契約](#section-3)
- [4. 狀態與所有權](#section-4)
- [5. 主要流程](#section-5)
- [6. 已知限制](#section-6)
- [7. 測試與維護](#section-7)

<a id="section-1"></a>

## 1. 執行環境與場景

目標開發／CI 版本 Godot 4.7.2（由 `.godot-version` 固定，runner 強制核對），60 Hz／Jolt Physics（velocity/position steps 各 32）、桌面 Forward+／Vulkan（Compatibility 可降級）。[project.godot](project.godot) 的入口為 [world/main_world.tscn](world/main_world.tscn)，[world/test_world.tscn](world/test_world.tscn) 保留舊存檔及測試配置。目前沒有網路同步或任務系統；Checkpoint autoload 提供主世界檢查點。

專案功能標記為 4.7；開發與 CI 使用 4.7.2 stable。舊驗收紀錄中的 4.6.1 CI 是歷史資訊，不代表目前支援第二個引擎版本。

```text
MainWorld
├── Player                  玩家、Camera、互動射線、UI
├── WorldEntities           共用動態物件容器
├── WorldGenerator
│   └── chunk               地形、道路、導航、POI 入口建築
├── PoiInstances            同局副本狀態、轉場、串流錨點
│   └── InteriorViewport    獨立 World3D，僅探索時存在
│       └── PoiInterior     房間／走廊／導航／WorldEntities／室內玩家
├── NewRv
│   └── Chassis             VehicleBody3D、油電、材料、耐久
│       ├── Wheel_*         VehicleWheel3D；獨立輪槽 hitbox 常駐底盤
│       └── 座椅／車板／插槽／加油孔／道具箱   已安裝的 Equipment
└── StartRun                車庫門、整備／出發／封閉狀態
```

正式 RV 使用獨立 starter_rv 配置，保留引擎、電池、兩包維修包、平板與完整駕駛室；發電機、工作台、分解機由起始車庫提供。new_rv 保留完整測試配置。

### 起始避難所與世界識別

起始建築外殼擴為 50 × 45 × 14 m，封閉側翼與主樓使用原生幾何完成立面，僅獨立屋頂設備保留灰盒；中央車庫與活動門接口保留。場址 Resource 的 bounds 同步管理整地／植被排除，側後方土坡依 building_bounds 計算。外殼的靜態盒碰撞以 navigation_solid 標記，ChunkGenerator 將其轉成投影障礙，避免碰撞盒下方留下可走地形；鄰區重建沿用相同標記。模型需求與本輪驗收見 [擴建紀錄](docs/validation/2026-10-01-shelter-expansion.md)。

正式主場景明確選擇生成 v8；共用 WorldProfile 預設及測試世界保持 v6。v7／v8 的第一個停靠點為固定 WALK_IN 避難所，場址共用整地、植被排除、导航與串流範圍；三台設備及十二件物資只在首訪生成，沿用 WorldEntities／outdoor_sites 的動態物件保存。車庫門由 StartRun 管理 preparing → opening → started → closing → sealed，區塊重建時重新綁定門並套用狀態。ready_for_play 只表示地形／玩家可操作，不等於旅程已開始。整備期間停止時鐘與敵人處理，不跳過敵人生成。

Checkpoint v3 增加 world_id 與 start_state（version、phase）；只接受受信任的 legacy／shelter 場景映射，禁止由存檔提供任意場景路徑。shelter 對應 v7／v8，只保存 preparing／started／sealed；門移動期間拒絕保存。恢復開場狀態發生於子節點 ready 前，動態物件完成轉移後重新套用敵人狀態。缺少 world_id 的舊檔使用 legacy，保留 v2–v6 地形與原位置，不建立車庫或補發物資。

### 輪胎與爆胎路障

Chassis 四個輪槽的 wheel_health 為唯一耐久來源，0 表示爆胎；puncture_wheel 拒絕空槽與重複爆胎。TireDynamics 在底盤控制輸出後逐輪套用抓地、轉向及驅動修正；接地壞胎於接觸點施加隨速度平滑變化的阻力，另以接地壞胎的左右差與前後權重計算轉向偏差，不直接設定車身旋轉或清除速度。外觀與半徑只在爆胎／修復切換時更新。既有 WheelSocket、RepairOperation 與 Prop condition 支援維修／換胎；VehicleSnapshot 的 health 與物品 condition 已能保存爆胎，無新存檔欄位或版本遷移。

v2–v7 的 TireSpikeStrip 使用 WorldField.rng_for(band, "tire_spike_strip") 獨立種子流，在 ChunkGenerator 建立道路後生成，不消耗既有物資／敵人 RNG。路障屬 chunk，隨串流釋放與確定性重建；舊存檔載入也會產生此新障礙，地形生成版本不變。Area3D 只選取附近 Chassis，沒有車時停用 physics_process；附近每台車最多檢查四個接地點的跨幀線段與釘帶局部 AABB。輪寬計入邊界、離地與傳送跨距不觸發，無每幀全世界掃描或額外物理射線。釘帶不是可攀／可拆設備，不進 SaveSceneCatalog。回歸與限制見 [爆胎驗收](docs/validation/2026-09-22-tire-puncture.md)。

### v8 公路隨機內容

正式 main_world 新局選擇 v8，沿用避難所開場及小 POI；共用 WorldProfile 預設與 legacy fixture 保留 v6，v2–v7 存檔保留原生成。檢查點仍 v3，shelter 接受 v7／v8，legacy 禁止這兩版開場身份。

RoadSpawns.plan(field, band) 使用獨立道路釘帶／廢車／怪物 RNG，提供靜態姿態與 Raker 位置；前 450 m、安全據點與所有物件的 5 m 接縫距離受保護。一般車陣保留至少 5 m 中央通道，少量車陣橫置封路。靜態內容屬 chunk，加入導航烘焙；v8 改用這條釘帶流程，舊版保留 TireSpikeStrip.build。

導航 map／region 同步完成後建立道路 Raker，加入 WorldEntities 並尊重 skip_actors。generated_bands 防止回訪、死亡、遠距清理及重載補怪；v8 拒絕導航尚未發布時保存，以免漏掉即將生成的怪物。清理按怪物目前位置與戶外串流錨點前後 450 m 判斷，不以出生 chunk 決定；loaded WALK_IN 保護與舊版其他散落物清理維持。v8 正式 profile 設 chunks_ahead=2，與目前帶共覆蓋至多 450 m，避免前方道路怪物立即被遠距清理；舊版 profile 設定保留。自訂更遠載入窗仍按 450 m 規則清理。實作、測試與未驗證範圍見 [本輪紀錄](docs/validation/2026-10-01-random-road-spawns.md)。

### 樹木撞毀

Chassis 讀取實際物理接觸，以至少 3 m/s 的水平速度、朝接觸法線內至少 0.1 m/s 的接近速度判定撞樹，高速斜擦也能折斷；離開樹幹、低速及垂直落地不觸發。TreeImpact 只處理破壞，Chassis 在補速後按每棵樹真正造成的速度損失結算一次傷害，沿用下方 VehicleImpact 契約及 take_damage 扣引擎耐久。引擎歸零沿用現有停機／維修流程。

底盤快取前一物理步的線／角速度，避免 Jolt 已解算的硬碰撞讓撞擊速度歸零。先處理全部樹木撞擊，再依最後的破壞狀態判定實體阻擋，避免同 shape 的早期擦碰法線留下錯誤阻擋。只補回沿原水平行進方向損失的速度，每棵新毀樹保留 85%；同棵樹的多個接觸只計一次。接觸上限至少 128；已毀 shape 的延後停用期間不重扣傷害，有反向實體阻擋法線或接觸報告達上限時不補速，垂直與角速度仍由物理解算。

ForestTrunks 保留一個共用靜態碰撞體，shape owner 識別單棵樹，延後停用其碰撞並隱藏對應 MultiMesh instance。TreeFall 在 0.75 m 斷裂面留下斷樁，依材質分離木質與葉面，完整木質網格按世界高度切成最長 3.2 m 的 RigidBody3D 斷木，每段 2–4 kg；圓柱碰撞跟隨網格，layer／mask 1、CCD、摩擦 0.08，不排除 RV。斷木起始外觀承接原樹，依車身位置向外側散開並由物理解算傾倒，不留 HingeJoint 或樹冠碰撞。葉面依高度／方位分成實際網格小簇，保留貼圖與頂點色，重力／旋轉落到取樣地面後壓成薄層；預估落點先取樣，接觸時再確認地形，不逐葉逐幀射線。地面射線排除動態物件／角色。原樹接觸尚未清除時，輕量斷木不作為硬牆補速 veto；只剩斷木接觸後不再補速。斷木的真實地面接觸觸發塵土。木材與葉片獨立清理：木材含斷樁在 20–22 秒淡出後移除全部碰撞體，也可存在至少 8 秒、連續離開視野 2 秒後提前回收；葉簇保持不透明，存在至少 6 秒且全部落地後，連續離開視野 2 秒才釋放。逐組網格世界 AABB 檢查目前 Camera3D 六個 frustum 平面，回望各自重設计時，缺相機只阻止視野清理，木材定時回收仍有效；兩組均釋放後移除效果父節點。碎片隨 chunk 卸載釋放，不進 actor 或存檔。舊版路邊活樹／枯樹使用相同撞擊契約。

ForestScenery.build 首次建立森林前 await TreeFall.prepare：獨立 32×32 SubViewport 先建立一棵實際落葉／斷木／粉塵效果，停止處理、凍結剛體並停用碰撞，渲染兩幀後釋放，不播放音效、不寫破壞帳本或觸發導航。共用 Shader、頂點格式及陰影 pipeline 在載入期準備，blocked PCM 音效也預先合成；一次旗標避免串流重複準備。不可變原 mesh 的 surface arrays 快取最多 32 資源；切木只計算世界高度並在原局部座標裁切，葉面共用變換／法線矩陣，減少首次與每次撞擊的網格計算。

WorldGenerator／WorldField 共用 destroyed_trees 帳本，獨立於可淘汰的 forest_cache；森林 ID 使用 band／確定性生成索引，路邊樹使用原始位置。重建前仍消耗原外觀 RNG，存活樹位置與型號不漂移。Checkpoint v3 新增可選帳本，先驗證再恢復，舊檔缺欄位視為空帳本，不改生成版本。

破壞後以 0.35 秒合併導航重烘焙，沿用原 NavigationRegion 並序列化更新；接縫附近的已載入鄰帶一起更新，鄰帶 halo 也排除已毀樹。自動回歸為 test_tree_impact.gd，可見輪驅入口見 [測試場指南](docs/guides/playgrounds.md#tree-impact)。

### 車輛碰撞傷害

VehicleImpact 集中定義損失速度平方 × 0.75、單次上限 120 HP。樹木／怪物門檻 0.1 m/s，一般實體 0.75 m/s，地面累積損失 1 m/s。Chassis 先處理樹木及怪物讓路，再量測接觸點法線速度損失，避免把已補回的硬碰撞解算誤算為傷害。每棵新毀樹保留 85% 水平速度，怪物每次有效撞擊保留 95%；同時存在反向硬物阻擋或接觸報告截斷時不補速。Monster 在首次接受撞擊時通知底盤（包括致命撞擊），沿用既有怪物傷害、擊退與冷卻，重複 Area／剛體／探針通知不重結算；攀爬／車頂支撐接觸不算撞擊。

一般實體依 collider ID 保存事件，地面共用一個事件，0.15 秒內累積損失並只支付新增差額；持續抵住硬物刷新接觸時間，離開至少 0.25 秒才重建事件。地面事件只由有效衝擊刷新，不因平穩持續接地而阻止下一次落地；累積損失上限為事件中最大向內平移速度，一般實體上限為接觸點向內速度，排除回彈超額計費。不同障礙的事件互不冷卻。vehicle_impact 訊號回報種類、事件累積損失及本次新增扣血。

VehicleBody3D 在 _integrate_forces 之後才套用輪胎懸吊衝量：底盤先保存接觸解算後的線／角速度，再於 _physics_process 讀取 direct state 和 VehicleWheel3D 接觸點／法線，量測同一步的懸吊速度變化。接地法線 y > 0.5 視為地面，接近速度至少 1.5 m/s、單步衝擊至少 0.15 m/s，扣除重力常態支撐；近乎水平的地面另外要求向下平移，避免加速／煞車俯仰誤傷。出生／解除凍結／大距離傳送後 0.75 秒不計費。煞車及轉向的地面切向減速不計傷害；排除底盤自身及已連接設備的接觸。此傷害保存於既有引擎狀態，沒有增加存檔欄位。驗收見 [車輛碰撞](docs/validation/2026-10-02-vehicle-impact.md)。

### 世界時間與太陽

正式場景持有 WorldClock，集中維護累積遊戲秒數與一天的現實分鐘數，預設 day 1 / 08:00 / 30 分鐘。每幀依 delta 前進，跨日由累積秒數推導；minute_changed 提供日期、時、分，HUD 每遊戲分鐘更新。PROCESS_MODE_INHERIT 尊重 SceneTree 暫停及候選世界停用，背包／平板與 POI 不暫停世界。

WorldClock 獨佔正式室外 Environment 與 DirectionalLight3D 的光照設定，取代 WorldGenerator 的固定光照。太陽在 +X 升起、-X 落下，06:00／18:00 越過地平線，最高仰角約 58°；光源 basis 與天空 sun_direction 共用同一向量，地平線下光源能量歸零。天空、距離霧與環境填光按太陽高度平滑插值，霧距離不隨時段突然跳動（Forward+ 遠景 160–420 m；Compatibility 18–380 m）。使用自訂陰天天空、低解析 radiance cache、關閉天空反射來源；Forward+ 體積霧見下方「局部體積霧」小節，天氣由 WorldWeather 取樣後合成。

Checkpoint v3 增加可選 clock 字典（elapsed_seconds、day_length_minutes），與生成版本分開。讀取時檢查數字型別、有限值及範圍；prepare_world 在子節點 ready 前恢復，HUD 在 ready 強制刷新。舊 v1/v2/v3 缺欄位沿用 day 1 / 08:00，不改寫來源檔案、不計算離線時間。POI 的 own_world_3d 保留自身照明，戶外時鐘持續流動，返回立即使用目前時段。

`tests/day_night_playground.tscn` 的調時／加速鍵只用於驗收。歷史美術樣板凍結時鐘並明確使用 exponential fog，避免新光照每幀覆寫 A/B 環境。

### 動態天氣與雨聲

WorldClock 持有 WorldWeather（RefCounted），使用世界 seed 衍生的獨立 RNG；advance 將現實 delta 換算成遊戲秒後，同步推進時間與天氣。WorldWeather 提供 changed、sample、set_weather、capture／restore／valid_state，狀態以 Vector3 表示晴朗程度、雨級、霧級。分段剩餘時間與轉換進度都使用遊戲秒；set_time 是驗收調光入口，不重抽天氣。

WorldClock 仍唯一寫入正式室外 Environment、DirectionalLight3D 及天空 shader。夜間環境光能量為 0.002，天空與霧同步降至近黑；照明主要依賴場景燈具。小霧／大霧的距離霧終點為 110／38 m，8 m 起漸入；濃霧使用較暗的灰綠天空與霧色，壓低太陽直射、日輪及體積散射，避免遠景輪廓清晰或霧中物件泛白。無額外霧時維持下述遠景設定。

ForestFog 在 chunk 建立／退出時向該世界時鐘登錄／解除材質，不使用跨世界全域 shader 參數。新 chunk 立即接收目前密度；晴天淡出林間霧。天氣從無霧過渡至小霧時，全域及林間體積霧一起淡出，由距離霧接手，避免體積霧二次合成重新顯露已遮蔽的輪廓。天空 shader 使用 disable_fog，起霧後收斂至相同霧色。Compatibility 僅使用距離霧。

WeatherRain 使用兩層固定種子 MultiMesh 雨幕：近景 24,576 粒子／半徑 24 m／高 32 m，遠景 49,152 粒子／半徑 96 m／高 48 m。種子只上傳一次，rain_field shader 以 CPU 傳入、尊重暫停的時間計算落雨、世界座標環繞和 billboard；每幀只更新相機、時間、天氣參數，不逐滴更新位置或碰撞。大雨最多提交 73,728 粒子，小雨約 24,323；兩層交界及範圍邊緣漸淡，數字代表提交量，不是遮擋後實際可見數。

RainCover 使用兩張 64×64 世界座標環狀高度圖，近格 0.75 m、遠格 3 m；每物理步分別更新 256／128 格，60 Hz 下完整刷新約 0.27／0.53 秒。圖內攜帶 cell 座標與有效旗標，避免移動／傳送時舊資料錯用；未知格暫時隱藏雨。高度快取查詢第 1 層實體碰撞，排除玩家、怪物、底盤和設備；地形、建築與未分類道具依快取頻率刷新。最近 8 片有 BoxShape3D 實體碰撞的 RV roof 設備，以每物理步的逆變換傳入 shader，逐粒子做垂直線與有向盒相交，支援傾斜、拆除與破壞，不留下車頂高度圖殘影。超過 8 片車頂的密集場景未驗收。

水花另取樣攝影機周圍最多 8 條落點射線，最多 64 個、壽命 0.18 秒，弱參照及局部座標跟隨承接物件。包含 1 條聲音遮蔽射線，合計上限 393 次／物理步，與粒子數無關。大雨抑制太陽直射光和天空日輪。獨立 POI 停止戶外雨幕與水花、保留低音量雨聲；2 條程序 PCM 循環依雨勢混合，專用 bus 的低通隨頭頂遮蔽變化，世界退出時移除 bus。Compatibility 使用相同空間 shader，無需 GPU 粒子碰撞節點；其雨幕密度與範圍不縮水。

Checkpoint v3 的可選 weather 字典保存 source／target、transition_elapsed、remaining、rng_state；在 prepare_world、子節點 ready 前還原。缺欄位沿用陰天，非法值在世界重建前拒絕。正式天氣與測試快捷鍵分離；既有美術樣板固定天氣。驗收入口見 [天氣測試場](docs/guides/playgrounds.md)。

### 局部體積霧（目前正式設定）

桌面渲染改為 Forward+／Vulkan。WorldClock 設定薄全域體積霧與 160–420 m 遠景距離霧；ForestFog 使用獨立外觀 RNG，按地形低處與實際步道路線高度建立 FogVolume，隨 chunk 回收。世界座標 3D 噪聲和柔化邊界控制局部濃淡，霧不參與碰撞、導航或怪物感知，也不改地形生成版本與物資。

RV 車頂的 CabinAir 持有負密度排霧區，僅在安裝完成且可運作時啟用；獨立 World3D 室內副本不啟用室外體積霧。Compatibility 降級沿用 18–380 m 距離霧，不建立 FogVolume。地表紋理作為污痕資料遮罩採原始取樣，避免 Forward+ 的色彩空間轉換改變材質閾值。驗收見 [局部體積霧](docs/validation/2026-09-17-volumetric-fog.md)。

### 正式戶外 D 風格

前一輪霧效修正（目前保留為 Compatibility 降級）：原生 Depth 模式，18–380 m、curve 0.65、最大混合量 1，避免近景過早洗灰。天空 horizon_color 使用 source_color，與 Environment.fog_light_color 共用時段色彩（白天 a4aca9）；fog_sky_affect 為 0，天際線由天空本身匹配，高處只有低對比固定雲層。此 Compatibility 路徑沒有額外全螢幕霧後製或體積霧；Forward+ 的正式設定見局部體積霧小節。

ForestMeshes 使用共用的不透明低模分枝網格與粗葉脈／樹皮材質；ForestScenery 將原有世界座標轉成 48m 格內局部座標，樹／灌叢裁切距離為 340m／160m、遲滯 16m。未改生成 RNG、實例數、樹位或碰撞。這是正式渲染更新，不需要存檔或生成版本升級。

地表 shader 用現有三角形的導數計算平面法線，不改 mesh 頂點或碰撞；只取原泥地貼圖的低頻污痕。天空 shader 的光色由 WorldClock 驅動，配合距離霧與環境填光。OutdoorPresentation 保留約 540p 的舊室外縮放選項；後製不進行像素格量化或抖色，顯示偏好改由 GameSettings 與 Esc 設定選單管理。入口材質由外觀專用快取持有，不修改室內共用材質。

### 工業恐怖美術

- `IndustrialArt` 快取室外 StandardMaterial3D 與 256px 程序材質；兩張原創生成紋理位於 `assets/materials/industrial/`，Godot 匯入限制為 512px、使用 mipmap。室外建築以 mesh override 改外觀，不能修改室內共用的 POI 材質資源。
- RV 的共享掉漆材質維持 StandardMaterial3D；PanelWear／EngineAppearance 使用 detail multiply 疊加損傷，保留原本貼圖。健康狀態仍是老舊外觀，損傷／修復由原耐久資料驅動。
- CabinLightStrip 是獨立 Equipment；新車兩條各依附車頂，CabinLighting 只管理本條燈光。VehicleEnergy 每有效燈條支付 0.03/s，控制台提供總開關及逐條停用。拆下、損壞、移動或無電時熄滅；車頂排霧仍由 CabinAir 負責。
- IndustrialTheme 統一背包、生命、駕駛 HUD、平板及道具箱配色、方角框線、按鈕焦點。保留原字體與中文 fallback、資訊布局、互動及原生 UI 解析度。
- 本輪不改生成版本、地形／導航／碰撞或存檔格式；副本的 3D 材質與照明不在範圍內。驗證見 `docs/validation/2026-09-17-industrial-art.md`。

### 可切換美術樣板

`tests/industrial_style_playground.tscn` 繼承既有室外驗收流程，載入正式世界 seed 42。`world/art_sample/` 提供 SampleForest、SampleMaterials、維修廠附加立面，以及固定陰天天空／泥地 shader。替代 MultiMesh 與材質均由樣板持有；A/B 還原當前正式資源。樣板植被依 48m 格子分批，樹／灌叢裁切距離 300m／110m，保留 12m 遲滯。正式版分區後，樣板沿用来源節點變換與 forest_kind metadata，不解析分區名稱為型號。新載入 chunk 只掃直接子節點掛上外觀，沒有全樹每幀遍歷。

RV 牆板的局部 PanelWear source 隨比較切換，保留真實耐久損傷；車內燈繼續使用正式供電判定。新增立面是視覺樣板，正式擴展前還需補上高層量體的物理／攀爬設計及導航驗收。不得把獨立樣板視為已全面替換主世界。


<a id="section-2"></a>

## 2. 模組責任

| 模組 | 檔案 | 邊界 |
|---|---|---|
| 玩家協調 | [player.gd](player/player.gd) | 攝影機、移動、攀爬、生命、座位／UI／放置授權、手持外觀 |
| 玩家背包 | [player_inventory.gd](player/player_inventory.gd) | 6 格、選取、大型限制與消耗，不持有場景節點 |
| 玩家持物姿勢 | [player_carry_visual.gd](player/player_carry_visual.gd) | 依背包 is_large 切換右手／雙手，移動動畫後套用手臂 IK 與五指握合；手腕局部旋轉保留原動畫，拇指朝前。手電筒燈身依掌面貼合、四指依圓柱截面求解，燈頭維持朝前。下次動畫取樣前還原，死亡交接保留姿勢、重生清除快取。只調整手持外觀，不改移動／背包規則 |
| 互動 | [player_interact.gd](player/player_interact.gd) | 射線、目標提示與結果、E／F 獨立按鍵狀態、快速事件緩衝、輪胎安裝特例 |
| 放置 | [equipment_placement.gd](player/equipment_placement.gd) | 預覽位置／朝向、確認／取消輸入 |
| 可撿物 | [interactable_item.gd](props/interactable_item.gd) | Prop 剛體、名稱、大型旗標、回收產出與手持配置 |
| RV | [chassis.gd](rv/chassis.gd) | 控制授權、引擎／排檔／手煞車入口、輪槽、耐久、設備登錄與重量／重心 |
| 能源 | [vehicle_energy.gd](rv/vehicle_energy.gd)、[battery_state.gd](rv/battery_state.gd) | 代理有效插槽的 BatteryState、集中物理步調度；燃油屬於底盤 |
| 材料 | [material_storage.gd](rv/material_storage.gd) | 本車存量、容量、原子扣款、溢出保留 |
| 保存 | [checkpoint.gd](rv/checkpoint.gd)、[vehicle_snapshot.gd](rv/vehicle_snapshot.gd) | 版本化磁碟檢查點、車輛／設備／輸入物件關係還原 |
| RV 互動轉接 | [fuel_port.gd](equipment/fuel_port.gd)、[wheel_hitbox.gd](rv/wheel_hitbox.gd) | 加油入口、拆輪 |
| 設備基類 | [equipment.gd](equipment/equipment.gd) | 放置、物理／材質恢復、連線快取、耗電、破壞 |
| 專用設備 | [equipment/](equipment/) | generator 供電、scrapper 回收、tablet_screen/UI 顯示製作、crafting_station 出料、driver_seat 駕駛 |
| 串流 | [world_generator.gd](world/world_generator.gd) | 固定座標區塊窗口、分幀建立、遠景與距離清理 |
| 世界資料 | [world_field.gd](world/terrain/world_field.gd)、[world_profile.gd](world/terrain/world_profile.gd) | 獨立 RNG、三層噪音、區域權重、道路及停靠計畫、共用高度查詢 |
| 地形道路 | [chunk_generator.gd](world/chunk_generator.gd) | 網格、碰撞、路面、停靠設施、裝飾、實際碰撞導航和物資／敵人 |
| 場址計畫 | [exploration_site.gd](world/terrain/exploration_site.gd) | v3／v4 路線、平台、鏡像、窄口、圍牆分段及邊界，共用於整地／生成／導航／串流 |
| 顯示與偏好 | [game_settings.gd](core/game_settings.gd)、[outdoor_presentation.gd](world/outdoor_presentation.gd) | 全域偏好驗證／保存、viewport 品質與室外色調；Canvas UI 不縮放 |
| POI 外部 | [poi_config.gd](world/poi_config.gd)、[poi_spawner.gd](world/poi_spawner.gd) | v3 四種外觀、v2 原入口、穩定 ID／返回點與註冊 |
| 副本轉場 | [poi_instance_manager.gd](world/instances/poi_instance_manager.gd)、[poi_interior.gd](world/instances/poi_interior.gd) | 獨立世界、導航、返回、探索與玩家掉落物保存 |
| 隨機地堡 | [interior_layout.gd](world/instances/interior_layout.gd)、[interior_profile.gd](world/instances/interior_profile.gd)、[bunker_content.gd](world/instances/bunker_content.gd) | 可擴充房型、隨機 1–3 層、新訪 30–60 模組目標、manifest 版本 3 與一次性內容生成 |
| 怪物 | [monster.gd](enemies/monster.gd) | AI、導航、接觸觀測、攀爬、攻擊、車撞傷害、掉落 |
| 選敵 | [combat_targeting.gd](enemies/combat_targeting.gd) | 候選排序，使用 actor 提供的接觸判斷 |

玩家外觀由 `player.tscn/Visuals/Model` 實例化已驗收 v020 GLB，11 Mesh、41 變形骨、原尺寸 1.60 m。`PlayerModelVisual` 只管理顯示，不持有移動、生命或存檔狀態。Visuals 的 Y=0.25 對齊既有膠囊底部，繞 Y 180° 對齊控制器 -Z；攝影機位於根座標 (0, 1.78, -0.20)，實際眼高約 1.53 m。碰撞膠囊、玩家 root 與攀爬探針不變。

InteractRay 明確排除自己的玩家碰撞體，避免從較高相機往下看時命中自身膠囊。PlayerGrab 對蹲姿抓取者沿用駕駛座的 0.17 m 下拉分量，加上原 0.18 m 前拉仍在 0.25 m 上限內，保留球體掃掠與固定視角；怪物模型、骨長與原動作不變。

本地攝影機排除第 18 顯示層的完整身體／頭套，納入腳本專用第 21 層的去頭顯示副本與六個完整陰影副本。其餘五個配件沿用第 1 層；預設外部／後照鏡攝影機看完整模型，不納入第 21 層。新建副本只過濾頭部三角形索引，原 Mesh、Skin、材質與權重不改。鏡面仍使用第 20 層；自訂燈若縮限 light_cull_mask，需納入第 21 層。本地副本關閉 GI，避免重複烘焙。此契約支援現有單人及跨 World3D 轉場；多人需要按攝影機所有權擴充，尚未實作。正式玩家移除 TEST 動作，由 PlayerLocomotionVisual 讀取控制器局部速度播放 idle／jog／run 四方向循環，0.16 秒混合，不使用 root motion；跳躍依上升／下降／接地切換三段非循環姿勢，落地 0.2 秒回穩且可立即再次跳起；攀爬讀取相對 RV 的實際位移選取 hold／up／left／right，車身搬運本身不驅動步態；顯示骨架依壁面距離補有限貼牆位移，第一人稱鏡頭同步同一世界位移，避免視點與身體分離；不移動控制器，鏡頭角度仍由滑鼠控制。混合前移除上一幀骨架補償避免累加，登頂／脫離時身體與鏡頭一起收回位移；死亡交接保留當下視點，重生恢復原站立眼位。登頂辨識既有向內轉移與支撐，容許接地旗標晚一幀，接 0.3 秒收手；手動脫離接落下姿勢。抓取仍保留最後姿勢，专用動畫待後續製作；入座沿用整個玩家隱藏、離座恢復。正式死亡已接入 PlayerRagdoll，固定 60 Hz，保留 Jolt 32／32；布娃娃以局部轉動慣量及角阻尼穩定關節，落地／恢復及 79 組完整回歸已通過。見 [角色整合驗收](docs/validation/2026-09-27-player-model-integration.md)與[死亡布娃娃驗收](docs/validation/2026-09-27-player-death-integration.md)。

PlayerRagdoll（`player/player_ragdoll.gd`）僅持有暫態物理與死亡鏡頭，生命／模式仍由 Player 管理。首次死亡以不可變 rest pose 建立 14 個物理骨，再恢復當下動畫姿勢啟動物理，沿用 v020 碰撞與關節配置，腳部質量各 2.5 kg、合計 69.5 kg；第 8 碰撞層與環境接觸，排除自身膠囊。死亡解除抓取、座位、攀爬、UI 和放置，繼承世界速度並停用控制膠囊。第一人稱固定死亡起始方向、平移跟隨頭部，球體掃掠限制鏡頭偏移；本地身體和配件在死亡期間不遮住鏡頭，完整外部模型與陰影仍存在。兩秒後以真實站立膠囊檢查附近地面與淨空；受阻則每 0.25 秒重試。恢復後關閉 simulator 與碰撞、重設姿勢、恢復控制並續播正式移動動畫；不留持久屍體、不改存檔格式。跨 World3D 的死亡轉場取消會在返回位置重新綁定物理。新動作與關節交接細節見 [v021 動作驗收](docs/validation/2026-09-27-player-animations-v021.md)。

2026-09-22 的舊怪物 GLB 試接與 Zombie 場景已非現行敵人契約；當時的模型、膠囊縮放及原地測試動畫見[歷史資產說明](assets/models/monster/README.md)與[驗收](docs/validation/2026-09-22-monster-model.md)。目前正式敵人外觀與動作由下述 Raker 場景負責。

獨立 `raker.tscn` 使用 v021 左右整手網格／權重／UV 重建、54 根變形骨與三節四指动画、v019 掌向、v018 口腔與 v012 頭部／軀幹加密模型原尺寸 2.18 m，遊戲外觀等比放大 1.20 倍至 2.616 m，含立體深眼窩、凹陷嘴部與內嵌 2K 污垢膚色貼圖；`Raker` 繼承 Monster 的導航／攀爬／RV 支撐，增加慢速逼近、短促追擊與獨立追車狂奔（車速 +1.2 m/s、上限 18 m/s、加速 10 m/s²）、對一般玩家抓咬掙脫、對攀爬玩家與結構保留橫掃／專用攻擊、接觸時重新驗證傷害、受傷中斷和死亡布娃娃。低姿態膠囊 1.85 m，跨破口門檻維持低姿態；站起須有淨空。41 段原地骨架動畫由 `raker_visual.gd` 切換，含低姿態受傷／落地／死亡，匯入資源不共用修改。主世界一般戶外停靠點新生成的敵人全部使用 Raker，數量／位置／生成 RNG 不變；新訪地堡也使用 Raker 候選池。SaveSceneCatalog 登錄其場景，既有 WorldActorSnapshot 保存物種類型與 HP。資產與限制見 [Raker 說明](assets/models/raker/README.md)。

Raker 車撞效果只由 Monster 新接受撞擊後的 hook 觸發，沿用共用傷害／冷卻及 RV 結算。接近速度 ≥6 m/s 或死亡切入 15 個 PhysicalBone3D；較輕撞擊保留 0.55 秒擊退。切換延後至碰撞查詢結束，停用控制膠囊、動畫、頭手 IK、抓咬及 AI；物理骨承接當下姿態和撞擊速度。原始 GLB／54 骨／1.2 倍外觀不改，碰撞尺寸烘入放大倍率並抵銷 body_offset basis，保持物理 scale=1。碰撞層 128／mask 1，只與環境及車體接觸，不做布娃娃肢體互撞；CCD、關節限角及局部慣量維持原專案 60 Hz／Jolt 設定。初始手腳穿過車頭接觸面時，全姿態沿法線最多推出 1.2 m；撞擊點另有短粒子與程序音效。

存活 Raker 倒地至少 2.5 秒且全部身體速度低於 1 m/s 持續 0.35 秒後，檢查附近下方支撐與完整站立淨空；受阻持續等待，以 0.8 秒姿勢混合起身。死亡保留物理 18 秒後連同碰撞清理，死亡期間支撐移除仍會下落。根位置跟隨骨盆，外觀世界座標獨立，避免重複位移並支援距離清理。WorldActorSnapshot 對戶外存活倒地怪新增可選 ragdoll 字典（外觀世界 transform、54 個骨局部 pose、骨盆速度），先驗證再恢复；舊檔相容，死亡屍體不存。讀檔保留倒地姿勢，肢體角速度和恢復計時不保存。驗收與輪驅重播見 [Raker 車撞布娃娃](docs/validation/2026-10-02-raker-impact-ragdoll.md)。
RakerGrab 是怪物的暫態抓取狀態機，PlayerGrab 持有唯一抓取者、輸入、HUD 與鏡頭鎖。0.36 秒前搖後重新驗證雙臂可達性和遮擋，再開始固定 2 秒倒數；6–10 次需求只抽一次，80% 以整數比例判定。咬合第 0.22 秒獨立扣血一次，避開一般受傷冷卻，同一 tick 解除存活玩家的輸入、鏡頭和 HUD；怪物自行進入 0.35 秒 RELEASE，死亡回呼重入清理時不重啟流程。Blender 咬合原在 0.38 秒，以 BITE_SPEED（0.38／0.22）同步加速，咬擊混合縮至 0.035 秒；伸手動畫以 0.6／0.36 倍速播放。玩家模式 GRABBED 優先於 SEATED，save/load 沿用 NORMAL gate 拒絕，無存檔欄位變更。駕駛事件和 Chassis 輪詢輸入都封鎖，仍保留車輛物理與鬆油門回收。雙方 tree_exiting、轉場、受傷、死亡、失去接觸／支撐、強制離座共用解除入口。

RakerPoseModifier 使用 SkeletonModifier3D 在動畫後依實際臉向修正三節頸骨，僅更改旋轉，權重 35%／35%／30%；一般追視為 180°/s、yaw ±90°、站立上 30°／蹲姿上 40°、下壓 25°。站立 reach／hold 保留原脊椎姿勢，頸部下壓可至 70°。三種 bite 都以嘴部接觸點求解三節脊椎，每節相對輸入最多 55°；0.045–0.18 秒快速前探，實際抓住玩家後，嘴部目標在固定視線前 7.5 cm，咬合朝向與該視線相對並保留頸部限角，避免近距離追視反覆翻動。骨架局部座標快取避免移動 RV 的物理／渲染幀錯位。動畫由各 actor 獨立 AnimationLibrary 播放；雙臂 IK 與接觸檢查共用 RakerGrab.head_grip 頭側抓點、臂長和肘部方向。雙掌朝內、指根向上及玩家腦後伸展，指節向掌心屈曲，前臂分攤 65% 扭轉。接近檢查採原鏡頭錨點，抓住後雙手跟隨實際頭部位置。PlayerGrab 在咬擊開始鎖定前拉方向：前拉 18 cm，駕駛另下拉 17 cm，總位移約 24.8 cm；以半徑 9 cm 球體掃掠阻擋，偏移存在鏡頭父節點座標以跟隨 RV。抓取開始以 0.15 秒抬頭看向怪物，之後將角度固定在鏡頭父節點座標直到解除；咬擊不再追嘴巴或施加向下／側傾頓挫；抓取時 near 暫設至不大於 1.2 cm，解除時恢復原位置及 near。存活解除同時恢復當前玩家視角的滑鼠捕捉和地面輸入回呼；座位維持其原有輸入所有權，轉場／死亡不搶回鏡頭。傷害幀暗紅閃光獨立衰減。見 [固定抓咬視角驗收](docs/validation/2026-09-24-raker-fixed-grab-view.md)。



<a id="section-3"></a>

## 3. 共用契約

- [groups.gd](core/groups.gd)：rv、chassis、equipment、monster_damageable、rv_power_generators、crafting_stations、player、monsters。正式程式用 `Groups.*`，部分測試用原字串釘住契約。
- [item_names.gd](core/item_names.gd)：物品、背包、配方和材料庫名稱常數。
- [rv_connection.gd](core/rv_connection.gd)：由父節點向祖先搜尋；RV 須為 Node3D、屬 rv 群組並提供 `add_item`／`deduct_materials`，避免 Equipment／Chassis 預載循環。
- [climb_math.gd](core/climb_math.gd)：RV 辨識、壁面幾何、附著位移與屋頂轉移共用計算。
- [rv_support.gd](core/rv_support.gd)：記住腳下精確支撐面和 RV transform，補償固定車板缺少的平台速度；支撐刪除、換車或單步位移過大時解除。
- [world_entities.gd](core/world_entities.gd)：建立／重用場景動態容器，場景釋放後可重建。

互動採 `interact(player)`／`interact_hold(player)` 方法契約，受傷目標提供 `take_damage(amount)`。群組與祖先階層錯誤可能造成離線或候選忽略，而非編譯錯誤。

### 設備統一規格

新增或修改可搬移設備沿用下列現有契約；這是製作與接入規格，不表示已有自動產生任意設備的工具。固定 EngineBay／RearRamp，以及作為 Prop 的引擎／電池，是既有例外，不套用自由搬移設備的所有權流程。

| 面向 | 統一規則與來源 |
|---|---|
| 根節點與資料 | 繼承 [Equipment](equipment/equipment.gd)（RigidBody3D），以 [EquipmentDefinition](equipment/equipment_definition.gd) 集中 type_id、名稱、重量、最大 HP、直立限制與操作淨空；persistent_id 屬實例，不能用共用 Resource 保存個別耐久／工作。 |
| 外觀與碰撞 | 外觀子節點與功能碰撞分離；get_placement_bounds 合併根層 CollisionShape3D，新增／替換模型時需保持可驗證的占用範圍。bottom_face 指定貼合面，放置方向由共同規則決定；需要額外動態掃掠的門扇另由專用設備處理。 |
| 安裝與歸屬 | get_connected_rv／refresh_rv_connection 取得真正所屬車；mount_support 是精確支撐，與車輛歸屬分開。initial_support 只供新場景預裝，讀檔使用保存的支撐 ID。一般設備自由貼面，結構設備走固定槽位，預覽與確認都須通過 PlacementRules。 |
| 可用性與清理 | can_operate 統一檢查啟用、支撐、預覽、毀損、耐久與連車。以 availability_changed／removing 通知；在 _on_service_stopped／_on_before_destroy 清理工作、輸入、UI 或座位。搬移立即停機，取消還原原物理狀態；失去支撐後掉落並繼承車輛點速度。 |
| 資源與供電 | 能源由 VehicleEnergy 調度，材料由本車 MaterialStorage 管理；設備／UI 不另持有一份油電材料總量。交易失敗不吞資源、不重複退款；生產輸入由工作站持有，缺電暫停，搬移／摧毀安全退料，出口受阻保留工作。 |
| 受損與修復 | take_damage／needs_repair／repair_health 共用耐久入口；以 destroy_on_zero_health 明定刪除或留可修殘骸。設備維修沿用 RepairOperation；損傷外觀只讀耐久，不新增另一份 HP 或隱藏碰撞。 |
| 保存 | 場景須納入 SaveSceneCatalog；VehicleSnapshot 保存 id、scene、transform、health、enabled、support 與 service。新增 service 欄位要同步擴充捕捉、驗證、還原與相容預設；現有欄位白名單不會自動接受任意設備資料。 |
| 接入驗證 | 以正式場景驗證預設方向／淨空、安裝／取消、跨車歸屬、斷電、支撐移除、歸零、資源清理及保存還原；功能另補適用測試。物理改動依 AGENTS 做實機攀爬／支撐／拆頂檢查。 |

基礎回歸見 [設備生命週期](tests/test_equipment_lifecycle.gd)、[RV 系統](tests/test_rv_systems.gd)、[檢查點](tests/test_rv_checkpoint.gd)。凍結設備的碰撞力矩限制仍見第 6 節；遵守上述規格不代表大型外掛物理已解決。


<a id="section-4"></a>

## 4. 狀態與所有權

| 狀態 | 擁有者 | 資料 |
|---|---|---|
| 背包 | PlayerInventory | `{name, is_large, scene_path, state}` 陣列、active_slot；state 保存 ID、condition、scrap_yields、回收結果及電池子型別資料 |
| 玩家模式 | player.gd | NORMAL／PLACING／UI／SEATED／DEAD／GRABBED，由欄位推導優先模式，非完整集中狀態機 |
| 移動 | 各 actor | NORMAL／CLIMBING、附著 RV、前一 transform、接觸寬限、冷卻、RVSupport |
| 怪物意圖 | Monster | WANDER／CHASE／ATTACK、追蹤玩家、攻擊目標 |
| 車輛 | Chassis＋VehicleEnergy＋MaterialStorage | 控制、4 輪槽身分／耐久、引擎耐久代理、電池與材料；相容屬性轉送至專責狀態 |
| 設備 | Equipment | 穩定 ID、EquipmentDefinition、啟用、車輛與支撐、預覽快照、耐久及工作清理 |
| 生產工作 | 各工作站 | 配方 ID、預留材料、剩餘電費／時間、輸入物件所有權、待出料結果 |
| 串流 | WorldGenerator | active_chunks 的 node/index/start_z/end_z、next_band、building、WorldField 和 profile |
| 副本 | PoiInstanceManager／InteriorLayout | active_id、saved_instances actor 快照、rooms／edges、局部 RNG |

地形、入口和路旁靜態模組由 chunk 擁有。動態敵人、搜刮物、玩家丟棄品、合成品和死亡掉落使用所屬世界的 WorldEntities。室內與主場景根節點都以 entity_domain metadata 指定自己的容器，避免初始 ready 時 current_scene 尚未設定而落到 SceneTree 根。WorldGenerator 只清理同一 World3D、錨點後方超過 450 m 的動態物件。玩家進副本後，錨點固定在進入前位置。

例外：主場景既有物品仍在根部，拆下輪胎、成品與掉落電池使用 WorldEntities。室內物資和怪物死亡掉落都使用室內容器。

玩家 `enter_*`／`exit_*` 授權 UI、座位與放置，呼叫方須尊重拒絕。DEAD 阻擋輸入／移動；平板和座位在玩家死亡或設備失效時釋放模式。


<a id="section-5"></a>

## 5. 主要流程

### 世界

WorldGenerator 建立 WorldField／WorldProfile／POISpawner → 正式 v8 初始後 2／目前 1／前 2 個固定網格帶（共用 profile 保留前 3 帶） → 查詢區域／道路／停靠計畫 → 共用整地結果生成地表、路面與碰撞 → 安置靜態內容 → 烘焙導航並生成動態內容。行駛中的建立分多影格執行，完成前不發佈到 active_chunks；一次只有一個建立作業。

串流比較室外玩家或副本錨點 Z；v2–v4 只向 −Z 推進，v5+ 維護前後窗口並可回頭載入。WorldField 以世界座標計算有界平面曲線；道路高度取低頻地形需求，按 150 m 高度節點限坡，再 smoothstep 插值。WorldProfile 預設路寬 15／10 m、坡度上限 8%、區域長 900 m／過渡 240 m。seed_for(index, domain) 隔離道路、停靠、外觀、路線、裝飾、loot、敵人和副本亂數，入口 ID 為 v{generation_version}:world_seed:stop:index；重播的是生成配置，不是物理與 AI 時序。檢查點 v3 另存 generation_version（2–8），缺省為 2；新 WorldProfile 預設 6。舊檔不改地形與 POI ID。

外部停靠點位置為 index×450±75 m。v4 起始維修廠位於 (335.2,6,-45)，v3 保留 (135,6,-45)，每三點兩個離路入口、一個小補給；v2 保留 (49,0,-45) 近路維修站與原比例。ExplorationSite 以道路局部座標建立左右及前後鏡像模板，檢查完整場址是否落在版本對應碰撞帶內（v4 寬 900 m，v2／v3 寬 450 m），必要時改向另一側；無無限重抽。WorldField.surface 將場址平台、緩坡、步道及保留區整合到共用取樣，公路高度優先。spawn_site 使用同一份 building/road/frame/id/seed，外觀不消耗物資 RNG。四款外觀沿用既有入口及副本。

地形網格使用相鄰取樣圈計算法線，邊界共享世界位置及高度。v4／v3 導航分別涵蓋 900／450 m 寬碰撞帶，cell_size=0.25 m；v2 維持 240 m／0.5 m。使用實體碰撞，排除高 7 cm 的重複瀝青層，補相鄰地形、圍牆與建築碰撞資料；邊界資料由共用計畫提供，不依賴相鄰 chunk 載入順序。v3／v4 高容許 detail 誤差抑制噪音坡面新增的重疊細三角形，可通行輪廓仍由 voxel 決定；v2 保留原設定。非同步烘焙後發佈獨立 NavigationMesh，navigation_ready 等待 region 和 map 真正同步，避免初始空網格。怪物地面高低差仍使用導航；path_height_offset 對齊角色腳底；落地且已到達路徑點水平範圍時，以實際腳下高度推進路徑點，避免簡化網格埋入土坡造成繞圈。未移動的目標不重複重設路徑；移動目標維持 0.25 秒更新間隔。

場址牆段依中心 Z 歸唯一 chunk；整地跨帶查詢同一計畫。玩家位於場址 bounds 或室內 stream_anchor 時，protected_bands 保留並補建停車區、路線及建築的區塊與 halo。ForestScenery 以獨立 RNG 的 8 m 網格抖動形成樹林，逐列分幀規劃，樹幹簡化碰撞也提供相鄰導航 halo；快取至多 16 個帶。ForestMeshes 快取四款不對稱針葉樹、兩款枯樹與三款灌叢，共九批 MultiMesh；forest_art_variants 獨立亂數只選外觀，不改既有樹位、碰撞與 seed。遠景左右及前方網格只提供視覺。新造景延續分幀建立，build_ms／max_slice_ms 記錄成本。

室外日夜照明由 WorldClock 控制，Forward+ 使用局部體積霧與遠景距離霧，Compatibility 降級只保留距離霧。GameSettings autoload 管理全域顯示、輸入與音量偏好；Esc SettingsMenu 是設定入口，F8 不再處理顯示。值在載入與寫入時檢查型別、有限值及範圍；缺漏或非法持久化欄位各自回預設。偏好寫入獨立 ConfigFile，不進角色／車輛或 Checkpoint 快照，短時間多次滑桿變更合併保存，關閉選單時 flush，錯誤由 save_completed 與 last_save_error 回報。舊 display_preferences.cfg 的 retro=false 遷移至手動 100% 解析度及關閉復古色調，retro=true 保留舊室外 540p 模式及色調。

register_viewport 把 3D 縮放、抗鋸齒與陰影品質套用到主 viewport 及新建立的室內 SubViewport。舊解析度模式維持室外目標高度 540、最高 1，室內原生解析度；手動 50–100% 解析度同時套用室內外。復古色調與解析度分開，亮度／對比／飽和度使用 3D 後製，Canvas UI 保持清晰。品質預設只修改解析度、抗鋸齒、陰影與霧，其他欄位不變，個別品質調整後保留「自訂」來源，即使數值又與預設相同也不自動改回；此來源隨偏好保存，只有明確選取預設或重設顯示頁才切回預設。霧品質只影響體積霧，不改距離霧、WorldClock 天氣或光照；Compatibility 的體積霧控制不可用。視窗模式使用確認倒數，取消或逾時回復原設定；headless 不可驗證原生視窗輸出。

SettingsMenu 不設定 SceneTree.paused，玩家 settings_open 是額外輸入遮罩。Player、互動射線、DriverSeat 與 Chassis 共同使用 is_gameplay_input_blocked，涵蓋事件與 held-key 輪詢；關閉時記錄仍按住的操作，放開後才恢復。重力、傷害冷卻、車頂支撐、世界時間、敵人與油電照常推進。駕駛期間釋放油門／腳煞車／轉向，不改引擎、gear 或 handbrake。平板與放置擁有各自 Esc 優先權；被抓、死亡、讀檔及 POI 轉場時拒絕設定入口，失去 actor 所有權時關閉。步行／駕駛 FOV 與滑鼠設定從服務即時更新現有及新建立的相機。

設定介面的 bool 控制使用 ButtonGroup 互斥「關／開」按鈕，勾選與背景共同表示狀態，容器不加入焦點輪巡。畫質組合 0 在 UI 命名「遊戲預設」，不改既有偏好欄位或預設值；render_mode 0／1 顯示「依場景自動／自訂比例」。解析度摘要讀玩家所在 viewport 的實際尺寸及 scaling_3d_scale，開啟期間持續更新，避免把尚未使用的儲存比例當成目前畫面，並支援室內與視窗縮放。自動模式隱藏比例滑桿。

`InteriorLayout` 生成版本 3 manifest，新訪隨機目標 30–60 模組、1–3 層，透過完整 socket transform 接合與三維 AABB 排斥擴展；候選／接口耗盡可提早停止。樓梯與新層首房原子安置，普通分類按 Profile 權重抽選，各層共用。`InteriorRoomDefinition` 以 ID＋內容版本解析，場景提供 footprint／clear_height／socket，新增普通尺寸／分類不改生成器。已保存 v3 manifest 原樣讀取，不套新房數目標。

`PoiInterior` 統一組裝、封牆、導航、探索、出生／出口與玩家掉落物保存。未接通 socket 的門框移除，牆板留在自身占地內，避免共享可見面閃爍。導航發布 immutable mesh 並等待 region／map 同步。`BunkerContent` 在初訪用獨立 RNG 配置深處一具 70% 耐久強化引擎，以及上限 2–12 件散落物、1–5 個各含兩件小型物資的補給箱；合法位置不足時不強行達標。敵人生成最多嘗試 `clamp(房間數 / 15, 1, 4)` 個合格房間，每次獨立以 30% 機率從可擴充候選池選出 Raker，因此可沒有敵人，也可有多隻。合格房間避開入口 24 m 房間連接距離及 18 m 空間距離。`BunkerCache` 使用靜態碰撞與分離視覺；玩家長按 E 1 秒，一次領一件，背包拒收不刪物。地圖按實際占用及保存層距繪製 B1–B3，HUD 顯示引擎與返回提示。

保存實際布局與內容，不依 seed 重抽；`CheckpointSchema` 驗證逐房版本、接口對齊、占用、連通、內容與補給箱快照。剩餘補給品保留 Prop 完整狀態與 ID，活 actor 保留位置及生命；已訪舊 v3 地堡缺內容欄位時維持空內容，不補抽新物資。新增目錄／修改權重不改變舊布局，缺失版本拒絕。`Checkpoint` 在記憶體丟棄已識別的 pre-bunker v1／v2 POI，保留其他世界資料，不在讀取時覆寫來源。原生成器／專用資產已移除。詳見 [地堡契約](docs/guides/bunker-interior.md)。

PoiInstanceManager 在入口互動後鎖定玩家輸入、建立 own_world_3d 的 SubViewport，完成載入後 reparent 原玩家與 UI。根 CanvasLayer 顯示 viewport texture，輸入轉交子 viewport，視窗縮放同步。室內設定開啟時，根合成層由 20 提升至 60 並隱藏室外 POI 標題；關閉後恢復，避免室外 HUD 蓋住選單。正常退出先保存室內 Prop、活怪與補給箱的完整剩餘狀態，再把原玩家移回主世界並檢查返回落點，釋放副本幾何。saved_instances 供同局重返重建相同布局與內容；室外檢查點把這份資料一併寫入磁碟。非活動副本不繼續模擬。轉場有明確狀態與操作序號；離場取消沿共用安全收尾路徑保存室內狀態、恢復控制並清理暫建 viewport。

WorldEntities.same_world 用於群組選敵、碰撞例外及串流清理；怪物每 physics tick 清掉跨世界的快取玩家目標。怪物與物品不穿越入口，只有原玩家與背包轉移。實例快照目前支援 Prop／Monster，未支援搬入副本的任意設備。

地堡新增 16 個房間內容版本 2，舊版定義停用生成但保留解析，布局仍為 version 3。新版家具碰撞獨立於 Visuals/Model；封牆沿用所在房間的牆／塗裝材質。BunkerLighting 以保存 seed、room ID 與固定版本字串做 SHA-256 排序，選出四捨五入後 60% 的普通模組熄燈，排除 entry／stairs；不消耗布局或內容 RNG，不增加存檔欄位。舊房間內容版本 1 保留原照明。

Flashlight 是小型 Prop，初始世界以場景實例放在地面。`state.flashlight={charge,on}` 使用獨立欄位，不能混用 RV 的 `state.battery`；VehicleSnapshot 驗證有限 0–100 電量和開關型別，SaveSceneCatalog 明確登錄場景。玩家背包狀態為耗电真值，手持節點只鏡射 Spotlight；在 NORMAL、選取且可見照明時按 100/300 每秒扣電。PlayerGrab 在抓取開始前記錄實際亮燈狀態；原本亮著的手電筒在 GRABBED 期間保持可見、正常耗電，由持物姿勢將燈頭朝向抓取者臉部，解除後恢復一般朝向。切換、丟棄及倉庫移轉在序列化前關燈；模式暫停不耗電。讀檔用原 actor 替換流程清除初始地面實例，不另補發。

### 設備放置與支撐

F 長按 → 玩家授權 → 保存父節點／變換／freeze／碰撞層／速度／材質 → 停止服務 → 共用 PlacementRules 驗證 ghost。驗證使用各碰撞形狀和定義的操作空間，檢查合法支撐、重疊、朝向和支撐循環；確認前重新計算候選。結構板提供可選面中心接點吸附。

確認後分開記錄本車歸屬與 mount_support。設備向本車登錄；支撐 removing/tree_exiting 先停機，再延後解除掛載，帶 RV 點速度落至 WorldEntities。取消還原完整物理快照。UI、駕駛與生產由共用停止入口清理，重複清理不重複退款／退料。目前搬移時的 removing 通知只由 RVPanel 補上，一般 Equipment 同底盤搬移可能遺留依附設備；此為待修缺口，見第 6 節。

### 能源、道具與生產

BatterySocket 繼承 Equipment 並保存 installed_battery；VehicleEnergy 透過弱參照查詢底盤的有效插槽，Chassis.current_power/max_power 保留代理介面。同車最多接通一顆電池，未接入的背包／倉庫電池不參與供電。搬移開始、支撐脫落或損壞時，插槽將 BatteryState 轉成世界 Prop 並清空自己；掉落點在車體外，繼承車輛點速度。取消搬移不自動收回。

底盤直接保存 current_fuel/max_fuel；FuelPort 只提供加油交易，拆除、損壞或多裝入口均不改變存量／容量。BatterySocket 交換先檢查新電池與舊電池去處，滿背包使用原槽位；沒有有效插槽就沒有隱藏電量。

Chassis 物理步呼叫 VehicleEnergy：扣引擎油耗 → 依本車穩定 ID 呼叫正常發電機 → 電池待機支出 → 工作站 step_work。發電需要引擎運轉；無油停止引擎。發電機開關／門檻不會自動點火；燃油保留只限制發電附加負載。玩家進副本時室外照常模擬。

Prop 進 HopperArea → Scrapper 取得唯一 processing_owner，保存物理快照並隨機器定位 → 一個處理槽分步付費 → 固定一次回收結果 → MaterialStorage 接受後才刪物。缺電保留進度；滿庫保留完成結果；拆卸／摧毀恢復輸入物理。

RecipeDefinition/RecipeCatalog 定義七個配方（汽油罐、兩款電池、輪胎、兩款引擎與引擎維修包）。平板只 request_craft，工作站檢查有效性／完整電費並預留材料，進度逐步耗電；取消退材料，已用電不退。完成後檢查出料空間才生成；堵塞保留待出料工作。spawn_item 的即時介面也在完整驗證後扣材料與電費，失敗回復。成品屬於本世界 WorldEntities，繼承 RV 點速度；製作電池初始電量為零。

MaterialStorage 保存底盤數字材料，material_capacity 預設 300；容量不依賴設備，超額只允許消費／退款，不再領出 Material Bundle。底盤 stored_items 保存完整道具記錄，item_capacity 預設 24 格。ItemBox 開啟不耗電的 item_storage_ui；同車箱子共用底盤倉庫，先驗證容量／背包大型限制再轉移，按鈕保留原項目快照以拒絕過期操作。搬移、損壞、斷線與玩家死亡關閉 UI。

### 駕駛、維修與保存

控制仍由 Chassis 集中協調，未另做 VehicleController 類別。引擎狀態與入座分離，方向鍵遙控只可由測試明確啟用。輪槽常駐，即使沒有輪胎仍可射線互動；輪胎 ID／condition 在拆裝間保留。RepairOperation 累計持續瞄準時間，一般設備／輪胎完成才扣 2 Metal Parts 並補 60 HP；引擎另用專用維修包；切換目標、移動車輛、發動引擎或中斷免費取消。

Checkpoint autoload 在主場景攔截 F6/F9。保存限室外 NORMAL 模式、沒有 POI 轉場或地形建立中。Variant 序列化禁用 objects，版本 3；先寫 .tmp、flush 並讀回比對，將上次有效檔備份為 .bak，再 rename 至 user://rv_checkpoint.save。讀取透過 CheckpointSchema 與 SaveSceneCatalog 驗證格式、值域、巢狀 POI、場景根類別、支撐 ID 和循環；磁碟錯誤按階段回報。

F9 先在停用物理與處理的獨立 World3D 暫建完整候選世界，等待地形與導航就緒，再套用 actors；原世界直到提交成功才釋放。WorldEntities.transfer 保留設備的支撐、電池和工作生命週期。失敗或逾時恢復原世界，來源存檔不變。

檢查點包括玩家背包／位置／生命、世界 seed／profile／有效 bands、RV、鬆散 actors 與已訪 POI 記憶。主場景 enter_tree 先配置保存的地形範圍，生成時跳過動態物資；ready 建立車輛／設備、接回支撐 ID、電池、輪胎、油料、材料及工作，最後恢復模擬。分解機持有輸入不重複列入室外 actors。版本 1 經記憶體轉換後驗證：車載燃油歸原底盤、舊電池建立插槽；游離油箱燃油及材料包（含背包、世界、POI、分解輸入）歸第一台保存車輛。保留超額材料，必要時提高燃油容量避免遺失，原檔不被讀取覆寫。新存檔保存道具倉庫及底盤容量，電池只存於設備 service。未知版本拒絕；目前沒有室內直接保存或多槽。v5 已保存休眠 walk-in 場址，仍不提供場址外所有散落物的永久歷史恢復。

### 攀爬與戰鬥

玩家 W 加 RV 壁面命中，通過法線／高度／頭頂條件開始攀爬。套 RV transform 差並保留碰撞；W 登頂，S／Space 脫離；過大角速度、位移、失去接觸或頂部阻擋會中止。

Monster 結合 NavigationAgent3D、直接追蹤 fallback、卡住監測與高度協助。MonsterBoarding 管理附近入口選擇、掛門／登頂模式、接觸前相對速度抽樣、抓握耐力、恢復和車頂失衡；ClimbMath／RVSupport 仍負責碰撞、登頂與隨車支撐，不改玩家攀爬策略。車門提供實際 leaf 邊界與關閉狀態；不把整個門框當成葉片。

所有攻擊最後經過 boarding.can_attack，掛門攻擊只由掛門流程發出，攀牆途中與抓穩期間禁止結構攻擊。屋頂破壞仍由 UnderfootProbe 與玩家高度授權。車身運動取樣跨短暫地板接觸缺失保持連續，避免重新接觸誤判從靜止加速。RVSupport.capture 在 is_on_floor 成立但缺少滑動碰撞時，用膠囊腳底短射線驗證真實支撐，避免地板吸附造成逐影格漏跟車；支撐拆除仍立即失效。碰撞前保存怪物世界速度，車撞／抓握共用 ClimbMath.point_velocity；高速撞擊先於抓握，並有傷害／重抓冷卻。

MonsterBoardingVisual 僅處理程序生成手臂與原創 PCM 空間音效，透過 attack_landed 接收真正命中的事件，不改碰撞形狀。抓握、模式和導航目標屬暫態，讀檔重新判斷，不改 checkpoint 格式。

MonsterCabinRoute 是目前 4 × 12 m RV 的局部 AStar3D 步行圖，20 cm 網格、實際角色膠囊重疊／掃掠檢查，含對角連線。目標或車輛改變及每 0.65 秒重新規劃；路點存在車輛本地座標，隨轉向／平移轉換。落在設備上時從真實高度檢查離開桌面的水平路段，再由重力落地。近戰終點需視線可及，不單純靠近座位中心；玩家不可及時不把車內設備當替代攻擊目標。RVStructureSlots 提供被拆除後仍存在的破口位置，開門角度至少 70° 且完整膠囊可通過才視為出口。走道封死等待重規劃，車內不使用隨機跳躍脫困。DriverSeat 碰撞拆為座墊／底座與椅背，避免整塊盒子包住乘員而完全阻擋近戰。圖不保存至 checkpoint，也不取代室外 NavigationAgent3D。

CombatTargeting 做一般排序，Monster 觀測候選並執行攻擊。腳下設備只能由 UnderfootProbe 實際命中選取，且需較低位置的追蹤玩家授權；同 physics tick 共用射線結果，其他攻擊路徑排除同一支撐目標，避免繞過授權。

一般移動時，已在近戰距離／高度範圍且視線通暢的玩家優先於接觸設備與拆頂目標，直接進入 ATTACK；接觸攻擊不能先消耗其共用冷卻。攀車目標更新只選目標，不逐影格覆寫 CHASE，避免阻止攻擊狀態執行。待機取 detection_range、追擊／攻擊取 lose_interest_range。Player 的受傷無敵計時在座位／介面移動鎖之前更新，兩者不會延長無敵。正式 Raker 場景回歸見 [test_raker.gd](tests/test_raker.gd)、[test_raker_cabin.gd](tests/test_raker_cabin.gd) 與 [test_raker_boarding.gd](tests/test_raker_boarding.gd)。

### RV 外觀與駕駛室原型

預設 RV 更新為 WAYFARER 工業露營車：深綠車殼、奶油白窗框／屋頂、橘色標示、透明有碰撞的玻璃、前後燈與輪圈。側牆分成六片：面向車頭時，右側由前到後為牆／門／牆，左側為牆／牆／牆；後方是一組向外開啟的雙扇大門。每片側牆、側門整組、後門整組可獨立搬移與破壞，屋頂仍為一整片。

駕駛座綁定座椅、方向盤、儀表台、排檔桿、手煞車與踏板，F 搬移整組。方向盤跟隨底盤轉向，排檔桿／手煞車位置與速度、油電儀表同步車況；操控沿用 B、Space、Z/X/C、R/T。駕駛時背包欄隱藏，底部顯示車況與操作提示，離座恢復。加油孔與電池插槽位於車外維護側。

[模型結構說明](rv/visuals/README.md)；[展示場景](tests/rv_design_workshop.tscn)（F2 外觀、F3 車內、F4 駕駛、F5 輪驅、F6 舊版、F7 控制台）。舊車殼保留在 [rv/legacy/new_rv.tscn](rv/legacy/new_rv.tscn)。

#### 分片結構、槽位與門扇

- `rv/structure_slots.gd` 由底盤持有九個永久槽：六側面、前、後、頂。以射線與槽位平面求交，空槽不依賴牆面碰撞；槽位預覽僅在搬移時顯示。
- `rv_panel.gd` 保存 `structure_kind`／`mount_slot`，安裝在底盤座標，鄰片互不支撐；搬移時發送 removing，釋放真正附掛於該片的設備。
- `rv_door.gd` 沿用 Equipment 所有權：門框、可旋轉門扇碰撞都屬同一根剛體，傷害、維修、F、保存只處理一組。葉片視覺與碰撞同步；開關預檢完整掃掠路徑，動畫中逐步複查動態阻擋。
- `EquipmentPlacement` 優先選相容槽位並自動旋轉；`PlacementRules.rejection_reason` 共用實際碰撞檢查和玩家提示。V 仍可回到自由貼面／直立放置。
- snapshot 沿用 v2 的可選 service.mount_slot／door_angles，校驗槽型、重複占用、固定變換與有限角度。載入會冪等轉換原廠位置的舊長牆，重連其設備到對應分片；自訂舊牆保持原狀，游離設備不占槽。
- `test_rv_structure_modules.gd` 驗證拆裝、取消、傾斜底盤、阻擋、動態夾阻後反向開啟、依附掉落、獨立破壞、雙扇互動、保存與舊檔轉換。新增視覺測試場 `rv_door_playground.tscn`。

實測及限制見 [分片牆與門驗收](docs/validation/2026-09-16-rv-structure-doors.md)。

### 完整 RV、引擎與車況

- EngineDefinition（engine_standard／engine_upgraded.tres）集中 450／600 耐久、1.0／1.25 動力、1.0／1.15 引擎油耗及重量；EngineState 只保存 id／model／health，item() 轉為含同 ID 的大型道具記錄。
- 固定 EngineBay 持有唯一安裝狀態。Chassis.exchange_engine／remove_engine 原子轉移同格背包，service_reason 共用停穩／熄火／手煞車／開蓋條件。Chassis.take_damage 轉交引擎，has_working_engine 和 engine_start_reason 統一啟動條件；沒有底盤 HP 或整車毀損旗標。
- RepairOperation 對引擎使用 repair_requirement 契約；鎖住目標、引擎 ID 與維修包 ID，連續 3 秒後再次驗證並消耗道具，+150 耐久。一般設備／輪胎沿用材料路徑。
- VehicleEnergy 依引擎定義計算基礎油耗；只有有效引擎能運轉，發電仍由獨立設備提供。處理充電、待機、工作後統一支付車燈負載，lamps_powered 為實際供電結果。
- VehicleStatus.read 回傳 8 項圖示／等級／文字；CockpitVisual、VehicleDashboard、TabletUI 讀同一結果，沒有副本數值。VehicleLights 控制真實 SpotLight3D 與燈罩發光；舊裝飾燈材質不再常亮。
- chassis.tscn 原生網格與簡單複合碰撞保留舊輪槽和車殼座標。正式 new_rv 預裝完整服務；Equipment.initial_support 僅設定新場景預設依附（平板→工作台）。讀檔由已保存 support ID 還原，不套預設配置。
- RearRamp 是底盤固定子節點；檢查手煞車、速度、兩扇門角、地面法線與兩端支撐、完整展開路徑。1.4 m 寬斜面碰撞及兩折視覺分開，展開阻止 engine_force 並保持煞車，仍可怠速。收起檢查上方占用；狀態保存 deployed／angle／length。
- DriverSeat 離座以 current_driver 的實際 Shape3D／局部變換和碰撞遮罩搜尋支撐地板。正常受阻保留所有權；破壞、拆除、死亡強制搜索外圈支撐／上方淨空並解除座位。
- EquipmentPlacement 對自由放置累積繞面法線的旋轉和切面平移，細調後重新射線確認接觸仍屬原支撐，再用 PlacementRules 驗證。結構槽維持固定姿態。接觸箭頭與控制提示跟隨預覽清理。
- RVPanel.dependency_summary 沿 mount_support 遍歷本車設備，區分直接與間接依附。PanelWear／EngineAppearance 只讀耐久，複製材質實現磨損／玻璃裂紋，絕不改變碰撞或狀態所有權。
- v3 VehicleSnapshot 保存 engine_item、headlights、hatch_open、ramp。v1／v2 沿用結構／儲存轉換，再以車輛 ID 衍生穩定標準引擎 ID、舊 HP 轉入；v3 不重新遷移或補發。EngineState.unique_ids 對車輛快照與整份檢查點（含背包／地面／倉庫／POI／分解輸入）驗證引擎唯一性，並驗證模型與道具場景一致。
- CraftingStation 依實際產物根層碰撞檢查出料空間，以產物碰撞 AABB 底部計算出料高度；完成但阻塞的工作留在佇列，不重複出貨或扣款。

#### 新增驗證入口

駕駛體驗增量：Chassis 集中油門、腳煞車、速度相關轉向上限；road_speed 以物理步實際位移取樣，僅供儀表／聲音，不改變動力學。VehicleMirrors 擁有兩個共享 World3D 的 SubViewport，相機裁掉鏡面專用第 20 層避免遞迴，192×256 並交錯 UPDATE_ONCE 更新；前側板弱參照由設備登錄訊號刷新，離座停用、讀檔重連。

EngineHatch／RearRamp 持有 progress、目標與 moving，動作前及逐步做碰撞掃掠，受阻維持姿態。坡板先滑出再翻折，動作中雙片碰撞、完成後連續斜面。save_block_reason 與 VehicleSnapshot.capture 拒絕非穩定狀態，Checkpoint 顯示具體原因；正式保存仍只寫既有穩定 hatch_open／ramp，不保存過渡動畫。

VehicleAudio 快取原創 PCM stream，每車一個引擎迴圈／最多三個一次性空間音源，操作提交後觸發並有節流；僅引擎視覺子樹可震動。WorkLighting 的工作台燈隨設備釋放，CabinLighting 跟獨立燈條；照明只透過控制台控制；VehicleEnergy 支付各類可用燈具的負載。VehicleSnapshot 的可選 comfort 保存燈具請求、亮度與震動並在套用前檢查型別／有限值／範圍；cabin_light_devices 標記將舊車頂內建燈一次性轉換成有固定 ID／支撐關係的燈條，已拆除燈條的新版存檔不補回。音源來源見 [音效說明](assets/audio/README.md)。

| 測試 | 覆蓋 |
|---|---|
| test_rv_engine.gd | 預裝、引擎所有權、滿背包交換、大型道具、故障服務、維修、性能差、車燈、v2／v3 與實際引擎製作 |
| test_rv_boarding.gd | 正式角色攜引擎走坡板／走道，展開阻擋／占用／坡度、驅動互鎖、安全離座與自由放置 |
| test_rv_checkpoint.gd | 磁碟往返：安裝／背包／倉庫／地面引擎 ID、型號、耐久，以及拒絕跨所有權重複 |
| rv_rebuild_playground.tscn | 可見引擎艙／坡板／汽車儀表／夜間車燈／真實輪驅回放 |

完整測試與實機證據見 [驗收紀錄](docs/validation/2026-09-16-rv-rebuild-engine.md)。該次紀錄使用本機 Godot 4.7.2；目前 CI 也固定至 4.7.2。外掛設備撞擊力矩、極端翻車、怪物群和長途經濟未因此視為完成。


<a id="section-6"></a>

## 6. 已知限制

- 2026-09-22 審查確認的 A01–A03 仍待修正：一般 Equipment 搬移未通知依附物；玩家 UI 模式停止重力／RVSupport 更新；v5 普通動態物件清理仍只判斷正 Z 遠距。A04 的 POI 離場取消及正常安全清理路徑已在本輪修正；歷史重現證據仍見 [架構審查 A01–A04](docs/report/ApocalypseRV_Architecture_Audit_2026-09-22.md)，本輪結果見[地堡驗證](docs/validation/2026-09-29-bunker-content.md)。
- POI 導航生命週期及車內每隻怪物同步重建路徑的群體成本尚未量測；不代表已重現崩潰或卡頓。
- 設備仍是獨立凍結剛體。重量／重心已彙總，但側撞與大型外掛的碰撞力矩未合併到車體；翻車、偏載、怪物群需專項實測。
- 控制、輪槽與登錄仍共用 Chassis；能源、材料、保存已抽離，後續可按需求再拆控制／掛載服務。
- 配方出料使用產物根層的實際碰撞形狀檢查；新增產品需驗證碰撞配置與出料淨空。
- 簡化載重只加總底盤、已安裝引擎與有效的已安裝設備，並依位置計算重心；電池本體、抽象材料、庫存道具、燃油與鬆散貨物不納入車體質量。插槽與倉庫設備本體仍計重；游離道具保留既有剛體行為。BatteryState.weight 保留供道具物理與舊存檔相容使用，VehicleSnapshot 載入後以同一 update_load 重算車重，無需存檔遷移。首版檔位不模擬離合器／轉速。
- 保存只支援室外檢查點，沒有多人所有權、室內直接保存或多槽；v2–v4 仍單向串流；v5 可回程載入。
- 隨機地堡有 16 個啟用的廢棄房型與保留的 16 個舊版定義，已增加家具、表面破損及暗房；九類複雜設備仍以灰盒等待建模交付。完整地表設施、更多物資／敵人變化與長局平衡仍未製作。本次驗收見 [場景與手電筒](docs/validation/2026-09-29-bunker-art-flashlight.md)。
- 真實輪驅與停車倒車測試通過，但燃油關閉的測試場不是長途資源平衡證據；未宣稱全部玩法與模擬步組合完成驗收。


<a id="section-7"></a>

## 7. 測試與維護

### POI 資產層與副本驗證

`PoiDefinition`（`world/poi_definition.gd`）及 `world/poi_definitions/*.tres` 統一兩類 POI 的 ID、場景、場址範圍、入口路徑及室內 profile。POIConfig.DEFINITIONS 是資產目錄；GENERATION_IDS 是保留原順序的 v3／v4 生成池，兩者分開。POISpawner 與 chunk 鄰帶導航共用 scene_for_site，未知 ID 不退回預設；無 exterior 的舊場址解析至 maintenance_legacy。生成時只為 INSTANCE_ENTRANCE 註冊 PoiInstanceManager；入口與返回路徑由定義傳入 metadata，未使用定義的既有測試保留原節點路徑預設。v5 的 WalkInSites 使用定義 site_bounds 整地、清空植被及保護跨帶場址；舊場址規則不變。戶外保存記錄 content_version，不支援的版本拒絕載入，尚無自動佈局遷移。詳見 [共用規範](docs/guides/poi-authoring.md)。

加油站 `fuel_pump.tscn` 以 `Visuals/Model` 實例化 `assets/models/gas_station/fuel_pump.glb`，Collision 保留原三塊 BoxShape3D，字樣仍由 Godot 維護。GLB 不帶碰撞或行為；來源為 `scripts/build_fuel_pump_glb.py`。測試場 F7 只切換新舊 Visuals，原碰撞物件不重建。尺寸、匯入比例、碰撞及探索回歸由 `test_gas_station.gd` 驗證。

`world/poi_kit/buildings/gas_station.tscn` 是同世界可步行進出的靜態建築資產，分離 Visuals、Collision、Furnishings、LootSpawns、AccessPoints 與 Lights。資產不自行產生物資，也不持有副本管理器；`tests/gas_station_playground.gd` 負責測試地面、導航烘焙、正式玩家／RV 及一次性固定 seed 物資生成，道具進入 WorldEntities。生成 v5 已接入正式串流、場址與檢查點；`test_gas_station.gd` 驗證同世界通行、導航、E 拾取及替換外觀後碰撞仍存在。

`world/poi_kit/` 提供 `PoiRoom`、`PoiDoorSocket`、`PoiFurniture` 與 `PoiLootPoint`、`PoiEntrance`。房間原點在地板中心，接點 local -Z 朝外；`connect_to()` 依完整 transform 接合不同尺寸房間，拒絕不相容接口。Visuals、Collision、Furnishings 與標記彼此獨立。所有副本使用 InteriorProfile 登錄的 16 個地堡模組；舊副本專用資產與展示場已移除。

物資標記只提供 caller RNG 的抽選契約；初訪地堡由 BunkerContent 使用獨立 RNG 安置內容，BunkerCache 保管未領取物件。入口只發出 entry_requested，由 PoiInstanceManager 管理；場景及 Resource 可在編輯器直接修改。首批來源 `build_bunker_kit.py` 拒絕覆蓋既有 kit。詳見 [製作規格](world/poi_kit/README.md)。

`test_poi_asset_kit.gd` 驗證房型接口與玩家跨接縫；`test_interior_*.gd` 驗證 1000 seeds、扩充、逐門掃掠、三層大型搬運、導航與 manifest 保存；`test_poi_instances.gd` 驗證正式入口、世界隔離、外部電量、掉落／重返。實機觀察與自動檢查分開記錄。

### 統一驗證

測試入口為 `scripts/test.ps1`，預設 `quick`；`integration`、`slow`、`assets`、`smoke` 分組供開發選擇，`full` 執行全部有效測試與正式主世界驗證。`tests/suites.json` 必須覆蓋每個頂層測試，未分類、重複或缺檔即失敗。CI 在各 job 的獨立 checkout 分組跑全部覆蓋；本機保留逐支獨立程序，避免共享存檔與 autoload 狀態污染。固定 60 fps 模擬排程不修改物理 Hz、time_scale 或求解器；`-RealTime` 提供實時對照。等待導航及 checkpoint 背景工作的測試使用 `tests/support/test_wait.gd` 的條件與期限；有效物理採樣時段仍保留。命令、維護與證據位置見 [測試指南](tests/README.md)。

底盤腳煞車以固定物理步長逐步追蹤踏板輸入（加壓 0.35 s、釋放 0.15 s），最大制動值 100；手煞車／坡板互鎖使用獨立 300。這些保留為原 60 Hz 的調校值；VehicleBody3D 的 brake 實際為每步衝量上限，輸出乘以 `60 × delta`，避免提高至 120 Hz 後每秒制動加倍。設備重心透過父層局部 transform 組合，避免長距離行駛時 world-to-local 浮點誤差導致反覆寫入同一重心。

串流效能：地形取樣、網格組裝與導航接縫採約 4ms 的合作式時間預算；單次引擎 mesh／碰撞建構仍不可中斷，並非硬性幀時間上限。導航接縫重用共享頂點取樣；森林碰撞先在場景樹外完整組裝再加入，避免逐棵修改作用中的 compound body。遠距物件清理每 0.5 秒執行，最多延後半秒；載入與場址保護仍每幀檢查。量測與限制見 [串流效能驗證](docs/validation/2026-09-18-streaming-performance.md)。

[scripts/test.ps1](scripts/test.ps1) 檢查實際 Godot process 的退出碼、錯誤日誌與 `PASS:`；smoke 需專屬 WORLD_READY_FOR_PLAY 標記。`-TestFilter` 可指定檔名或逗號分隔的多個樣式，合併去重後只跑選取項目；`-Smoke` 額外檢查正式主場景，`-StartAt test_name` 從指定測試接續。每項預設期限 240 秒，CI 每個分組 job 期限 30 分鐘；報告須區分分段與單次完整執行。CI 為 [tests.yml](.github/workflows/tests.yml)，版本／commit／工作樹、選取清單、結果及耗時保存於 `.godot/test-logs/` 的各次執行目錄。

| 測試 | 關注範圍 |
|---|---|
| [test_player_inventory](tests/test_player_inventory.gd) | 格數、選取、大型限制、消耗 |
| [test_equipment_lifecycle](tests/test_equipment_lifecycle.gd) | 玩家授權、取消、跨 RV 連線、正確車輛供電 |
| [test_combat_targeting](tests/test_combat_targeting.gd) | 獨立選敵策略 |
| [test_monster_navigation](tests/test_monster_navigation.gd) | 導航、高度、碰撞、攀爬和攻擊 gates，尤其腳下射線授權 |
| [test_player_climbing](tests/test_player_climbing.gd) | 攀爬幾何與 helper 契約 |
| [test_moving_rv_climbing](tests/test_moving_rv_climbing.gd) | 生產場景、移動 RV 攀爬／支撐／拆頂，含物理驅動情境 |
| [test_world_entities](tests/test_world_entities.gd) | chunk 刪除後容器存活、場景重建 |
| [test_rv_systems](tests/test_rv_systems.gd) | 電池交易、能源、正式設備工作／清理、失效授權 |
| [test_rv_extended](tests/test_rv_extended.gd) | 底盤容量、加油孔、維修、輪胎、重量、長停耗電 |
| [test_rv_braking](tests/test_rv_braking.gd) | 漸進踏板、不同速度煞停距離、倒車、引擎熄火與獨立駐車 |
| [test_rv_handling](tests/test_rv_handling.gd) | 正式輪驅起步、轉向、低速停靠倒出、平地／5° 坡車況與設備配重、支撐離座 |
| [test_rv_experience](tests/test_rv_experience.gd) | 維修蓋／坡板中途阻擋與反向、過渡態保存拒絕、燈具供電／耗電、設定相容與音效狀態 |
| [test_rv_shared_storage](tests/test_rv_shared_storage.gd) | 掉落電池、共用道具倉庫、滿庫／滿背包、引擎救援、舊檔轉換 |
| [test_rv_checkpoint](tests/test_rv_checkpoint.gd) | 磁碟與主世界重建、電池及生產所有權 |
| [test_rv_resource_cycle](tests/test_rv_resource_cycle.gd) | 搜刮、回收、製作、加油、維修、充電與再出發 |
| [test_rv_physics_regression](tests/test_rv_physics_regression.gd) | 正式 RV 裝載設備穩定性 |
| [test_poi_definitions](tests/test_poi_definitions.gd) | 完整 POI 目錄、ID 唯一性、資源與場景契約、類型分流及舊版場址相容 |

本次改版見 [共用儲存驗收](docs/validation/2026-09-16-rv-shared-storage.md)。先前執行結果見 [RV 驗收紀錄](docs/validation/2026-09-15-rv-systems.md)。文件更動檢查連結與來源；程式更動執行適用測試及統一 runner。物理更動另須依 [AGENTS.md](AGENTS.md) 做互動視覺檢查。資源交易、能源與保存已有正式場景回歸；長途經濟、極端翻車和怪物群仍需擴大驗收。

遵循 GDScript tabs、可行時明確型別、snake_case 檔案／函式、PascalCase class、UPPER_SNAKE_CASE 常數；重用 core 契約。新增 POI 必須有有效內容，新增物品需設回收產出，設備需驗證連線／取消／毀損。

地形每帶依生成版本寬度建立網格（v4 為 301×51 個頂點，v2／v3 為 151×51），行駛中分批取樣、組裝及安置；導航背景烘焙，無獨立作業執行緒生成場景節點。`test_world_generation.gd` 驗證 100 seed、載入順序、坡度、停車與實際網格／導航接縫；`test_roadside_exploration.gd` 使用正式玩家從停車區走到物資、以 E 拾取再返回。`highway_playground.tscn` 提供正式輪驅 5 km 及停車倒出回放。量測、測試環境與限制見 [驗收紀錄](docs/validation/2026-09-15-highway.md)。

### v6 路邊小 POI

正式主場景選擇 v8，v7／v8 沿用 v6 小 POI 規則；共用 profile 與測試世界預設 v6，v2–v6 分支保留原 seed、場址、物資與舊資產。`MinorSites` 獨立規劃每 1,200 m 區間的小場址，最多四次候選，避開大型場址與車道；穩定 ID 使用 `v版本:seed:minor:cell`，v6 保留原 `v6:` 前綴。六主題各三個 WALK_IN 定義，不重排 POIConfig.GENERATION_IDS。v6 不再生成固定 index % 3 == 2 的舊小點，該 stop 查詢返回空字典。

`WorldField.sites_near_z` 與 `stops_in_band` 合併大型與小型場址，作為整地、植被、道路裝飾、導航鄰帶幾何、釘帶避讓與 protected_bands 的共用入口；縱向查詢有上限 256 筆的唯讀快取。主題、佈局、位置、美術、物資、敵人各有獨立 RNG。小場景資產的 Visuals 不持有碰撞或 actor 標記，外觀隨機化不改通路。

`PoiDefinition.enemy_count_range` 預設為零，非零時驗證 EnemySpawns 中足量且在界內的 Marker3D。WalkInSites 首訪抽取物資與敵人，actor 均屬 WorldEntities；加油站既有物資 RNG 不變。卸載與復原沿用 outdoor_sites／WorldActorSnapshot，無第二套保存資料。Checkpoint 格式仍 v3，新增接受 generation_version 6；休眠狀態記錄 definition_id 和 content_version，未知版本拒絕。更多內容與驗收見 [小 POI 規格](world/roadside_pois/README.md) 與 [本輪驗收](docs/validation/2026-09-26-minor-pois.md)。

### v5 加油站保存基礎（v6 沿用）

`WalkInSites` 在停靠點 index % 3 == 1 配置 gas_station；index 0 維持維修廠。定義占地加外圈步行餘量參與 WorldField.court_distance，因此地形、植被排除與車道共用同一計畫。建築碰撞參與 chunk 導航及鄰帶補圖。導航 readiness 先確認 region iteration 與有效 bounds，再等 map 上可查詢到鄰近網格；只在 map RID 或同步 iteration 改變時重做最近點搜尋，避免等待期間每個物理步反覆掃描整張戶外導航網格。共用邊界點不必只屬於自己，等待期間重新取得 map，支援檢查點跨 World3D 轉移。

WorldGenerator v5 維護前後載入窗口、場址 pinned bands 及 generated_bands，回程重建不重抽小補給點。加油站初次用獨立 walk_in_loot RNG 讀取標記；靜態資產仍不生物資。卸載 owner band 前，WalkInSites 收集 bounds 內主世界的鬆散 Prop／Equipment／活怪，保留完整 transform、狀態及速度，釋放活動 actor；回程只還原保存的剩餘物件。搬入後丟下的物品也包含在內，車輛及車上設備／庫存不歸場址。

Checkpoint v3 增加可選 outdoor_sites／generated_bands；活動物件只放 actors，休眠場址只放 outdoor_sites，WorldActorSnapshot 共用驗證／建立／捕捉契約。EngineState 的全樹唯一性檢查涵蓋休眠物件。舊檔不改版圖；戶外 content_version 不符拒絕還原。加油機尚無燃油交易功能，遠離場址的普通散落物仍沿用既有遠距清理規則。
