# 功能實作契約

2026-11-12 從 [architecture.md](../../architecture.md) 移出的各功能實作細節，內容保留原文，尚未逐段整理。段落多半帶有日期與版本號：版本以程式常數為準，與程式不符時以程式為準，並在這裡修正。整理規則見 `docs-maintenance` skill。

## 近期功能摘要

2026-11-09 精神值與白影。玩家的 `PlayerSurvival` 新增 `san`，以生存模擬時間從 100 在 1200 秒降至 0。Checkpoint v7 與列印身體 v2 共用此欄位，同格式既有存檔省略時以 100 載入。白影刷新以世界時鐘的 06:00–18:00 為白天，累計有效戶外物理時間，進入室內保留倒數。白天抽中後採樣距鏡頭 35–55 公尺的地面，以包住動態輪廓的球體檢查出現點完全位於鏡頭視錐外。日落後輪廓完全離開畫面時結束遭遇。白影現身後沿地面追向玩家，直視時速度為 5.5 m/s，其餘時間為 3 m/s。追擊使用接地採樣和膠囊掃掠，碰到玩家即進入既有死亡流程。坐姿以實際軀幹判定，車殼和設備可阻擋接觸。首次通過步行／駕駛視角的中央停留與頭胸遮擋判定後，按直視距離扣除 SAN。整個輪廓離開畫面時，以玩家為中心搜尋不同方位的接地點，確認落點淨空、視線暢通且整個輪廓位於視錐外後瞬移。每次重新直視都能再次觸發。連續遮蔽與不可見各有獨立計時，分別達 3 秒與 30 秒時隱藏並重設出現等待。白影材質依 3D 渲染像素在模型深度所覆蓋的寬度，有限度地加寬遠處輪廓，保留既有深度遮蔽。遭遇僅存在於當前戶外世界。詳見[白影指南](white-apparition.md)。

巨型避難所地下通道從接待室以外的未連通牆面接口抽選樓梯間入口，檢查門前淨空與導航可達性。巨型避難所、地堡及無燈柱廳的獨立樓梯間共用 `InteriorProfiles.STAIR_DESTINATIONS`，以各自的 seed 抽選底門目的地並保存 `stair_destination`。轉場管理器使用各副本的穩定保存 ID 並記住來時的門，離場時可逐層返回。[室內指南](megashelter-interiors.md)

2026-11-01 巨型避難所室內：生成 v19 將 `modular_megashelter` 接到獨立 World3D 的 `megashelter` profile；外殼內容仍 v7，既有地形／道路及外觀 RNG 域保留。只開放地面一層，入口、大廳、三至五間功能房與少量連接空間通常共六至八個模組，按外部面積選擇模組尺寸。首訪二至四件散物與一個箱子，沒有敵人或升級引擎目標。`InteriorProfiles` 供生成與 Checkpoint 共用分流；保存完整布局、探索、箱子與散物，回訪不補貨。Checkpoint v7／VehicleSnapshot v6 不變，只接受生成 v19，舊局重新開始。本次轉場／保存檢查與 seed 42 實際回放已通過；完整範圍與待驗項目見[室內指南](megashelter-interiors.md)。

2026-10-30 巨型避難所地面裝飾：外殼內容 v7，`MegashelterDetails` 提供低層設備、露筋碎塊及入口遮簷；地面配置使用獨立 RNG，生長／結構／屋頂仍沿用 v5 域。附件錨定接地牆板，實際 bounds 避讓門框及結構，並保留前方接近空間。原生零件進入既有三材質批次，地面排風機已停用；牆面沿用四項改進前的修補位置與剝落變體，獨立 `repair_variant` 選用六種新裝飾模型並檢查避讓，牆面及地面服務鐵件依 seed 與組件 ID 抽選鏽蝕程度。入口鋪面含門檻、排水與破損收邊，同樣合批；碰撞與鄰帶導航仍消費同份 plan。見[地面裝飾驗證](../validation/2026-10-30-megashelter-facade-refinement.md)。

2026-10-28 電子指南針：`ElectronicCompass extends Item` 共用物品 ID、倉庫與保存契約，不保存搜尋目標。`BuildingLocator` 從普通越野及獨立大樓候選帶查詢 `modular_megashelter`，依建築原點的水平距離選取 2 km 內最近目標，包含未載入場址。手持副本每秒或移動超過 20 m 啟動背景搜尋，工作執行緒擁有獨立 `WorldField`／profile／快取，完成後才在主執行緒更新讀值；跨 domain 結果以 epoch 拒絕，保留工作 locator 至執行緒 join。只查玩家祖先內同 World3D 的生成器。箭頭及距離逐幀更新；實物與預覽待機，不啟動世界服務。`carry_offset` 調整共用手臂求解中的持物中心，指南針上移以避開操作提示。新局倉庫提供一件，另登錄製作配方；已生成的保存場址不補發。模型來源與軸向見 [資產說明](../../assets/models/electronic_compass/README.md)。

2026-10-28 巨型住宅密度：生成 v18 的 `modular_megashelter`（`Abandoned Megashelter`）增加獨立 300 m 候選帶，每帶最多一棟；最多嘗試三種 footprint、各 64 次位置，無合法位置則略過。一般越野候選維持 55%，原有 2% 大樓抽選及場址保持不變且優先保留；新增大樓完整整地範圍必須避開其他場址、道路及河谷，坡度上限維持 0.65，新增大樓場址地面高差上限為 12 m（原候選仍為 6 m）。四個固定種子共 288 個 150 m 區塊抽樣新增 64 棟，平均每 4.5 區塊一棟；屬平均密度，沒有固定間距保證。新增大樓使用獨立 `megashelter` 身分與 RNG 域，納入相同場址查詢及單一區塊歸屬；道路 RNG 域維持 v15。

2026-10-30 巨型住宅材質：三個合併網格的混凝土、剝落預鑄面板與鏽蝕鋼件改由固定種子的連續三維噪音直接生成，不再讀取或隨機拼接 albedo 圖。所有紋路以整棟局部公尺座標取樣，跨模組與轉角延續；外牆原漆使用獨立種子 RNG 連續產生全色相 RGB 色碼，不從固定色票抽選，色相仍隨機，但彩度與明度回到先前灰舊範圍（牆漆 S 0.10–0.16／V 0.50–0.54），混凝土及鋼件同步收窄明暗；混凝土保留礦物灰、鋼件原漆採同色相深灰，污垢與鏽蝕沿用實際材質色。種子另決定老化程度、剝落尺度與形狀、殘漆比例、鏽色及雨痕長度，連續局部受潮場再產生同棟內的差異。近景補骨材、細孔、稀疏裂紋、剝漆底層與鏽殼／鏽坑，氧化色使用獨立噪音。雨痕沿重力方向且跨牆板共用相位，UV2 的實際牆頂／梁與門楣下緣高度調整滴水強度；鏽水跟隨最多四條實際排水管，入口雙管優先。牆腳與水平面積垢，滴水區有黴斑與淡色礦物沉積，次像素噪音及微凹凸依像素足跡漸隱。保留維修蓋板、露筋、缺失風口、封閉背板、三個材質批次及共用碰撞／bounds 流程。正式濾鏡下檢查 legacy 540p 與 low 50% 渲染；噪音增加逐像素運算，不能視為所有 GPU 上都更快。舊圖保留供參考但不再載入，詳見[材質說明](../../assets/materials/megashelter/README.md)。

`ModularMegashelter.configure_exterior(plan, include_visuals)` 組裝封閉無窗外觀；室內接入改由上方 v19 摘要及室內指南管理，外殼本身不生成物資或敵人。正式生成與鄰帶導航共用 `site.exterior_plan`，並以 `POIConfig.instantiate_site(site, include_visuals)` 組裝可視場景或碰撞／bounds 幾何。Checkpoint v7、VehicleSnapshot v6，不支援舊生成版本遷移。2026-10-27 初版的自動檢查、seed 6 正式場址輪驅及效能結果屬歷史驗收；完整自由遊玩未完成，正式世界遠景受霧遮擋，詳見[初版驗證](../validation/2026-10-27-modular-megashelter.md)。本次密度及材質調整的自動契約位於 `tests/support/megashelter_contracts.gd`，未重新做輪驅或自由遊玩驗收。

2026-10-25 生存狀態：`PlayerSurvival` 屬目前受控身體，保存 `{hunger, starvation_elapsed}`，以玩家物理 delta 推進，沿自身祖先查找 StartRun／POI／staging 狀態並檢查載入 gate；不讀日夜累計時間或任意候選世界。滿值 100／1200 秒，零值每 5 秒獨立扣 1 HP，保留戰鬥無敵時間並沿用死亡入口。Player 在移動前推進，低於 40 時耐力恢復乘 0.5、20 以下禁止衝刺，同一 tick 生效。`PlayerConsumables` 以一次右鍵按壓持有 slot＋Item ID＋scene，完成 2 秒前反覆檢查能力與所有權，移除一份後才補營養；中斷／完成後需放開才可重試。`FoodDefinition extends ItemDefinition` 保存營養與食用時間，`FoodCatalog` 以允許場景查定義，不信任保存資料中的名稱或營養。食物沿用 Item 身分／倉庫／物理／串流快照；新局三份食物獨立於教學維修角色契約。Checkpoint v7 必要 `player.survival`；列印身體 v2 保存並交換同一 survival，未控制不推進，重生／新列印滿值。VehicleSnapshot 仍 v6，無格式遷移。下方 v6 描述涉及既往整合時，以此段及頂部政策為當前保存契約。

**存檔更新政策（2026-10-27）**：更新造成舊存檔不相容時直接重新開局，不維護相容分支、資料遷移或專門適配。當前只接受 Checkpoint v7／VehicleSnapshot v6、生成 v19、OrientationController v4 與 OrientationWorkshop v3；不偵測舊存檔路徑。歷史驗收紀錄保留原日期與範圍。

2026-10-16 倉庫配置：v12 第二室新增可重用靜態貨架、貨箱與棧板，16 件原有 Item 改由分散的出生標記配置；保留舊矮架及碰撞路徑，已保存的物資維持原位置。`WarehouseApproaches` 僅保存設計用接近點，不生成遊戲提示或改變交易判定；貨架燈具屬建築、光源置於 Furnishings。[驗證與驗收](../validation/2026-10-16-orientation-warehouse.md)。

2026-10-16：兩室基地階段四加入獨立靜態建築收邊、舊牆皮、屋架／管線、屋頂機組及兩張實體宣導海報。大型結構網格細分以穩定陰影；滑門移至隔牆外側軌道，避免門片與牆皮交疊，活動碰撞仍不烘焙成永久導航障礙。機組基座、軌梁與碰撞由新版場景持有，不改物品 ID 或教學保存格式。獨立 Demo 與作弊測試場仍可使用單間車庫。結果與驗收見[階段四紀錄](../validation/2026-10-16-orientation-stage4.md)。

