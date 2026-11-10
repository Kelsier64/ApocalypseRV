# 遊玩與測試場指南

全部功能與接入狀態見 [功能總覽](features.md)，正式操作見 [README](../../README.md)，規則與數值見 [GDD](../../GDD.md)。本頁先列完整入口，再保留各測試場的詳細操作與歷史驗收連結。測試場快捷鍵不等同主世界按鍵。

## SAN 幻覺測試場

用 Godot 執行 [san_playground.tscn](../../tests/san_playground.tscn)。按 ↑／↓ 增減 5 點 SAN，按住可連續調整。F6 可輸入精確值或負值。F5 入座或離座，入座後按 Space 放手煞，再用 WASD 試駕。SAN 低於 20 時，F7 觸發閉眼，F8 觸發輸入延遲，F9 觸發方向誤動。徒步時按 1 或 2 選零食，再按住右鍵食用。F10 重設測試場。

右上角的 Active 顯示當下效果與輸入延遲的毫秒數。按 F8 後連續變向，或在駕駛座放開手煞後踩油門，可感受指令晚一拍才生效。按 F9 可觀察走路或駕駛逐漸偏移，強烈發作時可能短暫反向轉向。每次都會重新抽選強度與持續時間。

SAN 低於 20 時，按 F4 眨眼並在睜眼時隨機切換視覺幻覺，或按 Shift+F4 依序預覽負片、黑白、過飽和、空間扭曲、色彩分離和視野收窄。右上角顯示目前效果的剩餘秒數。倒數完會顯示 Next blink，可按 F7 測試睜眼後恢復或接續。SAN 為 0 或負值時，按 F11 觸發長閉眼。可用 F6 比較 SAN 19、10、0 和 −30 的自然發作頻率與持續時間。

## 完整場景目錄（2026-11-02）

以實體檔案及場景腳本盤點：`tests/` 共 **58 個場景**，包含 **53 個 playground**（51 個頂層、2 個巢狀）及 **5 個檢視／工作坊／review**；其中 **56 個已納入 Git、2 個僅存在本機且被忽略**。下表逐一涵蓋，另列 5 個 `world/` 的遊玩／美術入口。操作依程式核對；本次文件整理未啟動 Godot，不代表這些場景都已完成新版人工驗收。

「正式系統」表示測試場引用正式角色、設備或服務；「主世界」表示使用正式世界或其衍生場景；「獨立實驗」表示視覺／模型研究，不能據此認定已接入主遊戲。即使引用正式系統，測試場仍可能提高 HP、凍結車輛或移除敵人，詳見後文與腳本。

從專案根目錄執行，將路徑換成任一表列場景：

```powershell
godot --path . --log-file .godot/playground.log res://tests/megashelter_interior_playground.tscn
# 場景自訂參數放在第二個 -- 之後
godot --path . --log-file .godot/playground.log res://tests/megashelter_interior_playground.tscn -- --seed=42 --replay
```

### 主遊戲與其他世界入口

| 場景 | 用途與接入狀態 | 操作／差異 |
|---|---|---|
| [main_world](../../world/main_world.tscn) | 正式主入口；目前教學、出庫與戶外生存流程 | 使用 README 的正式操作；專案預設啟動此場景。 |
| [demo_world](../../world/demo_world.tscn) | 主世界衍生展示；保留出發流程 | 固定小霧並停用自然天氣，無限材料／燃油；不是一般資源平衡。 |
| [cheat_test_world](../../world/cheat_test_world.tscn) | 主世界衍生作弊測試；保留舊車庫配置 | 預設無限燃油、電力及材料；用於自由試玩。 |
| [test_world](../../world/test_world.tscn) | 獨立世界生成與存讀檔測試入口 | 正式玩家／完整 RV／物資；沒有正式新版教學起始流程。 |
| [ruined_wall_study](../../world/art_samples/ruined_wall_study.tscn) | 獨立破損混凝土／鋼筋美術樣板 | F1 全景、F2 細節、F12 輸出當前畫面；`--capture` 自動輸出預覽。 |

### 教學、世界與 POI（15 個）

| 場景 | 用途與接入狀態 | 主要操作／模式 |
|---|---|---|
| [orientation_playground](../../tests/orientation_playground.tscn) | 主世界：目前接待室／終端課程／維修出發 | 正式操作；`--terminal-review` 開正式教學終端，`--workshop-review` 看工作區。 |
| [starting_shelter_playground](../../tests/starting_shelter_playground.tscn) | 主世界：出庫、外殼與舊車庫驗收入口 | F2 輪驅離場、F3 外觀、F4 室內／玩家、F5 封路；`--replay`。 |
| [highway_playground](../../tests/highway_playground.tscn) | 主世界：道路起伏、山路與停靠輪驅 | F1–F3 里程視角、F6 行駛、F7 停靠、F8 駕駛／跟車；`--replay`／`--parking`。 |
| [outdoor_horror_playground](../../tests/outdoor_horror_playground.tscn) | 主世界：正式戶外氛圍、入口與大物步行 | F2 視角、1–4 入口外觀、F3 搬運回放、F4 進出、F6 RV、F10 平板。 |
| [rear_pressure_playground](../../tests/rear_pressure_playground.tscn) | 主世界 fixture：後方廢車通行與偏離壓力 | F2 穿越廢車、F3 後方霧／遭遇、F4 鏡頭；`--replay` 跑通行。 |
| [gas_station_playground](../../tests/gas_station_playground.tscn) | 正式資產獨立場：加油站商店／維修間／加油棚 | F1 步行、F2 外觀、F3 商店、F4 維修間、F5 回放、F6 加油機、F7 灰盒／模型。 |
| [production_gas_station_playground](../../tests/production_gas_station_playground.tscn) | 主世界：正式加油站場址與整地／森林 | F2 鳥瞰、F3 玩家、F5 真實輪驅停靠、F7 截圖；此場移除怪物。 |
| [minor_poi_playground](../../tests/minor_poi_playground.tscn) | 正式資產獨立場：18 套路邊小 POI | 左右切佈局、N 換 seed、F1 步行、F2 總覽、F7 截圖；`--capture-all`。 |
| [production_minor_poi_playground](../../tests/production_minor_poi_playground.tscn) | 主世界：實際小 POI 排程、地形及停靠 | `--seed=0 --cell=0` 選場址；F2 總覽、F3 步行、F5 輪驅；`--replay`。 |
| [bunker_playground](../../tests/bunker_playground.tscn) | 正式系統獨立場：多層地堡生成、地圖與搬運 | F1 步行、F2 總覽、F3 掀頂、F5 搬運、R 重建；`--rooms=12 --floors=3 --seed=42`。 |
| [poi_instance_playground](../../tests/poi_instance_playground.tscn) | 主世界：地堡入口、室內副本與返回 | F6 或 `--replay` 正式 E 進出、F7 外觀、F8 截圖。 |
| [megashelter_playground](../../tests/megashelter_playground.tscn) | 正式資產獨立場：巨型避難所外殼、生長模組與停車 | F2 外觀、F3 入口、F4 步行、F5 下一 seed、F6 隨機、F7 天氣／時間、F8 模組、F10 輪驅。 |
| [megashelter_world_playground](../../tests/megashelter_world_playground.tscn) | 主世界：排程生成的巨型避難所、坡度與停車 | `--world-seed=42 --row=0 --column=0`；F2 外觀、F3 入口、F4 步行、F9 截圖、F10 輪驅；`--replay`。 |
| [megashelter_interior_playground](../../tests/megashelter_interior_playground.tscn) | 正式系統獨立場：真正外殼入口／室內管理器／玩家、全部房間與搬運返回 | F1 步行、F2 總覽、F3 掀頂、F4 下一房、F5 搬運回放、F6 下一 seed、F7 入口、F8 截圖；E 返回、L 手電筒、M 地圖。 |
| [megashelter_viewer](../../tests/megashelter_viewer.tscn) | 正式外殼檢視器；不包含步行／室內驗收 | 右鍵旋轉、中鍵平移、滾輪縮放；1 全景、2 入口、3 屋頂、F5 下一 seed、F6 隨機。 |

