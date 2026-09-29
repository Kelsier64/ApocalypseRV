# Godot 場景與程序視覺資產盤點

> 歷史快照：2026-09-29 封存，保留當時觀察與規則，不再日常更新。現行流程見 [建模入口](../../modeling/README.md)。

2026-09-29 後續：油桶與滿／空汽油罐保留遊戲包裝場景，外觀改為原生灰盒；原模型已 [收存](../../../art_source/retired_props/2026-09-29/README.md)。部分用途 README 已校正，當前對應見 [來源 manifest](asset-provenance.md)。以下為 2026-09-28 的靜態盤點基線，原分類不代表後續變更仍未處理。

日期：2026-09-28。範圍是 `props/`、`equipment/`、`rv/`、`world/`、`player/`、`enemies/` 的場景、相關程序 mesh，以及 `assets/materials/`。依 [3D 場景 skill](../../../.agents/skills/apocalypse-rv-3d-scenes/SKILL.md)、[AGENTS](../../../AGENTS.md)、[架構](../../../architecture.md) 與 [目錄指南](../../guides/codebase.md) 做靜態盤點；沒有改場景、搬檔、重建模型、啟動 Godot 或執行遊戲驗收。

## 判讀方法與涵蓋範圍

本次列舉上述六目錄全部 **109 個 `.tscn`**：props 10、equipment 18（包含 1 個純 UI）、rv 22、world 55、player 2、enemies 2。逐家族追場景 `ext_resource`、關鍵節點、材質、程式載入、生成版本與保存白名單；代表場景另讀幾何和碰撞分離方式。這不是逐模型目視評分或 GLB 幾何審計。

以下狀態不等同 [交接佇列](../../modeling/README.md) 的 `queued`／`integrated`：

| 分類 | 本報告的含義 |
|---|---|
| 簡單 mesh＋材質成品候選 | 規則形狀已具用途、表面與功能；可直接保留為正式美術，不必轉 GLB。最終外觀仍待目視驗收。 |
| 既有複雜原生／程序外觀 | 已有細部、組裝或程序生成且被使用；保留，不因新 skill 的新製作規則而降回灰盒。是否值得精修另判斷。 |
| 灰盒／外觀占位候選 | 來源明示灰盒，或實際內容只表達占用體積、缺乏物件識別細節。後者明列為判讀，非已確認製作需求。 |
| 匯入模型包裝 | `.tscn` 提供功能／碰撞，GLB 提供外觀；存在引用不代表本次完成模型驗收。 |
| 對照／相容／樣板 | 由實際消費者判定；名字含 test、legacy、sample 不足以判廢。 |

優先度：**P0** 先修正分類與來源標示、保護引用契約；**P1** 優先目視／確認需求；**P2** 維護或選擇性精修；**P3** 保留相容及對照。優先度不是批准製作或刪除。

## Props：可搬運物件（10 場景）

所有十個道具均列入 [SaveSceneCatalog.PROPS](../../../core/save_scene_catalog.gd)，還可能由配方、物資點及存檔動態載入，不能只查主場景。