目前兩室教學使用 `orientation_shelter`，40 × 60 m 兩室。`OrientationController` 課程 v4、`OrientationWorkshop` v3；Checkpoint 外層 v6、StartRun v1 不變。第一室仍檢查原終端開機及拆下；第二室所有參考均選做，成功交易可任意順序記錄，`step` 只保存單向推進的建議與復原邊界，不授權出口。新局一次性設為原引擎 0 耐久、原電池 0 電量、`roof_1` 毀壞。兩片指定牆板各損失 20–60 耐久，原左前胎有三分之一機率爆胎，否則剩 10–29 耐久。車況以獨立的世界種子亂數配置。以持久 ID 提供充電備用電池、2 包維修包、備胎、8 件廢料及 2 油桶。取消 v12 電量保底。配置後不因讀檔、返回或查看終端重施故障／補發。只接受 OrientationController v4、OrientationWorkshop v3 的完整欄位與目標；不執行課程或入口快照升級。`OrientationRecovery` 在任意順序交易批次結束且安全時捕獲待建立的建議邊界，已有復原點不被後續同段操作覆蓋；接待室仍不將部分開機冒充原始入口。`capture_world(world,false,true)` 只放寬有效終端閱讀的內部捕獲，所有權分開驗證、禁止遞迴、隔離載入成功後替換且不改手動檔案。感應門只依原 RV 的方向、位置及連續向前至少 0.35 秒／淨前移至少 0.5 m 開啟；停車懸吊微動不授權，未完成的移動觀察不保存，與教學證據、車況或服務狀態無關；普通車輛系統仍限制駕駛。玩家及整車碰撞離場後才恢復時間／天氣／敵人，即使清單未完成仍解鎖原終端說明書。Item v2 的 ID、所有權、開機與內部電量保留。[計畫](../plans/starting-tutorial-two-room.md) · [選做指南驗證](../validation/2026-10-15-orientation-optional.md)。

Item 共用契約：可搬運道具與原設備共用 `Item`、`ItemDefinition`、`ItemState` 及 `ItemMount`，以背包紀錄持有手持狀態；短 F 進入獨立預覽，長 F 拆下固定物品。Item 免疫一般怪物攻擊，支撐被拆後掉落並可拾取；2026-10-10 Slender Speaker 僅保留砸擊接觸每拳對同一 Item 扣 60 耐久的專用例外，歸零才摧毀；抓取接觸設備時保留設備及其碰撞。檢查點目前為 v7，舊檔保持原樣且須重新開局。此處描述實作，歷史驗收連結保留當時範圍，不代表本輪全部測試或實機已通過。

教學倉庫的 Scrap A–F 使用六件 `props/scavenge_loot/` Item，G／H 保留原廢料；馬達為大型物品。`OpeningSiteContent.ORIENTATION_SALVAGE` 集中角色對應場景，沿用原 ID 與各件固定三份金屬產量。`SaveSceneCatalog` 登錄新場景；Checkpoint 的教學角色驗證只接受原廢料或該角色指定的新物品，保留當前格式已保存的舊外觀，不補發、不升級保存格式。Wrapper 使用獨立基本碰撞，不以生成網格建立物理形狀。詳見[物資製作與整合](../../art_source/scavenge_loot_references/README.md)。

2026-10-09 整合更新：正式新局選擇生成 v10，沿用 v9 道路種類規則，新增森林 Slender Speaker 的獨立導航與區段紀錄；該輪檢查點支援生成 v14；目前改為 v17。`SlenderSpeaker extends Monster` 覆寫行為，`PlayerGrab.Mode.EXECUTION` 共用抓取所有權並保留 Raker 分支。行為、音樂及實機驗證結果見[本輪紀錄](../validation/2026-10-09-slender-speaker-pr.md)。下方 v9 專節描述該版既有契約，不能用其歷史測試證明 v10 已通過。

## 世界、環境與敵人

### 輪胎與爆胎路障

Chassis 四個輪槽的 wheel_health 為唯一耐久來源，0 表示爆胎；puncture_wheel 拒絕空槽與重複爆胎。TireDynamics 在底盤控制輸出後逐輪套用抓地、轉向及驅動修正；接地壞胎於接觸點施加隨速度平滑變化的阻力，另以接地壞胎的左右差與前後權重計算轉向偏差，不直接設定車身旋轉或清除速度。外觀與半徑只在爆胎／修復切換時更新。既有 WheelSocket、RepairOperation 與 Item condition 支援維修／換胎；VehicleSnapshot 的 health 與物品 condition 已能保存爆胎，無新存檔欄位或版本遷移。

TireSpikeStrip 使用 WorldField.rng_for(band, "tire_spike_strip") 獨立種子流，在 ChunkGenerator 建立道路後生成，不消耗既有物資／敵人 RNG。路障屬 chunk，隨串流釋放與確定性重建；當前規劃器建立道路時產生此障礙。Area3D 只選取附近 Chassis，沒有車時停用 physics_process；附近每台車最多檢查四個接地點的跨幀線段與釘帶局部 AABB。輪寬計入邊界、離地與傳送跨距不觸發，無每幀全世界掃描或額外物理射線。釘帶不是可攀／可拆設備，不進 SaveSceneCatalog。回歸與限制見 [爆胎驗收](../validation/2026-09-22-tire-puncture.md)。

### v10 森林 Slender Speaker

2026-10-11 地面跑動抓取：出手時可見、沒有目標 RV、非攀爬／爬行且水平速度至少 4 m/s 的玩家，使用 2.2 倍伸手動畫、起點周圍 5 m 的有限追蹤及 12 m/s 手部落點修正，最後 0.05 秒以實際時間鎖定。倍率在動作提交時固定，後續減速或姿勢改變不重設動畫時鐘；靜止與車上目標沿用原節奏。視線、真實手部掃掠及抬升碰撞仍為必要條件。平地 5／8 m/s 持續直線移動的自主追擊、接觸及完整抬升曾做專項驗收；當時衝刺案例只補充耐力以維持速度，不代表坡地、急轉彎或障礙場景皆必抓。現行自動覆蓋範圍見第 7 節。

2026-10-10 森林導航補正：巨人接地且已達路徑點水平容差時，以實際腳底高度校正 NavigationAgent 的抵達判定，避免簡化地形網格高於／低於坡面造成原地繞圈。要求前進卻被靜態側面持續阻擋 0.5 秒時，沿真實接觸法向選取附近可導航點，以最高 1.5 m/s 的要求速度、最多 3 秒做連續掃掠脫困，再恢復觀測／記憶目的地；不改感知與遭遇所有權。正式森林徘徊、坡面追玩家及 RV 輪驅追蹤的歷史專項結果見[驗證紀錄](../validation/2026-10-10-slender-speaker-forest-tracking.md)，不屬現行自動覆蓋。

2026-10-10 天氣限制：正式生成只接受所屬世界 `WorldClock.weather.sample().z >= WorldWeather.FOG_LIGHT`（霧級 0.5，小霧以上）。依實際過渡後霧量判斷，不使用目標天氣、常駐遠景霧或畫質設定；晴天、單純下雨與缺少時鐘均不生成。無霧時同樣消耗候選區段，之後起霧、回訪或讀檔不補刷。天氣轉晴不移除已有巨人，存檔中已有巨人仍正常還原；機率、導航、同時一隻及安全距離沿用原規則。

2026-10-09 encounter 更新：`slender_speaker_encounter.gd` 是唯一的持續遭遇與行為意圖 owner。`_refresh_sight()` 只發布觀測值，分開記錄可見玩家、其實際所屬 RV（`player_vehicle`），以及獨立可見 RV；可見車外玩家不能因旁邊另一台車也可見而被歸類成車內乘員。owner 保留同一名玩家／同一台 RV、最後觀測接觸點與 RV 局部座標；車上玩家丟失視線時，只能用重新看見的同一 RV 座標系搬移已記住的點，不能讀取隱藏玩家的即時位置、姿勢或座位。`target_player`／`target_vehicle` 是執行相容介面，遮擋不再等同清空目標；`reset_after_restore()` 才清除 owner、觀測與執行上下文。完整契約與本輪驗證見[持續遭遇與實際輪驅驗證](../validation/2026-10-09-slender-speaker-encounter.md)。

owner 使用正式 `Chassis.road_speed()` 分類車輛模式：追車時低於 6 km/h 持續 0.5 秒進入 `cabin`，車艙模式時高於 10 km/h 持續 0.75 秒回到 `pursuit`；含邊界的中間區間保留原模式，停車規劃器不再自行用接觸點速度切換。可見高速 RV 是持續追車證據，車殼擋住乘員時仍維持 `vehicle_assault`；車外同一玩家失去視線則維持 `ground` 身分，以最後觀測點搜尋，不能轉而攻擊旁邊可見 RV。砸擊、抓取、抬升、握持、壓殺與收手共用已提交的 action context，鎖定原目標與動作種類；新的下車／速度觀測可以緩存，收手完成後才套用模式與目標變更。手部仍只按實際碰撞結算。

車艙搜尋與車外搜尋使用最多 8 秒觀測記憶，搜尋本身不能授權底盤攻擊或隱藏玩家抓取。已認識車內乘員丟失視線時，以最後看見的 RV 局部接觸點作為攻擊區域，不加入移動方向前推。若該點有可見屋頂遮擋，先拆該處屋頂；沒有可見遮頂時，以獨立 `cabin_memory` 動作砸向記住的接觸點，須同一 RV 仍可見、記憶未過期、導航與伸距可達及朝向就緒。此動作可以落空，玩家與障礙只按真實手部第一接觸結算；車輛或屋頂可見本身不能刷新該乘員的 8 秒期限；已提交的 `roof` 動作若實際命中同一片規劃屋頂、造成耐久下降，且所屬 RV 當下仍可見，便從該次進展重新給予 8 秒檢查時間，以支援每擊 60 傷害的連續拆頂。空揮、零傷害、打到別片車板或失去 RV 視線都不延長；不更改最後觀測點，不授權隱藏玩家抓取或底盤攻擊。同一玩家／RV 的較舊緩存目擊不能縮短較新的拆頂進展期限，緩存的下車或不同 RV 身分則沿用該目擊本身的期限。首次只看見 RV、尚未認識乘員時，可見屋頂是直接檢查目標，只要仍有實際屋頂視線便可持續檢查；沒有可見屋頂／乘員／路線時，規劃器回傳 `search`／`unavailable`，不以空結果退回底盤砸擊。已知乘員的車艙搜尋過期後，若同一 RV 當下仍可見，就忘記乘員身分、車內最後觀測點及記憶砸擊授權，重新給予 8 秒未知乘員檢查，按初次看見 RV 的規則選擇剩餘屋頂；可見屋頂持續支持此檢查，重新看見乘員後才恢復抓取。動作提交期間先維持原身分，收手解鎖後才轉換；已觀測下車、不同／不可見 RV 及車外搜尋不套用此轉換。未知乘員檢查沒有可見屋頂或玩家、且期限耗盡後，才回到巡遊，抑制同一靜止 RV 立即重新開局；看到玩家，或該 RV >10 km/h 持續 0.75 秒，才解除抑制。以下日期段落保留既有幾何、動畫與歷史驗收範圍；選敵、模式切換及搜尋授權以本段契約為準。

