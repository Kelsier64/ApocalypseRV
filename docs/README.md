# 開發文件索引

- [2026-10-10 Slender Speaker 車內移動及右後角修正](validation/2026-10-10-slender-speaker-cabin-corner-fix.md)：修正拆頂轉向邊界晃動，分開移動測試的準備及動作期限，含原失敗重現與原生物理回歸。

- [2026-10-10 Slender Speaker 正式世界霧天生成](validation/2026-10-10-slender-speaker-fog-spawn.md)：只在小霧以上生成、無霧區段不補刷，含保存及正式森林驗證。

- [2026-10-10 Slender Speaker 抓取視角與兩秒停留](validation/2026-10-10-slender-speaker-pov.md)：第三人稱觀看完整玩家、雙手與音箱、小幅滑鼠環繞及完整兩秒 HOLD，含相關回歸與車外／駕駛原生處決重播。


- [2026-10-10 Slender Speaker 丟失乘員後繼續拆頂](validation/2026-10-10-slender-speaker-lost-survivor-roof.md)：已知乘員搜尋逾時後改用未知乘員檢查，涵蓋剩餘屋頂實際接觸與八項回歸。
- [2026-10-10 Slender Speaker 遊蕩與轉彎修正](validation/2026-10-10-slender-speaker-patrol-turning.md)：繞過 RV 車殼、跳過被占用巡邏點，分開轉向與速度漸變，含物理回歸與原生輪驅畫面。
- [2026-10-10 Slender Speaker 腳部模型](validation/2026-10-10-slender-speaker-feet.md)：重做五趾、腳踝、足弓與趾甲，含 Godot 近照及走跑預覽。
- [2026-10-10 Slender Speaker 中後艙完整遭遇修正](validation/2026-10-10-slender-speaker-hatch-and-rear.md)：修正開孔屋頂的不可達落點及後艙搜尋，驗證離座走動、拆頂、抓取至完整抬升。
- [2026-10-10 Slender Speaker 完整屋頂接近修正](validation/2026-10-10-slender-speaker-roof-approach.md)：修正慢滑時反覆追逐幾公分站位，驗證首次拆頂與底盤保護；後續中後艙問題見上方紀錄。
- [2026-10-10 Slender Speaker 同側跨車艙抓取與設備阻擋](validation/2026-10-10-slender-speaker-cross-cabin.md)：優先調整手部落點，移除抓取直接拆設備，含原生畫面與自動回歸。

整理日期：2026-09-28。`docs/` 包含現行指南、計畫、驗收、研究與美術目標；只有 `docs/archive/` 是歷史封存區。驗收紀錄保留當時結果；本次檔案整理另有獨立紀錄。

## 從哪裡開始

共用事故車：[路旁與 28 輛起始封路驗證](validation/2026-10-09-wreck-car.md)，含烤漆色差、翻覆底盤與輪驅接近檢查。

屋頂過濾設備：[三箱模型與正式場景驗證](validation/2026-10-09-roof-filter-bank.md)，含尺寸／朝向、碰撞與導航保留檢查。

屋頂通風機組：[3D／ComfyUI skill 實測與正式整合](validation/2026-10-09-roof-air-handler-skills.md)，含六視角、降面、碰撞與導航保留檢查。

Slender Speaker 持續遭遇：[單一 owner、觀測與提交動作、搜尋期限及實際輪驅驗證](validation/2026-10-09-slender-speaker-encounter.md)。本輪結果與限制由該紀錄列出；下方各歷史驗收保留當時範圍。

Slender Speaker 未拉手煞車：[拆頂車內發呆、慢滑站位與可見目標切換修正](validation/2026-10-09-slender-speaker-open-roof.md)。

Slender Speaker 自由 playground：[設備擋手、後艙換位轉圈與車底接觸修正](validation/2026-10-09-slender-speaker-live-playground.md)；後續[角落轉向與抓取後完整抬升](validation/2026-10-09-slender-speaker-corner-lift.md)。

Slender Speaker 抓取：[手掌直接拆除車板與設備、連續伸手抓人](validation/2026-10-09-slender-speaker-palm-demolition.md)。前次[手指擦碰與抬升修正](validation/2026-10-09-slender-speaker-grab-reliability.md)保留當時結果。