| 資產家族／代表路徑 | 製作方式、目前用途與證據 | 分類、未知與建議 |
|---|---|---|
| 汽油罐 `gas_can`／`gas_can_empty`；[汽油罐](../../../props/gas_can.tscn) | 兩個包裝都實例化 `assets/gas_can.glb`，掛可互動道具腳本；有油／空罐共用外觀，遊戲狀態分開。 | 匯入模型包裝，P2。保留原點、手持比例和碰撞；空滿辨識是否充足待目視。 |
| 油桶；[oil_barrel](../../../props/oil_barrel.tscn) | `assets/oil_barrel.glb`＋道具外層；主世界直接使用，POI 物資也引用。 | 匯入模型包裝，P2；不因模型在 assets 根目錄而搬移。 |
| 電池 `battery`／`battery_large`；[基礎場景](../../../props/battery.tscn)、[大型變體](../../../props/battery_large.tscn) | 0.45×0.3×0.3 m 綠色盒體、同尺寸碰撞、Charge Label；大型變體繼承，只改容量／重量。 | 簡單體積已功能化，但端子／外觀識別有限；P1 目視判定「可用簡單成品」或需少量材質／端子改善。兩種共模是實際設計，不能推定缺模型。 |
| 廢鐵；[scrap](../../../props/scrap.tscn) | 0.3 m 無專屬材質 BoxMesh、同形碰撞及回收產出；正式物資高頻使用。 | 灰盒候選（內容判讀），P1；最小可辨識廢鐵可能用簡單 mesh＋材質完成，無須先排複雜建模。 |
| 散落輪胎；[wheel](../../../props/wheel.tscn) | 深色 CylinderMesh，半徑 0.7 m、厚 0.5 m；可搬運與更換輪胎。與車上 `rv/visuals/wheel.tscn` 是不同外觀來源。 | 簡化占位候選，P1；先確認是否能重用車輪視覺及尺寸契約，不另造重複輪胎模型。 |
| 標準／升級引擎；[engine_standard](../../../props/engine_standard.tscn)、[engine_upgraded](../../../props/engine_upgraded.tscn) | 原生網格有 Block、Head、散熱 Rib、ValveCover、Alternator、Pulley、Tag；材質共用 RV 色系，具獨立道具碰撞和引擎狀態。 | 既有複雜原生外觀，P1 目視；屬未來建模候選但不是空白灰盒。需與固定引擎艙顯示一併核對，不直接抹除細節。 |
| 維修包；[engine_repair_kit](../../../props/engine_repair_kit.tscn) | 橘色 0.4×0.24×0.28 m 盒體、淺色條與標籤，使用既有材質；簡單剛體碰撞、維修消耗。 | 簡單 mesh＋材質成品候選，P2；識別及手持觀感待目視，沒有必須 GLB 化的理由。 |

## Equipment 與 RV（40 場景）

關係主幹：[正式 new_rv](../../../rv/new_rv.tscn) → [chassis](../../../rv/chassis.tscn)＋設備包裝 → `rv/visuals/`。視覺不全在名為 Visuals 的樹下：既有設備有 `Details`、根層 Mesh、`Leaf0/Leaf1`；未來替換須遵守原路徑。保存白名單仍列出 `rv_floor` 及四片舊長牆。