2026-10-09 自由 playground 補正：屋頂拆除意圖納入接近記憶，即使屋頂暫時遮住乘員，只要車輛及屋頂仍可見，就繼續更新並攻擊可見屋頂，不因乘員丟失而卡在重複轉向。巨人砸擊的實際手部路徑對接觸 Item 每拳扣 60 耐久，同一拳不重複扣血；尚有耐久時仍阻擋手部，歸零後才清除並繼續同一條掃掠路徑；車板仍只結算第一片，玩家仍按原砸擊規則扣血，占用中座椅不做附帶拆除。抓取及抬升開始的完整玩家形狀若只有不超過 5 mm 的靜止接觸，可沿實際接觸法向脫離；查詢增加 1 mm 以穩定微小接觸法向，總修正向量不超過 6 mm，仍通過完整形狀掃掠與終點檢查並同步調整握持偏移。適用地板及側面微小接觸；深層重疊、後續路徑阻擋及停用中的坐姿膠囊不套用容差，不忽略整個底盤。抓取接觸拆除規則保持；完整自由場景重現與回歸見[實機流程修正](../validation/2026-10-09-slender-speaker-live-playground.md)。

2026-10-09 角落與完整抬升補正：停車攻擊的縱向離位門檻由 8 cm 改為 20 cm，容許車身輕微漂移期間完成朝向；已規劃的拆頂站位若與當下可見車殼邊緣或屋頂高度相差超過 20 cm，刷新幾何落點但保留同一片屋頂。抬升先沿接觸位置向上，錨點上升 2.75 m 後在接續 1 m 高度內平滑收回原握持位置，雙手同步修正，整段仍做完整玩家碰撞掃掠。驗證必須完成抬升到 HOLD，不能以單幀取得控制權通過；見[角落與抬升驗證](../validation/2026-10-09-slender-speaker-corner-lift.md)。

2026-10-10 同側抓取與設備阻擋：車艙規劃水平伸距由 3.5 m 調整為 5.5 m，使車內左右移動先調整手部落點而非繞車換邊。出手期間既有視線追蹤與末段鎖定維持；設備接觸不再直接拆除，阻擋手部時收手重試。完整跨艙抓取、設備阻擋及原生畫面見[本輪驗證](../validation/2026-10-10-slender-speaker-cross-cabin.md)。

2026-10-09 未拉手煞車補正（當時水平伸距 3.5 m；本輪改為 5.5 m）：可見乘員已在既有破口下方時，放棄不再覆蓋其位置的舊屋頂目標。停車規劃中的慢滑車輛，若可見乘員已在水平 3.5 m、縱向 1.5 m 抓取範圍且巨人保持至少 1.1 m 車外間距，就先原地轉向，再按實際接觸抓取；短暫丟失視線只保留已觀察的原地轉向，不能憑記憶出手。車外對側玩家的導航另外避開可見 RV 實體。見[拆頂與慢滑驗證](../validation/2026-10-09-slender-speaker-open-roof.md)。

`SlenderSpeaker extends Monster` 保留 WorldEntities／受信任場景與 actor 保存契約，覆寫物理行為、免傷及車撞反應，不執行 Raker 攀車／抓咬。音箱 socket 決定視線方向與音訊位置，物理射線處理遮擋；聲音不參與目標獲取。`SlenderSpeakerSettings` 集中追擊、轉向、攻擊與處刑時序。追車上限為 45 km/h（12.5 m/s），以 2.5 m/s² 漸增速度；實際轉向角速度在 5–45°/s 間平滑降低目標速度，最急轉向比例為 45%，一般減速率 6 m/s²；跟車接近時以 2 m/s² 上限及一秒接近緩衝提早減速，出彎重新漸增。走跑使用共同腳步相位，依實際速度連續混合 9.6／10 m 的步幅及姿勢，避免 8 m/s 切換門檻的步頻驟降。`slender_speaker_vehicle_follow.gd` 依實際底盤形狀規劃車尾外約 4 m 的跟隨點，以 RV 接觸點速度及距離誤差控速；RV 突然停止時，額外依車殼邊界限制向內的相對速度，必要時緊急煞車；攻擊和收手持續導航，腿部沿走跑相位播放，上身保留砸擊動作；抬手蓄力前 1.3 秒保留走跑的完整骨盆與腿部姿勢，最後 0.5 秒才混入砸擊下揮姿勢；移動收手直接混回當下走跑姿勢，避免先回到直立待機。最後 0.5 秒按車速預測並固定世界落點；實際手部先碰到車板後短暫貼住該表面，1.8 秒時仍只結算第一片接觸車板。移動使用 CharacterBody 掃掠，手部沿實際骨架接觸路徑掃掠；砸擊依第一個實際接觸結算：`RVStructurePanel` 車牆與屋頂均使用 `take_damage(smash_wall_damage)`，每擊扣 60 耐久，歸零後拆除，設備依原支撐系統掉落；局部破口露出的目標 `Chassis` 使用 `take_damage(smash_chassis_damage)`，首版每拳扣 60 引擎耐久，不要求全部車板破壞。完整車板及障礙仍阻擋手部路徑，同一拳不穿透或重複扣傷。低底盤砸擊允許最多 2.5 m 的骨盆下蹲修正，抓取維持原本 1.1 m 上限。

`slender_speaker_foot_contact.gd` 在正式物理步完成骨架姿勢與世界移動後，沿左右腳跟、腳掌及五個腳趾的接觸體積掃掠。實際踢到／踩到任何同世界存活玩家時，透過既有 `Player.take_damage(foot_player_damage)` 扣 40 HP，共用 0.5 秒受傷無敵及死亡流程。每隻腳對同一玩家只在新的接觸開始時結算，持續重疊不重扣，分開後再接觸才重新判定。車殼、設備及地形保持第一接觸遮擋；坐姿使用既有姿勢代理，沒有座椅穿透例外。腳部不傷設備，不以巨人的整個身體碰撞體或目標距離扣血。還原與大距離傳送清除舊路徑，缺少正式骨架時不建立替代傷害範圍。

一檔／停車修正：可見的靜止 RV 也參與首次感知，仍檢查音箱視角、距離及遮擋；過期後是否重新建立遭遇由上述 owner 抑制規則決定。追車的底盤攻擊須進入 4.3 m 表面距離，跟車目標仍在底盤外 4 m；導航到達容差為 0.1 m，低速時改用巨人所在側的外側接近位置，目標附近 0.15 m 內停止微調並面向車輛。急煞後需要拉開距離時，沿導航路徑面向車輛倒退，走跑相位依實際前後移動方向推進。下揮及收手按手臂實際長度與水平伸距求所需下蹲，仍以 2.5 m 上限及實際碰撞結算，避免低速時 IK 拒絕不可達解而反覆砸空。

`slender_speaker_parked_attack.gd` 接收 owner 已選定的 RV 與當下可見乘員，只負責車艙幾何與 `approach`／`ready`／`search`／`unavailable` 計畫。先拆可見車內玩家上方的一片可見屋頂；初次尚未看見乘員時，從距巨人最近且可見、可達的真實屋頂表面開始檢查，保留選定車板直到移除，接著從剩餘屋頂重新選最近的一片，不以隱藏玩家位置導航。屋頂上的玩家直接抓取，不拆其腳下屋頂。拆開後從車側接近可見乘員，現行抓取站位距實際車殼 1.24 m，站位進入／離開範圍為 12／24 cm，本體碰撞半徑仍為 1.1 m；導航、手部與完整玩家路徑仍須實際通過。沒有遮頂且失去已見乘員時，可在期限內砸向最後看見的車內位置；沒有乘員位置記憶的未知檢查則等待並按期限結束，不能退回車殼／局部底盤攻擊。砸擊玩家使用 `take_damage(smash_player_damage)`，首版 40 HP；坐姿胸／頭／肩代理與真實障礙依掃掠先後比較，砸擊沒有座椅碰撞例外，同一拳不穿透車板或重複傷害。

完整屋頂接近時，已到同側且不用繞行、距車殼 2.55–3.05 m、距落點水平不超過 3.5 m、縱向偏差不超過 1 m，即可完成原地轉向，不再追逐慢滑 RV 的 4 cm 站位誤差。已進入的同一屋頂轉向在側向 2.45–3.15 m 內保留，避免懸吊晃動在進入邊界反覆切換走路與轉身；水平伸距、縱向偏差及繞行限制仍須每次通過，新站位／新屋頂、恢復重規劃及還原清除該狀態。仍須導航就緒、朝向誤差不超過 2°，才提交獨立 `roof` 動作；真實手部掃掠決定命中，不授權底盤傷害。原地轉向記憶只能引導面向，不能自行出手。初次修正見[完整屋頂接近紀錄](../validation/2026-10-10-slender-speaker-roof-approach.md)，邊界晃動與車內移動測試修正見[後續驗證](../validation/2026-10-10-slender-speaker-cabin-corner-fix.md)。

2026-10-10 中後艙連續遭遇補正：有開孔的屋頂以整片車板授權，再從同一片的實體碰撞區塊選取原側可達落點，不能把開孔另一側當成唯一落點。落點投影回真實碰撞盒，懸吊傾斜時刷新表面而保留既有站位；縱向基準取固定站位，避免重複投影累積偏移。玩家短暫穿過開孔視線時，僅保存最後實際看見的接觸點；失去視線後使用該 RV 局部位置搜尋及砸擊，不再採用 0.5 秒／3 m 的移動前推。位置記憶不授權抓取，也不刷新 8 秒期限；重新看見玩家才恢復抓取。此次追蹤與最近屋頂規則見[本輪驗證](../validation/2026-10-10-slender-speaker-last-seen-attack.md)。Slender Speaker 抬升時如被同一 RV 的傾斜側板卡住，可沿實際接觸法向累計讓位最多 5 cm，每一步水平路徑、終點及向上路徑均須完整玩家形狀檢查通過。此例外不適用設備、屋頂或 Raker，不排除任何新的碰撞體。見[中後艙完整遭遇驗證](../validation/2026-10-10-slender-speaker-hatch-and-rear.md)。

