# 自動測試

從專案根目錄執行 [scripts/test.ps1](../scripts/test.ps1)。Godot 版本由 [.godot-version](../.godot-version) 固定。

```powershell
# 日常行為檢查，預設 quick
./scripts/test.ps1
# 不啟動引擎，列出選取範圍
./scripts/test.ps1 -Suite full -List
# 全部有效回歸及正式主世界啟動
./scripts/test.ps1 -Suite full
# 僅選相關測試；若需要主世界就緒檢查，加 -Smoke
./scripts/test.ps1 -TestFilter 'test_bunker_*.gd,test_interior_*.gd'
# 同一批程式修改的後續執行，資產未變且已匯入時可省略匯入
./scripts/test.ps1 -TestFilter test_player_inventory.gd -SkipImport
# 只驗證正式世界地形、導航、玩家就緒與移動
./scripts/test.ps1 -Suite smoke
# 不需 Godot 的 runner 自我測試
./scripts/test-runner.tests.ps1
```

## 分組與覆蓋

`test_slender_speaker_encounter`、`test_slender_speaker_parked_attack` 新增精確最後看見位置、最近可見屋頂及後艙→中艙→前艙的剩餘車頂順序。`test_slender_speaker_chassis_smash` 以正式玩家、RV 與手部動畫驗證玩家藏到另一處後，巨人自主砸向舊位置並落空；既有未知乘員檢查仍不能砸擊裸底盤。驗證紀錄見[最後看見位置與最近車頂](../docs/validation/2026-10-10-slender-speaker-last-seen-attack.md)。

`test_slender_speaker_fog_spawn` 屬 quick，驗證生成器只讀所屬世界實際霧量、小霧 0.5 的含邊界門檻、起霧／散霧過渡、單純下雨及缺少時鐘的拒絕。`test_slender_speaker_world` 屬 integration，以正式森林與導航驗證無霧略過不補刷、已有巨人在無霧 checkpoint 中還原，以及讀檔後起霧回訪仍不補刷。[本輪紀錄](../docs/validation/2026-10-10-slender-speaker-fog-spawn.md)。

`test_slender_speaker_encounter` 屬 quick，以觀測資料測試單一 encounter owner：車上／車外身分、低於 6 km/h 持續 0.5 秒及高於 10 km/h 持續 0.75 秒的模式切換、動作提交與延後變更、8 秒搜尋、可見屋頂初次檢查、已知乘員搜尋逾時後轉為未知乘員拆頂，以及未知檢查過期抑制，另驗證真正拆頂進展延續搜尋、同身分緩存期限合併及下車期限隔離。`test_slender_speaker_encounter_drive` 屬 integration，使用自由 playground 的同一名正式 Player 與同一台未固定 RV，經正常車內移動、駕駛座互動、輪胎加速及服務煞車，驗證落空後重新接近、追車與停車再接近；不以設定角色位置、車速、AI 階段或目標代替執行中的操作。`grab_tracking` 另驗證真實遮擋下不讀取隱藏姿勢、伸手末段鎖定及觀測路線卡住後實際向外走。這些覆蓋描述不代表本輪原生畫面或 full suite 已完成；目前結果及限制見[持續遭遇驗證](../docs/validation/2026-10-09-slender-speaker-encounter.md)。

`test_slender_speaker_playground_equipment`、`test_slender_speaker_playground_tracking` 屬 integration，直接載入自由 playground、正式 new_rv 與引擎物理回呼，不固定底盤、不強制攻擊階段：驗證屋頂設備拆除到駕駛抬升，以及後艙換位／持續走動後自主拆頂抓取。`test_slender_speaker_execution_floor_contact` 驗證微小地板／側面接觸、世界座標精度、完整形狀掃掠及頂板／深層重疊阻擋。[本輪結果](../docs/validation/2026-10-09-slender-speaker-live-playground.md)。

`test_slender_speaker_chassis_smash` 另驗證已知乘員搜尋逾時後轉為未知乘員拆頂：正式玩家先被看見，再由碰撞幾何遮擋，經過完整 8 秒物理步倒數後，自主拆除舊觀測區域外的剩餘屋頂。要求兩次實際 60 傷害接觸、玩家持續不可見、沒有盲抓或底盤傷害；固定車身與玩家隔離該轉換，倒數後使用完整導航與攻擊控制器。[本次回歸結果](../docs/validation/2026-10-10-slender-speaker-lost-survivor-roof.md)。