Slender Speaker 車內移動：[固定攻擊區域、短暫遮擋與卡住恢復](validation/2026-10-09-slender-speaker-cabin-movement.md)。

Slender Speaker 轉身／轉頭：[連續轉彎、頸部追視與音箱視線](validation/2026-10-09-slender-speaker-head-look.md)。

Slender Speaker 停車步態：[取消持續側移、前進繞車與到位轉身](validation/2026-10-09-slender-speaker-forward-approach.md)。

Slender Speaker 車內外鎖敵：[站立乘員、離座下車與繞車抓取修正](validation/2026-10-09-slender-speaker-target-switch.md)。

Slender Speaker 自由測試：[正常駕駛／步行操作與停車鎖敵修正](validation/2026-10-09-slender-speaker-free-play.md)。

Slender Speaker 停車攻擊：[拆屋頂、任一手接觸抓取、砸擊玩家與實機影片](validation/2026-10-09-slender-speaker-parked-attack.md)。

Slender Speaker 抓取動畫：[抬升肩肘翻轉修正與半速近景](validation/2026-10-09-slender-speaker-lift-joints.md)；[車內外共用彎腰動作，忽略被抓駕駛的椅背](validation/2026-10-09-slender-speaker-shared-grab.md)；[上一版彎腰與鏡頭驗證](validation/2026-10-09-slender-speaker-bend-grab.md)保留當時結果。

Slender Speaker 一檔／停車：[低速底盤命中、靜止選敵與煞停退步](validation/2026-10-09-slender-speaker-low-speed-parked.md)。

Slender Speaker 處決動畫：[雙臂小幅內收與實機驗證](validation/2026-10-09-slender-speaker-crush-arms.md)。

Slender Speaker 局部破口更新：[底盤實際接觸傷害與驗證](validation/2026-10-09-slender-speaker-chassis-smash.md)。

Slender Speaker：[v10 森林巨人整合與 PR 驗證](validation/2026-10-09-slender-speaker-pr.md)，包含正式行為、模型、生成／保存、測試命令與限制。

公路獨立生成：[v9 數量、逐隻選點與廢車朝向](validation/2026-10-07-independent-road-spawns.md)，包含獨立油桶人／普通 Item 油桶、v8 相容與不補發生命週期；本輪測試狀態以該紀錄為準。

地堡柴油發電機：[ComfyUI／3D scene skill 實測與修正](validation/2026-10-07-bunker-diesel-generator-skills.md)，含正式電力廳視覺替換、可編輯 glTF、六視角／素色檢查、尺寸與碰撞驗證。

汽油罐：[滿／空共用模型與 3D／ComfyUI skill 實測](validation/2026-10-09-gas-can-skills.md)，含尺寸／灰盒保留、拾取、加油回空罐、檢查點保存與已知拓樸問題。

油桶人：[Blender 雙腿、偽裝追逐、接觸自爆與保存驗收](validation/2026-10-07-barrel-man.md)，含正式玩家／RV 展示場、輪驅重播及模型來源；[腳踝、腳掌與五趾細修](validation/2026-10-07-barrel-man-feet.md)補上新版近景與蒙皮檢查。普通油桶與地堡裝飾桶共用相同藍色桶身。

油桶人引爆更新：[1.5 m 近距離範圍、0.5 秒倒數及接觸立即引爆](validation/2026-10-07-barrel-man-proximity.md)，含倒數保存、F8 重播及本輪測試。

油桶人特效：[火球、翻捲黑煙、塵浪與飛散火星](validation/2026-10-07-barrel-man-vfx.md)，含實機逐格畫面與效果生命週期回歸；保留目前已調整的 3 m／2 秒設定。

新版爆炸：[Blender 流體圖集、金屬碎片與厚重音效](validation/2026-10-08-barrel-blast-realism.md)，包含原生玩家／輪驅重播、相容模式與成本限制。

駕駛爆炸視角：[火煙體積與正式駕駛相機修正](validation/2026-10-08-barrel-driver-explosion.md)，含一般油桶／油桶人輪驅 POV、Forward+／Compatibility 像素回歸及完整牆遮蔽。

一般油桶：[車輛接觸立即爆炸](validation/2026-10-07-oil-barrel-vehicle-explosion.md)，共用爆炸傷害與特效，包含固定車外設備碰撞、自車載運保護及 F10 輪驅重播。