`PlayerGrab.Mode.EXECUTION` 和 Raker 共用唯一所有權。僅在 `GRAB` 狀態沿左右手掌、手指的實際路徑掃掠，任一手碰到玩家即可當幀取得所有權。手掌中心由手腕與四指根部求得，以 0.24 m 半徑沿實際位移掃掠，依序直接拆除碰到的 `RVStructurePanel`，同一次伸手繼續；接觸 `Item` 時保留設備及其生命／碰撞，阻擋該手的伸入，不切換砸擊或收手；只拆接觸路徑上的物件，不拆玩家後方物件。車板沿用 `take_damage(current_health)`、支撐掉落與槽位保存，Item 只有砸擊接觸才經專用 `damage_from_giant_smash(smash_equipment_damage)` 每拳扣 60 耐久；受傷未歸零時保留碰撞與服務，歸零才清除碰撞、停止服務並走原移除流程，不修改一般怪物傷害規則。手指只判定玩家接觸，不拆物件或因擦碰停住整手；接觸點與手掌間仍須沒有完整障礙，避免隔牆取得玩家。地形／底盤碰撞不會被當作車板刪除；這類手掌阻擋仍保留安全起點與姿勢，手腕以每秒 18 m／600° 上限移動。待機接觸不抓人，砸擊接觸走原扣血流程。成功接觸才釋放座位／攀爬／車上支撐並啟動處刑曲；以接觸姿勢在 0.22 秒內混入抬升，抬升錨點不低於接觸時高度；完整玩家形狀仍檢查起點和移動路徑，受阻取消。玩家背包狀態保留；合攏完成一次處理尚存部位，接續既有死亡、屍體和復活。抓取及處刑拒絕 checkpoint；取消、移除或世界切換釋放抓取、相機與音樂。巡遊曲顯式循環，處刑曲不循環，尾音完成才恢復巡遊。本輪見[手掌拆障礙抓取](../validation/2026-10-09-slender-speaker-palm-demolition.md)；[前次抓取可靠性紀錄](../validation/2026-10-09-slender-speaker-grab-reliability.md)保留當時阻擋規則。

車外與駕駛座共用髖部前傾、雙掌朝內向下的 `grab`／`lift`，只按目標位置與高度修正；高處目標在前 0.25 秒建立正向高度修正，水平修正在前 0.8 秒建立。沒有駕駛專用轉掌、屋頂繞行、手指提前定格或起身混合。抓取掃掠及玩家抬升只忽略當下所乘的 `DriverSeat` 組件，仍由正式坐姿胸／頭／肩接觸、車殼／玻璃阻擋及完整玩家抬升路徑判定。座位例外於取消、移除或換世界清除，不影響一般碰撞和 Raker。每次取樣重設未被動畫覆寫的骨架位置，避免殘留變形；手臂 IK 隨伸手軸轉移原本彎肘平面。抬升初段保留接觸偏移，接著將軀幹帶回握持錨點。作者動畫的抬高手臂以實際 A-pose 手肘彎曲平面決定上臂旋轉，肘部引導持續朝前並降低，避免手掌旋轉傳回肩部造成半圈翻轉；lift／hold／crush／retract 共用此姿勢，驗證見[肩肘修正](../validation/2026-10-09-slender-speaker-lift-joints.md)。Slender Speaker 接觸取得所有權及抬升途中保持第一人稱，到達音箱前、進入 HOLD 時才切換獨立第三人稱相機，以實際玩家胸部為追蹤支點，預設沿遠離實際音箱的水平方向 2.2 m、側向 1.2 m、上方 1 m 取景，視線對準實際音箱，不依玩家身體朝向；相機包含完整身體圖層、排除第一人稱專用複本。第三人稱滑鼠可完整水平及垂直環繞構圖，沒有左右／上下角度範圍限制，完整轉圈以等價角度保存並讓相機上方向一起旋轉；沿用靈敏度及反轉 Y 設定；0.18 m 球形掃掠限制鏡頭與牆壁／車殼的距離，環繞觀看不改變玩家身體；抬升途中的第一人稱沿用慢速引導，切換時重設環繞偏移。取消、移除及換世界清除臨時相機、交回正常視角；處決死亡則保留目前第三人稱構圖，脫離巨人的追焦並直接跟隨布娃娃 spine_02 物理骨的世界位置（扣除 body_offset），隨身體落到地面，成功復活才清除並恢復正常视角；若其他相機已取得視角則保留其所有權。抬升 1.4 秒完成後 HOLD 停留 2 秒，再以 0.4 秒 CRUSH 完成處刑。一般 execution captor 未提供第三人稱構圖時沿用既有第一人稱引導；Raker 保留原流程。第三人稱驗證見[抓取視角紀錄](../validation/2026-10-10-slender-speaker-pov.md)。共用動畫原始證據見[共用抓取驗證](../validation/2026-10-09-slender-speaker-shared-grab.md)，後續停車決策與任一手接觸更新見[停車抓取驗證](../validation/2026-10-09-slender-speaker-parked-attack.md)。

`SlenderSpeakerSpawns` 使用獨立種子流，v10 在前 1500 m 以外按 1500 m 區段以 25% 機率規劃候選；候選必須位於道路邊緣外 40–100 m 的合法森林。巨人使用獨立 NavigationServer map，區塊以 15 m 高、1.1 m 半徑、0.275 m voxel 同步烘焙、發布與卸載。導航完成後才評估生成，距玩家不足 160 m、無合法候選或同世界已有活動巨人便永久略過該段。Checkpoint v6 要求 `generated_giant_segments`，防止重烘焙、回程、死亡與清理後補刷。恢復 actor 後重新綁定新 map 並清除舊感知。測試與限制見 [整合紀錄](../validation/2026-10-09-slender-speaker-pr.md)。

首次建立遭遇時可見玩家優先於可見 RV；同一名玩家仍有效且搜尋尚未過期時，其他玩家或另一台可見 RV 不能取代遭遇。胸、頭、肩任一真實姿勢點通過音箱視角與物理遮擋即可感知。離座／下車會在可見觀測後改變所屬 RV，已提交動作保留原對象直到收手完成，再清除不相容的接近計畫。車內乘員超出原側抓取範圍時，僅根據實際可見位置選擇可達的另一側，繞車路程計入外側轉角間的遮擋；不使用隱藏玩家的即時位置。案例與物理阻擋限制見[站立／下車驗證](../validation/2026-10-09-slender-speaker-target-switch.md)。

停車繞行使用身體朝行進方向的前進步態，到站後才轉向攻擊區域；不以朝向乘員的橫移代替走路。短暫離開音箱視野時，最多保留 8 秒最後看到的車殼幾何、外側路線、站位、朝向點和防撞間距快照，不更新隱藏玩家／RV 的即時位置；RV 也不可見時不能憑接近快照出手，僅同一 RV 仍可見且 owner 有未過期的車內接觸點時，可提交最後看見位置的砸擊。重新看到同一台 RV 保留規劃進度，換目標則清除。抓取站位距車殼 1.24 m，進入／離開站位範圍為 12／24 cm，其中沿車長方向維持 4／20 cm 進入／離位門檻以免手部碰到窄門框；身體朝向固定攻擊區域，誤差不超過 2° 才出手。可見玩家在區域內移動由頭和手部瞄準跟隨，持續超出 0.75 m 縱向範圍或 5.5 m 水平伸距達 0.5 秒才重選站位；車內左右橫移優先從原側調整手部落點，仍由實際骨長、手部接觸及抬升碰撞決定是否成功；繞角期間不反覆換側，選定屋頂在乘員不可見時保留；重新看見乘員位於其他破口後釋放無關屋頂，且不拆可見屋頂玩家腳下支撐。伸手前段只根據實際視線更新，最多追蹤初始接觸點周圍 0.75 m、修正速度 2 m/s，最後 0.25 秒固定落點。沒有平移或轉向進展達 1.5 秒時，以實際導航和碰撞向外走約 0.9 m 後重新規劃；恢復期間保留目標身分，短暫丟失／重獲同一目標不取消恢復。歷史步態結果見[前進繞車修正](../validation/2026-10-09-slender-speaker-forward-approach.md)，本輪見[車內持續移動修正](../validation/2026-10-09-slender-speaker-cabin-movement.md)。

轉角不再要求先對齊 37° 以內才前進，而是以低速前進弧線、剩餘轉彎半徑和煞停距離控速；低速實際轉向使用既有 `turn_left`／`turn_right`，避免原地旋轉時仍播待機。`slender_speaker_look.gd` 在原動畫／IK 後調整真實頸骨，三組音箱共同追視最後觀測點：左右 75°、上下 20°、水平速度上限 120°/s。身體沿導航前進，視野及音訊繼續使用實際 socket；抓取／處刑時追視層淡出至原動作。音箱射線起點位於實體內時也判定遮擋，避免轉頭伸入牆體後穿牆感知。驗證見[轉身與轉頭修正](../validation/2026-10-09-slender-speaker-head-look.md)。

2026-10-10 遊蕩與轉彎補正：PATROL 依已觀測車殼繞過未烘焙進地形導航的 RV，轉角離開視野時保留最後觀測的碰撞幾何；重新看見車輛才更新位置，離開 PATROL 或還原時清除。被車身占用的巡邏點會跳過，不重新取得已過期的空車遭遇。水平移動以行進軸轉向，速度單獨按加減速率調整，避免朝向改變後速度向量仍保留大量側向分量；倒退前先煞到零，再按正常加速度起步，車殼防撞限制最後套用。回歸涵蓋兩種 RV 朝向、連續巡邏點與 30／60／120 Hz 左右轉彎及倒退煞車。

### v10 偏行壓迫與後方車群

`RoutePressureSample` 以有符號道路投影取進度，保留出生點後方負值；只在正常路線或據點實際占地／出入口／步道 12 m 範圍推進 highwater。探索通道使用所屬據點的道路入口進度，整片森林場址 AABB 不提供豁免。`RoutePressureState` 是獨立可保存的真實秒數狀態機：120／100 m 偏行門檻、3 秒確認、30 秒一隻巨人；80／70 m 恢復遲滯、3 秒離場、12 秒退霧和 60 秒刷新冷卻。巨人生成失敗每 2 秒重試，退霧重入保持濃度連續。舊存檔的 Raker 波次欄位仍可讀取，載入時會捨棄待生成名額。

`DeviationPressure` 隨主世界暫停／staging 停止；整備、死亡與抓取期間不計時。副本及轉場期間釋放戶外霧，返回重新取樣。`WorldClock.effective_visual_weather` 只改顯示用晴天／霧，取自然霧與偏行霧的較濃值；自然 RNG、雨量、原巨人天氣判定和保存不變。新串流霧材質立即同步，低畫質仍有距離霧。

`PressureSpawns` 每名額最多 24 候選，使用已發布且連通的巨人導航、實體地面、完整膠囊碰撞、據點／步道避讓及正常 AI 感知。巨人距玩家 120–160 m，可出現在負區段與深林。合併整個視覺外形判定相機視錐或完整遠霧遮蔽，面向玩家但不強制目標。每次插入重驗與自然刷新共用的巨人名額。怪物仍屬 `WorldEntities`，沿用原戰鬥、掉落、actor snapshot 及清理；退霧不釋放怪物。

