# 教學出生點環境細節

2026-10-18，分支 `codex/tutorial-spawn-detail`，正式 v12 兩室基地。

## 內容

- 接待室新增接待桌／抽屜、紙本文件、椅子、原創區域地圖、時鐘、長椅、四格置物櫃、滅火器及終端框／配線／防滑墊。地圖是可編輯 SVG；小型物件採 Godot 原生幾何，沒有本輪 ComfyUI 生成資產。
- 維修室新增固定工具牆、扳手／鐵鎚、虎鉗、零件盤及桌下工具箱；兩室補上配電箱、門框護板、實體房號、排水格柵與四盞向下壁燈。
- 正式基地室內地板使用獨立材質，加入混凝土分縫、細裂紋、油漬及中央成對輪痕；外側前坪沿用原材質。新增塗裝材質重用原有舊金屬 shader。
- 靜態美術及碰撞分別為 [interior_details.tscn](../../world/orientation_shelter/interior_details.tscn)、[interior_details_collision.tscn](../../world/orientation_shelter/interior_details_collision.tscn)。沒有改動課程／存檔格式、物品 ID、原出生標記或門禁判定。

## 本輪檢查

Godot 4.7.2，PATH 安裝位置 `C:\Program Files\godot\godot.exe`。AGENTS.md 列出的舊安裝路徑本機無執行檔。

| 檢查 | 結果 |
|---|---|
| 新資產匯入 | PASS；`.godot/test-logs/20261018-195457-048-selected-21196/`。 |
| `test_orientation_shelter` | 最終 PASS；`.godot/test-logs/20261018-195803-561-selected-33372/`，場景分層、支撐、英文文字、門洞及車道。 |
| `test_orientation_warehouse` | 最終 PASS；`.godot/test-logs/20261018-195925-893-selected-26876/`，16 件原物資身份、連續膠囊接近路線、拾取視線、舊物資位置及八米車道。 |
| 新增幾何／邊界 | 419 個 MeshInstance、6,710 三角面；全部位於 building_bounds。新增預算為 10,000 三角面；原生簡單網格已低於預算，無需降面。全基地靜態總計 7,007 個 MeshInstance、548,160 三角面；不含執行時 RV、物品、角色、地形與文字。日誌 `.godot/spawn-detail/audit-final.log`。 |