| 家族／完整涵蓋 | 製作方式、用途與來源證據 | 分類、候選與整理優先度 |
|---|---|---|
| 正式車輛組裝、底盤；[new_rv](../../../rv/new_rv.tscn)、[chassis](../../../rv/chassis.tscn) | 4×12 m 原生 mesh 底盤，Deck／Rail／Cross／Arch／Bumper 與獨立碰撞、VehicleWheel、固定服務件；正式世界引用，預裝服務設備。 | 既有複雜原生外觀，P1 先做總體目視。簡單甲板／直梁可保留成品；駕駛室等複雜形體另判，不把整車統一列灰盒。 |
| 車殼／門：`rv_ceiling`、`rv_side_panel`、`rv_side_door`、`rv_rear_door`、`rv_wall_front`；[側門](../../../equipment/rv_side_door.tscn)、[屋頂視覺](../../../rv/visuals/roof.tscn) | 已有窗框、玻璃、框板、共享磨損材質；門扇樞軸及碰撞由 `rv_door.gd` 同步，永久槽由 `structure_slots.gd` 管理。屋頂包裝另實例化 roof 視覺。 | 混合：簡單板件可作成品；多部件門／前窗是既有整合外觀，P2。優先保留門洞、動作掃掠與可攀尺寸，不為視覺整理改碰撞。 |
| 相容板件：`rv_floor`、`rv_wall_left`、`rv_wall_right`、`rv_wall_back`；[舊長牆](../../../equipment/rv_wall_left.tscn) | floor 為簡單板；長牆已有多片 mesh／窗，不是 `rv/legacy/` 的單片外觀。正式新車不用這組長牆，但 SaveSceneCatalog 及 VehicleSnapshot 遷移仍需要。 | 相容資產，P0 標清用途、P3 保留。不能與 legacy 場景混同，也不能因無新車實例刪除。 |
| 駕駛座與控制台；[driver_seat](../../../equipment/driver_seat.tscn)、[cockpit](../../../rv/visuals/cockpit.tscn)、[控制腳本](../../../rv/cockpit_visual.gd) | 包裝持有三組碰撞；視覺含椅身、方向盤、踏板、排檔、手煞車、儀表及指針，讀正式車況。 | 既有複雜原生外觀；P1 高價值目視／建模候選。需先記錄腳本依賴節點與 pivots，再決定是否製作新模型。 |
| 工作台 `crafting_station`；[設備](../../../equipment/crafting_station.tscn)、[細節](../../../rv/visuals/crafting_station.tscn) | 桌面＋Details（桌腳等），根層桌面／四腳碰撞及 SpawnMarker；生產出料與工作燈有功能契約。 | 簡單桌體可當成品，P2。作業設備細節若日後升級，再分出獨立模型候選，不能將整張桌子當複雜模型待辦。 |
| 發電機 `generator`、分解機 `scrapper`；[發電機細節](../../../rv/visuals/generator.tscn)、[分解機](../../../equipment/scrapper.tscn) | 設備包裝＋同名 rv/visuals 場景；發電機含燃油頂部、機塊、支架、通風條、風扇；分解機保留本體與細節。正式車上運轉設備。 | 既有原生設備外觀，P1／P2。引擎／轉子等機械是建模候選，但只有目視確認不足後才排期。 |
| 加油孔 `fuel_port`、道具箱 `item_box`、平板 `tablet_screen`；[箱體](../../../equipment/item_box.tscn)、[平板](../../../equipment/tablet_screen.tscn) | 均為功能包裝＋同名 Details；加油孔還有根層盒體及 CSG 圓蓋，不能只換 Details 就假定全外觀已替換。箱體、屏幕為規則構件。 | 簡單 mesh＋材質成品候選，P2。保留互動面、掛載與 UI；[tablet_ui](../../../equipment/tablet_ui.tscn) 為純 UI，不納入 3D 模型製作。 |
| 獨立燈條；[cabin_light_strip](../../../equipment/cabin_light_strip.tscn)、[CabinLighting](../../../rv/cabin_lighting.gd) | 1.2×0.06×0.1 m 金屬殼，程序新增光罩 mesh 與 SpotLight，供電決定發光；正式車預裝。 | 簡單 mesh＋材質成品候選，P2。僅看 tscn 的單一盒子會漏掉執行期發光面。 |
| 電池槽；[battery_socket](../../../rv/battery_socket.tscn) | 原生小型框／盒構件，裝於 chassis，列入設備保存白名單。 | 簡單構件候選，P2；模型替換不能接管電池狀態。 |
| 引擎艙／維修蓋；[engine_bay](../../../rv/engine_bay.tscn)、[engine_bay.gd](../../../rv/engine_bay.gd)、[engine_hatch](../../../rv/engine_hatch.gd) | 固定服務槽＋Hatch＋內嵌 EngineVisual；顯示由 installed_engine 決定，材質磨損由 EngineAppearance 寫入。EngineVisual 並非直接實例化引擎道具場景。 | 既有複雜原生外觀，P1；與兩種引擎道具是同家族的多個表現，先統一規格再建模。 |
| 後坡板；[rear_ramp](../../../rv/rear_ramp.tscn) | Stowed／Deck 分開視覺，收納兩折、展開動畫與獨立碰撞；RearRamp／RampControl 管理互鎖。 | 規則板件＋已整合活動組件，P2；可維持原生 mesh 成品，主要驗收接縫、運動和步行。 |
| 車輪；[wheel 視覺](../../../rv/visuals/wheel.tscn) | 輪胎、輪圈、螺帽的多部件原生網格；底盤按既有半徑縮放，TireDynamics 控制爆胎視覺。 | 既有較細外觀，P1 先與散落輪胎核對共用可能性；非必須重作。 |
| 附加程序視覺；[車鏡](../../../rv/vehicle_mirrors.gd)、[車燈](../../../rv/vehicle_lights.gd)、[PanelWear](../../../rv/panel_wear.gd)、[EngineAppearance](../../../rv/engine_appearance.gd) | 鏡面 QuadMesh＋SubViewport；車燈發光／SpotLight；磨損疊材質、玻璃裂紋；另有 work_lighting、cabin_air。 | 功能視覺／效果，P2，不是缺失建模檔。替換材質時保留狀態覆蓋及可見層。 |
| `rv/legacy/` 八場景：new_rv、chassis、driver_seat、ceiling 與四壁；[legacy 組裝](../../../rv/legacy/new_rv.tscn) | 舊 CSG／簡單車殼；仍共用現行服務件。`tests/rv_design_workshop.gd` F6 載入，`test_rv_structure_modules.gd` 用於相容檢查。 | 有明確對照／測試消費者，P3 保留；不作新建模優先項。 |