油桶模型：[原 GLB 減面與貼圖烘焙試作](validation/2026-10-06-oil-barrel-optimization.md)，含 3,000 三角形版本；[meshoptimizer 直接減面實測](validation/2026-10-07-oil-barrel-meshoptimizer.md) 比較六組設定與 Godot 渲染。正式道具現已接入原 Blender 烘焙版本。

統一物品：[Item、固定放置與支撐掉落](validation/2026-10-06-unified-items.md)，含大型設備背包、服務停機、怪物免疫、v5 保存與本輪自動／實機驗收。

三片屋頂：[前／中／後獨立結構與左側梯子洞口](validation/2026-10-06-rv-split-roof.md)，含平板型態、逐片破壞、碰撞與本轮自動／實機驗證。

玩家登車：[梯頂停止與手動離梯](validation/2026-10-06-ladder-manual-exit.md)移除登頂自動推送，放開按鍵後由 WASD 自行走出；[接梯手感修正](validation/2026-10-06-ladder-transitions.md)記錄縮小觸發距離、放慢攀爬及鏡頭靠近；[貼牆梯子重做](validation/2026-10-05-rv-wall-ladders.md)記錄自由放置與移除入口固定梯位；[初版紀錄](validation/2026-10-05-rv-ladders.md)保留當時測試，初版配置已被取代。

RV 車體：[固定地板恢復驗證](validation/2026-10-07-rv-fixed-floor.md)，含十一槽、底盤地板碰撞／支撐、v5 存檔相容及原生平板觀察。歷史 [固定結構與平板施工驗證](validation/2026-10-05-rv-structure-construction.md) 保留當時十槽、v4 及拆地板結果；現行地板不可獨立破壞。

玩家動畫與 Raker 咬擊：[玩家跑步與 Raker 咬擊姿勢修正驗收](validation/2026-10-05-ci-player-raker.md)，記錄三項 CI 失敗的修正、14 項相關回歸及原生輸入驗證。

屍體道具：[怪物／玩家屍體拾取、手持晃動、分解與保存](validation/2026-10-04-corpse-props.md)，含專用測試場與本輪回歸結果。

Esc 設定選單：[不暫停遊戲、視訊效果與移除 F8](validation/2026-10-03-settings-menu.md)，含偏好遷移、輸入回歸與桌面驗收；[Esc 無反應回報重測](validation/2026-10-03-settings-esc-recheck.md) 補上正式啟動路徑檢查；[開關與解析度介面改進](validation/2026-10-03-settings-ui.md) 記錄新版呈現。

獨立美術樣品：[破損混凝土牆近景](../world/art_samples/README.md)，包含 Godot 場景、實機渲染和材質來源；尚未替換正式避難所牆體。

Raker 車撞：[撞飛、存活起身與死亡布娃娃](validation/2026-10-02-raker-impact-ragdoll.md)，含輪驅重播、姿勢保存及物理回歸。

樹木撞毀與車輛受傷：[依減速結算碰撞與地面傷害（目前）](validation/2026-10-02-vehicle-impact.md)、[首次停頓、減速與木材清理](validation/2026-10-02-tree-impact-preparation.md)；歷史結果：[落葉保留與輕量斷木](validation/2026-10-02-tree-leaves.md)、[初版驗收](validation/2026-10-02-tree-impact.md)、[保留動量與倒塌效果](validation/2026-10-02-tree-impact-momentum.md)、[倒樹實體碰撞修正](validation/2026-10-02-tree-impact-collision.md)。

最新場景驗收：[避難所破損分布修正](validation/2026-10-03-shelter-spall-distribution.md)；先前紀錄見 [牆體構造重做](validation/2026-10-03-shelter-wall-rebuild.md)、[材質與風格修整](validation/2026-10-03-shelter-wall-style.md)、[加深與老化](validation/2026-10-03-shelter-dark-walls.md)、[去除綠色牆帶](validation/2026-10-01-shelter-weathering.md)、[牆體重做](validation/2026-10-01-shelter-walls.md)、[原生建築與部件修正](validation/2026-10-01-shelter-native-art.md)、[外觀擴建](validation/2026-10-01-shelter-expansion.md) 與 [正式世界開場](validation/2026-09-30-starting-shelter.md)。