### RV、設備與物品（13 個）

| 場景 | 用途與接入狀態 | 主要操作／模式 |
|---|---|---|
| [rv_systems_playground](../../tests/rv_systems_playground.tscn) | 正式能源、充電、電池、製作與車輛回放 | F2 引擎、F3 換電池、F4 入座、F5 平板、F6 回放、F7 平板免傷、R 重設；`--replay`。 |
| [rv_interaction_playground](../../tests/rv_interaction_playground.tscn) | 正式射線／E 互動隔離場；固定玩家位置 | F2 電池槽、F3 座位、F4 加油孔、F5 道具箱、F6 掉落電池；1 電池、2 汽油罐。 |
| [rv_door_playground](../../tests/rv_door_playground.tscn) | 正式側門／雙扇後門、阻擋與破壞 | F2 側門、F3／F4 後門兩扇、F5 拆側門、F6 障礙箱、F7 拆後門；E 正式開關。 |
| [rv_structure_playground](../../tests/rv_structure_playground.tscn) | 正式固定結構、受損、支撐掉落與平板施工 | F2 平板、F3 傷左中牆、F4 拆右前牆、F5 拆中屋頂、F1 慢動作、R 重設。 |
| [rv_roof_playground](../../tests/rv_roof_playground.tscn) | 正式三片屋頂／梯子；繼承攀車場 | F1 平板、F11 只拆中屋頂；其餘沿用攀車場；`--art-review`。 |
| [rv_rebuild_playground](../../tests/rv_rebuild_playground.tscn) | 正式完整 RV、引擎艙、坡板及故障燈 | F8 引擎艙、F9 後門／坡板、F10 故障、F11 夜間、F12 輪驅；`--drive`。 |
| [rv_design_workshop](../../tests/rv_design_workshop.tscn) | WAYFARER 正式造型與舊版 RV 對照 | F2 外觀、F3 車內、F4 駕駛座、F5 真實輪驅、F6 舊版、F7 控制台。 |
| [driving_experience_playground](../../tests/driving_experience_playground.tscn) | 正式駕駛視角、後視鏡、燈光與維護 | F1 前方、F6／F7 左右鏡、F8 引擎艙、F9 坡板、F11 夜間、F12 輪驅。 |
| [tire_puncture_playground](../../tests/tire_puncture_playground.tscn) | 正式爆胎／釘帶與偏轉 | 1–4 單輪爆胎、F6 輪驅過釘帶、R 重設；`--replay`。 |
| [tree_impact_playground](../../tests/tree_impact_playground.tscn) | 正式輪驅撞樹、斷木與落葉；無導航／串流 | F6 單樹、F7 16 棵連撞、R 重設；`--replay`／`--chain`。 |
| [item_playground](../../tests/item_playground.tscn) | 正式 Item 支撐、掉落、背包、放置與分解 | F2 拆牆、F3 看工作台、F4 鏡頭、F6 修牆、F7 看分解機、F8 長 E 回放。 |
| [crafting_station_playground](../../tests/crafting_station_playground.tscn) | 製造機列印視覺預覽；直接取樣進度，非完整資源交易 | 1–8 配方、Space 暫停、R 重播、左右旋轉；`--capture`，`--crouch` 看蹲姿列印。 |
| [printed_player_playground](../../tests/printed_player_playground.tscn) | 正式配方／能源／控制權切換；RV 凍結供隔離 | 開場排入 20 秒列印；WASD／滑鼠、E 換身體、R 再製造；`--verify` 行為檢查。 |

### 玩家、動作與身體（12 個）

| 場景 | 用途與接入狀態 | 主要操作／模式 |
|---|---|---|
| [player_model_playground](../../tests/player_model_playground.tscn) | 主世界：正式玩家模型與視角 | F1 第一人稱、F2 低頭、F3 旁觀、F4 回放；`--replay --quit-replay`。 |
| [player_animation_playground](../../tests/player_animation_playground.tscn) | 正式移動、四向跑步、死亡／重生與跳躍 | WASD／Shift、F1 低頭、F2 外部、F3 回放；`--jump` 看跳躍、`--replay` 自動。 |
| [player_carry_playground](../../tests/player_carry_playground.tscn) | 正式手持與握姿的原地觀察 | F1 鏡頭、F2 換道具、F3 原地走、F4 俯仰、F5 手部、F6 近景角度。 |
| [player_climb_animation_playground](../../tests/player_climb_animation_playground.tscn) | 正式玩家攀梯動畫、收手與視角 | F1 第一人稱、F2 外部、F3 重播；`--animation-review`／`--camera-review`。 |
| [player_driving_playground](../../tests/player_driving_playground.tscn) | 正式坐姿／方向盤／踏板觀察；車體凍結、車殼可隱藏 | F1 回正、F2 左轉、F3 右轉、F4 鏡頭、F5 踩踏、F6 車殼。 |
| [player_death_playground](../../tests/player_death_playground.tscn) | 主世界：正式死亡布娃娃與座位清理 | F1 第一人稱、F2 旁觀、F3 致命傷、F4 回放、F5 坐姿死亡；`--replay --quit-replay`。 |
| [player_dismemberment_playground](../../tests/player_dismemberment_playground.tscn) | 正式身體／受傷爬行／Raker 咬擊結果的隔離場 | 1 頭、2／3 左右臂、4／5 左右腿；F1 鏡頭、F6 傷殘咬、F7 致死咬、F8 前進、R 重設。 |
| [corpse_playground](../../tests/corpse_playground.tscn) | 正式屍體物理、搬運與分解 | E 拾取、G 丟棄、F1 第一人稱、F2 拾取捷徑、F3 旁觀、F4 行走、F5 死亡、F6 分解捷徑；`--replay`。 |
| [pistol_playground](../../tests/pistol_playground.tscn) | 正式玩家／手槍／彈藥與敵人射擊；敵人移動停用 | 左鍵單發、右鍵瞄準、R 換彈；F6 回放、F7 巨人射線、F8 拾取；`--replay --capture`／`--headless-check`。 |
| [rv_climb_playground](../../tests/rv_climb_playground.tscn) | 正式雙角色攀車／轉彎留車／砸頂；RV 使用腳本運動 | F2 移動、F3 屋頂梯、F4 鏡頭、F5 入座砸頂、F6 車內、F7 側梯、R 重設；`--replay`。 |
| [player_import_v020/playground](../../tests/player_import_v020/playground.tscn) | 獨立 v020 匯入／骨架姿勢研究；無布娃娃 | F1–F8 姿勢、F9 低頭、F10 手部、F11 旁觀、Space TEST 片段、P 截圖；`--capture`。 |
| [player_ragdoll_v020/playground](../../tests/player_ragdoll_v020/playground.tscn) | 獨立 v020 布娃娃實驗；不是正式死亡入口 | F1–F10 情境、Space 倒下、R 恢復、C 碰撞體、T TEST 片段、WASD；`--replay --quit-replay`。 |