[RV 視覺說明](../../../rv/visuals/README.md) 提供既有製作目的，但「模型原型」標題不等同每個子件都未完成；應按上述用途分別判定。

## 世界、POI 與程序造景（55 場景）

| 家族／涵蓋 | 製作方式、使用關係與證據 | 候選與整理優先度 |
|---|---|---|
| [test_world](../../../world/test_world.tscn) | `project.godot` 的正式主場景，實例化玩家、RV、道具，持有 WorldGenerator／PoiInstances／WorldClock。 | P0：名字含 test 但不是可刪樣板；自身是組裝入口，不需建模。 |
| 地形、道路、標線、擋牆；[chunk_generator](../../../world/chunk_generator.gd)、[ExplorationSite](../../../world/terrain/exploration_site.gd)、[RoadsideKit](../../../world/terrain/roadside_kit.gd) | SurfaceTool／ArrayMesh 依 WorldField 生成地表道路，shader 世界座標紋理；路線旁擋牆與標線用規則 mesh，跟場址規劃保持一致。 | 程序地景及簡單構件成品候選，P2；不能以「沒有 GLB」當建模缺口。 |
| 正式森林；[ForestMeshes](../../../world/terrain/forest_meshes.gd)、[ForestScenery](../../../world/terrain/forest_scenery.gd) | 六種樹（四有葉、兩枯樹）與三灌叢，SurfaceTool 建分叉、稜面樹幹和不透明枝葉；快取 ArrayMesh＋按 48 m 格 MultiMesh 批次；generation_version ≥4 使用。 | 既有複雜程序外觀，P2；已有 UV、頂點色、樹皮／枝葉材質，不是單錐灰盒。需改造時保留 RNG、樹幹碰撞及繪製策略。 |
| 路旁套件九場景；[roadside_kit 說明](../../../world/roadside_kit/README.md) | tree、dead_tree、rock、pole、sign、rail、wreck、camp、shed，由 `instantiate_module(kind)` 動態取用；首次建置腳本產生可編輯靜態 `.tscn`。pole/sign/rail 等仍有路線用途，舊樹叢分支用於 <v4，舊小場址配置由 v2–v5 保留。 | 混合，P3 保留版本相容。標牌／護欄／棚架是簡單構件；舊 wreck／camp 是明顯簡化量體候選，但不能當作 v6 精細小 POI，也無須優先精修舊版本。 |
| 爆胎釘帶；[tire_spike_strip](../../../world/tire_spike_strip.gd) | 程序底板＋24 個共 mesh 尖錐＋警示條；Area 只收集近車，輪接地点決定爆胎。 | 簡單重複構件成品候選，P2；不因尖錐數量多判成機械建模需求。 |
| 加油站；[gas_station](../../../world/poi_kit/buildings/gas_station.tscn) | 原生建築外殼、棚、玻璃、標牌、Lights；獨立 Collision／AccessPoints／LootSpawns，Furnishings 實例化下列家具。WALK_IN 定義由 v5 起使用，v6 沿用。 | 混合場景，P1。說明仍稱「灰盒」，但牆地板／簡單棚架有材質與用途，可保留簡單成品；不能把已換 GLB 的加油機列待建模。未來維修機械另分候選。 |
| 三種家具；[shelf](../../../world/poi_kit/furniture/shelf.tscn)、[workbench](../../../world/poi_kit/furniture/workbench.tscn)、[cabinet](../../../world/poi_kit/furniture/cabinet.tscn) | 原生規則板件＋材質、獨立碰撞與 LootSpawns；加油站仍引用。 | 簡單 mesh＋材質成品候選，P2；舊副本移除不使這三件成孤兒。 |
| 加油機；[fuel_pump](../../../world/poi_kit/furniture/fuel_pump.tscn)、[灰盒對照](../../../world/poi_kit/furniture/fuel_pump_graybox.tscn) | 正式 wrapper `Visuals/Model` 取 `assets/models/gas_station/fuel_pump.glb`，Godot 維護字樣，外層三塊碰撞。灰盒僅供 F7 外觀比較及尺寸回歸。 | 匯入模型包裝＋明確對照灰盒，P2／P3。加油機造景無燃油交易；功能停用不代表模型缺失。 |
| 地堡入口五場景；[service_entrance](../../../world/poi_kit/exteriors/service_entrance.tscn)、[exterior_style](../../../world/poi_kit/exteriors/exterior_style.gd) | maintenance／warehouse／pump／research 四款繼承基礎入口；@tool 腳本添加 BunkerFacade、柱、標識與燈。`maintenance_legacy.tres` 也指向相同基礎入口且 interior_profile=bunker。 | 已有基本軍事立面、規則構件，P2。名稱曾指不同設施，但現行四款不是四個完整特色建築模型；特色外設若要新增需另確定需求。 |
| 地堡十六模組；[目錄](../../../world/poi_kit/rooms/bunker)、[profile](../../../world/instances/catalog/bunker.tres) | entry、stairs；small_01–03、medium_01–02、large_01–02、corridor_01–02、passage_01–02、hall_01–03。靜態原生幾何與混凝土／漆面／鋼材、管線／燈具／基本陳設；房型資源登錄場景，PoiInterior 按 manifest 組裝、封閉未接接口。 | 混合：簡單牆／地板／門框／直管已可作成品；基本櫃體不應自動排 GLB。P2 目視材質尺度與接縫，特殊機械陳設如需添加才列候選。無物資／怪物是內容範圍，不是模型全部未完成。 |
| v6 小 POI 十八場景；[目錄與主題表](../../../world/roadside_pois/README.md)、[製作來源](../../../scripts/build_minor_pois.gd)、[minor_appearance](../../../world/roadside_pois/minor_appearance.gd) | wreck、camp、shed、checkpoint、cargo、rest 各 _0／_1／_2；由建置腳本預製靜態原生 mesh，非每幀重建。Visuals／Collision／Furnishings／LootSpawns／AccessPoints／EnemySpawns 分離；執行期只調漆色／DecorSlot，WalkInSites 管物資敵人。 | 既有可探索混合場景，P1／P2。事故車／翻覆車、貨車尾、帳篷屬較複雜候選；棧板／箱堆、棚架、野餐桌、告示牌可保留簡單成品；不要按整個 POI 一律重建。 |
| 天空、霧、雨、水花；[WorldClock](../../../world/world_clock.gd)、[WeatherRain](../../../world/weather_rain.gd)、[ForestFog](../../../world/terrain/forest_fog.gd) | 程序天空 shader、FogVolume、QuadMesh＋MultiMesh 雨幕／水花、遮雨資料；由時鐘／天氣驅動。 | 功能視覺效果，P2，非實體模型缺口。戶外後處理由 [OutdoorPresentation](../../../world/outdoor_presentation.gd) 控制，不能以場景縮圖推定實際材質觀感。 |
| 歷史美術樣板；[world/art_sample](../../../world/art_sample)、[industrial_style_playground](../../../tests/industrial_style_playground.gd) | 獨立 sample_forest／sample_materials／maintenance_sample 與地面／天空 shader；測試場呼叫。 | P3 保留比較用途。正式 ForestMeshes 與此來源分開；不是為清理就合併或刪掉。 |