`RearWreckLayout` 在 rear band 導航烘焙前建立最多 28 台既有廢車，以獨立路徑／逐台 RNG 在 X±24、Z10–110 m 隨機位置及朝向，檢查完整旋轉占地、植被、據點、支撐與保存 actor 避讓；保留連續 1.5 m 步行通道。v10 移除車堆、碎石 backing、長翼牆與橫向土堤，避難所本體地形不變；保留原植被 reservation mask，避免改變毀樹 band:index。v7–v9 仍建立原 roadblock 與土堤。

Checkpoint v6 要求 `route_pressure`（timing、RNG）和 `rear_wreck_layout`（穩定 ID、實際 transform、步行通道），先驗證再還原。尚未生成後方配置時允許空 layout，還原後依玩家／RV／道具實際碰撞占地建立配置；這是當前新局狀態，不是舊檔缺欄位適配。配置 ledger 跨卸載保留，回訪及重載不重抽。歷史規劃與驗證見[偏行刷新紀錄](../validation/2026-10-11-deviation-pressure.md)。

### 公路獨立生成

正式 main_world 與 WorldProfile 使用生成 v19；道路內容使用目前獨立規劃器。Checkpoint v7 只接受 shelter 主世界，不再提供舊版本道路規劃或 legacy 存檔身分。

RoadSpawns.plan(field, band) 使用當前純規劃器，分離釘帶、油桶人、普通油桶及廢車的數量／位置 RNG。油桶人 8% 一隻、普通油桶 20% 一個，各自獨立在中央路面選點。廢車 0–4 台機率為 60／25／10／4／1%，逐台獨立選位置及 0–TAU yaw，沒有固定陣形或中央通道保證。前 450 m、安全據點、5 m 接縫距離及實體重疊避讓維持，候選失敗可少於抽取數量。釘帶與廢車屬 chunk，加入導航烘焙；普通油桶為 WorldEntities 動態 Item。

導航 map／region 同步完成後建立道路怪物，加入 WorldEntities 並尊重 skip_actors。generated_bands 防止回訪、死亡、遠距清理及重載補怪；導航尚未發布時拒絕保存，以免漏掉即將生成的怪物。清理按怪物目前位置與戶外串流錨點前後 450 m 判斷，不以出生 chunk 決定；loaded WALK_IN 保護與其他散落物清理維持。正式 profile 設 chunks_ahead=2，與目前帶共覆蓋至多 450 m，避免前方道路怪物立即被遠距清理；自訂更遠載入窗仍按 450 m 規則清理。普通油桶沿用 Item／WorldActorSnapshot 保存及 generated_bands 防補發；重烘焙、拾取、爆炸、清理或重載皆不重新抽取。實作、測試與未驗證範圍見 [v9 本輪紀錄](../validation/2026-10-07-independent-road-spawns.md)，[v8 初版紀錄](../validation/2026-10-01-random-road-spawns.md)保留當時結果。

### 油桶人與接觸自爆

`props/oil_barrel.gd` 的 `OilBarrel extends Item` 保留普通油桶的拾取、放置及 v6 檢查點保存契約，車撞需接觸點法線相對接近速度至少 6 m/s。G 保留 3 m/s 拋出速度，疊加玩家相對移動及放手位置的 RV 點速度（含角速度）；離車後只另加已保存的水平載體速度，垂直分量已在玩家 velocity。剛離開駕駛座、尚未進入下一次正常移動時，velocity 仍含完整載體速度，油桶直接使用該值以免重複疊加。釋放前以完整桶碰撞形狀、從玩家一側的無重疊起點向持物位置掃掠，必要時縮短到障礙前方，空間不足則保留背包並提示。動態桶在 `_integrate_forces` 讀取真實接觸法線／接觸點，保留解算前一物理步的線／角速度以免 Jolt 解算後漏判；固定桶以自身碰撞形狀查詢補足移動中的 frozen 車板；Chassis 的物理接觸迴圈也直接通知油桶。可引爆來源為同 World3D 的 RV 車身／輪槽或已固定的 RV Item 設備；Area、角色、散落 Item、預覽、放置／回收處理中及跨世界接觸均排除，同車固定貨物忽略自車。合格撞擊或自空中最高位置下降至少 2 公尺後碰到向上支撐面時同步鎖定 `is_destroyed`，延後以桶身中心呼叫共用 `BarrelExplosion`，再移除 Item；掉落爆炸不授權任意 RV 接觸傷害，沿用真實距離及遮蔽。`ItemState.service.fall_height` 可選保存已下降距離，無下降距離時省略，拾取／放置／世界轉移時重設；WorldActorSnapshot 排除已毀損 Item，封住延後結算前的保存空窗。Chassis 使用既有讓路修正保留行駛，只收共用爆炸傷害，不再收同次一般 body/monster 撞擊傷害。

`BarrelMan` 繼承 Monster 的導航、群組及 WorldEntities 生命週期，獨立處理偽裝、起身、追逐、收腿與自爆，不呼叫一般抓咬、攀車或近戰。玩家優先，入座改追該車外表面；速度 6 m/s，追車上限 10 m/s。低頂下不強行伸展。桶身中心 3 m 球形查詢找到玩家／車體真實碰撞表面且通過 LOS 後，啟動 2 秒倒數；倒數不因目標離開而取消，追逐仍持續。每幀先處理真接觸，再推進倒數；實際玩家／車體接觸和致命傷立即鎖定死亡，延後安全結算爆炸。`receive_vehicle_body_contact` 明確區別真實物理接觸與前方探針。近距離判定排除 Area、Item 及其子碰撞，使用同 World3D 的啟用碰撞表面，車尾與車板不依底盤中心距離判斷。Chassis 與怪物自己的 shape 重疊／滑動接觸共同覆蓋車體、車板與輪槽。車輛讓路保留速度修正，自爆來源的 pending impact 以獨立標記保留至結算，即使來源已釋放仍不重扣一般撞怪傷害。

`BarrelExplosion.explode` 先收集同 World3D 全部受害者、真實碰撞形狀表面距離及 LOS，再依玩家、車板、引擎各自去重結算。完整車殼當次仍遮蔽乘員，已存在破口能曝露玩家；Item 完全免傷，也不能藉父節點轉交引擎傷害，但車板毀損仍觸發既有支撐掉落。爆炸半徑 4 m；玩家 1.5 m 內 70 HP／一肢，0.8 m 內最多兩肢；車板 2 m 內 120 HP，引擎 60 HP，外圈線性衰減。實際接觸 RV 直接授權引擎傷害，避免車尾漏傷。`Player.apply_explosion_hit` 共享一次傷害冷卻，從尚存四肢無重複抽取、先斷肢再死亡，斷肢共用切斷前速度及爆風。特效無拾取或保存身份，沒有持續燃燒或怪物連鎖爆炸。

既有 v8 道路、v8／v9 貨物／棚屋小據點、新訪地堡以獨立種類 RNG 分別替換 10%、15%、20% 原敵人名額；數量、選點與既有物資 RNG 不變。貨物／棚屋各有一個普通 Item 油桶對照，首訪建立，後續按原 actor 保存。道路根原點去除原怪物出生的 0.5 m 抬高，小據點取實際地面。SaveSceneCatalog 允許 `barrel_man.tscn` 的 monster 身份；WorldActorSnapshot 保存 `barrel` 狀態，保存階段與過渡進度、讀檔重新找同世界目標；倒數狀態以 `proximity_fuse_remaining` 保存，缺欄位拒絕載入，死亡來源不保存。檢查點使用 v6、生成 v14，還原已保存活怪與清空區域。`BarrelManSettings` 集中追逐、倒數範圍／時間、爆炸與生成比例設定。

`barrel_explosion_effect.gd` 負責獨立 8 秒特效生命週期：短閃光與單盞有陰影點光、Blender 預烘焙火煙、貼地揚塵、少量火星及八片彎曲桶身金屬。共用兩張火煙圖集，每次爆炸有獨立材質時間；火煙 shader 在 BoxMesh 邊界內沿視線積分 12 個密度樣本，以不透明場景深度截斷，避免駕駛鏡頭穿過中央平面時特效消失。火焰快速膨脹上升，煙霧缓升至消散；沒有即時流體求解。碎片以掃掠射線反彈／停落，落地聲最多三個同時播放、每次爆炸最多五次；音效預先烘焙。加入 WorldEntities 前先設定爆點局部座標，使 world-space 粒子與地面查詢從正確位置開始；揚塵只在 2.5 m 內找到向上的實體支撐時建立，略過角色／斷肢／散落物及其他 entity domain。所有視覺節點不含碰撞、傷害或保存身份，結束後一起釋放。資產及驗證見 [火煙與碎片](../validation/2026-10-08-barrel-blast-realism.md)、[駕駛 POV 修正](../validation/2026-10-08-barrel-driver-explosion.md)。

行為、爆炸、保存與真 RV 接觸自動檢查及目前尚未完成的模型／畫面驗收見 [油桶人紀錄](../validation/2026-10-07-barrel-man.md)。

### 樹木撞毀

SlenderSpeaker 由 `move_and_slide()` 的實際身體接觸撞毀樹木，使用掃掠前的水平速度及命中 shape index。朝接觸法線內至少 0.1 m/s 的走路／追擊接觸即可觸發；靜止、離開樹幹及垂直落地不觸發。共用 ForestTrunks／路邊樹的破壞、倒塌、導航更新及 destroyed_trees 帳本；已毀樹等待延後停用時不觸發牆面脫困，其他實體仍保留碰撞與脫困。歷史專項結果見 [撞樹驗收](../validation/2026-10-11-slender-speaker-tree-impact.md)。

Chassis 讀取實際物理接觸，以至少 3 m/s 的水平速度、朝接觸法線內至少 0.1 m/s 的接近速度判定撞樹，高速斜擦也能折斷；離開樹幹、低速及垂直落地不觸發。TreeImpact 只處理破壞，Chassis 在補速後按每棵樹真正造成的速度損失結算一次傷害，沿用下方 VehicleImpact 契約及 take_damage 扣引擎耐久。引擎歸零沿用現有停機／維修流程。

底盤快取前一物理步的線／角速度，避免 Jolt 已解算的硬碰撞讓撞擊速度歸零。先處理全部樹木撞擊，再依最後的破壞狀態判定實體阻擋，避免同 shape 的早期擦碰法線留下錯誤阻擋。只補回沿原水平行進方向損失的速度，每棵新毀樹保留 85%；同棵樹的多個接觸只計一次。接觸上限至少 128；已毀 shape 的延後停用期間不重扣傷害，有反向實體阻擋法線或接觸報告達上限時不補速，垂直與角速度仍由物理解算。

