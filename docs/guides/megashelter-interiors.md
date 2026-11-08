# 巨型避難所室內

2026-11-01：`modular_megashelter` 使用 `INSTANCE_ENTRANCE`，入口轉入獨立 World3D 的 `megashelter` profile。外殼仍是封閉無窗的內容 v7，主要房間集中在地面一層，室內另有獨立樓梯間通往地下地堡。正式世界生成為 v19；Checkpoint v7／VehicleSnapshot v6 不變。v18 舊局須重新開局，沒有資料遷移。

## 配置與內容

每棟必有入口及大廳，再選三至五個功能房間與少量連接空間，通常共六至八個模組。`MegashelterInteriorLayout.generate(seed, exterior_area, profile)` 依外部量體的水平面積總和選擇模組尺寸，避免靠增加大量房間填滿建築。接口、占地、連通性與內容版本共用 `InteriorLayout.validate()`；不使用地堡的地下樓梯、30–60 房配置或引擎目標。

室內採民用避難所用途、老化混凝土與鋼件、固定燈具及局部黑暗。全新場址只配置二至四件散放物資與一個補給箱；沒有敵人或升級引擎獎勵。補給箱沿用持續搜索及每次一件的物品交易。遊戲中的提示使用英文。

2026-11-03 照明：地面層、勤務樓梯間與地堡都使用零環境底光及獨立的短距離[室內灰階設定](../../world/instances/interior_dark_adaptation.tres)。近身保留較暗的灰階輪廓，3 m 外無灰階補光；燈照不到的位置接近全黑，手電筒保留原照明距離與電量。固定燈具加強局部衰減、柔和陰影與 Forward+ 接觸遮蔽。地面層依保存 seed 選取約一半功能房熄燈，接待室、大廳與主要通道保留照明；地下地堡沿用自己的 60% 規則。詳見[灰階指南](night-vision.md#副本的短距離灰階與黑暗)。

## 地下通道

通往樓梯間的單扇鋼門依大樓 seed 隨機設於接待室以外房間的未連通牆面接口。抽選使用獨立 RNG，檢查門前站立淨空及從入口可達的導航路徑；位置依保存布局重現，物資與玩家掉落物不參與重抽。2026-11-06 起移除房名、樓層、出口及補給箱的模型文字，操作提示只在畫面介面顯示；不再使用 `BUNKER / STAIRS` 等 3D 字樣。

2026-11-08 起，地面層、勤務樓梯間及地堡也移除常駐房名、房數、探索數與返回／按鍵說明。探索仍持續記錄；M 主動打開地圖時只顯示樓層、房間輪廓、連線與樓梯圖示，不顯示內部房間編號。

對著這扇門按 E，進入[勤務樓梯間](../../world/poi_kit/rooms/megashelter/stairwell.tscn)。沿兩段折返梯下降 4.5 m，在 B1 的單扇鋼製小門按 E 進入該棟大樓專屬的[地堡](bunker-interior.md)。回程沿原路上樓，返回原先的房間，再經接待室出口通往戶外。

## 入口與保存

外殼場景提供 `Entrance`（`PoiEntrance`）及 `ReturnPoint`；`POISpawner` 根據 definition 設定 `poi_interior_profile`，`PoiInstanceManager` 管理轉場、串流錨點與安全返回。外部 plan、碰撞與既有 RNG 域保持不變；鄰帶導航使用相同外部碰撞，不建立可玩室內。

`InteriorProfiles` 登錄 `megashelter`、`megashelter_stairwell` 與 `bunker`。每棟大樓的地面層、樓梯間與地堡各有保存 ID，切換門時先保存離開的副本。Checkpoint 依保存的 `layout.profile` 分流檢查房型及物資，未知 profile 或請求／保存不一致時拒絕載入。房間 manifest、已探索房間、散落 Item、搜索狀態及箱內剩餘物資共同保存；回訪重建 manifest，不重抽布局或補貨。玩家帶入後丟下的物品同樣屬該副本的 WorldEntities。

## 驗證範圍

核心 [轉場測試](../../tests/test_poi_transition_persistence.gd) 透過 [室內契約](../../tests/support/megashelter_interior_contracts.gd) 抽樣固定 seed／外部面積，檢查確定性、單層、小房數及模組尺寸隨面積調整；另以正式 spawner／manager 實測入內、拾取、搜索、丟物、退出與回訪。原有地堡的取消、死亡及逾時保存案例保留。外殼的共同 factory、碰撞及串流導航由 [外部契約](../../tests/support/megashelter_contracts.gd) 檢查。

2026-11-01：轉場／室內保存、Checkpoint、串流生成及正式世界 smoke 均通過。[Checkpoint 測試](../../tests/test_checkpoint_failures.gd) 另建立真實小型室內，將布局、探索、散物與箱子寫入完整檢查點並讀回精確比較。轉場測試抽樣 16 個 seed × 三種外部面積，檢查六至八個模組、單層與種子重現。日誌位於 gitignored `.godot/test-logs/`，最後通過批次為 `20261101-225441-660-selected-31332`（轉場）、`20261101-225156-207-selected-7840`（Checkpoint）及 `20261101-225022-387-selected-37808`（生成／smoke）。

Forward+ 的 seed 42 遊戲視窗中實際觀察步行回放通過全部七室、大型引擎搬運（158.5 m）、室外 E 入口及室內 E 返回；日誌無錯誤。較大房型的 seed 48 另以相同回放完成七室與 183.6 m 搬運返程，日誌通過；此輪採固定模擬步進，不作效能基準。已檢視 seed 42／43／48 的實際渲染、機電區與 seed 43 最終 HUD。截圖及回放日誌保留於 `.godot/art-work/megashelter-interior/` 及 `.godot/megashelter-interior-*.log`。未進行廣域自由探索或全 seed 遊玩；自動導航連通不等於所有 seed 都已逐室走查。

2026-11-01 後續細化：接待室入口補成獨立的大門與行人小門，包含門縫、鎖桿、手輪、鉸鏈、把手、閉門器、踢板及實體出口牌。兩扇門各有貼合門面的互動碰撞，共用返回室外流程；移除懸浮的 `[E]` 門牌。接待室占地、連接口、房數與保存格式不變。原生構件集中於 `MegashelterInteriorKit`；桌椅與櫃架補上接合、木條、抽屜、斜撐及少量文件，衛生間以有開口的洗手盆、排水彎管、馬桶、瓷面收邊和格柵替換原占位。管線／風口依房型與牆面 ID 選擇不同組合，避開門洞。混凝土破損有實際凹槽、不規則斷面與局部彎折鋼筋，碎屑沿破口散落。

本輪轉場／保存測試通過，批次 `20261101-232640-004-selected-7400`；新增契約檢查兩個門面、互動形狀、站立淨空，以及從兩扇門內側玩家視高射線先命中同一個正式出口。Forward+ 固定步進回放 seed 42／48 完成全部七室、大型引擎搬運（159.8／185.1 m）及行人小門 E 返回，日誌無腳本／shader 錯誤，分別為 `.godot/shelter-details-replay.log` 及 `.godot/shelter-details-final-verified.log`。已檢視大小門、房間全景與手電筒下的洗手盆、馬桶、牆面凹槽；機電管組已移離西側門洞。上方 Checkpoint、串流及主世界 smoke 屬細化前結果，本輪未重跑這些無關檢查，亦未做全 seed 自由探索或效能基準。

## 檢視入口

執行 `godot --path . res://tests/megashelter_interior_playground.tscn -- --seed=42`，或在編輯器開啟[檢視場景](../../tests/megashelter_interior_playground.tscn)後按 F6。F1 步行、F2 全局、F3 隱藏天花板、F4 下一間、F5 搬運／小門出口回放、F6 下一個 seed、F7 看大小門、F8 截圖；E 互動、L 手電筒、M 探索地圖。檢視模式沿用正式室內燈光，測試場額外提供一把手電筒，正式場址不會因此補發。`--capture --detail-capture --quit-after-capture` 匯出全景、入口及近照；近照以原手電筒光束設定補光並標示 FLASHLIGHT，不改正式場景照明。截圖留在 gitignored `.godot/art-work/megashelter-interior/`。

[外殼規格](megashelter-exteriors.md) · [POI 接入規範](poi-authoring.md) · [地堡規格](bunker-interior.md) · [測試入口](../../tests/README.md)