`test_slender_speaker_playground_corners` 屬 integration，直接載入 mode 0 的正式車輛，涵蓋四個車艙角落與拆頂後持續橫越後艙的正式輸入。測試保留輪胎與懸吊物理、自主感知及手部接觸，要求抓取持續完成抬升到 HOLD；第一幀抓取成功後立即取消不能通過。後艙 tracking 也已延長至完整抬升；[本輪結果](../docs/validation/2026-10-09-slender-speaker-corner-lift.md)。

`test_slender_speaker_open_roof_attack` 屬 integration，覆蓋部分／全部拆頂、未拉手煞車自然慢滑、車內正常走動後停下，前四組要求第一次抓住後完整抬升且沒有放開。未穩定懸吊的第五組只要求自主出手與真接觸；另檢查記憶轉向不受 1.15 m 導航邊界干擾，也不能直接攻擊。`target_switch` 增加車外另一側與貼近裸底盤的繞行抓取。[驗證與限制](../docs/validation/2026-10-09-slender-speaker-open-roof.md)。

`test_slender_speaker_turning`、`test_slender_speaker_head_look` 屬 integration，驗證 90°／135° 轉角的前進、轉身步態及到位，與真實頸骨轉角／速度限制、手臂隔離、音箱視野、牆遮擋及回到原抓取姿勢。[本輪結果](../docs/validation/2026-10-09-slender-speaker-head-look.md)。

`test_slender_speaker_patrol` 屬 integration，使用正式 RV、實際感知與正常 8 秒期限，驗證空車遭遇過期後在未烘焙車殼的導航網格上繞行、兩個連續巡邏點到達、兩種車身朝向、轉角不中斷及車內巡邏點跳過。巨人保持真實碰撞與自主階段，不以傳送或強制目標推進。`turning` 另以 30／60／120 Hz 實際物理步測量左右連續轉彎的位移／身體側向分量，並檢查倒退先煞停、再以正常加速度起步。

`test_slender_speaker_forest_tracking` 屬 integration，使用正式 v10 seed 42、區段 11 的自然森林生成與相鄰地形，啟用巨人控制器驗證 60 秒連續徘徊、坡面追玩家、真實樹幹碰撞後脫困，以及道路上的 RV 輪驅追蹤。導航高度差必須超過原路徑容差；脫困保留樹木與連續碰撞移動。測試期間停止串流、凍結車外玩家，RV 使用測試輸入驅動真實輪胎；不代表所有 seed、串流中追擊或玩家自由移動已驗收。見[正式森林導航修正](../docs/validation/2026-10-10-slender-speaker-forest-tracking.md)。

`test_slender_speaker_cabin_movement`、`test_slender_speaker_grab_tracking` 屬 integration：正式 Player 輸入／碰撞下持續前後和左右走動、固定站位及朝向、實體遮擋與無即時 RV 目標的記憶防撞、伸手前段有限追蹤／末段鎖定，以及撞上實體障礙後向外走的恢復。車內移動使用獨立 60 秒自主拆頂準備、8 秒連續移動及 20 秒靜止恢復期限；真實接觸抓到玩家才可提前結束移動，不讓拆頂耗盡移動與恢復預算。[初次驗證](../docs/validation/2026-10-09-slender-speaker-cabin-movement.md) · [後續期限及右後角修正](../docs/validation/2026-10-10-slender-speaker-cabin-corner-fix.md)。

`test_slender_speaker_grab_reliability` 屬 integration：手掌實際接觸拆除、指尖擦碰容許、4 m/s 逃離，以及左右車側十個實際站位偏移；`acquisition` 使用正式站姿、攀爬、屋頂與駕駛座姿勢驗證接觸、抬升及手肘連續性。[本輪結果](../docs/validation/2026-10-09-slender-speaker-palm-demolition.md)。

車內持續移動另有 `--native-physics` 模式，由引擎物理回呼驅動兩個角色，以不同渲染時序檢查相同情境；此模式不指定 `--fixed-fps`，也不執行需要手動控制位置的局部速度探針：

```powershell
godot --headless --path . --log-file .godot/cabin-movement-native-physics.log --script res://tests/test_slender_speaker_cabin_movement.gd -- --native-physics
```