| 需求 | 文件 | 責任 |
|---|---|---|
| 啟動遊戲、查按鍵 | [README](../README.md) | 快速開始與統一驗證入口 |
| 理解玩法、數值與未實作願景 | [GDD](../GDD.md) | 現行遊戲設計 |
| 修改程式、查所有權與資料流 | [architecture](../architecture.md) | 現行實作與限制 |
| 找程式、資產來源與清理邊界 | [程式與資產目錄指南](guides/codebase.md) | 目錄責任、引用、存檔相容及驗證 |
| 選擇下一項開發工作 | [計畫總覽](plans/README.md) | 狀態、依賴與剩餘工作 |
| 操作展示場、驗收場景 | [遊玩與測試場指南](guides/playgrounds.md) | 命令、快捷鍵與測試設定 |
| 執行與維護自動測試 | [測試指南](../tests/README.md) | 快速集、完整回歸、耗時與分類規則 |
| 開發約定 | [AGENTS](../AGENTS.md) | 協作與工具指引 |
| 待辦與原始想法 | [todo](../todo)、[todo_prompt](../todo_prompt)、[GDD_add](../GDD_add.md) | 保留原項目、POI 方向與補充提案；實作狀態見 GDD 及計畫總覽 |

## 文件維護規則

- README 保持快速入口；玩法規則與數值放 GDD，技術契約放 architecture，展示場細節放指南。
- 現況與程式不符時核對程式、場景與測試後修正文檔；計畫提案與研究建議不自動成為現有功能。
- 計畫標明已實作、部分實作、待實作或已被取代的範圍，附驗收連結。新增功能按主題併入現行文件，避免在首尾不斷追加日期章節。
- 驗收與審查報告保留當時版本、環境、結果與限制；修正結果另留紀錄，不把歷史測試寫成當前重新通過。
- `docs/archive/` 內文與歷史規格保留原樣。舊相對連結可能失效，以下提供目前位置的直接入口。

## 開發計畫

完整狀態與證據見 [計畫總覽](plans/README.md)。

## 指南

- [單圖 3D 生成、減面與驗收](guides/image-to-3d-workflow.md) — 工具、主 agent 直接生成／修整、raw 檢查、可選減面與場景接入。

- [Raker 資產建置入口](guides/asset-builds.md) — 目前 v021 來源流程與舊腳本移除紀錄。

- [程式與資產目錄指南](guides/codebase.md) — 進入專案、追查場景依賴、維護原始美術與安全清理。

- [隨機地堡製作與保存契約](guides/bunker-interior.md) — 16 模組、自由尺寸擴充、接口與 manifest 保存。

- [可動 3D 角色製作與接入規格](guides/character-modeling.md) — 現行共通契約、玩家／Raker 個別尺寸、骨架、動畫、匯入與布娃娃配置，以及玩家五切口接口；舊 Zombie、面數預算與擴充提案另存 [v2 歷史快照](archive/modeling-2026-10-05/character-modeling-v2.md)。

- [POI 共用製作與接入規範](guides/poi-authoring.md) — 類型、Resource、場景層級、素材替換及生成／保存責任。

- [遊玩與測試場指南](guides/playgrounds.md) — `guides/playgrounds.md`

## 審查與修正

- [2026-09-22 架構、潛在問題與遺產清理審查](report/ApocalypseRV_Architecture_Audit_2026-09-22.md) — 保留當時重現證據；A04 離場保存已由下方地堡內容更新修正，A01–A03 仍待處理。
- [R01–R07 修正與驗收](report/ApocalypseRV_Fixes_2026-09-18.md) — `report/ApocalypseRV_Fixes_2026-09-18.md`
- [ApocalypseRV 專案審查與修改建議](report/ApocalypseRV_Review_2026-09-18.md) — `report/ApocalypseRV_Review_2026-09-18.md`

## 驗收紀錄

- [2026-10-09 v10 CI 導航發布修正](validation/2026-10-09-ci-navigation.md) — 受限工作池重現、巨人導航發布與啟動取消、PowerShell runner 自測及本輪回歸。

- [2026-10-07 CI 不穩定測試修正](validation/2026-10-07-ci-flakiness.md) — 戶外追逐的非同步準備隔離、油桶人倒數 fixture／現行預設，以及屍體測試原生退出追查。

- [2026-10-03 Esc 設定與視訊效果](validation/2026-10-03-settings-menu.md) — 即時設定、輸入釋放、室內合成、獨立保存與原生視窗確認。