### 怪物、追擊與巨人（10 個）

| 場景 | 用途與接入狀態 | 主要操作／模式 |
|---|---|---|
| [raker_playground](../../tests/raker_playground.tscn) | 正式 Raker AI 與動畫；玩家 HP 提高 | Space 移動目標、F6 受傷、F7 死亡、F8 23 段動畫、F9 定格、R 恢復 AI。 |
| [raker_vehicle_playground](../../tests/raker_vehicle_playground.tscn) | 正式輪驅追車、步態、轉彎與地面／車內／駕駛抓咬 | F2 定速、F4 鏡頭、F6 重生、F8 預覽、F10 轉彎、F11 抓咬情境、F12 重試；`--grab-ground`／`--grab-cabin`／`--grab-driver`。 |
| [raker_impact_playground](../../tests/raker_impact_playground.tscn) | 正式輪驅撞擊、存活起身與致死布娃娃 | 1–4 案例、Space 開始、R 重播、F4 鏡頭、F9 暫停；`--replay --review --case=0`。 |
| [monster_pursuit_playground](../../tests/monster_pursuit_playground.tscn) | 正式 Raker 追擊、玩家／設備傷害與牆壁遮擋 | F3 加牆並固定移動、F4 移牆；玩家 HP 提高，攻擊冷卻不變。 |
| [monster_model_playground](../../tests/monster_model_playground.tscn) | 上列正式 Raker 戰鬥近景 | 沿用追擊場；F6 傷害閃白、R 重設。 |
| [monster_boarding_playground](../../tests/monster_boarding_playground.tscn) | 正式掛車／破門／砸頂；車板 HP 與握力提高方便觀察 | F6 門降至 15 HP、F5 屋頂降至 15 HP、F7 耗盡握力；F2 為腳本車體運動。 |
| [monster_cabin_playground](../../tests/monster_cabin_playground.tscn) | 正式破口進車／車內追擊；目標板件 15 HP | 預設破側門、F3 屋頂落入、F4 玩家移車外、R 重設；隱藏屋頂外觀但保留碰撞。 |
| [crawler_playground](../../tests/crawler_playground.tscn) | 正式獨立 Crawler 角色與四肢步態；未加入隨機生成池 | 左右繞看、Space 待機／爬行、Tab Raker 對照、F4 正式追擊、R 重設。 |
| [reverse_crawler_playground](../../tests/reverse_crawler_playground.tscn) | 獨立腹部朝上 Crawler 變體；未加入隨機生成池 | 與 Crawler 相同操作；不覆蓋原腹部朝下版本。 |
| [barrel_man_playground](../../tests/barrel_man_playground.tscn) | 正式油桶人／油桶爆炸，玩家、車撞、追車及坡面 | F1 動畫、F2 手動、F3 玩家回放、F4 車撞、F5 追車、F7 坡面、F8 感應、F10 普通桶、F11 駕駛 POV。 |

### 巨人專項與環境美術（6 個已追蹤）

| 場景 | 用途與接入狀態 | 主要操作／模式 |
|---|---|---|
| [slender_speaker_playground](../../tests/slender_speaker_playground.tscn) | 正式巨人／玩家／RV；自由駕駛及 8 種行為重播 | 預設 mode 0 自由模式；F2 啟停巨人、F6 鏡頭、F7 暫停、F11 重設；`--mode=1` 至 `--mode=8` 明確啟用回放。 |
| [slender_speaker_bend_review](../../tests/slender_speaker_bend_review.tscn) | 正式接觸與彎腰／抬升的視覺專項 review；非自由遊玩 | `--scenario=ground` 或 `driver`；`--angle=front`／`side`／`hands`／`pov`；Space 播放／暫停、1–4 鏡頭。 |
| [day_night_playground](../../tests/day_night_playground.tscn) | 主世界：正式日夜、光照與夜視曲線 | F1 四時段、F12 快轉、Home 暫停、F2 視角、5 高處太陽、K 重載夜間曲線。 |
| [weather_playground](../../tests/weather_playground.tscn) | 主世界：正式雨／霧／晴陰、時間與車頂遮蔽 | 6 預設天氣、7 雨、8 霧、9 晴陰、0 自然推進、Backspace 拆頂；`--heavy-rain`。 |
| [volumetric_fog_playground](../../tests/volumetric_fog_playground.tscn) | 日夜場衍生霧效對照；局部體積霧與舊距離霧 | B 切模式、7／8 局部密度、其餘沿用日夜場；`--entry` 從入口開始。 |
| [industrial_style_playground](../../tests/industrial_style_playground.tscn) | 獨立工業美術樣板；部分針葉樹／高窗／RV 材質未接入正式版 | F1 樣板／目前正式版、F2 視角、F3 搬運、F4 進出、F6 RV、F9 損傷、F10 平板。 |

### 本機限定工作坊（2 個；Git 忽略）

這兩個入口在本次盤點的工作目錄中確實存在，但不隨版本庫交付；其他 clone 可能沒有檔案。本次只記錄，不把場景或生成物加入 Git。

| 場景 | 用途與接入狀態 | 主要操作／模式 |
|---|---|---|
| [slender_speaker_workshop](../../tests/slender_speaker_workshop.tscn) | 巨人 Stage 01 獨立造型／材質／尺寸工作坊 | 1–9 視角、L 燈光、F8 擷取、Esc 離開；`--capture-review --quit-after-review`。 |
| [slender_speaker_animation_workshop](../../tests/slender_speaker_animation_workshop.tscn) | 巨人 Stage 02 動畫／手部／處刑視覺預覽；處刑預覽不結算正式行為 | 1–6 視角、[／] 片段、Space 暫停、逗號／句號逐格、E 處刑、M 位移、R 重播、F8 擷取；`--capture-hands-studio`／`--capture-motion-revision`。 |

## 詳細操作與驗收範圍

以下日期與「通過」敘述保留歷史驗收的時間與範圍；目前自動入口以 [tests/README](../../tests/README.md) 為準。Headless 不驗證畫面、滑鼠捕捉或操作手感。

## Crawler 爬行怪物

`godot --path . --log-file .godot/crawler-playground.log res://tests/crawler_playground.tscn`