ForestTrunks 保留一個共用靜態碰撞體，shape owner 識別單棵樹，延後停用其碰撞並隱藏對應 MultiMesh instance。TreeFall 在 0.75 m 斷裂面留下斷樁，依材質分離木質與葉面，完整木質網格按世界高度切成最長 3.2 m 的 RigidBody3D 斷木，每段 2–4 kg；圓柱碰撞跟隨網格，layer／mask 1、CCD、摩擦 0.08，不排除 RV。斷木起始外觀承接原樹，依車身位置向外側散開並由物理解算傾倒，不留 HingeJoint 或樹冠碰撞。葉面依高度／方位分成實際網格小簇，保留貼圖與頂點色，重力／旋轉落到取樣地面後壓成薄層；預估落點先取樣，接觸時再確認地形，不逐葉逐幀射線。地面射線排除動態物件／角色。原樹接觸尚未清除時，輕量斷木不作為硬牆補速 veto；只剩斷木接觸後不再補速。斷木的真實地面接觸觸發塵土。木材與葉片獨立清理：木材含斷樁在 20–22 秒淡出後移除全部碰撞體，也可存在至少 8 秒、連續離開視野 2 秒後提前回收；葉簇保持不透明，存在至少 6 秒且全部落地後，連續離開視野 2 秒才釋放。逐組網格世界 AABB 檢查目前 Camera3D 六個 frustum 平面，回望各自重設计時，缺相機只阻止視野清理，木材定時回收仍有效；兩組均釋放後移除效果父節點。碎片隨 chunk 卸載釋放，不進 actor 或存檔。舊版路邊活樹／枯樹使用相同撞擊契約。

ForestScenery.build 首次建立森林前 await TreeFall.prepare：獨立 32×32 SubViewport 先建立一棵實際落葉／斷木／粉塵效果，停止處理、凍結剛體並停用碰撞，渲染兩幀後釋放，不播放音效、不寫破壞帳本或觸發導航。共用 Shader、頂點格式及陰影 pipeline 在載入期準備，blocked PCM 音效也預先合成；一次旗標避免串流重複準備。不可變原 mesh 的 surface arrays 快取最多 32 資源；切木只計算世界高度並在原局部座標裁切，葉面共用變換／法線矩陣，減少首次與每次撞擊的網格計算。

WorldGenerator／WorldField 共用 destroyed_trees 帳本，獨立於可淘汰的 forest_cache；森林 ID 使用 band／確定性生成索引，路邊樹使用原始位置。重建前仍消耗原外觀 RNG，存活樹位置與型號不漂移。Checkpoint v6 要求完整帳本，先驗證再恢復。

木質小樹叢用獨立的 ForestShrubs 複合碰撞體，由 Chassis 接觸觸發同一撞擊判定。被撞毀的實例以 band／候選位置索引記入 destroyed_trees，TreeFall 散開枝葉並揚起塵土。步行與導航沿用原本的通行範圍。