- [2026-10-03 咬手第一人稱與轉向修正](validation/2026-10-03-player-arm-bite-pov.md) — 保留玩家朝向、抬臂與嘴部撕扯、接觸後即時輸入與第一人稱回放。

- [2026-10-03 落地頭顱與血泊修正](validation/2026-10-03-player-gore-refinement.md) — 頸口重切、清除交疊碎面、自然紅色血泊與明暗近景對照。

- [2026-10-03 玩家斷肢與爬行](validation/2026-10-03-player-dismemberment.md) — Blender 五切口、六組受傷動畫、Raker 左臂／頭部咬斷、能力與保存、相關自動測試及實機畫面；含 10 月 4 日斷頭第一人稱追蹤修正。

- [2026-09-30 玩家單手／雙手持物](validation/2026-09-30-player-carry.md) — 手臂 IK、五指握合、狀態切換與第一人稱／外部視角。

- [2026-09-29 廢棄地堡場景與手電筒](validation/2026-09-29-bunker-art-flashlight.md) — v2 房間、60% 暗房、九份建模需求，以及初始世界手電筒與五分鐘電量。

- [2026-09-29 地堡 Raker 遭遇與舊怪物移除](validation/2026-09-29-bunker-raker.md) — 每機會 30% 生成、舊存檔缺失怪物遷移及 81 套完整回歸。

- [2026-09-29 地堡搜刮、遭遇與引擎回收](validation/2026-09-29-bunker-content.md) — 30–60 模組、補給箱、深處引擎、進出與回訪保存的歷史自動測試；當時的 Zombie 遭遇已由 Raker 生成規則取代。

- [2026-09-29 油桶／汽油罐灰盒與資產來源整理](validation/2026-09-29-prop-grayboxes.md) — 原檔收存、來源 manifest、舊 Raker 建置保護與道具外觀初查。

- [2026-09-28 3D 製作 skill 實測](validation/2026-09-28-3d-skill-forward-test.md) — 獨立 subagent 規劃與交接演練、格式驗證；未執行遊戲驗收。

- [2026-09-28 程式庫與文件整理](validation/2026-09-28-codebase-cleanup.md) — 未使用資源清理、存檔相容邊界與本輪檢查。

- [2026-09-27 攀爬鏡頭同步修正](validation/2026-09-27-player-climb-camera.md) — 貼牆位移同步視點、登頂／脫離回復、死亡交接及重生眼位。
- [2026-09-27 玩家正式移動動作 v021](validation/2026-09-27-player-animations-v021.md) — 待機、四方向慢跑／快跑、上升／下降／落地、攀升／橫移／登頂姿勢、固定 60 Hz 與動畫至布娃娃交接；另記高處壓力測試限制。
- [2026-09-27 玩家模型正式接入](validation/2026-09-27-player-model-integration.md) — 完整身體、第一人稱去頭顯示與影子、主世界移動／跳躍／上下車，保留中性姿勢。
- [2026-09-27 玩家死亡布娃娃接入](validation/2026-09-27-player-death-integration.md) — 正式死亡／安全重生、第一人稱無翻滾鏡頭、固定 60 Hz／Jolt 32／32，局部慣量修正後落地／恢復及 77 組完整回歸通過；120 Hz 證據保留為歷史紀錄。
- [2026-09-27 玩家 v020 布娃娃](validation/2026-09-27-player-v020-ragdoll.md) — 前階段獨立物理测试；14 碰撞體、落地／斜坡／階梯與恢復控制，當時尚未整合正式玩家。
- [2026-09-27 玩家 v020 GLB／Godot 匯入](validation/2026-09-27-player-v020-import.md) — 11 Mesh／41 變形骨、來源保全、姿勢對照與第一人稱／完整影子；保留該阶段驗收紀錄。

- [2026-09-26 路邊小 POI](validation/2026-09-26-minor-pois.md) — v6 獨立分布、18 套 WALK_IN、搜刮／怪物保存及測試場。

- [隨機軍事地堡](validation/2026-09-24-random-bunker.md) — 16 模組、自由尺寸擴充、三層通行、主世界進出與保存。