[Crawler](../../enemies/crawler.tscn) 共用原 Raker 的網格、材質與骨架，以獨立姿勢控制器形成腹部朝下、四肢外張的對角交錯步態。原 Raker 場景及 GLB 未修改。Crawler 使用低伏碰撞盒與 Monster 的基本追擊／接觸攻擊，不使用 Raker 抓取或攀車動作，目前未加入隨機生成池。

展示場預設原地爬行；左右方向鍵繞看、Space 切待機／爬行、Tab 顯示原 Raker 對照、F4 切正式追擊、R 重設。正式玩家隱藏並固定在場內作為追擊目標，HP 提高以便觀察。

2026-10-26：Godot 4.7.2 的正面／側面／踏步 GPU 渲染已檢視；平地追擊檢查確認實際位移、接地與攻擊，`test_item_persistence` 通過 Crawler 與 Raker 的獨立保存／還原。坡面足部貼合、車廂通行及群怪未驗收。

### Reverse Crawler 腹部朝上版本

`godot --path . --log-file .godot/reverse-crawler-playground.log res://tests/reverse_crawler_playground.tscn`

[Reverse Crawler](../../enemies/reverse_crawler.tscn) 是另一個獨立場景，共用 Crawler 行為與 Raker 原模型，改為腹部朝上、反向拱背、倒轉頭部並將臉抬向前上方。手掌與腳掌撐地，以對角肢體交錯踏步；原 Crawler 的腹部朝下姿勢保留。展示場操作相同，目前未加入隨機生成池。

2026-10-26：已檢視正面、側面與踏步渲染，檢查平地實際追擊／接地／攻擊，並通過三種怪物的獨立保存／還原測試。坡面、車廂與群怪仍未驗收。

<a id="pistol"></a>

## 手槍與盒裝子彈

```powershell
godot --path . --log-file .godot/pistol-playground.log res://tests/pistol_playground.tscn
```

使用正式 Player、手槍、彈藥盒、Raker、油桶人與森林巨人。左鍵每按一次射擊、按住右鍵瞄準、R 換彈；E 拾取、F 放置、G 丟棄、1／2 切換物品。F2 移至牆前、F3 重設、F4 切換近距離外部鏡頭、F6 完整射擊回放、F7 巨人射線、F8 桌上拾取。外部鏡頭建議先 F7 移至空曠區，避免測試桌遮擋。

加 `-- --replay --capture` 自動回放並將畫面寫入 `.godot/pistol-playground-captures/`；加 `--pickup` 直接朝向桌上手槍。回放檢查單發、空槍、換彈、Raker 死亡、油桶人爆炸、牆壁遮擋及巨人無敵，結束保留手動操作。加 `--headless-check` 會依結果退出，適合無畫面行為檢查；不能替代原生握姿、尺寸和效果觀察。此場敵人停用自主移動以隔離射擊。[本輪驗證及限制](../validation/2026-10-11-pistol.md)。

<a id="barrel-man"></a>

## 油桶人

```powershell
godot --path . --log-file .godot/barrel-playground.log res://tests/barrel_man_playground.tscn
```

| 按鍵 | 行為 |
|---|---|
| F1 | 普通油桶、偽裝、起身／收腿、6／10 m/s 原地動畫並排 |
| F2 | 正式玩家手動接近，WASD／滑鼠操作；房間、開口與斜坡可用 |
| F3 | 正式玩家連續前進，觸發喚醒、追逐與接觸自爆 |
| F4 | 正式 RV 輪驅撞偽裝桶；此模式停用該怪物 AI，隔離實際車體接觸 |
| F5 | 怪物從車後追上正在輪驅前進的 RV，接觸自爆 |
| F7 | 坡面／轉向路線：正式怪物追逐標示的無碰撞目標，上下坡、左右轉向、落下及落地 |
| F8 | 正式玩家走進目前設定範圍後停步；顯示倒數與實測引爆時間，接觸可提前引爆 |
| F6 / F9 | 保存／恢復本展示場怪物；使用獨立檔案，不是完整世界 checkpoint |
| F10 | 正式 RV 輪驅撞一般油桶 Item，接觸立即引爆；前側鏡頭檢查爆點及車殼損傷 |
| F11 | 同 F10 輪驅流程，正式玩家入座，以駕駛 POV 檢查爆炸 |
| P / R / Esc | 暫停／重設當前情境／釋放滑鼠 |

命令末尾加 `-- --replay`、`-- --vehicle-replay`、`-- --chase-replay`、`-- --terrain-replay` 或 `-- --proximity-replay` 可直接啟動 F3／F4／F5／F7／F8。另加 `--headless-check` 在有限模擬時段後檢查實際位移、碰撞／傷害、坡面路線或倒數並退出；可搭配 `--headless --fixed-fps 60`。`--capture` 只在有渲染器時記錄有限時間點、爆炸前緩存及爆炸後畫面，路徑寫入日誌。

F7 為觀察腳掌與動作而關閉該實例的導航代理，讓它依既定目標跨越平台邊緣；加速、重力、碰撞與動畫仍使用正式實作。F1 是原地動畫展示，不代表角色實際移動。F5 是短距離追車，不代表任意高速、翻車或密集群怪均已驗收。具體觀察與自動測試分開記錄於 [本版驗收](../validation/2026-10-07-barrel-man.md)。

`-- --oil-barrel-replay` 直接啟動 F10，可再加 `--headless-check --capture` 自動檢查 18 秒輪驅重播、保存渲染畫面並退出。油桶使用正式 Item 場景，RV 只送入油門與煞車，沒有直接設定移動或呼叫爆炸。結果見 [一般油桶車撞驗收](../validation/2026-10-07-oil-barrel-vehicle-explosion.md)。

在油桶／撞怪／追車重播加 `--driver-pov` 使用正式駕駛座相機；擷取畫面建議引擎參數 `--fixed-fps 60 --resolution 1280x720`，避免 PNG 寫檔延遲跳過早期火焰。此模式保留正式玩家受傷與車殼遮蔽，檢查爆炸當下的相機所有權。駕駛畫面與原生渲染回歸見 [POV 修正紀錄](../validation/2026-10-08-barrel-driver-explosion.md)。

## 目錄