首次倉庫檢查已印出全部行為 PASS，但結束時程序以 `-1073741819` 異常退出；沒有把該次記為通過。單獨重跑及維修桌最終位置檢查均正常以 0 結束。未修改引擎關閉或測試清理邏輯；既有關閉相容問題另見 [PR #46 紀錄](2026-10-18-pr46-ci.md)。

## 畫面與範圍

以正式主世界的 Forward+／08:00 整備光照，透過臨時相機擷取出生視角、接待室總覽、內門、RV 車道、維修區、桌面、置物櫃及工具牆。依畫面調暗初版地板、改用向下照明，並修正工具牆嵌入前牆的位置；最終近景可見工具板、桌面及虎鉗。最終程序正常結束，日誌 `.godot/spawn-detail/final-render.log` 無腳本錯誤。

這是實際世界的定點渲染檢查，沒有宣稱手動走遍基地或完成教學／駕駛，也沒有 FPS 基準測試。未跑完整套件或與本輪無關的攀爬／拆頂情境。

開啟 [orientation_playground.tscn](../../tests/orientation_playground.tscn) 按 F6，或正式主場景開新局，可檢視接待室的視覺密度、原終端可辨識度及維修室的布景。美術觀感仍由使用者驗收。

## 後續：整棟與第二室細化

依使用者要求擴展至全棟，沿用同一分支；上方接待區結果保留為前一輪紀錄。

- 兩室屋架新增斜撐及下弦、懸吊回風管／接縫／吊桿，側牆增加六組帶護網的排風扇與支架管線。第二室加入貨架實體編號、柱腳護板及六組帆布包覆貨堆，原物資與走道不移動。
- 接待室側邊加入水處理設備區；室外前坪加入備用發電機、配電櫃、排氣管、基座與防撞柱。直接重用既有 ComfyUI 來源的 `bunker_filtration_pump`、`bunker_diesel_generator`、`bunker_switchgear` 模型，碰撞另設於 Collision。
- 全棟外牆補上漆帶、基座、百葉檢修板、落水管與後側檢修蓋；入口增加實體招牌、緩衝件及雨棚燈殼。主樓與側翼分別貼合 Z=14.5／14.0 的原立面。
- 屋頂增加通風帽、檢修口、側翼維護踏墊；主屋頂改用有搭接縫、卷材色差及積灰的獨立防水材質。未新增房間或改動外殼、場址尺寸、出生點、課程及存檔。
- 美術／碰撞集中於 [building_details.tscn](../../world/orientation_shelter/building_details.tscn)、[building_details_collision.tscn](../../world/orientation_shelter/building_details_collision.tscn)。原創帆布是可編輯的 [OBJ](../../assets/models/depot_canvas_cover/depot_canvas_cover.obj)，材質程序生成。

整棟擴充模組的預算為 60,000 三角面，最終 **748 個 MeshInstance／54,369 三角面**，包含上述三個既有生成模型；新增所有可見網格均在原 building_bounds 內。重用模型保留原有預算與來源；原生結構已足夠精簡，未為本輪再次降面。沒有 FPS 基準測試。

最終相關驗證：`test_orientation_shelter`、`test_orientation_warehouse` **2/2 PASS**，含匯入；日誌 `.godot/test-logs/20261018-212612-261-selected-33272/`。外部發電機、防撞件與門邊緩衝件加入後，`test_orientation_departure` 的原生輪驅出庫也 PASS；該次三項皆通過，日誌 `.godot/test-logs/20261018-212143-024-selected-25140/`。之後僅修正高處護網／吊架、上層貨堆和材質，未改動出庫區碰撞。

正式主世界 seed 42、Forward+ 定點檢查第二室入口、貨架、屋架、接待室、水設備、正面／側面／背面、發電機與屋頂，共 13 個視角；修正護網支撐、風管吊架接觸及帆布角落穿插後，最終日誌 `.godot/depot-whole-building/review-final.log` 正常結束且無腳本錯誤。最後屋頂材質另以兩視角複查，`.godot/depot-whole-building/roof-final.log`。沒有人工走遍基地或手動完成教學。

另以內建 ImageGen 製作了新空壓機的透明參考圖，依 [生成技能](../../.agents/skills/comfyui-image-to-3d/SKILL.md) 取得使用者確認後，完成下方 ComfyUI 生成與整合。

開始本輪時已有使用者的 `project.godot` 輸入序列化修改，保持原樣且不納入本輪提交。

## 後續：ComfyUI 空壓機

同日使用者確認參考造型，單次本機 TRELLIS.2／1024／seed 42 工作約 79 秒完成。原型 49,910 面，經 Y+90° 朝向與尺寸校正、gltfpack 1.3 減面後為 **4,990 面／6,490 頂點**，低於單件 5,000 面預算；三張 PBR 圖片 bytes 保留。原始 GLB 與生成紀錄保留在忽略工作目錄，交付 [正式資產](../../assets/models/depot_air_compressor/README.md)、[可編輯來源與參考圖](../../art_source/depot_air_compressor/README.md)。

模型放於第二室前牆旁 `(-16.8,0.03,12.95)`，尺寸 1.45 × 0.95 × 0.65 m，服務面朝 −Z；輪／腳最低點與設備墊頂 Y=0.03 貼合，獨立盒碰撞與模型包圍盒相差不到 1 mm。保留原物資及接近路線，新增一盞實體壁面工作燈。空壓機為固定布景，沒有新增教學任務或可操作空壓系統。

整棟擴充模組加上空壓機與燈殼後合計 59,395 三角面（原 54,369＋空壓機 4,990＋燈殼 36），仍低於 60,000 面預算。

檢查原型與減面版的六視角、材質及素色幾何；把手開孔、儲氣桶、壓力錶與兩輪保留，輪轂及小型散熱鰭片有所簡化。拓樸限制及原始來源雜湊記於資產來源 README，未將技術匯出成功冒充可製造網格。

`test_orientation_shelter`、`test_orientation_warehouse` **2/2 PASS**，含資產匯入；日誌 `.godot/test-logs/20261018-213740-176-selected-34132/`。實際主世界三個玩家高度定點檢查尺寸、貼地、朝向及走道可見性，補燈後複查；最終日誌 `.godot/art-work/depot_air_compressor/run-01/context-final.log` 正常結束，支撐／碰撞尺寸核對通過。未重跑與新增角落布景無關的整段出庫或完整套件，未宣稱手動遊玩。

## 後續：貨架布景辨識與接縫閃爍

依使用者回饋，96 個使用設備道具箱外觀的固定布景全部改成 [自製封箱紙箱](../../assets/models/warehouse_carton/README.md)：倒角紙箱、牛皮紙、封箱膠帶與包裹標籤，沒有把手、設備鎖扣或 Item 行為。單件 44 三角面，低於 100 面預算；保留中心原點、1 × 0.6 × 0.7 m 尺寸及原實例縮放。實際可拾取物資與 RV 設備不改。

貨架原木層板與橘色側梁的頂面重疊寬 3 cm，梁端也與橫梁／立柱產生共面外露。木板寬度改為 1.42 m、側梁長度改為 4.14 m，消除外露面的重疊；交叉斜撐分層並補穿接螺栓。所有承放頂面、原物資位置及獨立碰撞維持原樣。

`test_orientation_warehouse` **PASS**，含資產匯入；`.godot/test-logs/20261018-215645-050-selected-28180/`。正式主世界以五個定點檢視紙箱、上下層板邊、梁端與走道，並核對 96 個新模型的包圍盒與原碰撞一致（1 mm 容差）、木板／側梁頂面交疊為 0。最後修整梁／立柱接合後另複查兩個近景；最終日誌 `.godot/warehouse-cargo-fix/review-final.log`。沒有人工遊走或完整套件驗收宣稱。

後續腳部清理：移除 `building_details.tscn` 中與立柱重疊的 24 個 `RackFootGuard` 裝飾及專用網格，保留原貨架立柱與底板。正式主世界左右腳部及整排三個定點渲染已檢視；24 座貨架、96 支立柱與 96 片底板數量正確，所有立柱底面位於地面且與原碰撞位置及尺寸一致。最終日誌 `.godot/warehouse-foot-fix/review-final.log` 正常結束。此輪僅刪除視覺節點，未重跑先前的行為套件，未宣稱手動遊玩。

## PR #47 CI：室外串流基準同步

2026-10-19：[PR integration](https://github.com/Kelsier64/ApocalypseRV/actions/runs/39141325575/job/117716191659) 與 [push integration](https://github.com/Kelsier64/ApocalypseRV/actions/runs/39141307744/job/117716138996) 均僅 `test_poi_instances` 的室內／室外串流隔離斷言失敗；同批 quick、slow、assets、smoke 通過。兩份失敗紀錄都在進入 POI 後繼續生成正常室外 band 3，且發布完成落在斷言之後，沒有生成室內座標 Z=-2000 附近的區塊。這支 fixture 使用 v6，並未載入本輪 v12 美術。

原等待發生在把玩家移至入口之前；之後取樣時，入口位置所需的串流視窗仍可能未完成。測試改為先等待室外錨點所需的完整區塊集合（含保護帶）、導航及生成工作完成，再移動室內玩家。移動後跨越兩個 process frame，確保串流更新實際執行；斷言同時檢查區塊索引集合、無生成工作及原室外錨點，取代僅比較數量。沒有修改遊戲串流邏輯、等待期限或 runner 判定。

本機原版一次通過，未宣稱穩定重現；最終修正版 `test_poi_instances` **PASS，8.74 秒、退出碼 0**，完整進出、物品保存與導航斷言保留。命令：`./scripts/test.ps1 -Godot 'C:\Program Files\godot\godot.exe' -TestFilter 'test_poi_instances.gd' -SkipImport`；日誌 `.godot/test-logs/20261019-002646-469-selected-21796/`。另在忽略目錄以衍生生成器刻意讓室內座標驅動室外串流，新斷言如期拒絕（區塊由 `[-2,-1,0,1,2,3]` 變成空集合且 `building=true`、退出碼 1）；證據 `.godot/pr47-ci/wrong-anchor.log`。對照腳本未交付，未在本機重跑完整 integration 組。

## PR #47 CI：共用訓練 fixture 的關閉相容處理

`26160fc` 的 [push integration](https://github.com/Kelsier64/ApocalypseRV/actions/runs/39145143334/job/117727353590) 已通過。另一次 [PR slow](https://github.com/Kelsier64/ApocalypseRV/actions/runs/39145146642/job/117727363311) 則在 `test_training_workshop` 印出完整 PASS 後以 `-1073741819` 退出，沒有行為斷言失敗；退出碼與時機符合 [先前定位的 Godot 4.7.2 腳本關閉問題](2026-10-18-pr46-ci.md)。本機原版一次正常退出，未宣稱每次可重現。

原 `Item` 基底參照只存在於 completion，直接執行 workshop／maintenance 未涵蓋。本次將既有 static 參照移至共用 workshop 基底，由 workshop → maintenance → completion → journey 共用單一定義；沒有修改交易、駕駛、關閉等待或 runner 判定。

本機四個獨立入口 **4/4 PASS，退出碼皆為 0**：completion 67.41 秒、journey 36.15 秒、maintenance 32.20 秒、workshop 26.18 秒。命令：`./scripts/test.ps1 -Godot 'C:\Program Files\godot\godot.exe' -TestFilter 'test_training_workshop.gd,test_training_maintenance.gd,test_training_completion.gd,test_training_journey.gd' -SkipImport`；日誌 `.godot/test-logs/20261019-004416-082-selected-25884/`。這是移動相容參照後的驗證，不將本機通過冒充遠端完整 CI 結果。