- [Raker 固定抓咬視角](validation/2026-09-24-raker-fixed-grab-view.md) — 抓住時抬頭並固定角度，移除向下追嘴與頓挫，嘴部改對準固定視線。
- [Raker 抱頭與快速貼臉咬擊](validation/2026-09-24-raker-bite-contact.md) — 加快伸手與咬合、雙手抓頭、三姿勢嘴部接觸與近距離鏡頭修正。
- [Raker v021 整隻手重建](validation/2026-09-23-raker-v021.md) — 移除舊手、重建掌部與指縫、三節四指、權重、手部 UV 與 41 動畫，整合正式遊戲。
- [Raker v020 四指關節反折](validation/2026-09-23-raker-v020.md) — 修正 Blender bind 網格／骨架及全動畫，保留拇指；6,520 個遊戲手指取樣與 15 組怪物回歸通過。
- [Raker v019 Blender 來源掌向](validation/2026-09-23-raker-v019.md) — 修正來源動畫拇指朝後／掌心外翻，重新烘焙、匯出及關閉執行期修正的來源驗證。
- [Raker 只低頭、掌向與咬後輸入](validation/2026-09-23-raker-neck-hands-input.md) — 取消站立俯身、執行期抓握及真實輸入驗證；來源步態掌向問題由後續 v019 修正。
- [Raker 站立抓咬與即時解除（前次）](validation/2026-09-23-raker-attack-alignment.md) — 前次俯身與掌向方案已由上方修正取代；保留歷史驗收。
- [Raker v018 蹲姿臉向與內藏牙齒](validation/2026-09-23-raker-v018.md) — 實際臉向補償、原生嘴縫、閉嘴藏齒及咬合動畫。

- [Raker v017 貼臉咬擊與口腔](validation/2026-09-23-raker-v017.md) — 30／40° 上抬、前探抓頭、碰撞掃掠、牙齒與咬合衝擊。

- [Raker v016 可動頸部與抓咬掙脫](validation/2026-09-22-raker-v016.md) — 限角追視、三組抓咬動畫、硬控、駕駛滑行與固定種子驗證。

- [輪胎爆胎與低機率路邊釘帶](validation/2026-09-22-tire-puncture.md) — 四輪獨立狀態、16 種組合、維修／保存與世界生成；含解鎖後的爆胎、轉彎支撐與拆頂目視證據。

- [裂爪 Raker：2.18 m 新怪物與 22 段動畫](validation/2026-09-22-raker.md) — 獨立行為、命中時機、低姿態進出 RV、生成／保存及完整回歸。
- [裂爪 v011 外觀接入](validation/2026-09-22-raker-v011.md) — 污垢貼圖、深眼窩與嘴部正式替換及 Raker 回歸。
- [Raker v013 步態與追車狂奔](validation/2026-09-22-raker-v013.md) — 三種步態、18 m/s 上限與追車回歸。
- [Raker v014 姿勢與追車測試場](validation/2026-09-22-raker-v014.md) — 手臂內收、背頸前彎、走跑相位切換與正式輪驅 playground。
- [Raker v015 小幅抬頭與轉向](validation/2026-09-22-raker-v015.md) — 下巴微抬、回頭方向鎖定、移動朝向一致及轉彎回放。
- [裂爪 v012 頭部／軀幹加密](validation/2026-09-22-raker-v012.md) — 16,116 三角面、輪廓平滑、動畫掃描及正式主世界模型驗證。

- [2026-09-22 室內 v2 主世界接入](validation/2026-09-22-interior-v2-main-integration.md) — 正式入口分流、舊副本相容與接入結果。
- [2026-09-22 室內 v2 驗收](validation/2026-09-22-interior-v2.md) — 布局、接口、樓梯、目標與捷徑。

- [怪物 GLB 試接](validation/2026-09-22-monster-model.md) — 模型、骨架、材質、循環播放、受傷與登車實機檢查；包含車內追擊失敗及原外觀對照。

- [車內燈條設備與控制台](validation/2026-09-22-cabin-light-equipment.md) — 獨立拆裝、控制台開關、耗電、保存與舊燈轉換。

- [RV 駕駛體驗](validation/2026-09-22-driving-experience.md) — 油門／轉向、鏡面、機械動畫、音效、可控照明及白天／夜間完整回放；保留人工驗收限制。

- [正式世界加油站](validation/2026-09-20-production-gas-station.md) — v5 場址、回程串流、物資保存與實機輪驅停靠。