- [Slender Speaker 實際行為](#slender-speaker-runtime)
- [油桶人](#barrel-man)
- [Raker 車撞與布娃娃](#raker-impact)
- [起始避難所車庫](#starting-shelter)
- [RV 能源與維護](#section-1)
- [RV 車殼、駕駛室與門](#section-2)
- [RV 固定結構與平板施工](#structure-construction)
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
- [Item 固定、掉落與拾取](#unified-item)

<a id="slender-speaker-runtime"></a>

## Slender Speaker 實際行為

`godot --path . --log-file .godot/slender-runtime-review.log res://tests/slender_speaker_playground.tscn`。

直接執行預設為 **自由模式（mode 0）**：玩家坐在正式駕駛座，引擎啟動、一檔、手煞車拉起。Space 放手煞車後用 WASD 駕駛，B 切換引擎，R／T 升降檔，E 離座；走動、滑鼠視角及長按 E 入座均使用正常操作。巨人起初暫停，準備好後按 F2 啟用／暫停巨人。F6 觀察鏡頭、F7 暫停／繼續整個模擬、F11 重設全部、Esc 正常設定、Ctrl+F12 結束測試。自由模式沒有自動油門／煞車、定時結束或 R 重設；停車、下車、重新發動都由玩家決定。

只有明確傳入 `-- --mode=1` 至 `--mode=8` 才啟用重播。重播中 F1 第一人稱抓取／處刑、F2 輪驅直路追車、F3 輪驅彎道追車、F4 停車拆殼、F5 跟車移動拆殼；F6 切換相機、F7 暫停、F8 擷取、F11 重設、F12 返回自由模式、Esc 結束。此場使用正式巨人、玩家及 RV，真正結算接觸、車板破壞與死亡；RV 重播只輸入油門／轉向，沒有直接搬動車輛。

命令末尾加 `-- --mode=1 --capture --quit-after-review` 自動擷取並退出，模式可選 1–8。F9／模式 6 為定速跟車步態檢查，模式 7 為局部破口露出底盤，F10／模式 8 為停車拆屋頂後抓出駕駛；模式 8 加 `--pov` 使用駕駛視角，加 `--review-wait` 在開始前暫停，F7 開始。錄製建議引擎參數 `--fixed-fps 30 --resolution 1440x900`；輸出 `.godot/slender-runtime-captures/`，manifest 記錄逐幀時間、行為、模型與程式開始／結束雜湊。`--headless-check` 執行行為重播而不擷取畫面。獨立場的森林用碰撞樹幹驗證追蹤／遮擋，不代表正式世界生成。

正式森林生成、獨立導航與保存的專項自測已退出核心清單；歷史範圍與限制見[PR 驗證](../validation/2026-10-09-slender-speaker-pr.md)。現行自動入口保留遭遇 owner 與抓取行為，詳見 [測試指南](../../tests/README.md)。

<a id="unified-item"></a>

## Item 固定、掉落與拾取

```powershell
godot --path . --log-file .godot/item-playground.log res://tests/item_playground.tscn
```

場景把正式工作台固定在 RV 右側牆，使用正式玩家背包、互動及放置流程。測試場 F2 拆牆、F3 對準掉落工作台、F4 切外部鏡頭、F5 對準地面、F6 修復牆、F7 對準分解機、F8 重播正式 E 動作持續 1.2 秒；這裡的 F6 不執行主世界保存。F8 用於驗證長按投入，不直接呼叫分解機接收。

依序觀察：F2 拆牆後工作台掉落；F3 對準後 E 拾取，工作台以雙手拿著；短 F 出現獨立輪廓並隱藏手持模型，物品仍保留在背包；右鍵／Esc 取消後恢復手持顯示，G 取消後丟出；左鍵合法位置固定，原 ID／耐久保留。修復牆後可重新安裝到 RV，確認固定與支撐關係正常。滿背包或缺手臂時，拾取失敗應保留原物件。

所有 Item 免疫怪物攻擊，結構仍可被拆；物品保留碰撞及遮擋。自動入口保留 `test_item_player.gd`、`test_item_persistence.gd`，實機步驟不表示本輪已完成全部觀察。

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

F6 自動輪驅撞向前方樹木，撞後繼續供油 2 秒再煞車；F7 重載為 8 排、共 16 棵的連續撞樹回放，R 重設目前模式。W/S 油門／煞車、A/D 轉向、Space 發動並切換手煞車。畫面顯示引擎耐久、撞毀棵數及連撞最低速度；確認車頭推開帶實際碰撞的輕量斷木、撞擊後繼續前進，葉簇落地形成薄層，留在視野內不消失，並有碎木、塵土及斷樁。斷木和斷樁在撞後 20 秒開始淡出，22 秒連同碰撞移除，落葉仍保留；視野外木材可提早回收。旁邊的樹保留外觀及碰撞。日誌 TREE_REPLAY 記錄真實輪驅撞擊速度，TREE_VISUAL 記錄批次實例移除與鄰樹碰撞，TREE_CHAIN_REPLAY 記錄 16 棵連撞結果。回放抵達 65 m 後主動煞車，最後顯示零速屬回放結束。此測試場不包含導航與串流；保存、重建、導航及相機視野清理的專項結果屬歷史驗收，目前需另行檢查。最新結果見 [首次停頓與木材清理](../validation/2026-10-02-tree-impact-preparation.md)，前階段結果見 [落葉與連撞驗證](../validation/2026-10-02-tree-leaves.md)。

<a id="starting-shelter"></a>

## 起始避難所車庫

```powershell
godot --path . --log-file .godot/shelter-playground.log res://tests/starting_shelter_playground.tscn
godot --path . --log-file .godot/shelter-replay.log res://tests/starting_shelter_playground.tscn -- --replay
```

使用正式主場景、RV、物資、地形與開場控制器。F2 從原停車位開始輪驅出發，F3 查看外觀，F4 切換室內全景／玩家視角，F5 查看廢車封路。`--replay` 自動開門、入座並以油門／煞車／轉向駛出車庫、轉入公路，確認門封閉後退出；加上 `--keep-open` 保留結果畫面。`--inspect-exterior` 或 `--inspect-roadblock` 僅選擇初始觀察鏡頭。

回放只在入座時切換玩家模式，行駛期間不設定車輛 transform 或速度、不停用正常油耗。它驗證空載基本 RV 的出發；舊場址裝載三種設備、門防夾、保存與相容性的專項自測已移除；目前 `test_orientation_departure.gd` 檢查新課程交易、正式離場與已開出口的保存恢復。這些不是翻車、超載或大量敵人追車的驗收。

牆體近景：F6 查看入口與側翼窗洞，F7 查看玩家高度的內牆，F9 查看牆腳凹陷與斷面。`--inspect-facade` 以近景開始；另加 `--art-daylight` 只在這個測試場把時間設為 15:00，便於檢查立面光影，不改正式開場時間或天氣。

<a id="player-carry"></a>

## 玩家持物動作

```powershell
godot --path . --log-file .godot/carry-playground.log res://tests/player_carry_playground.tscn
```

F1 切換外部／第一人稱、F2 輪換手電筒／廢鐵／電池／油桶／引擎／空手、F3 原地播放步行、F4 切換抬頭／低頭、F5 手部近景、F6 旋轉近景角度。F3 只供固定機位觀察動畫；移動時的持物姿勢須另行以真實輸入觀察。

一般小物使用右手，大物依背包 `is_large` 使用雙手；持物與移動共用全身骨架。手持副本保留場景原尺寸與 hold_rotation，不再使用舊 hold_scale 或尺寸上限縮小，允許遮擋視線；不改地面物品或碰撞。G 從當下手持道具的世界位置與姿態放出，沿用原本朝角色前方的輕拋方向與速度；沒有手持顯示節點時仍使用原本的安全退路。預設抓點從持物網格包圍盒計算，可在 Item 根節點下加入 `GripRight`／`GripLeft` Marker3D 指定接觸點；手電筒已指定右手握柄位置。既有 hold_position 隨整體包圍盒置中，不再決定鏡頭內的持物位置。

攀爬／攀頂及就座時收起持物；被抓時由抓取姿勢接管空手。Item 放置預覽暫時隱藏手持模型，目標位置顯示輪廓，背包仍擁有物品；取消後恢復手持顯示。先前持物驗收與限制見 [持物驗收](../validation/2026-09-30-player-carry.md)，該紀錄保留當時流程，不代表新版預覽所有權的驗證。

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

1,000 seeds、逐套玩家與物資、串流保存及跨區塊步行的專項自測已退出核心清單；歷史結果見 [小 POI 驗收](../validation/2026-09-26-minor-pois.md)。效能抽樣：`godot --headless --path . -s res://scripts/profile_minor_streaming.gd`。

<a id="section-1"></a>

## RV 能源與維護

引擎內建充電功能，電池仍是可更換 Item，須放入插槽才供電。充電預設啟用，平板可設定 80% 充電門檻與 5 單位燃油保留；引擎運轉時，行駛或原地怠速均可充電，並支付額外發電耗油及引擎耗油。電池沒電仍可坐進駕駛座按 B 手動發動，或直接換一顆電池。地上或背包中的電池不自動供電。

預設 RV 底盤自帶 300 材料單位、24 格道具倉庫、100 燃油容量，附加油孔、道具箱與已裝滿電電池的插槽設備。平板可啟停引擎、切換設備、調整發電門檻／保留油量、查看材料與排隊製作。駕駛座入座後 B 啟停引擎，沒電也能手動發動；獨立引擎開關已移除。瞄準設備顯示用途、E／F／H 操作與失敗原因。

道具箱 E 開啟不耗電的共用道具倉庫，可存入／取出背包道具，保留電量與耐久；箱子拆除不影響存量或容量。手持汽油罐對已安裝加油孔 E 加油，燃油保存在底盤。材料只有數量，由分解取得、製作與維修消耗，不再領出材料包。

電池插槽長 F 拆下拾取，手持短 F 重新固定；拆下、脫落或損壞時，電池另行成為可拾取的掉落 Item，保留電量。取消放置預覽不收回電池或退回插槽原位置。電池短 E 裝入／交換、長 E 取出至背包；同車只接通一顆，倉庫電池不供電。

F6 保存到 `user://rv_checkpoint_v6.save`，F9 限室外一般操作狀態使用；完成驗證與重建後才取代目前遊戲，失敗保留原世界。成功保存將上一份有效檔備份至 `rv_checkpoint_v6.save.bak`。v6 保存玩家、車輛、獨立結構槽位、設備支撐、油電、物品、工作與已訪 POI；缺口、空引擎槽及門角度保持原狀，不補發設備。施工或 Item 放置預覽期間禁止保存，不保存施工進度；一次一個檢查點，不支援副本內保存。只支援 v6、生成 v14 與當前課程／房型，舊版需重新開局；沒有舊版遷移或舊路徑偵測。

```powershell
godot --path . --log-file .godot/rv-systems-visible.log res://tests/rv_systems_playground.tscn -- --replay
```

此場景用正式 RV／設備回放熄火耗電、原地充電、換電池、製作與輪驅轉彎。F2 引擎、F3 換電池、F4 入座、F5 平板、F6 回放、F7 傷害平板（免傷驗證）、R 重設。測試場按鍵與主世界 F6 存檔各自獨立。

此次設備／儲存調整見 [新版設計與驗收](../../docs/validation/2026-09-16-rv-shared-storage.md)。執行進度見 [RV 計畫](../../docs/plans/2026-09-15-rv-systems-roadmap.md)，測試與限制見 [RV 驗收紀錄](../../docs/validation/2026-09-15-rv-systems.md)。凍結設備對外掛碰撞的力矩傳遞、極端翻車與怪物群尚未全面驗收。

<a id="section-2"></a>

## RV 車殼、駕駛室與門

預設 RV 更新為 WAYFARER 工業露營車：深綠車殼、奶油白窗框／屋頂、橘色標示、透明有碰撞的玻璃、前後燈與輪圈。側牆分成六片：面向車頭時，右側由前到後為牆／門／牆，左側為牆／牆／牆；後方是一組向外開啟的雙扇大門。每片側牆、側門整組、後門整組固定於槽位並可獨立破壞，屋頂分前／中／後三片；結構配置及維修從平板施工。地板是底盤固定部分，不參與結構施工。

駕駛座綁定座椅、方向盤、儀表台、排檔桿、手煞車與踏板，F 搬移整組。方向盤跟隨底盤轉向，排檔桿／手煞車位置與速度、油電儀表同步車況；操控沿用 B、Space、Z/X/C、R/T。駕駛時背包欄隱藏，底部顯示車況與操作提示，離座恢復。加油孔與電池插槽位於車外維護側。

[模型結構說明](../../rv/visuals/README.md)；[展示場景](../../tests/rv_design_workshop.tscn)（F2 外觀、F3 車內、F4 駕駛、F5 輪驅、F6 舊版、F7 控制台）。舊車殼保留在 [rv/legacy/new_rv.tscn](../../rv/legacy/new_rv.tscn)。

短按 E 開關瞄準的門扇，後門兩扇可分別操作。六片側牆／門、前牆、後門、三片屋頂為十一個固定結構槽，不繼承 Item，也不能 F 搬移／自由放置或 H 維修。槽位由底盤保留，部件毀壞後仍可從平板重建；側牆與側門、普通與左側開孔屋頂都透過平板互換型態。地板保留底盤固定網格與碰撞，平板沒有地板列或操作。

開關門檢查整段路徑，角色或物件進入時停止；再按 E 可反向操作。活動門扇不允許安裝設備，固定門框可以。破壞一片結構只讓附掛於該片的設備停機並連鎖掉落，其餘板件獨立。重建或變型有碰撞阻擋時顯示原因，不能把角色或其他物件包進新部件。

v6 檢查點獨立保存十一槽型態、耐久、毀壞狀態與門角度，先恢復結構再接回設備支撐。舊十二槽地板及早期單片屋頂格式拒絕載入，不轉換結構或 Item 支撐。

```powershell
godot --path . --log-file .godot/rv-doors-visible.log res://tests/rv_door_playground.tscn
```

測試場 F2 側門、F3／F4 後門左／右扇、F5 破壞側門、F6 切換障礙箱、F7 破壞後門；E 使用正式門扇互動，F5／F7 為破壞捷徑。舊版搬移驗收屬歷史結果，見 [2026-09-16 紀錄](../../docs/validation/2026-09-16-rv-structure-doors.md)。

<a id="structure-construction"></a>

## RV 固定結構與平板施工

```powershell
godot --path . --log-file .godot/rv-structure-playground.log res://tests/rv_structure_playground.tscn
```

F2 開平板、F3 傷害左中牆、F4 破壞右前牆、F5 只破壞中段屋頂、R 重新載入。這些為測試場捷徑，主世界 F6 仍是保存。平板「車體結構」頁選型態及操作；每槽列出耐久、缺口、附掛設備和不能施工的原因，不提供地板操作。

三片屋頂與梯子另有 `tests/rv_roof_playground.tscn -- --art-review`：F1 平板、F3 左側梯登頂回放、F5 入座、F6 車內／外鏡頭、F11 只拆中段、R 重設。[本輪驗證](../validation/2026-10-06-rv-split-roof.md)分開記錄自動檢查與原生觀察。

維修花 2 Metal Parts／2 秒補 60 HP；重建花 6／6 秒回滿血；六個側槽的牆門互換、三個屋頂槽的普通／左側開孔型態互換花 2／4 秒並保留耐久比例、新門關閉。需有電、熄火且速度 ≤ 0.5 m/s，一車一項；變型須移走直接／間接附掛設備。確認完成才扣料，受擊、關閉 UI、平板失去服務、斷電、發動或超速皆取消。施工期間不能保存。平板本身免傷、仍可 F 搬移，失去支撐會掉落；重新安裝並供電後可使用。

人工觀察項目：修復與扣料、牆門互換與門扇 E 開關、破牆後附掛設備掉落、拆頂失去支撐，以及固定地板仍可站立且平板無地板操作。自動檢查保留 `test_rv_structure_modules.gd` 的結構／支撐／保存案例；施工扣料與平板操作需另行驗收。指南列出驗收步驟，不代表本輪桌面觀察或完整套件已通過。

屋頂前／中／後為三個獨立槽，各 50 kg／120 HP，初始普通／左側開孔／普通。選定任一屋頂槽可將普通與左側開孔型態互換，沿用 2 Metal Parts／4 秒及耐久比例；重建可選任一型態，6／6 秒。左側洞口 1.45 × 1.6 m，車內梯貼左內牆對準中片；確認洞內的人物或梯子會阻止封成普通屋頂，洞口本身不產生隱形碰撞／雨遮，毀壞一片後其餘片保持完整。存檔為 v6，只接受目前十一槽布局。

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

目前公路測試場使用生成 v14，舊生成分支已移除；2026-09-16 的密林記錄屬歷史結果。Esc 設定中的顯示偏好獨立保存，不遷移舊 display_preferences.cfg 欄位；F8 不再切換顯示。復古色調只影響室外 3D，不降低背包、平板或互動文字解析度。詳見 [歷次密林驗收](../../docs/validation/2026-09-16-dense-forest.md)。

```powershell
godot --path . --log-file .godot/horror-visible.log res://tests/outdoor_horror_playground.tscn
```

F2 切換公路／停車處／遮蔽步道／入口／回望視角，1–4 換四款外觀，F3 回放正式玩家攜引擎步行，F4 在門前送出 E 互動／從室內返回，F5 切換視窗大小，Esc 開啟正式設定，R 重設。測試場只替換同一位置的入口模型供比較；正式世界依 seed 配置。截圖、效能與驗證範圍見 [室外氛圍驗收](../../docs/validation/2026-09-16-outdoor-horror.md)。

在 WorldGenerator 設定 `world_seed` 可重現整條路線，`-1` 每局另選 seed；`profile` 集中景觀、路寬、坡度、密度和串流設定。現行世界支援雙向串流，遠景不提供可探索碰撞。

```powershell
godot --path . --log-file .godot/highway-visible.log res://tests/highway_playground.tscn
```

F1/F2/F3 預覽不同里程的景觀，F6 執行固定 seed 的道路輪驅，F7 測停車、倒出及返回公路，F8 切換駕駛／跟車鏡頭。回放以正式油門／轉向和 VehicleBody3D 輪胎物理移動，僅起點擺位；測試場停用耗油並移除隨機怪物、廢車和釘帶，保留地形及護欄碰撞。完成後再次按回放鍵會重載測試場，再按一次啟動。可用 `-- --replay` 或 `-- --parking` 自動執行；`--keep-open` 保留結果視窗，headless 可加 `--fixed-fps 60`。指定 `--from`／`--to` 只載入該段附近的初始區塊，`--driver-view` 使用正式座椅鏡頭：

```powershell
godot --path . --log-file .godot/mountain-uphill.log res://tests/highway_playground.tscn -- --replay --from=1660 --to=1900 --driver-view --keep-open
godot --path . --log-file .godot/mountain-downhill.log res://tests/highway_playground.tscn -- --replay --from=4950 --to=5170 --driver-view --keep-open
```

本輪短段與限制見 [山路驗證](../validation/2026-10-21-mountain-road.md)。

路旁九種模組提供可編輯場景，見 [roadside kit](../../world/roadside_kit/README.md)。地形驗收與效能紀錄見 [驗收紀錄](../../docs/validation/2026-09-15-highway.md)。

<a id="section-5"></a>

## POI 資產與副本

16 個當前 content_version=2 廢棄地堡模組，沒有 content_version=1 載入支援，六種首批尺寸、隨機 1–3 層。普通模組 60% 暗房，外觀／碰撞／門口分層，可在編輯器擴充。[製作規格](bunker-interior.md)。

美術檢查在地堡測試命令最後加 `--art-inspect`，可加 `--inspect-room=hall_03` 選起始房型（該 seed 未生成時回到入口）：測試專用手電筒自動拾取、怪物暫停；F4 轉向房內四角，F6／F7 切到下／上個房間，L 使用正式手電筒開關，F8 存當前房型和開關狀態截圖至 `.godot/bunker-art-*.png`。房間定位僅用於檢視，不能當成步行通過證據；F5 的連續搬運回放獨立驗證通行。正式遊戲仍須在初始世界地面 E 拾取手電筒。

```powershell
godot --path . --log-file .godot/bunker.log res://tests/bunker_playground.tscn -- --rooms=12 --floors=3 --seed=42
godot --path . --log-file .godot/bunker-main.log res://tests/poi_instance_playground.tscn -- --replay
```

地堡測試場 F1 步行、F2 總覽、F3 掀頂、F5 連續搬運回放、R 重建、F8 截圖；M／Page Up／Down 是正式探索地圖。主世界回放 F6 或 --replay 從入口以 E 進出；F7 查看入口外觀、F8 截圖至 `.godot/bunker-exterior.png`。回放的測試引擎不屬於正式生成。舊資產 workshop／v2 playground 已移除。

<a id="section-6"></a>

## 日夜時間

正式世界從第 1 天 **08:00** 開始，現實 **30 分鐘為遊戲一天**。右上角顯示日期／時間；太陽移動、陰影、天空、環境光和霧色同步變化。進入室內時間繼續，SceneTree 暫停或檢查點載入準備期間停止；F6／F9 檢查點保存與恢復時間，v6 要求完整時間欄位。不計算離線時間。

快速觀看四個時段：`godot --path . --log-file .godot/day-night.log res://tests/day_night_playground.tscn`。測試場景 F1 切換清晨／正午／黃昏／夜晚，F12 加速至 1 分鐘一天，Home 停住／繼續；F2 換視角，5 從高處檢查日輪，F11 隱藏測試文字。這些時間快捷鍵只存在於測試場景。

<a id="section-7"></a>

## 正式美術與獨立樣板

正式戶外已採用 [D 低模目標方向](../../docs/art_targets/outdoor/2026-09-17-d-revision.md)：分叉低模樹冠、簡化泥地、冷霧與固定雲層。Esc 設定可選約 540p 的舊室外模式或手動 3D 解析度，另調復古色調；沒有額外像素格或抖色，HUD 保持清楚。驗收見 [正式戶外 D 紀錄](../../docs/validation/2026-09-17-outdoor-d.md)。後續 [霧效修正](../../docs/validation/2026-09-17-fog-refinement.md) 保留近景對比，統一天際線與霧色並減弱雲斑。

執行 `godot --path . --log-file .godot/style-sample.log res://tests/industrial_style_playground.tscn`，查看同一 seed 的新舊美術對照。F1 切換樣板／原版、F2 固定視角、F3 正式角色攜引擎走完全程、F4 進入／返回、F6 RV／駕駛室／設備視角、F7 切換測試電量、F9 測試牆板損傷、F10 平板、F11 隱藏樣板文字、F5 切換視窗尺寸；Esc 開啟正式設定。這些測試按鍵僅屬樣板，不改正式操作。

獨立樣板仍保留前一輪針葉樹、高窗維修廠與 RV 材質實驗；F1 現在對照的是目前正式美術，不是凍結的歷史版本。正式遊玩請使用主場景；正式畫面驗收使用 `res://tests/outdoor_horror_playground.tscn`，F11 隱藏驗收文字。高窗量體與 RV 實驗材質仍未併入正式版。歷史資料見 [視覺研究](../../docs/research/2026-09-17-lethal-company-visual-direction.md) 與 [樣板驗收](../../docs/validation/2026-09-17-style-sample.md)。

室外植物、地面、四款入口與 RV／設備已使用統一的老舊工業材質；生成紋理與完整提示詞見 [材質說明](../../assets/materials/industrial/README.md)。HUD、背包和平板保留操作方式，改為方角暗底及灰白／暗黃配色。目前新局與 v6 檢查點只使用生成 v14 的植物配置。

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

玩家沿貼牆的車內梯從開口登頂，怪物沿車壁攀爬。F2 切換車輛運動、F3 車內梯回放、F4 換攝影機、F5 玩家入座測拆頂、F6 車內近景、F7 側門梯回放、F9 保存當前畫面、F10 以正式放置控制器搬移車內梯、R 重設；加 --animation-review 隱藏藍色玩家標記。F10 只設定玩家與鏡頭，由瞄準的真實牆面決定預覽位置，可用方向鍵細移後左鍵安裝。去掉 `-- --replay` 可手動 WASD／Space。這些按鍵只用於 playground，與主遊戲 R 的設備模式切換不同。

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

此追蹤／近戰場景現載入 Raker：藍色方柱標記玩家，黃色小方塊為可受傷設備。玩家生命提高且保持介面移動鎖，可觀察怪物追近後的攻擊。F3 放入牆壁並固定怪物移速，F4 移除牆壁；現行 Raker 自動回歸保留 `test_raker_grab.gd` 的抓取結果、所有權與清理；追擊及普通近戰需另行觀察。[舊追蹤驗收](../../docs/validation/2026-09-16-monster-pursuit.md)記錄的是當時場景。

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

- `6` 依序切換陰天、小雨、大雨、小霧、中霧、大霧、晴天、大雨加大霧；預設立即切換方便比較。
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

畫面顯示車速、怪物速度、步態、動畫與距離。建議先 F2 測低速追上，再選 90 km/h 目標觀察 64.8 km/h 狂奔上限；定速期間 A/D 仍可轉向，怪物貼車後按 F6 可重測。預覽可配合 F4 側面檢查駝背和頸部，F6 返回 AI。啟動時加 `-- --preview` 可直接看待機姿勢，`-- --turns` 直接啟動轉彎回放。無限碰撞地板防止掉出路面，超過道路範圍會自動重設。測試場入口與操作需手動檢查，已無獨立自動自測。

`godot --path . --log-file .godot/raker-climb.log res://tests/rv_climb_playground.tscn -- --replay --raker`

新怪物與玩家攀上移動 RV；F5 入座觸發砸頂、屋頂破壞及墜落。其他快捷鍵沿用 RV 攀爬測試場。

## 多樓層室內 v2


## 輪胎爆胎與釘帶

`godot --path . --log-file .godot/tire-playground.log res://tests/tire_puncture_playground.tscn`

F6 自動油門駛過單側釘帶，7 秒後漸進煞車；也可加 `-- --replay` 自動開始。1–4 分別讓左前／右前／左後／右後爆胎，R 重設。Space 啟動引擎並切換手煞車，W/S 油門／煞車、A/D 修正、Z 倒車、X 前進。使用正式輪驅與爆胎邏輯，畫面顯示各輪耐久和故障位置。這裡的 F6 是測試快捷鍵，正式世界仍為保存。

16 種輪胎組合、操控與釘帶接觸、維修／換胎／保存及確定性生成的專項自測已退出核心清單，變更時須另行驗收。驗收及尚未完成的目視檢查見 [爆胎紀錄](../validation/2026-09-22-tire-puncture.md)。

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

地面／車內／駕駛咬後控制的專項視窗自測已移除。使用上方抓咬場景手動檢查咬後身體位移、水平與垂直轉向、油門恢復，以及抓取中失去滑鼠捕捉後的恢復。現行 `test_raker_grab.gd` 只作行為回歸，headless 結果不能驗證作業系統滑鼠捕捉。未達 60% 或剩餘 HP 不足時仍按原規則死亡，等待重生期間不是抓取狀態。


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

使用正式玩家與 RV，回放梯子攀升、下降、車輛轉彎中的停留與登頂收手。F1 第一人稱、F2 外部視角、F3 重播、Esc 關閉；截圖存到 `docs/validation/rv-ladders-20261005/`，舊版截圖保留。登頂仍由現有控制器直接轉移站位，動畫不改路徑或速度。

雙角色回歸仍用 `rv_climb_playground.tscn -- --replay`，加 `--animation-review` 隱藏藍色標記以觀看正式模型。此測試車體凍結於抬高位置，回放起點設在車內梯下方，與 `test_moving_rv_climbing.gd` 一致；手動起點與正式玩家控制器不變。

鏡頭同步複驗可加 `--camera-review`：保存攀爬低頭／平視畫面到 `docs/validation/rv-ladders-20261005/camera/`，保留上一版圖片。

### 玩家駕駛動作

```powershell
godot --path . --log-file .godot/player-driving.log res://tests/player_driving_playground.tscn
```

使用正式玩家與駕駛座，隱藏車殼、凍結車體，檢查坐姿與控制件接觸。F1 回正、F2 左轉、F3 右轉、F4 切換外部／第一人稱／側面、F5 切換踩踏、F6 顯示／隱藏完整車殼。這是姿勢觀察場，不代表已驗證輪驅行駛。方向盤方向與回正、骨架接觸、跟車姿態及座位生命週期的專項自測已移除，須在此場景另行觀察。