`test_slender_speaker_cross_cabin_reach` 屬 integration：正式玩家以實際輸入橫越 2.33 m，巨人保持原側，透過真實手部接觸與完整抬升到 HOLD 驗證 4.47 m 伸手；另一案例檢查超出 5.5 m 後重新定位。`grab_reliability` 與 `playground_equipment` 驗證抓取保留設備並受其阻擋、移開設備後正常抓取，以及砸擊設備每拳扣 60 耐久、同拳不重扣、未歸零保留碰撞與服務，後續砸擊歸零才摧毀。`test_slender_speaker_foot_player` 屬 integration，驗證正式骨架腳部掃掠造成 40 HP、持續接觸不重扣、分開後再次接觸、既有受傷冷卻、實體遮擋與死亡流程。見[本輪驗證](../docs/validation/2026-10-10-slender-speaker-cross-cabin.md)。

`test_slender_speaker_roof_approach` 屬 integration：自由 playground 三片屋頂完整、未拉手煞車、正式玩家在後艙左右兩側，驗證巨人進入可達區域後 3 秒內開始拆頂，實際掃掠拆除選定屋頂且其他屋頂／底盤完整。另檢查伸距、側向間距、縱向偏差、繞行及未就緒導航的拒絕邊界。見[完整屋頂接近驗證](../docs/validation/2026-10-10-slender-speaker-roof-approach.md)。

`test_slender_speaker_continuous_roof_encounter` 屬 integration：完整屋頂、真實輪胎懸吊與未拉手煞車，分別測中艙／後艙初始站位，以及正常離開駕駛座後步行到中艙／後艙。四案均須由實際拆頂、手部接觸，一路到完整抬升 HOLD，並逐步排除車體攻擊／底盤傷害；每片 120 耐久屋頂至少收到兩次 60 傷害，第一拳後不得丟失尚未拆完的屋頂遭遇。另驗證開孔屋頂兩側實體落點、屋頂乘員保護、同一規劃器在 0.5–3° 側傾時落點仍位於實體表面。`test_slender_speaker_encounter` 檢查移動玩家的精確最後看見位置、車內記憶砸擊授權及隱藏資料拒絕、8 秒乘員搜尋及逾時後未知乘員拆頂轉換。見[中後艙驗證](../docs/validation/2026-10-10-slender-speaker-hatch-and-rear.md)。

`test_slender_speaker_target_switch` 與 `test_slender_speaker_standing_attack` 屬 integration：前者以正式 playground、離座／步行輸入、真實感知與手部接觸檢查下車後目標切換、遮擋與伸手期間的目標穩定；後者檢查站立乘員的拆頂、跨艙同側抓取與完整處刑流程。此次結果及物理阻擋限制見[車內外鎖敵驗證](../docs/validation/2026-10-09-slender-speaker-target-switch.md)。

`test_slender_speaker_free_play` 屬 integration，載入正式 playground，透過正常輸入事件驗證輪驅起步、煞停／再起步、R 升檔、離座步行、重新入座、37 秒以上自由操作、巨人切換、暫停／重設及離開重播。`test_slender_speaker_parked_attack` 另涵蓋車後／右侧追車轉停車時的實際感知、車側導航與屋頂命中，並保留音箱視角／牆遮擋測試。