- [行駛卡頓與漸進煞車](validation/2026-09-22-driving-performance-braking.md) — 導航等待搜尋節制、長距離重心穩定、腳煞車調整與幀時間比較。

- [RV 簡化載重](validation/2026-09-22-simple-vehicle-load.md) — 電池與庫存不計重、保存相容性、輪驅及車頂支撐回歸。

- [日夜與動態天氣](validation/2026-09-20-weather.md) — 天氣、遮雨、保存、40 組回歸與實機觀察。

- [POI 共用定義與規範](validation/2026-09-19-poi-definitions.md) — 兩類 POI、資產登錄、入口分流與舊世界資料相容。

- [加油機 GLB 替換驗證](validation/2026-09-19-fuel-pump-import.md) — 原創外部模型匯入、碰撞保留與灰盒比較。

- [室外加油站探索測試](validation/2026-09-19-gas-station.md) — 同世界商店／維修間／後院、物資與步行驗證。

- [串流 CPU 效能與回歸檢查](validation/2026-09-18-streaming-performance.md) — `validation/2026-09-18-streaming-performance.md`
- [公路地形與沿途探索驗收](validation/2026-09-15-highway.md) — `validation/2026-09-15-highway.md`
- [RV 系統執行與驗收紀錄](validation/2026-09-15-rv-systems.md) — `validation/2026-09-15-rv-systems.md`
- [密林壓迫感與遠距入口：後續驗收](validation/2026-09-16-dense-forest.md) — `validation/2026-09-16-dense-forest.md`
- [怪物相對速度攀車與兩種破壞模式（2026-09-16）](validation/2026-09-16-monster-boarding.md) — `validation/2026-09-16-monster-boarding.md`
- [破口進出與車內追擊（2026-09-16）](validation/2026-09-16-monster-cabin.md) — `validation/2026-09-16-monster-cabin.md`
- [怪物追蹤與近戰修正（2026-09-16）](validation/2026-09-16-monster-pursuit.md) — `validation/2026-09-16-monster-pursuit.md`
- [室外恐怖氛圍與離路物資點驗收](validation/2026-09-16-outdoor-horror.md) — `validation/2026-09-16-outdoor-horror.md`
- [WAYFARER 車體與駕駛室原型](validation/2026-09-16-rv-cockpit.md) — `validation/2026-09-16-rv-cockpit.md`
- [RV 電池與設備互動修正](validation/2026-09-16-rv-interactions.md) — `validation/2026-09-16-rv-interactions.md`
- [RV 完整組裝、新底盤與可替換引擎驗收](validation/2026-09-16-rv-rebuild-engine.md) — `validation/2026-09-16-rv-rebuild-engine.md`
- [RV 底盤共用儲存與設備入口](validation/2026-09-16-rv-shared-storage.md) — `validation/2026-09-16-rv-shared-storage.md`
- [RV 分片車殼、車門與安裝槽驗收（2026-09-16）](validation/2026-09-16-rv-structure-doors.md) — `validation/2026-09-16-rv-structure-doors.md`
- [世界時間、太陽與日夜霧效 — 2026-09-17](validation/2026-09-17-day-night.md) — `validation/2026-09-17-day-night.md`
- [戶外霧效修正 — 2026-09-17](validation/2026-09-17-fog-refinement.md) — `validation/2026-09-17-fog-refinement.md`
- [室外與 RV 工業恐怖美術驗收](validation/2026-09-17-industrial-art.md) — `validation/2026-09-17-industrial-art.md`
- [正式戶外 D 風格驗收](validation/2026-09-17-outdoor-d.md) — `validation/2026-09-17-outdoor-d.md`
- [工業恐怖美術樣板驗收](validation/2026-09-17-style-sample.md) — `validation/2026-09-17-style-sample.md`
- [局部體積霧 — 2026-09-17](validation/2026-09-17-volumetric-fog.md) — `validation/2026-09-17-volumetric-fog.md`

## 設計研究

- [Lethal Company 視覺風格與 ApocalypseRV 差距研究](research/2026-09-17-lethal-company-visual-direction.md) — `research/2026-09-17-lethal-company-visual-direction.md`
- [《Lethal Company》恐怖氛圍設計研究](research/lethal-company-horror-atmosphere.md) — `research/lethal-company-horror-atmosphere.md`

## 美術目標

