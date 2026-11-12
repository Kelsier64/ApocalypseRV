# 目前功能總覽

盤點日期：2026-11-02。依目前工作樹的程式、場景與現行指南整理，涵蓋正式玩法、獨立原型、開發工具及全部 playground 入口。這是功能盤點，沒有重新執行遊戲驗收；歷次測試與實機結果仍以各篇驗收紀錄的日期和範圍為準。

目前是 **Godot 4.7.2 單人公路生存沙盒原型**。核心循環為：兩室教學整備 → 駕駛 RV → 探索與搬運 → 分解／製作／維修 → 應對怪物與偏行壓力 → 室外檢查點保存。

- **正式**：已接到主世界或正常可取得的物品／設備；仍可能有調校與驗收限制。
- **獨立原型**：可以在專用場景觀察／操作，但未加入正式生成或完整遊戲循環。
- **工具**：開發展示、回放、建模或驗證入口。
- **待做／待驗**：尚未實作的擴充，或已有實作但驗收範圍不足；在末節分開列出。

[所有測試場、命令與操作](playgrounds.md) · [正式操作表](../../README.md#怎麼玩) · [設計細節](../../GDD.md) · [模組與契約](../../architecture.md) · [自動測試](../../tests/README.md)

## 世界入口與版本

| 入口 | 用途／差異 |
|---|---|
| [main_world.tscn](../../world/main_world.tscn) | 正式入口；兩室教學、完整戶外／副本循環與 F6／F9 檢查點 |
| [demo_world.tscn](../../world/demo_world.tscn) | 快速展示；seed 42、小霧、單間車庫、無限材料與燃油，電力正常消耗；啟程後安排一次巨人遭遇，沒有正式檢查點 |
| [cheat_test_world.tscn](../../world/cheat_test_world.tscn) | 現行生成＋單間車庫；預設無限燃油／電力／材料，仍需有效電池；沒有正式檢查點 |
| [test_world.tscn](../../world/test_world.tscn) | 保留的舊測試世界；沒有正式檢查點，配置不代表現行新局 |

正式、Demo 與作弊世界均使用生成 **v19**。外殼內容 v7、Checkpoint v7、VehicleSnapshot v6 是不同版本欄位；目前保存至 `user://rv_checkpoint_v7.save`，只接受當前正式世界，不遷移舊局。依據：[WorldProfile](../../world/terrain/world_profile.gd)、[Checkpoint](../../rv/checkpoint.gd)、[VehicleSnapshot](../../rv/vehicle_snapshot.gd)。

## 開局與教學

| 功能 | 現況與範圍 | 主要來源／測試場 |
|---|---|---|
| 兩室教學基地 | 正式；接待室啟動並帶走終端才開內門，倉庫提供可任意順序操作的選做指南 | [controller](../../world/tutorial_shelter/orientation_controller.gd)、[orientation playground](../../tests/orientation_playground.tscn) |
| 故障車整備 | 正式新局有故障引擎、空電池、中段毀壞屋頂、部分牆損與爆胎；倉庫提供備用物資，沒有油電保底 | [workshop](../../world/tutorial_shelter/orientation_workshop.gd)、[opening content](../../world/tutorial_shelter/opening_site_content.gd) |
| 出庫與正式啟程 | 原 RV 朝出口前進即感應開門；玩家及全車離場後才啟動正式世界模擬，不要求做完指南清單 | [StartRun](../../world/starting_shelter/start_run.gd)、[bay gate](../../world/tutorial_shelter/bay_gate.gd) |
| 重試、略過與說明書 | 啟程前 Esc 可安全重試／略過；離場後同一終端成為可搜尋說明書；讀檔不重發物資 | [recovery](../../world/tutorial_shelter/orientation_recovery.gd)、[manual](../../equipment/training_manual.gd) |
| 舊單間車庫 | 工具／展示入口；按鈕啟程，供 Demo、作弊世界及獨立場景使用 | [starting shelter playground](../../tests/starting_shelter_playground.tscn) |

## 玩家、身體與生存

| 功能 | 現況與範圍 | 主要來源／測試場 |
|---|---|---|
| 第一人稱移動 | 正式；步行、衝刺、跳躍、蹲行、受阻保持蹲姿；移動載具上的相對運動與安全離座 | [Player](../../player/player.gd)、[player driving](../../tests/player_driving_playground.tscn) |
| 體力 | 正式；衝刺／跳躍消耗、延遲恢復與耗盡限制；駕駛及攀梯不耗體力 | [Player](../../player/player.gd) |
| 梯子攀爬 | 正式；W 上、S 下、Space 脫離，含登頂與從上方下梯；大型持物、缺臂或缺腿限制攀梯 | [RV ladder](../../equipment/rv_ladder.gd)、[rv climb](../../tests/rv_climb_playground.tscn) |
| 完整身體與動畫 | 正式；低頭可見身體、完整影子、四向走跑、跳躍／落地、攀梯、持物與駕駛姿勢 | [model visual](../../player/player_model_visual.gd)、[animation](../../tests/player_animation_playground.tscn)、[carry](../../tests/player_carry_playground.tscn) |
| 生命、死亡與屍體 | 正式；受傷冷卻、死亡布娃娃，約兩秒後在安全淨空處恢復；一般死亡留下可回收屍體，沒有局結束 | [ragdoll](../../player/player_ragdoll.gd)、[death](../../tests/player_death_playground.tscn)、[corpse](../../tests/corpse_playground.tscn) |
| 活體斷肢與爬行 | 正式；頭、雙臂、雙腿五切口；缺肢限制移動／持物／駕駛，缺腿改爬行；存活身體狀態可保存 | [body state](../../player/player_body_state.gd)、[dismemberment](../../tests/player_dismemberment_playground.tscn) |
| 飢餓與食用 | 正式；FOOD 約二十分鐘降至零，影響體力／衝刺及飢餓傷害；三種食物，按住右鍵食用，受傷等操作可打斷 | [survival](../../player/player_survival.gd)、[consumables](../../player/player_consumables.gd)、[food catalog](../../core/food_catalog.gd) |
| 列印身體與控制切換 | 正式配方；可製作 Player Body，以 E 交換控制，背包跟隨玩家，生命／部位／飢餓／體力／蹲姿隨各身體交換；須有安全空間，不能拾入背包 | [printed player](../../props/printed_player.gd)、[playground](../../tests/printed_player_playground.tscn) |

## 物品、互動與裝備

| 功能 | 現況與範圍 | 主要來源／測試場 |
|---|---|---|
| 統一 Item 與六格背包 | 正式；拾取、選取、丟棄、獨立 ID／耐久／電量；每件一格、不堆疊，最多一件雙手大型物品 | [Item](../../props/item.gd)、[inventory](../../player/player_inventory.gd)、[item playground](../../tests/item_playground.tscn) |
| 自由固定與拆卸 | 正式；F 預覽、旋轉、貼面／直立與細移；驗證碰撞、操作空間及支撐，長按 F 拆卸；預覽保留背包所有權 | [placement](../../player/equipment_placement.gd)、[rules](../../core/placement_rules.gd) |
| 支撐鏈與掉落 | 正式；區分車輛歸屬及實際支撐；車板或底層設備失效，附掛物停機並帶平台速度掉落，保留身分與功能狀態 | [mount](../../core/item_mount.gd)、[RV support](../../core/rv_support.gd) |
| 共用倉庫 | 正式；道具箱存取同車物品，材料為車輛數值庫存；拆除箱子不刪庫存 | [item box](../../equipment/item_box.gd)、[material storage](../../rv/material_storage.gd) |
| 搜刮物與模型圖示 | 正式；12 款具名回收物、燃油／電池／引擎／輪胎／食物等；快捷欄使用預載模型快照，顯示雙手、電量及彈量 | [scavenge loot](../../core/scavenge_loot.gd)、[icons](../../core/inventory_item_icons.gd)、[props](../../props/) |
| 手電筒 | 正式；手持時按右鍵開關，有限內建電量、保存剩餘電量；目前不能充電 | [flashlight](../../props/flashlight.gd)、[bunker playground](../../tests/bunker_playground.tscn) |
| 電子指南針 | 正式；手持自動定位 2 km 內最近巨型避難所，含未載入場址；獨立室內顯示無訊號 | [compass](../../props/electronic_compass.gd)、[building locator](../../core/building_locator.gd) |
| 手槍與彈藥 | 正式；單發、瞄準、換彈、12 發彈匣與盒裝備彈；實體遮擋射線，怪物傷害與油桶人致命爆炸；巨人無敵 | [weapon](../../player/player_weapon.gd)、[pistol playground](../../tests/pistol_playground.tscn) |

## RV 駕駛、車況與建造

| 功能 | 現況與範圍 | 主要來源／測試場 |
|---|---|---|
| 真實輪驅與排檔 | 正式；四輪 VehicleBody3D、前輪轉向／後輪驅動，四前進檔／空檔／倒檔、漸進油門及腳煞車、手煞車與高速轉向限制 | [Chassis](../../rv/chassis.gd)、[driving experience](../../tests/driving_experience_playground.tscn) |
| 駕駛座、儀表與鏡面 | 正式；入／離座與安全淨空、速度／油電／輪況、左右後照鏡；離座不自動熄火或拉手煞車 | [driver seat](../../equipment/driver_seat.gd)、[instrument cluster](../../rv/instrument_cluster.gd)、[mirrors](../../rv/vehicle_mirrors.gd) |
| 可換引擎與維修 | 正式；標準／強化引擎，維修蓋、停穩熄火交換、維修包；耐久歸零熄火但引擎保留 | [engine bay](../../rv/engine_bay.gd)、[rv rebuild](../../tests/rv_rebuild_playground.tscn) |
| 輪胎磨耗、爆胎與換輪 | 正式；四輪獨立耐久，接地磨耗、釘帶爆胎、抓地／驅動／轉向減弱與偏移；拆裝保存輪況 | [tire dynamics](../../rv/tire_dynamics.gd)、[tire puncture](../../tests/tire_puncture_playground.tscn) |
| 碰撞與敵人車撞 | 正式；RV 碰撞受損與按相對接近速度處理撞怪／Raker 倒地，爆炸造成車殼／引擎傷害 | [vehicle impact](../../rv/vehicle_impact.gd)、[raker impact](../../tests/raker_impact_playground.tscn) |
| 十一槽可破壞車殼 | 正式；六側面、前牆、後門及三片屋頂各自受損／破壞；地板固定在底盤，不是可施工槽位 | [structure slots](../../rv/structure_slots.gd)、[structure](../../tests/rv_structure_playground.tscn)、[roof](../../tests/rv_roof_playground.tscn) |
| 車殼施工與變型 | 正式；平板維修／重建、側牆與門互換、普通與開孔屋頂互換；有電、停穩熄火、空間及支撐檢查，同車一項施工 | [construction](../../rv/structure_construction.gd) |
| 車門、維修蓋與後坡板 | 正式；門片、鉸鏈蓋及雙折坡板動畫／碰撞；坡板互鎖行車，不穩定機械姿態限制保存 | [door](../../equipment/rv_door.gd)、[hatch](../../rv/engine_hatch.gd)、[ramp](../../rv/rear_ramp.gd)、[door playground](../../tests/rv_door_playground.tscn) |
| 自由安裝梯子與設備 | 正式；側門梯／登頂梯為可搬移 Item，自由貼牆安裝，玩家依梯攀爬；固定設備接通本車才工作 | [RV ladder](../../equipment/rv_ladder.gd)、[interaction](../../tests/rv_interaction_playground.tscn) |
| 重量與重心 | 正式簡化模型；底盤、存活車殼、引擎及固定 Item 按位置彙總；燃油、庫存、材料與電池本體不計重，外掛力矩仍有限制 | [Chassis](../../rv/chassis.gd)、[架構限制](../../architecture.md#6-已知限制) |
| 燈光、音效與視覺 | 正式；頭燈、車內／維修照明、引擎與操作回饋、引擎外觀震動；車內遮霧與屋頂雨遮 | [lights](../../rv/vehicle_lights.gd)、[audio](../../rv/vehicle_audio.gd)、[cabin air](../../rv/cabin_air.gd) |

## 能源、回收、製作與平板

| 功能 | 現況與範圍 | 主要來源／測試場 |
|---|---|---|
| 燃油與電池供電 | 正式；駕駛／怠速油耗、汽油罐補油、普通／大容量電池交換、待機與工作耗電，缺電暫停 | [energy](../../rv/vehicle_energy.gd)、[battery socket](../../rv/battery_socket.gd)、[systems](../../tests/rv_systems_playground.tscn) |
| 引擎充電 | 正式；運轉引擎為插槽電池充電，平板設定充電啟用／電量門檻／保留燃油；沒有電池不累積隱藏電力 | [energy](../../rv/vehicle_energy.gd) |
| 分解機與資源循環 | 正式；接觸投入／雙手物長 E 投入、排隊粉碎、材料滿庫等待、一次抽取產出與停工退料；屍體及活體可被捲入分解 | [scrapper](../../equipment/scrapper.gd)、[feed motion](../../equipment/scrapper_feed_motion.gd) |
| 製造佇列與逐層列印 | 正式；最多四項工作、預留材料、逐步付電、取消退款、堵住等待，三軸機構及產物逐層成形 | [crafting station](../../equipment/crafting_station.gd)、[playground](../../tests/crafting_station_playground.tscn) |
| 十二項配方 | 標準引擎、強化引擎、引擎維修包、汽油罐、普通電池、大容量電池、輪胎、Player Body、手電筒、電子指南針、手槍、彈藥盒 | [recipe catalog](../../equipment/recipe_catalog.gd)（材料／時間／電費以各 recipe 資源為準） |
| 車載五頁 TUI | 正式；Overview、Energy、Equipment、Crafting、Structure；鍵盤焦點／滑鼠操作，控制能源／設備／製作／施工 | [tablet UI](../../equipment/tablet_ui.gd)、[presenter](../../equipment/rv_terminal_presenter.gd) |
| Shell 與作弊 | 正式終端功能；隱藏退出 TUI、歷史／補全、help／rvctl；獨立切換油／電／材料、飛行、立即設定時間／天氣 | [terminal commands](../../equipment/terminal_commands.gd)、[cheat world](../../world/cheat_test_world.tscn) |

## 戶外世界、POI 與探索

| 功能 | 現況與範圍 | 主要來源／測試場 |
|---|---|---|
| 種子生成與雙向串流 | 正式 v19；150 m 區塊、道路／地形／內容獨立 RNG、分幀建立、往返重載及載入視野保護 | [generator](../../world/world_generator.gd)、[world field](../../world/terrain/world_field.gd)、[highway](../../tests/highway_playground.tscn) |
| 山路與六類地貌 | 正式；連續彎道、寬窄、升降、草原／懸崖／濕地／山脊／峽谷／森林盆地、分群樹木灌叢與近路遮蔽 | [route](../../world/terrain/terrain_route.gd)、[landforms](../../world/terrain/terrain_landforms.gd) |
| 河川、橋梁與高架 | 正式；河谷／岸坡、全路寬跨河橋、依落差生成橋板／鋼梁／橋墩／護欄；沒有游泳或水流玩法 | [crossings](../../world/terrain/terrain_crossings.gd)、[bridge builder](../../world/terrain/bridge_builder.gd) |
| 路旁與越野 POI 排程 | 正式；路旁區間與越野網格分開安排，避開道路／水域／陡坡及其他場址，局部整地與植被避讓 | [minor sites](../../world/terrain/minor_sites.gd)、[offroad sites](../../world/terrain/offroad_sites.gd) |
| 十八套小 POI | 正式；camp／shed／wreck／checkpoint／cargo／rest 各三套，物資與遭遇；camp／shed 同時支援越野 | [roadside POIs](../../world/roadside_pois/README.md)、[minor POI](../../tests/minor_poi_playground.tscn)、[production](../../tests/production_minor_poi_playground.tscn) |
| 加油站與民用避難所 | 正式；NORTHLINE 商店／維修間／後院及兩款廢棄民用／庭院避難所可直接步行探索；加油機目前為造景 | [gas station](../../world/poi_kit/buildings/README.md)、[production gas](../../tests/production_gas_station_playground.tscn)、[POI config](../../world/poi_config.gd) |
| 巨型避難所外觀 | 正式；獨立候選密度、程序生長平面、多種結構／牆面／屋頂／入口細節，維持封閉無窗外觀；可經入口轉入室內 | [外殼指南](megashelter-exteriors.md)、[megashelter](../../tests/megashelter_playground.tscn)、[world](../../tests/megashelter_world_playground.tscn) |
| 巨型避難所室內 | 正式 v19；獨立單層、通常六至八模組、依外觀面積選房型；少量散物與一箱，無敵人／樓梯／升級引擎；大小出口門共用返回流程，回訪不補貨 | [室內指南](megashelter-interiors.md)、[interior playground](../../tests/megashelter_interior_playground.tscn) |
| 隨機軍事地堡 | 正式；四種入口、16 房型、目標 30–60 模組及 1–3 層；接口／樓梯空間可能使規模減少；暗房、補給箱、機率 Raker 與強化引擎 | [地堡指南](bunker-interior.md)、[bunker playground](../../tests/bunker_playground.tscn) |
| 副本轉場與探索地圖 | 正式；入口 E 進獨立 World3D、安全返回、探索圖與切層；外界 RV 油電持續，保存布局／探索／物資／箱子／敵人及玩家丟物 | [instance manager](../../world/instances/poi_instance_manager.gd)、[interior map](../../world/instances/interior_map.gd)、[poi instance](../../tests/poi_instance_playground.tscn) |
| 公路障礙與遭遇 | 正式；開場安全段、後方最多 28 台廢車，公路分開抽取油桶人／普通油桶／廢車／釘帶；廢車不能清除 | [road spawns](../../world/road_spawns.gd)、[rear wreck](../../world/starting_shelter/rear_wreck_layout.gd) |
| 偏行壓迫 | 正式；退後或離路過遠會起霧，事件持續 30 秒後可出現 Slender Speaker；合法探索場址／通道豁免，返回安全範圍後停止遭遇生成並退霧 | [deviation pressure](../../world/deviation_pressure.gd)、[rear pressure](../../tests/rear_pressure_playground.tscn) |
| 樹木碰撞與倒塌 | 正式；RV／巨人撞樹、斷裂倒塌與破壞狀態保存 | [tree impact](../../world/terrain/tree_impact.gd)、[tree playground](../../tests/tree_impact_playground.tscn) |

## 敵人與遭遇

| 功能 | 現況與範圍 | 主要來源／測試場 |
|---|---|---|
| Raker | 正式；追擊／蓄力攻擊、接觸戰鬥、抓咬與斷肢、車撞倒地／布娃娃恢復、死亡屍體 | [Raker](../../enemies/raker.gd)、[raker](../../tests/raker_playground.tscn)、[impact](../../tests/raker_impact_playground.tscn) |
| 攀車、車內追擊與拆殼 | 正式怪物流程；攀車追逐、車艙路徑／低姿態通行、攻擊玩家與車殼、破門拆頂，隨支撐破壞掉落 | [boarding](../../enemies/monster_boarding.gd)、[cabin route](../../enemies/monster_cabin_route.gd)、[boarding playground](../../tests/monster_boarding_playground.tscn) |
| 油桶人與爆炸 | 正式；油桶偽裝、喚醒追逐、近距離倒數／接觸／致命槍傷爆炸，遮擋與傷害；普通油桶也支援車撞爆炸 | [barrel man](../../enemies/barrel_man.gd)、[explosion](../../enemies/barrel_explosion.gd)、[playground](../../tests/barrel_man_playground.tscn) |
| Slender Speaker | 正式；霧天森林生成、視覺搜尋／記憶／追蹤、追車與繞車、逐片拆殼、跨車艙伸手、抓取抬升／處決、撞倒樹木；目前無敵 | [giant](../../enemies/slender_speaker/slender_speaker.gd)、[encounter](../../enemies/slender_speaker/slender_speaker_encounter.gd)、[playground](../../tests/slender_speaker_playground.tscn) |
| Crawler／Reverse Crawler | 獨立原型；腹部朝下／朝上爬行姿勢，共用追擊與接觸攻擊，可獨立保存；尚未加入正式隨機生成池 | [crawler](../../tests/crawler_playground.tscn)、[reverse crawler](../../tests/reverse_crawler_playground.tscn) |

一般怪物會繞行固定物品；設備的支撐被拆毀後會掉落。巨人另有直接砸擊設備的傷害規則，不能將「一般怪物不主動傷害 Item」套用到所有攻擊。細節以 [Monster](../../enemies/monster.gd) 與 [巨人砸擊](../../enemies/slender_speaker/slender_speaker_parked_attack.gd) 為準。

## 畫面、時間、天氣與設定

| 功能 | 現況與範圍 | 主要來源／測試場 |
|---|---|---|
| 日夜時間與太陽 | 正式；時間推進、日照／色調與 HUD 時鐘，狀態隨檢查點保存 | [clock](../../world/world_clock.gd)、[day night](../../tests/day_night_playground.tscn) |
| 動態天氣與雨聲 | 正式；晴／陰、各級雨霧及暴風雨、過渡、粒子／聲音、室內外雨遮與保存 | [weather](../../world/world_weather.gd)、[rain](../../world/weather_rain.gd)、[weather playground](../../tests/weather_playground.tscn) |
| 常駐霧與載入遮蔽 | 正式；近地白霧、距離霧、Forward+ 局部體積霧接受燈光，未完成區塊的視野保護；Compatibility 有降級 | [atmosphere](../../world/world_atmosphere_profile.gd)、[visibility guard](../../world/stream_visibility_guard.gd)、[fog playground](../../tests/volumetric_fog_playground.tscn) |
| 灰階暗部與顯示風格 | 正式；環境亮度門檻、局部亮度／距離曲線與相機交接，低模／低解析戶外風格；工業樣板另供對照 | [暗部指南](night-vision.md)、[outdoor](../../tests/outdoor_horror_playground.tscn)、[industrial](../../tests/industrial_style_playground.tscn) |
| 畫質、顯示、輸入與音量 | 正式；畫質組合、自動／自訂 3D 比例、抗鋸齒、陰影／霧品質、VSync／幀率、色彩、FOV／滑鼠及主音量，偏好獨立保存 | [settings](../../core/game_settings.gd)、[menu](../../player/settings_menu.gd) |
| HUD 與快捷欄 | 正式；生命／體力／飢餓／時鐘／互動／物品及駕駛資訊，F12 切換；選單與 HUD 保持清晰 | [HUD visibility](../../core/hud_visibility.gd)、[inventory UI](../../player/inventory_ui.gd) |

Esc 設定選單與平板並非世界暫停；敵人、傷害、重力與 RV 資源仍會運作。教學啟程前的模擬凍結另有專用規則。

## 保存與開發工具

| 功能 | 現況與範圍 | 主要來源／入口 |
|---|---|---|
| 室外檢查點 | 正式主世界 F6／F9；保存完整玩家／RV／教學／時間天氣／場址／副本狀態，上一份有效檔備份為 `.bak`；要求室外離座及穩定狀態 | [Checkpoint](../../rv/checkpoint.gd)、[schema](../../core/checkpoint_schema.gd) |
| 狀態與所有權驗證 | 場景白名單、唯一 ID、支撐鏈／物品狀態／室內 profile 驗證，錯誤／不相容資料拒絕載入；不是多槽永久世界保存 | [save catalog](../../core/save_scene_catalog.gd)、[world entities](../../core/world_entities.gd)、[profiles](../../world/instances/interior_profiles.gd) |
| 全部互動測試場 | 58 個 tests 場景：53 個 playground（含兩個巢狀版本）＋5 個 viewer／workshop／review；其中兩個 Slender 工作坊僅本機存在、未納入 Git | [完整分類表與每場操作](playgrounds.md) |
| 自動回歸與 CI | 16 個核心測試＋正式主世界 smoke，支援篩選、固定步進、日誌與 runner 自測；不覆蓋所有舊長情境 | [tests README](../../tests/README.md)、[runner](../../scripts/test.ps1) |
| 回放與效能量測 | 測試場各自的 replay／capture；另有駕駛／串流量測與路線回放腳本，結果需依實際執行環境解讀 | [driving benchmark](../../scripts/benchmark_driving.gd)、[streaming benchmark](../../scripts/benchmark_streaming.gd)、[trip replay](../../scripts/replay_rv_trip.gd) |
| 資產與場景製作 | 可編輯來源、資產重建、POI 房間／家具／入口規範、角色模型、image-to-3D 工作流及獨立檢視場 | [asset builds](asset-builds.md)、[POI authoring](poi-authoring.md)、[image-to-3D](image-to-3d-workflow.md)、[codebase](codebase.md) |

## 尚未實作與仍待驗收

尚未實作的主要玩法：多人合作、任務與正式勝敗／長局進度、玩家近戰、口渴／睡眠／治療、失血、可用加油機與廢車清除、雨水造成的淋濕／體溫／抓地等生存效果、湖泊／水流玩法。巨型避難所目前只開放單層，Crawler 兩型仍未加入正式生成。列印身體與暫時重生已存在，正式死亡代價與終局設計仍待決定。

已有實作但仍須擴大驗收：長途油電／材料及探索收益平衡、一般操作與音效手感、更多地形／室內 seed 的自由探索、串流與群怪效能、偏載／外掛碰撞力矩／極端翻車、怪物坡面與車廂通行。固定步進回放與 headless 通過不代表這些項目全部完成。

根目錄 GDD／architecture 和各計畫包含有日期的歷史段落；版本與接入狀態有差異時，先查本總覽連結的當前程式與專題指南。[計畫總覽](../plans/README.md) 用於追接續工作；[validation](../README.md) 的結果保持原日期，這次只做文件盤點及來源／連結核對。