## 玩家與敵人（4 場景）

| 家族／路徑 | 實際外觀關係與用途 | 分類、未知與優先度 |
|---|---|---|
| [player.tscn](../../../player/player.tscn) → [player_model_visual.tscn](../../../player/player_model_visual.tscn) | 正式玩家實例化 `assets/models/player_test_v020/player_export_test_v020.glb`；[PlayerModelVisual](../../../player/player_model_visual.gd) 使用 PLAYER_Rig/Skeleton3D、篩選第一人稱身體三角形、複製影子層；locomotion／ragdoll 保留骨架契約。 | 匯入模型包裝＋衍生 ArrayMesh；P0 標清 test_v020 目前為正式引用，P2 依角色驗收整理。不能改成膠囊灰盒或因名稱刪除。 |
| [zombie.tscn](../../../enemies/zombie.tscn) | `BodyMesh/Model` 引入 `assets/models/monster/monster_export_test.glb`；wrapper 旋轉 Y=π、縮放約 0.688，保留角色碰撞／導航探針；MonsterModelVisual 讀模型動畫。保存白名單仍支援 zombie，現行 chunk 預載的則是 Raker。 | 匯入模型包裝／相容及測試仍可用，P2／P3。不等同只供測試的檔案，也不據此宣稱現行新世界會自然生成 Zombie。 |
| [raker.tscn](../../../enemies/raker.tscn) | `assets/models/raker/raker.glb`＋RakerVisual／RakerPoseModifier；動畫、骨架手臂量測、攻擊／抓取對齊；chunk 與 v6 小 POI 生成使用。 | 已接入的複雜角色模型，P2；是否要改外觀須參照現存模型驗收及骨架約束，不能把「複雜」直接變成新建模 request。 |
| [MonsterBoardingVisual](../../../enemies/monster_boarding_visual.gd) | 只有 actor **沒有** `BodyMesh/Model` 才生成兩條 capsule 手臂；現行上述 GLB wrapper 不用此 fallback 手臂。 | 相容／測試後備視覺，P3。不是主怪物仍用膠囊造型的證據。 |