- [D：低模與低解析度修正版](art_targets/outdoor/2026-09-17-d-revision.md) — `art_targets/outdoor/2026-09-17-d-revision.md`
- [戶外目標圖：實際生成提示](art_targets/outdoor/2026-09-17-prompts.md) — `art_targets/outdoor/2026-09-17-prompts.md`
- [戶外 gameplay 美術目標圖](art_targets/outdoor/README.md) — `art_targets/outdoor/README.md`

## 歷史封存

- [Climbing and Combat Behavior](archive/2026-09-14/design/climbing-and-combat-behavior.md) — `archive/2026-09-14/design/climbing-and-combat-behavior.md`
- [Player Interaction Flow](archive/2026-09-14/design/player-interaction-flow.md) — `archive/2026-09-14/design/player-interaction-flow.md`
- [RV Equipment Interactions Design](archive/2026-09-14/design/rv-equipment-interactions.md) — `archive/2026-09-14/design/rv-equipment-interactions.md`
- [RV Power and Crafting Design](archive/2026-09-14/design/rv-power-and-crafting.md) — `archive/2026-09-14/design/rv-power-and-crafting.md`
- [World Generation and POI Pipeline](archive/2026-09-14/design/world-generation-and-pois.md) — `archive/2026-09-14/design/world-generation-and-pois.md`
- [World Generation Procedural Buildings](archive/2026-09-14/design/world-generation-procedural-buildings.md) — `archive/2026-09-14/design/world-generation-procedural-buildings.md`
- [ApocalypseRV - 遊戲設計企劃書（GDD）](archive/GDD.md) — `archive/GDD.md`
- [docs 已封存](archive/README.md) — `archive/README.md`
- [Architecture](archive/architecture.md) — `archive/architecture.md`
- [Monster AI Module Contract](archive/modules/monster-ai.md) — `archive/modules/monster-ai.md`
- [Player Traversal and Interaction Module Contract](archive/modules/player-traversal-and-interaction.md) — `archive/modules/player-traversal-and-interaction.md`
- [RV Systems Equipment Module Contract](archive/modules/rv-systems-equipment.md) — `archive/modules/rv-systems-equipment.md`
- [RV Systems Module Contract](archive/modules/rv-systems.md) — `archive/modules/rv-systems.md`
- [World Generation POI System Contract](archive/modules/world-generation-poi-system.md) — `archive/modules/world-generation-poi-system.md`
- [World Generation Procedural Building Module Contract](archive/modules/world-generation-procedural-building.md) — `archive/modules/world-generation-procedural-building.md`
- [World Generation Module Contract](archive/modules/world-generation.md) — `archive/modules/world-generation.md`
- [Monster Underfoot Raycast Single-Path Implementation Plan](archive/superpowers/plans/2026-04-09-monster-underfoot-raycast-single-path.md) — `archive/superpowers/plans/2026-04-09-monster-underfoot-raycast-single-path.md`
- [Monster Underfoot Attack Redesign (Raycast Single Path)](archive/superpowers/specs/2026-04-09-monster-underfoot-raycast-single-path-design.md) — `archive/superpowers/specs/2026-04-09-monster-underfoot-raycast-single-path-design.md`

## 資產與製作規格

- [建模 prompt](modeling/README.md) — 簡單物件直接做；複雜物件用灰盒與一份 [短 prompt](modeling/TEMPLATE.md)，不另維護進度清單。
- [2026-09-29 資產盤點與來源快照](archive/modeling-2026-09-29/inventory.md) — 歷史參考，不再日常更新；[來源說明](archive/modeling-2026-09-29/asset-provenance.md)。

- [Original industrial horror materials](../assets/materials/industrial/README.md) — `assets/materials/industrial/README.md`
- [正式戶外 D 風格素材](../assets/materials/outdoor/README.md) — `assets/materials/outdoor/README.md`
- [Concrete wall albedo](../assets/materials/poi_kit/README.md) — `assets/materials/poi_kit/README.md`
- [工業美術樣板材質](../assets/materials/style_sample/README.md) — `assets/materials/style_sample/README.md`
- [WAYFARER RV 模型原型](../rv/visuals/README.md) — `rv/visuals/README.md`
- [POI 資產樣板與製作規格](../world/poi_kit/README.md) — `world/poi_kit/README.md`
- [路旁資產模組](../world/roadside_kit/README.md) — `world/roadside_kit/README.md`