樹木破壞後以 0.35 秒合併導航重烘焙，沿用原 NavigationRegion 並序列化更新；接縫附近的已載入鄰帶一起更新，鄰帶 halo 也排除已毀樹。歷史專項結果見 [撞樹驗收](../validation/2026-10-02-tree-impact.md)，可見輪驅入口見 [測試場指南](playgrounds.md#tree-impact)。

### 車輛碰撞傷害

VehicleImpact 集中定義損失速度平方 × 0.75、單次上限 120 HP。樹木／怪物門檻 0.1 m/s，一般實體 0.75 m/s，地面累積損失 1 m/s。Chassis 先處理樹木及怪物讓路，再量測接觸點法線速度損失，避免把已補回的硬碰撞解算誤算為傷害。每棵新毀樹保留 85% 水平速度，怪物每次有效撞擊保留 95%；同時存在反向硬物阻擋或接觸報告截斷時不補速。Monster 在首次接受撞擊時通知底盤（包括致命撞擊），沿用既有怪物傷害、擊退與冷卻，重複 Area／剛體／探針通知不重結算；攀爬／車頂支撐接觸不算撞擊。

一般實體依 collider ID 保存事件，地面共用一個事件，0.15 秒內累積損失並只支付新增差額；持續抵住硬物刷新接觸時間，離開至少 0.25 秒才重建事件。地面事件只由有效衝擊刷新，不因平穩持續接地而阻止下一次落地；累積損失上限為事件中最大向內平移速度，一般實體上限為接觸點向內速度，排除回彈超額計費。不同障礙的事件互不冷卻。vehicle_impact 訊號回報種類、事件累積損失及本次新增扣血。

VehicleBody3D 在 _integrate_forces 之後才套用輪胎懸吊衝量：底盤先保存接觸解算後的線／角速度，再於 _physics_process 讀取 direct state 和 VehicleWheel3D 接觸點／法線，量測同一步的懸吊速度變化。接地法線 y > 0.5 視為地面，接近速度至少 1.5 m/s、單步衝擊至少 0.15 m/s，扣除重力常態支撐；近乎水平的地面另外要求向下平移，避免加速／煞車俯仰誤傷。出生／解除凍結／大距離傳送後 0.75 秒不計費。煞車及轉向的地面切向減速不計傷害；排除底盤自身及已連接設備的接觸。此傷害保存於既有引擎狀態，沒有增加存檔欄位。驗收見 [車輛碰撞](../validation/2026-10-02-vehicle-impact.md)。

### 世界時間與太陽

正式場景持有 WorldClock，集中維護累積遊戲秒數與一天的現實分鐘數，預設 day 1 / 08:00 / 30 分鐘。每幀依 delta 前進，跨日由累積秒數推導；minute_changed 提供日期、時、分，HUD 每遊戲分鐘更新。PROCESS_MODE_INHERIT 尊重 SceneTree 暫停及候選世界停用，背包／平板與 POI 不暫停世界。

教學整備的 `running=false` 只凍結模擬；WorldClock 仍以真實 delta 更新視覺與載入霧上限，避免開局未完成地景造成的 1 m 霧永久遮住房間。SceneTree 真正暫停及停用的讀檔候選世界仍透過 INHERIT 一起停止視覺處理。主場景 smoke 使用正常 process frames 驗證整備期間視野恢復，且時間與天氣保存狀態不前進。[修正驗證](../validation/2026-10-21-tutorial-fog.md)。

WorldClock 獨佔正式室外 Environment 與 DirectionalLight3D 的光照設定，取代 WorldGenerator 的固定光照。太陽在 +X 升起、-X 落下，06:00／18:00 越過地平線，最高仰角約 58°；光源 basis 與天空 sun_direction 共用同一向量，地平線下光源能量歸零。天空與環境填光按太陽高度平滑插值；陰天距離霧為 24–230 m，晴天 64–230 m，天氣與載入保護可進一步收近，所有畫質共用。使用自訂陰天天空、低解析 radiance cache、關閉天空反射來源；Forward+ 體積霧見下方「局部體積霧」小節，天氣由 WorldWeather 取樣後合成。

灰階暗部由同世界的 `DarkAdaptation`（NightVisionEffect）持有。WorldClock 寫入自然照明及霧，深夜原生環境底光為零，預設天空和霧共用黑色終端。NightVisionEffect 依每個像素的線性亮度與材質參考求出缺光量，距離曲線控制補光強度。原生照明充足、曲線值為零或像素屬於天空時保留原始畫面。室外沿用 [DarkAdaptationProfile](../../world/dark_adaptation_profile.tres) 與 [距離曲線](../../world/night_vision_curve.tres)。距離區間預設 0～60 m，參考能量 0.06。室內 PoiInterior 使用獨立 World3D 與 [室內 profile](../../world/instances/interior_dark_adaptation.tres)，環境底光為零、參考能量 0.06、曲線在 3 m 起歸零。曲線編輯透過 `Curve.changed` 直接更新顯示。

每個活動視圖以同 World3D、同姿勢與投影渲染中性底光參考。參考讀取來源相機的 Environment，缺省時讀取所屬世界的 Environment 或 fallback。黑色背景與距離霧保留霧的遮蔽，體積霧參考關閉環境光與 GI 注入。主圖沿用原生燈光、陰影、霧散射和材質發光，玻璃與天氣接續透明繪製。Forward+ 參考同步原視圖的 SSAO，Compatibility 由主視圖在合成後套用 SSAO。正式室內外維持固定曝光與線性色調映射。

啟用效果後，白天及夜間的活動視圖均增加一次同 3D 縮放比例的參考渲染，兩側鏡面只在既定刷新時同步參考。相機 bit 13～16 為視圖路由，bit 18 為實體燈光與天氣隔離。暫停保留上次參考，停用效果還原相機及燈光圖層。候選世界轉移後重新綁定目標 viewport 和 World3D。SDR 顯示校準在復古色調及飽和度之後套用，保留純黑與 64/255 以上的輸出；HUD 與嵌入的鏡面視圖各沿用原有呈現流程。Esc → Video → Calibrate Display 提供不調暗的即時場景與參考色階，Apply 保存，Cancel、Esc 或關閉面板恢復已保存值。舊亮度和對比設定不參與新校準。編輯及重載流程見[曲線指南](night-vision.md)。

來源 `get_camera_transform()` 提供含偏移、必要時已插值的顯示姿勢。參考相機與 Quad 在 `frame_pre_draw` 逐幀更新，因此明確關閉自己的 physics interpolation，並在定位後各呼叫 `force_update_transform()`；此時 SceneTree 的普通 transform notification 已處理完，僅設定 global_transform 會使繪圖端晚一幀。車身帶動相機／燈光晃動與鏡面轉向必須使用輪廓幾何的首幀回歸，純黑接收面或等待多幀後擷取無法驗證這種錯位。

Checkpoint v6 要求 clock 字典（elapsed_seconds、day_length_minutes），與生成版本分開。讀取時檢查數字型別、有限值及範圍；prepare_world 在子節點 ready 前恢復，HUD 在 ready 強制刷新。缺欄位拒絕載入，不計算離線時間。POI 的 own_world_3d 保留自身照明，戶外時鐘持續流動，返回立即使用目前時段。

`tests/day_night_playground.tscn` 的調時／加速鍵只用於驗收。歷史美術樣板凍結時鐘並明確使用 exponential fog，避免新光照每幀覆寫 A/B 環境。

### 動態天氣與雨聲

WorldClock 持有 WorldWeather（RefCounted），使用世界 seed 衍生的獨立 RNG；advance 將現實 delta 換算成遊戲秒後，同步推進時間與天氣。WorldWeather 提供 changed、sample、set_weather、capture／restore／valid_state，狀態以 Vector3 表示晴朗程度、雨級、霧級。分段剩餘時間與轉換進度都使用遊戲秒；set_time 是驗收調光入口，不重抽天氣。

2026-10-21 重構：`WorldWeather` 只管理自然天氣；常駐景觀霧、天氣霧的外觀及載入視野保護各自獨立。`WorldClock.atmosphere` 指向 [WorldAtmosphereProfile](../../world/world_atmosphere_profile.tres)，集中距離、密度、白霧色、體積取樣與串流緩衝；其 `mist` 為無副作用取樣，`visual_conditions` 合成偏行壓力。`WorldStreamVisibility` 只保存暫態視野上限，按真實秒數恢復，不參與保存或自然 RNG。WorldClock 取得實際相機的已完成地景距離，將景觀／天氣霧與載入上限取較近值，再統一寫入 Environment、天空、光源及局部霧材質。巨人與雨幕仍讀自然 `weather.sample()`。首階段保留原畫面，後續外觀修正拉開晴天、陰天與小霧的距離、色調及直射光；機率、時間及五欄位天氣保存格式不變。[重構驗證](../validation/2026-10-21-weather-refactor.md) · [天氣外觀修正](../validation/2026-10-21-weather-appearance.md)。

WorldClock 仍唯一寫入正式室外 Environment、DirectionalLight3D 及天空 shader。體積霧關閉 temporal reprojection，保留當幀散射與空間濾波，避免動態手電筒／車燈或短閃光留下前幀光束；灰階參考讀取同一模式，不以時段切換。夜間真實燈光保留原生光程、顏色及陰影，灰階適應只補足缺少的亮度。自然小霧／中霧／大霧的距離霧終點為 150／110／38 m，8 m 起漸入；曲線只限制灰階補光，真實燈光與發光仍受原生天氣霧影響。晴天採暖灰遠霧、直射光能量 1.3；陰天採冷灰遠霧、直射光 0.45；小霧轉為灰白色並縮短遠景。色調及光照隨過渡連續混合，雨與霧再壓低直射光。夜間霧色仍隨原生照明變暗，天空與完全遮蔽物體共用終端顏色。

ForestFog 在 chunk 建立／退出時向該世界時鐘登錄／解除材質，新材質與每幀更新使用相同有效天氣密度。舊版景觀霧與天空分支已移除。`WorldAtmosphereProfile.mist` 保留最遠 230 m 的常駐遮蔽、curve 1，晴天／低畫質同樣保留；陰天全域 0.0025／局部 0.14 密度，隨天氣霧淡出，由 150／110／38 m 距離霧接手。天空參與原生距離及體積霧合成，體積取樣範圍同步縮短以涵蓋廣角角落。`WorldGenerator.completed_scenery_clearance` 只計算包含實際相機的連續已完成區帶，忽略施工中區帶及不相連的 pinned islands；`WorldStreamVisibility` 將霧終點限制在該邊界內 8 m，收近即時、恢復每真實秒 20 m。ForestScenery 建立時讀取所屬時鐘的同一份 atmosphere；CPU MultiMesh AABB 含所有變換，植被裁切含半徑／遲滯／8 m 緩衝，所有頂點都在完全遮蔽後才切換。霧距離／裁切參數應在生成前配置，調整已生成地景的可見距離需重建區塊；密度與顏色在 apply_time 重新取樣。自然天氣 RNG、保存、區帶／怪物生成與回收規則不變。Compatibility 保留相同距離霧。[常駐白霧與載入遮蔽](../validation/2026-10-20-persistent-mist.md)。

WeatherRain 使用兩層固定種子 MultiMesh 雨幕：近景 24,576 粒子／半徑 24 m／高 32 m，遠景 49,152 粒子／半徑 96 m／高 48 m。種子只上傳一次，rain_field shader 以 CPU 傳入、尊重暫停的時間計算落雨、世界座標環繞和 billboard；每幀只更新相機、時間、天氣參數，不逐滴更新位置或碰撞。大雨最多提交 73,728 粒子，小雨約 24,323；兩層交界及範圍邊緣漸淡，數字代表提交量，不是遮擋後實際可見數。

RainCover 使用兩張 64×64 世界座標環狀高度圖，近格 0.75 m、遠格 3 m；每物理步分別更新 256／128 格，60 Hz 下完整刷新約 0.27／0.53 秒。圖內攜帶 cell 座標與有效旗標，避免移動／傳送時舊資料錯用；未知格暫時隱藏雨。高度快取查詢第 1 層實體碰撞，排除玩家、怪物、底盤和設備；地形、建築與未分類道具依快取頻率刷新。最近最多 8 個 RV roof 的 BoxShape3D 實體碰撞盒，以每物理步的逆變換傳入 shader，逐粒子做垂直線與有向盒相交，支援傾斜、拆除與破壞，不留下車頂高度圖殘影。超過 8 個車頂碰撞盒的密集場景未驗收；目前每台標準開口車頂使用 4 個。

水花另取樣攝影機周圍最多 8 條落點射線，最多 64 個、壽命 0.18 秒，弱參照及局部座標跟隨承接物件。包含 1 條聲音遮蔽射線，合計上限 393 次／物理步，與粒子數無關。大雨抑制太陽直射光和天空日輪。獨立 POI 停止戶外雨幕與水花、保留低音量雨聲；2 條程序 PCM 循環依雨勢混合，專用 bus 的低通隨頭頂遮蔽變化，世界退出時移除 bus。Compatibility 使用相同空間 shader，無需 GPU 粒子碰撞節點；其雨幕密度與範圍不縮水。

Checkpoint v6 的必要 weather 字典保存 source／target、transition_elapsed、remaining、rng_state；在 prepare_world、子節點 ready 前還原。霧級以 0／0.5／1／2 表示無額外霧／小霧／中霧／大霧；target 僅接受這四值，source 允許 0–2 的有限插值。陰天天氣的霧抽選機率為 20／40／25／15%，門檻為 0.2／0.6／0.85；雨勢獨立抽選。缺欄位或非法值在世界重建前拒絕。正式天氣與測試快捷鍵分離；既有美術樣板固定天氣。驗收入口見 [天氣測試場](playgrounds.md)。

### 局部體積霧（目前正式設定）

桌面渲染使用 Forward+／Vulkan，常駐距離白霧與隨天氣調整的全域／局部體積霧共用 atmosphere 設定；ForestFog 使用獨立外觀 RNG，按地形低處與實際步道路線高度建立 FogVolume，隨 chunk 回收。世界座標 3D 噪聲和柔化邊界控制局部濃淡，霧不參與碰撞、導航或怪物感知，也不改地形生成版本與物資。

RV 車頂的 CabinAir 持有負密度排霧區，僅在安裝完成且可運作時啟用；獨立 World3D 室內副本不啟用室外體積霧。Compatibility 保留相同距離霧，不建立 FogVolume。地表紋理作為污痕資料遮罩採原始取樣，避免 Forward+ 的色彩空間轉換改變材質閾值。體積霧首版驗收見 [局部體積霧](../validation/2026-09-17-volumetric-fog.md)，目前設定見上方動態天氣段落。

### 正式戶外 D 風格

正式距離霧使用原生 Depth 模式，陰天 24–230 m、晴天 64–230 m、curve 1、最大混合量 1；自然天氣與載入保護可收近終點。天空 horizon_color 與 Environment.fog_light_color 共用時段及天氣色彩，fog_sky_affect 為 1，使遠處物體與天空一起被霧遮蔽。Compatibility 共用此路徑，僅省略體積霧。

ForestMeshes 使用共用的不透明低模分枝網格與粗葉脈／樹皮材質；ForestScenery 將原有世界座標轉成 48m 格內局部座標，樹／灌叢裁切距離為 340m／160m、遲滯 16m。未改生成 RNG、實例數、樹位或碰撞。這是正式渲染更新，不需要存檔或生成版本升級。

地表 shader 用現有三角形的導數計算平面法線，不改 mesh 頂點或碰撞；只取原泥地貼圖的低頻污痕。天空 shader 的光色由 WorldClock 驅動，配合距離霧與環境填光。OutdoorPresentation 保留約 540p 的舊室外縮放選項；後製不進行像素格量化或抖色，顯示偏好改由 GameSettings 與 Esc 設定選單管理。入口材質由外觀專用快取持有，不修改室內共用材質。

### 工業恐怖美術

- `IndustrialArt` 快取室外 StandardMaterial3D 與 256px 程序材質；兩張原創生成紋理位於 `assets/materials/industrial/`，Godot 匯入限制為 512px、使用 mipmap。室外建築以 mesh override 改外觀，不能修改室內共用的 POI 材質資源。
- RV 的共享掉漆材質維持 StandardMaterial3D；PanelWear／EngineAppearance 使用 detail multiply 疊加損傷，保留原本貼圖。健康狀態仍是老舊外觀，損傷／修復由原耐久資料驅動。
- CabinLightStrip 是獨立 Item；新車兩條各依附車頂，CabinLighting 只管理本條燈光。VehicleEnergy 每有效燈條支付 0.03/s，控制台提供總開關及逐條停用。拆下、損壞、移動或無電時熄滅；車頂排霧仍由 CabinAir 負責。
- IndustrialTheme 統一背包、生命、駕駛 HUD 及道具箱配色、方角框線與按鈕焦點，這些介面保留原字體與中文 fallback。平板另用 RVTerminalTheme 的英文等寬終端配色及字元框線；所有 Canvas UI 維持原生解析度。
- 本輪不改生成版本、地形／導航／碰撞或存檔格式；副本的 3D 材質與照明不在範圍內。驗證見 `docs/validation/2026-09-17-industrial-art.md`。

2026-10-11 玩家快捷欄使用六個方形格子，沒有共用背景托盤；持有物品時只在其選取格上方顯示名稱，空手時不顯示名稱。格內有物品圖示、數字鍵與選取框，大型物品標示 `2H`，選取手電筒時顯示電量及開關狀態；手槍與彈藥盒顯示格內彈量，手持手槍時顯示備彈、換彈與使用狀態。`InventoryItemIcons` 依物品 `scene_path` 對應 `assets/inventory/` 的透明 PNG 快照，快照取自遊戲實際 3D 模型；未知物品顯示通用 SVG 圖示，不將 Texture 寫入背包或存檔。快捷欄只讀取預載紋理，不在執行時渲染模型或建立 3D Viewport。所有快捷欄裝飾忽略滑鼠輸入，放置操作仍由 Player 處理；駕駛時隱藏、離座恢復。快捷欄顯示須做畫面檢查；[test_item_player](../../tests/test_item_player.gd) 保留放置預覽圖示的行為檢查。

### 可切換美術樣板

`tests/industrial_style_playground.tscn` 繼承既有室外驗收流程，載入正式世界 seed 42。`world/art_sample/` 提供 SampleForest、SampleMaterials、維修廠附加立面，以及固定陰天天空／泥地 shader。替代 MultiMesh 與材質均由樣板持有；A/B 還原當前正式資源。樣板植被依 48m 格子分批，樹／灌叢裁切距離 300m／110m，保留 12m 遲滯。正式版分區後，樣板沿用来源節點變換與 forest_kind metadata，不解析分區名稱為型號。新載入 chunk 只掃直接子節點掛上外觀，沒有全樹每幀遍歷。

RV 牆板的局部 PanelWear source 隨比較切換，保留真實耐久損傷；車內燈繼續使用正式供電判定。新增立面是視覺樣板，正式擴展前還需補上高層量體的物理／攀爬設計及導航驗收。不得把獨立樣板視為已全面替換主世界。

## POI 與場址

### POI 資產層與副本驗證

大型場址先分流為 WALK_IN 或副本入口，再建立各自配置；`ExplorationSite.select_side()` 共用既有側向避讓判定，不為加油站或開場據點建立再刪除地堡路線。`WalkInSites` 保管戶外啟用／休眠生命週期，開場終端、固定物資及工作坊 ID 由 `OpeningSiteContent` 提供，僅初訪生成。`PoiInstanceManager` 的正常離場與取消共用 viewport 清理，快照時機及等待原生導航烘焙完成後釋放幾何的規則不變。

`PoiDefinition`（`world/poi_definition.gd`）及 `world/poi_definitions/*.tres` 統一兩類 POI 的 ID、場景、場址範圍、入口路徑及室內 profile。POIConfig.DEFINITIONS 是資產目錄；GENERATION_IDS 是保留原順序的 v3／v4 生成池，兩者分開。POISpawner 與 chunk 鄰帶導航共用 scene_for_site，未知 ID 不退回預設；場址以 definition_id 指定已登錄資產。生成時只為 INSTANCE_ENTRANCE 註冊 PoiInstanceManager；入口與返回路徑由定義傳入 metadata，未使用定義的 caller 保留原節點路徑預設。v5 的 WalkInSites 使用定義 site_bounds 整地、清空植被及保護跨帶場址；戶外保存記錄 content_version，不支援的版本拒絕載入，尚無自動佈局遷移。詳見 [共用規範](poi-authoring.md)。

加油站 `fuel_pump.tscn` 以 `Visuals/Model` 實例化 `assets/models/gas_station/fuel_pump.glb`，Collision 保留原三塊 BoxShape3D，模型上的 Godot 文字標籤已移除。GLB 不帶碰撞或行為；來源為 `scripts/build_fuel_pump_glb.py`。測試場 F7 只切換新舊 Visuals，原碰撞物件不重建。尺寸、匯入比例、碰撞及探索的歷史專項結果見 [加油站驗收](../validation/2026-09-19-gas-station.md)。

`world/poi_kit/buildings/gas_station.tscn` 是同世界可步行進出的靜態建築資產，分離 Visuals、Collision、Furnishings、LootSpawns、AccessPoints 與 Lights。資產不自行產生物資，也不持有副本管理器；`tests/gas_station_playground.gd` 負責測試地面、導航烘焙、正式玩家／RV 及一次性固定 seed 物資生成，道具進入 WorldEntities。生成 v5 已接入正式串流、場址與檢查點；同世界通行、導航、E 拾取及替換外觀後碰撞的歷史結果見 [正式加油站驗收](../validation/2026-09-20-production-gas-station.md)。

`world/poi_kit/` 提供 `PoiRoom`、`PoiDoorSocket`、`PoiFurniture` 與 `PoiLootPoint`、`PoiEntrance`。房間原點在地板中心，接點 local -Z 朝外；`connect_to()` 依完整 transform 接合不同尺寸房間，拒絕不相容接口。Visuals、Collision、Furnishings 與標記彼此獨立。地堡使用 InteriorProfile 登錄的 16 個地堡模組；巨型避難所使用獨立 megashelter catalog，透過 InteriorProfiles 分流；舊副本專用資產與展示場已移除。

物資標記只提供 caller RNG 的抽選契約；初訪地堡由 BunkerContent 使用獨立 RNG 安置內容，BunkerCache 保管未領取物件。入口只發出 entry_requested，由 PoiInstanceManager 管理；場景及 Resource 可在編輯器直接修改。只供舊版房型生成的 `build_bunker_kit.py` 已移除。詳見 [製作規格](../../world/poi_kit/README.md)。

房型接口、跨接縫、seed 掃描、大型搬運及完整室內導航屬歷史專項驗收；現行自動測試保留 [POI 轉場取消與保存](../../tests/test_poi_transition_persistence.gd)。實機觀察與自動檢查分開記錄。

### 路旁小 POI 與越野場址（生成 v19）

POI 定義的 `placement_modes` 以 `ROADSIDE`、`OFF_ROAD` 旗標指定放置類別，兩者可並用，且與 `kind`（副本入口／直接探索）分開。`MinorSites` 以獨立 RNG 規劃每 1,200 m 區間的路旁小場址，最多四次候選，避開大型場址與車道；穩定 ID 使用當前生成版本、seed 與道路 cell。六主題各三個 WALK_IN 定義，不重排 POIConfig.GENERATION_IDS。越野場址按橫向 3 欄、每格 300 × 900 m 的網格規劃，每格 55% 成為候選，8 次有界嘗試並避開道路、水域、陡坡及其他 POI；候選 40% 為 bunker、10% 為 civilian_shelter、10% 為 courtyard_shelter、40% 為 camp／shed；另以獨立 2% 機率選取 `modular_megashelter`，取代一般候選而不改原池權重。四款地堡入口 與 camp／shed 支援路旁及越野，兩款 shelter 僅越野，其他四類小型主題僅路旁。四款地堡入口 路旁場址距道路中心 49 m，為獨立位置，局部整地僅用於入口建築安置。越野場址依自然地面高度及隨機朝向配置，只在資產占地及外圈步行餘量局部整地；不生成公路標誌、方向標誌、車道、停車線、林間步道、迷宮或周界牆。穩定 ID 使用生成版本、seed、row、column。

`POIConfig.instantiate_site(site, include_visuals)` 為場景設定提供單一入口；程序外觀及鄰帶導航共用同一個 `site.exterior_plan`，保持碰撞與動態 bounds 一致。`WorldField.sites_near_z` 與 `stops_in_band` 合併大型與小型場址，作為整地、植被、道路裝飾、導航鄰帶幾何、釘帶避讓與 protected_bands 的共用入口；縱向查詢有上限 256 筆的唯讀快取。主題、佈局、位置、美術、物資、敵人各有獨立 RNG。小場景資產的 Visuals 不持有碰撞或 actor 標記，外觀隨機化不改通路。

`PoiDefinition.enemy_count_range` 預設為零，非零時驗證 EnemySpawns 中足量且在界內的 Marker3D。WalkInSites 首次載入時抽取物資，貨櫃與棚屋依既有標記和 RNG 生成油桶人，actor 均屬 WorldEntities；加油站既有物資 RNG 不變。越野地堡室內沿用 PoiInstanceManager.saved_instances 與 checkpoint 的 `poi` 狀態；戶外營地等沿用 outdoor_sites／WorldActorSnapshot，不新增專用保存格式。Checkpoint v7 要求 generation_version=19；休眠狀態記錄 definition_id 和 content_version，未知版本拒絕。更多內容與驗收見 [小 POI 規格](../../world/roadside_pois/README.md) 與 [民用避難所檢查](../validation/2026-10-22-civilian-shelter.md) · [v15 越野 POI 紀錄](../validation/2026-10-22-offroad-pois.md) · [路旁小 POI 歷史驗收](../validation/2026-09-26-minor-pois.md)。

### v5 加油站保存基礎（v6 沿用）

`WalkInSites` 在停靠點 index % 3 == 1 配置 gas_station；index 0 維持維修廠。定義占地加外圈步行餘量參與 WorldField.court_distance，因此地形、植被排除與車道共用同一計畫。建築碰撞參與 chunk 導航及鄰帶補圖。導航 readiness 先確認 region iteration 與有效 bounds，再等 map 上可查詢到鄰近網格；只在 map RID 或同步 iteration 改變時重做最近點搜尋，避免等待期間每個物理步反覆掃描整張戶外導航網格。共用邊界點不必只屬於自己，等待期間重新取得 map，支援檢查點跨 World3D 轉移。

WorldGenerator v5 維護前後載入窗口、場址 pinned bands 及 generated_bands，回程重建不重抽小補給點。加油站初次用獨立 walk_in_loot RNG 讀取標記；靜態資產仍不生物資。卸載 owner band 前，WalkInSites 收集 bounds 內主世界的散落或固定 Item／活怪，保留完整 transform、狀態及速度，釋放活動 actor；回程只還原保存的剩餘物件。搬入後丟下的物品也包含在內，車輛及車上設備／庫存不歸場址。

Checkpoint v6 要求 outdoor_sites／generated_bands；活動物件只放 actors，休眠場址只放 outdoor_sites，WorldActorSnapshot 共用驗證／建立／捕捉契約。EngineState 的全樹唯一性檢查涵蓋休眠物件。戶外 content_version 不符拒絕還原。加油機尚無燃油交易功能，遠離場址的普通散落物仍沿用既有遠距清理規則。

## 車輛與串流補充

底盤腳煞車以固定物理步長逐步追蹤踏板輸入（加壓 0.35 s、釋放 0.15 s），最大制動值 100；手煞車／坡板互鎖使用獨立 300。這些保留為原 60 Hz 的調校值；VehicleBody3D 的 brake 實際為每步衝量上限，輸出乘以 `60 × delta`，避免提高至 120 Hz 後每秒制動加倍。設備重心透過父層局部 transform 組合，避免長距離行駛時 world-to-local 浮點誤差導致反覆寫入同一重心。

駐車時，底盤在輪胎衝量結算後檢查車速與至少三輪的靜態地面接觸。低速時以有限的制動衝量逐步抑制沿支撐面的殘餘滑動，並補償沿坡重力，讓懸吊繼續運作。

串流效能：地形取樣、網格組裝與導航接縫採約 4ms 的合作式時間預算；單次引擎 mesh／碰撞建構仍不可中斷，並非硬性幀時間上限。導航接縫重用共享頂點取樣；森林碰撞先在場景樹外完整組裝再加入，避免逐棵修改作用中的 compound body。遠距物件清理每 0.5 秒執行，最多延後半秒；載入與場址保護仍每幀檢查。量測與限制見 [串流效能驗證](../validation/2026-09-18-streaming-performance.md)。

地形每帶依生成版本寬度建立網格（v4 為 301×51 個頂點，v2／v3 為 151×51），行駛中分批取樣、組裝及安置；導航背景烘焙，無獨立作業執行緒生成場景節點。100 seed、載入順序、坡度、停車、網格／導航接縫及正式玩家搜刮往返的專項結果屬歷史驗收。現行 [串流生成檢查](../../tests/test_streaming_generation.gd) 聚焦分片幾何、森林配置與實體碰撞。`highway_playground.tscn` 提供正式輪驅 5 km 及停車倒出回放。量測、測試環境與限制見 [驗收紀錄](../validation/2026-09-15-highway.md)。