## 材質與來源分層

| 素材／資源 | 實際消費者與判斷 | 建議 |
|---|---|---|
| [industrial](../../../assets/materials/industrial/README.md)：worn_paint、forest_floor PNG | 原創 image_gen 位圖，README 保存提示；RV 材質／小 POI 使用磨損漆，ChunkGenerator 使用地面貼圖；Godot import 控制執行期尺寸與 mipmap。 | P2 保留來源、import 配對。混凝土或漆面貼圖不等同已量測 PBR 完整度。 |
| [outdoor](../../../assets/materials/outdoor/README.md)：bough.svg | ForestMeshes 正式枝葉紋理；搭配頂點色、雙面不透明幾何，與樣板 alpha scissor needles 路線不同。 | P2 正式素材；任何替換須檢查遠距閃爍和森林批次成本。 |
| [poi_kit](../../../assets/materials/poi_kit/README.md)：concrete_albedo PNG | world/poi_kit/materials/concrete 與 bunker 材質使用；來源特別聲明 tile 效果仍需於最終模型及尺度檢查。 | P1 目視材質尺度、接縫；不能因貼圖已存在直接宣稱完美無縫。 |
| [style_sample](../../../assets/materials/style_sample/README.md)：panel、concrete、bark、needles SVG | README 說僅樣板使用，但 [ForestMeshes](../../../world/terrain/forest_meshes.gd) 在正式森林 preload bark；[IndustrialArt](../../../world/industrial_art.gd) 的 dress_exterior 也有 panel／concrete 引用，但本次未找到該函式呼叫者，不能推論兩者目前會在正式畫面顯示；needles 查到的使用在 sample_materials。 | **P0 文件與實際引用不一致**；bark 確為正式與樣板共用，其他兩個有程式引用但執行用途待確認，不能整夾當廢棄測試素材。先更新用途標示，搬移另做完整依賴檢查。 |
| [rv/visuals](../../../rv/visuals)：cream、dark、glass、green、light、metal、orange、red、rubber、screen、teal、white 共 12 `.tres` | 真正材質資源在模組旁；paint 色系引用工業磨損材質，透明玻璃／發光屏幕／狀態另分。 | P2 保持共享關係；換模型後仍需支持 PanelWear／EngineAppearance。 |
| [POI 材質](../../../world/poi_kit/materials)、[bunker 材質](../../../world/poi_kit/materials/bunker) | 共用 concrete／floor／orange／paint／steel／wood；地堡另有 concrete／floor／lamp／olive／steel／stripe。 | P2 模組材質不是 assets/materials 中的漏檔；保持室內資源不被戶外 dress_exterior 原地覆寫。 |
| [IndustrialArt](../../../world/industrial_art.gd) 的 NoiseTexture2D | 快取 256 px seamless 噪音，作 RoadsideKit 等表面基底；dress_exterior 留有 SVG 覆寫程式，但本次未找到呼叫者。正式森林另在 ForestMeshes 指定自己的 SVG 材質。 | 程序材質成品候選；不要把每個未落盤 NoiseTexture 列為缺貼圖，未呼叫程式也不當成已顯示證據。 |

## 建議的整理／製作順序