Slender Speaker：`test_slender_speaker_spawns` 屬 quick，驗證 v10 獨立森林規劃；`test_slender_speaker_animation` 屬 assets，核對正式模型、材質、骨架、掌向、步態接續與手臂擠壓；`behavior`／`acquisition`／`execution`／`moving_attack`／`world` 屬 integration，分別覆蓋視覺與攻擊、正式玩家／RV 接觸、共用玩家所有權與死亡、跟車攻擊／急停／步態，以及正式森林導航／checkpoint／回訪。測試範圍與結果見 [整合驗證](../docs/validation/2026-10-09-slender-speaker-pr.md)，重播操作見 [行為測試場](../docs/guides/playgrounds.md#slender-speaker-runtime)。

`test_road_spawns_v9` 屬 quick：4,096 seeds 的數量與獨立油桶／油桶人抽選、逐件位置／朝向、近距離及連續區段、實際廢車碰撞、安全區與舊版本隔離。道路生命週期及檢查點測試同時保留 v8 回歸，新增 v9 混合怪物與普通油桶的導航發布、休眠／移動保存、爆炸與回訪不補發。結果與畫面見 [v9 公路驗證](../docs/validation/2026-10-07-independent-road-spawns.md)。

`test_oil_barrel_vehicle_contact` 屬 integration：正式一般油桶與 RV 的低／高速、倒車、側面輪槽、車外固定梯架、固定桶與靜止接觸；低速／靜止接觸不爆，高速合格撞擊檢查單次爆炸、引擎 60 HP、沒有重複撞擊扣血、Item 保存、預覽／自車固定貨物保護及爆風不連鎖。`test_oil_barrel_drop` 驗證正式 G 拋出速度、停車／移動與轉彎車上拋桶、剛離座立即丟出不重複疊加車速、車壁重疊修正、空間不足保留物品及高處拋出爆炸。`test_oil_barrel_fall` 同屬 integration，涵蓋 1.9／2.1／4 公尺真實掉落、空中側碰、固定支撐釋放、低處世界轉移與空中保存還原。F10 輪驅重播另驗證持續油門下的實際撞桶與車殼損傷。

一般油桶駕駛視角重播：`godot --path . --fixed-fps 60 --resolution 1280x720 --log-file .godot/oil-barrel-driver-pov.log res://tests/barrel_man_playground.tscn -- --oil-barrel-replay --driver-pov --capture --headless-check`。`--driver-pov` 也適用 `--vehicle-replay`／`--chase-replay`，以正式玩家操作正式駕駛座入座，保留車殼遮蔽與玩家正常傷害；額外檢查爆炸時駕駛相機仍為目前相機。`--headless-check` 令重播在 18 秒後完成行為檢查並退出；只有實際顯示模式會保存畫面，真正 `--headless` 執行不驗證渲染。爆炸後含 0.05、0.12、0.2、0.4、0.8、1.5 秒的早期畫面，並記錄目前相機路徑、位置及火／煙體積中心的視角 Z（負值在相機前方）。畫面位於 `.godot/barrel-playground-captures/`。互動場景 F11 啟動駕駛視角撞一般桶；F10 回到外部視角重播，R 重設目前模式。

`test_barrel_blast_render` 屬 integration。日常 headless runner 檢查正式駕駛座／相機所有權、三維特效邊界及無遊戲碰撞；原生執行 `godot --path . --fixed-fps 60 --log-file .godot/barrel-blast-render-native.log -s res://tests/test_barrel_blast_render.gd` 額外比較 1280×720 的實際畫面，驗證早期駕駛火焰、進入煙火體積、反向／側面視角與完整不透明牆遮蔽。可加 `--rendering-method gl_compatibility` 驗證 Compatibility。測試會保存特效開／關畫面至 `.godot/barrel-blast-render/`，排除閃光燈、火花與碎片以免它們代替真正火／煙通過檢查；headless 的 `SKIP` 不代表像素檢查通過。

油桶人 `test_barrel_man`、`test_barrel_explosion`、`test_barrel_vehicle_contact`、`test_barrel_man_persistence` 屬 integration，覆蓋感知、偽裝、真實接觸、爆炸遮蔽／斷肢／車殼、生成與保存。`test_barrel_man_assets` 屬 assets，逐幀驗證匯入蒙皮、十組動畫、桶內折腿、桶壁交界與地面。另有 [油桶人展示場](../docs/guides/playgrounds.md#barrel-man) 的真實輪驅、連續玩家輸入及坡面重播；畫面與本次結果見 [驗收](../docs/validation/2026-10-07-barrel-man.md)。

Item 統一流程新增 `test_item_player.gd`（quick）：正式玩家驗證背包／手臂拒收不拆支撐、F 長按拾取與短按抑制、獨立預覽、取消／G、確認後消耗、角色重疊及失效支撐鏈拒絕、拆牆掉落後重新拾取，以及新物品／空油桶的完整狀態與 ID 保存。目前預覽操作會暫時隱藏手持模型，物品保留在背包，取消後恢復顯示；觀察與測試須分別檢查顯示和所有權。`test_item_services.gd` 覆蓋共用物品、服務／回收與怪物免傷；`test_item_persistence.gd`（integration）覆蓋 v5 與跨領域狀態；`test_item_navigation.gd`（integration）以實際怪物碰撞驗證多件固定 Item 的繞行、移除後恢復直路，以及封閉障礙無路時等待。實機入口 `item_playground.tscn` 見 [Item 測試場](../docs/guides/playgrounds.md#unified-item)。完整套件、smoke 與實機結果見 [本輪驗證紀錄](../docs/validation/2026-10-06-unified-items.md)，各階段結果保留當時的顯示行為。

車體改版由 `test_rv_structure_modules`、`test_structure_construction`、`test_rv_structure_snapshot` 與既有車輛、支撐、登車及存檔測試共同覆蓋。平板滑鼠操作與拆穿地板的原生觀察見 [2026-10-05 驗證紀錄](../docs/validation/2026-10-05-rv-structure-construction.md)，拆地板為當時功能；現行地板固定屬於底盤，沒有獨立破壞或平板施工操作。互動場景為 `rv_structure_playground.tscn`，操作見 [測試場指南](../docs/guides/playgrounds.md)。

[suites.json](suites.json) 是完整清單，每支頂層 `test_*.gd` 必須恰好分類一次。新增測試、遺漏分類、重複分類或不存在的檔案都會讓 runner 在引擎啟動前失敗。

| 分組 | 範圍 |
|---|---|
| `quick` | 隔離的背包、耐力、互動、攀爬契約、能源／資源交易、起始場址等行為 |
| `integration` | 有限情境的物理、導航、設備、POI 轉場、保存與世界重建 |
| `slow` | 多 seed 掃描、完整步行路線、反覆重建、長時間車輛情境 |
| `assets` | 匯入、蒙皮、骨架姿勢、外觀與資產規範驗收 |
| `smoke` | [main_scene_smoke.gd](main_scene_smoke.gd) 的正式世界就緒與移動 |
| `full` | 所有有效分組及 smoke；排除有原因記錄的重複項 |

`test_raker_boarding` 與 `test_moving_rv_climbing` 的預設 Raker 情境完全相同，因此清單記錄為 retired，保留檔案供舊命令直接執行，也可明確以 `-TestFilter` 選取。舊 v2–v6 地形與 legacy 世界 fixture 仍保留回歸；其保存改用 v5 檢查點，不代表接受舊版檢查點。`test_main_world_monsters` 的名稱保留，但其內容明確標示 legacy v5 fixture。正式 v10 主世界由 smoke 與 starting 系列涵蓋。

每支測試仍使用獨立 Godot 程序。本機不平行跑會共享磁碟 checkpoint 或全域服務的測試。GitHub Actions 以五個獨立 job 跑 quick、integration、slow、assets、smoke，涵蓋與 full 相同的有效測試；一組失敗不取消其他組。

CI 的 quick job 同時以 Windows PowerShell 5.1 與 PowerShell Core 執行 runner 自測。v10 巨人導航發布、啟動取消與受限工作池回歸見 [CI 修正紀錄](../docs/validation/2026-10-09-ci-navigation.md)。

## 執行與診斷

Runner 核對引擎版本，先匯入一次，再用 `--fixed-fps 60` 執行 headless 測試。這會解除實時等待並保持固定模擬步長；不縮短物理情境、減少 seed、調高物理 Hz 或改 `Engine.time_scale`。`-RealTime` 停用此選項，適合對照實時排程。資產匯入本身不使用加速。

每個程序都檢查退出碼、非空日誌、錯誤訊息與 `PASS:`；smoke 必須有 `WORLD_READY_FOR_PLAY` 標記。預設逐支跑完以收集所有失敗，最後以非零狀態結束；`-FailFast` 可在第一個失敗後停止。匯入失敗則立即停止後續測試。

`-TimeoutSeconds` 是每個程序的上限，預設 240 秒。超時會終止該測試與其子程序並記錄 `TIMEOUT`；若子程序清理失敗，停止後續測試並保留原因，避免殘留程序污染下一項。`-StartAt test_name` 從選取清單中的指定名稱接續；它不代表前面的測試已通過。`-TestFilter` 覆蓋分組，逗號分隔的樣式會合併、去重、按名稱排序；每個樣式均須選到測試。`-Suite full -TestFilter ...` 也只跑符合樣式的測試，需要 smoke 時明確加 `-Smoke`。

每次執行建立 `.godot/test-logs/<時間>-<分組>-<PID>/`，包含環境與工作樹清單 `manifest.txt`、結果及錯誤原因 `results.json`、耗時 `timings.csv` 與各支日誌，並在終端列出最慢五項。選取清單與實際結果分開記錄，可看出 FailFast 後未執行項目。資產測試的 JSON 證據位於 `.godot/test-logs/player_import_v020/`、`player_animation_skin/`、`player_ragdoll_v020/`，供最新一次檢查使用，不覆寫 `docs/validation/` 的歷史紀錄。

## 維護

優先驗證可觀察行為與公共契約。固定舊版三角形數、節點總數、某個歷史 helper 必須不存在等斷言，只有在它仍代表目前契約時才保留。資產來源與數值驗收留在 assets；相容性要求保留明確版本與 fixture。

等待非同步導航、生成或候選世界回收時，使用 [support/test_wait.gd](support/test_wait.gd) 的條件與期限，失敗要說明未就緒的工作。真實移動、穩定性、耗電或傷害情境仍保留原本模擬時段；不要把有意義的物理採樣全部改成「成功就提早停止」。純資料檢查不要建立完整主世界。

`--fixed-fps` 等待背景工作時仍會推進角色模擬。純場景準備期間應先停用被測角色，確認預期區塊數與導航就緒後再恢復；隔離環境怪物要涵蓋延後生成的 actor。`test_outdoor_encounter` 保留正式追逐、輪驅與煞車採樣，只在地形／導航準備階段凍結角色。數值邊界 fixture 明確設定測試參數，另驗證目前玩法預設，避免調整玩法數值使舊倒數斷言失效。

Headless 與實機觀察分開記錄；車輛或攀爬行為變更仍遵循 [AGENTS.md](../AGENTS.md) 的互動驗收要求。歷次結果見 [文件索引](../docs/README.md)，本輪改版與耗時見 [2026-10-01 驗證紀錄](../docs/validation/2026-10-01-test-runner.md)。

## 設定與原生顯示驗證

`test_game_settings.gd` 屬 quick，驗證偏好遷移、範圍、畫質預設、viewport 套用與保存；`test_settings_menu.gd` 屬 integration，驗證真實輸入、持續物理、傷害、入座、攀爬支撐及室內路由。

GPU 後製與視窗尺寸另用有期限的原生驗證腳本，不列入 headless suites。腳本使用隔離偏好檔，結束時恢復視窗與設定；輸出放在 `.godot/test-logs/settings-display/`。

```powershell
godot --path . --resolution 1280x720 --log-file .godot/test-logs/settings-display/native.log --script res://scripts/validate_settings_display.gd
godot --path . --resolution 1280x720 --rendering-method gl_compatibility --log-file .godot/test-logs/settings-display/compatibility.log --script res://scripts/validate_settings_display.gd
```

加上 `-- --manual-interior` 可開啟採用正式 PoiInstanceManager 的小型室內 fixture，提供 180 秒手動 Esc／GUI 驗收。此模式不宣告自動檢查通過；自動 GPU 證據、桌面操作與未驗證情境分別見 [設定選單驗收](../docs/validation/2026-10-03-settings-menu.md)。


## 大型物品與攀爬

`test_player_climbing.gd` 與 `test_player_inventory.gd`（quick）覆蓋 active_item.is_large、空手／小物、移除後恢復及玩家拒絕車壁的 gate。`test_player_large_item_climbing.gd`（integration）使用正式玩家與 RV，覆蓋 HUD 不重刷、世界拾取／倉庫取出時安全脫離、消耗／存入／丟棄後恢復、拒收不影響既有攀爬、物品 ID／狀態與平台速度交接。

```powershell
./scripts/test.ps1 -TestFilter 'test_player_climbing.gd,test_player_inventory.gd,test_player_large_item_climbing.gd,test_moving_rv_climbing.gd,test_player_carry.gd,test_rv_shared_storage.gd' -Smoke
```

2026-10-04 `855a17e` 的相關 quick／integration 回歸及正式世界 smoke 已在 CI 通過；整體 CI 仍有既存失敗與戶外測試不一致，不能宣稱 full suite 通過。上述命令可供重跑，完整證據見 [本輪紀錄](../docs/validation/2026-10-04-issues-8-17.md)。2026-10-04 該輪沒有本機引擎執行或原生視窗／實機觀察。實機需依 AGENTS 驗證持大型物品貼牆 W 的提示節制、丟棄／存入後攀爬恢復，以及移動／轉彎車身上拾取大型物品時不瞬移且物品仍可丟棄。原有登頂、拆頂與怪物攀爬仍須回歸。

## 可搬移 RV 梯子

`test_rv_ladders.gd`（quick）使用正式側門梯、車內梯及三片屋頂碰撞，覆蓋兩種模式的自由貼牆放置、連續瞄準與 5 cm 細移、地板／天花板／活動門扇拒絕、上下梯、關門阻擋、封住開口、移動車輛、搬移／取消、毀壞、實際牆面支撐失效與 v5 保存。大型物品與動畫測試使用真實梯子，怪物仍沿用車壁。當次執行結果與原生觀察見 [貼牆梯子重做驗收](../docs/validation/2026-10-05-rv-wall-ladders.md)。