1. **P0：先校正文檔分類，不搬檔。** `style_sample` 的正式引用、test_world 的主入口、player_test_v020 的正式 wrapper、相容長牆與 legacy 的差別應先清楚記錄。加油站 README 同時保留「已接 v5」與「後續接入主世界」舊段落，判讀以現行定義／生成器為準。
2. **P1：先看高頻道具與大型機械。** 廢鐵、散落輪胎、電池先做辨識度比較；能靠簡單 mesh／材質完成的就不排複雜模型。駕駛室、引擎／引擎艙、發電機和事故車等，保留現有外觀，目視後再決定是否需要獨立建模規格。
3. **P2：逐家族驗收簡單成品。** 板件、門框、坡板、家具、標牌、燈條、棚架及地堡表面需確認比例、材質尺度、接縫與通路；不因 primitive 數量而自動轉 GLB。
4. **P3：保留現有對照與相容。** legacy RV、加油機灰盒、舊版 roadside_kit 與 art_sample 有測試或舊版消費者；本報告沒有刪除候選結論。

以上均為候選與整理建議，本次未新增個別製作 request，也未把候選註冊為 queued。若實際啟動複雜資產製作，才依 skill 記錄獨立可替換節點、尺寸、方向、pivot、材質／動畫契約及驗收標準。

## 本次檢查與歷史證據分開

**本次完成：** 檔案列舉、場景引用／主要節點／製作方式靜態閱讀、生成版本及保存白名單追蹤、報告相對連結存在性檢查。**本次未做：** Godot 匯入、runner、模型重建、截圖／遊戲目視、全部模型面數／UV／材質品質／動畫逐項驗收。所有成品候選、複雜外觀的視覺品質與未有明確完成證據的項目均標準適用「待目視驗收」。

歷史記錄只作查證入口，不當作本次重跑：

| 歷史記錄 | 可支持的既有工作範圍 |
|---|---|
| [RV 控制台](../../validation/2026-09-16-rv-cockpit.md)、[引擎與坡板](../../validation/2026-09-16-rv-rebuild-engine.md)、[結構門](../../validation/2026-09-16-rv-structure-doors.md) | 當時的 RV 組裝、互動與視覺驗證；不推論所有後續模型狀態。 |
| [正式戶外 D](../../validation/2026-09-17-outdoor-d.md) | 正式程序森林／表面、與樣板的分工及當時畫面。 |
| [加油機匯入](../../validation/2026-09-19-fuel-pump-import.md) | 當時 GLB、外層碰撞、F7 A/B 與可見回放。 |
| [隨機地堡](../../validation/2026-09-24-random-bunker.md) | 十六模組與通行、整合及當時基本外觀；舊 POI kit README 的 2026-09-15 記錄不能代替此新版。 |
| [小 POI](../../validation/2026-09-26-minor-pois.md) | 十八套畫面、動線與 v6 整合；通過結果含分批續跑，不是單次全套完成的聲明。 |
| [玩家模型](../../validation/2026-09-27-player-model-integration.md)、[v020 匯入](../../validation/2026-09-27-player-v020-import.md)、[玩家動畫](../../validation/2026-09-27-player-animations-v021.md)、[怪物模型](../../validation/2026-09-22-monster-model.md)、[Raker 咬合](../../validation/2026-09-24-raker-bite-contact.md) | 角色歷次模型、動作及遊戲契約的專項證據；不得由單一報告概括全部狀態。 |

## 使用 skill 遇到的未明確行為規則

- Skill 對**新製作**說複雜資產先灰盒再留 prompt，又明確要求保留既有 production assets；沒有規定如何認定歷史多 primitive／程序外觀是否已美術定稿。本次用「既有外觀＋實際消費者＋待目視」記錄，不將缺正式驗收文字等同缺模型。
- **初次盤點時的規則觀察：** 原 skill 說不確定分類時維持可測灰盒並記 prompt，但未明列純盤點例外；本次任務明確不要求自動建 request，因此不改原件、不為每個疑問另建 prompt。本輪已補充純盤點／規劃不自動建立 request 的規則，並區分 draft／queued 的前置條件。候選沒有進入 production／queued 狀態。
- Skill 沒有數量門檻判定「過多 BoxMesh」，也沒有以 GLB 作完成標準。本次根據可辨識造型、活動部件、表面用途與幾何責任判讀；釘帶重複尖錐、板件房間、駕駛室機械不能套同一數量規則。
- 舊節點 `Details`、根層 mesh、`BodyMesh` 與新建議 `Visuals` 並存。Skill 已明示保留既有路徑；本次不把命名差異當需立即重構的缺陷。若後續替換外觀，仍須先記錄腳本實際依賴。
