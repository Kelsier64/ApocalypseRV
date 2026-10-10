# Slender Speaker 抓取視角與兩秒停留

2026-10-10，本輪修改以既有工作樹為基礎，保留其他開發中的修改。

目前 Slender Speaker 抓取已改為第三人稱，最新實作及驗證見文件末段。下方前兩輪保留歷史第一人稱調整的結果。

第一輪抓取視角原本每幀強制朝音箱轉，最高 120°/s、仰角 75°，且沒有滑鼠觀看。当輪改為接觸後先保留原朝向 0.2 秒，再於 0.6 秒內漸增引導，最高 60°/s、自動仰角 60°。音箱超出觀看仰角時保持左右朝向，避免經過正上方時追焦翻轉。滑鼠使用正常靈敏度與反轉 Y 設定，保留相對引導的左右 ±25°、上下 ±18° 偏移；觀看不改變被抓身體的 transform，解除時清除偏移並交回最終視線。

抬升維持 1.4 秒，HOLD 由 0.6 秒延長至 2 秒，接續原有 0.4 秒 CRUSH。抓住到死亡合計 3.8 秒。處刑音樂仍於抓取成功時開始；本輪未修改音檔或重新編排其節拍。

## 第一輪自動檢查

Godot 4.7.2，透過 `scripts/test.ps1 -Godot <Godot.exe> -TestFilter <篩選> -SkipImport`：

- `test_raker_grab`、`test_slender_speaker_behavior` 通過，日誌 `.godot/test-logs/20261010-123700-408-selected-39052/`。同批 acquisition、execution 初跑因舊時序／視角假設失敗，更新相關測試後重跑如下。
- `test_slender_speaker_acquisition`、`test_slender_speaker_execution` 通過，日誌 `.godot/test-logs/20261010-123743-701-selected-45352/`。
- 相機測試涵蓋 30／60／120 Hz 引導速度、正上方保持 yaw、觀看偏移持續／限幅、身體不旋轉、取消／死亡釋放。headless 不支援捕捉滑鼠，該模式直接檢查觀看事件處理器；另以有渲染程序執行相同 suite，通過 `_input` 路徑，日誌 `.godot/slender-pov-native-input.log`。
- 行為測試透過正式 phase clock 檢查 119 個 60 Hz 步仍為 HOLD，第 120 步進入 CRUSH，合攏完成才死亡。
- `git diff --check` 通過。未跑 full suite。

## 第一輪原生重播與畫面

有渲染的 Forward+／Vulkan 自動重播：

```powershell
godot --path . --resolution 1280x720 --log-file .godot/slender-pov-replay.log res://tests/slender_speaker_playground.tscn -- --mode=1 --capture --headless-check
```

實際記錄 LIFT 1.417 秒、HOLD 2.817 秒、CRUSH 4.817 秒、RECOVER／死亡 5.217 秒；HOLD 正好持續 2 秒，`SLENDER_RUNTIME_CHECK.valid=true`，沒有 script error。

檢視 `.godot/slender-runtime-captures/mode-1-1791607214912/` 的 `frame_00020.png`、`frame_00034.png`：抬升完成與停留末段均為正式玩家相機，可看到音箱表面，停留末段保持存活。擷取資料位於忽略的 `.godot/`，不納入提交。

Windows 互動視窗的 F7 暫停鍵未生效，改用自動重播；未驗證真人連續滑鼠操作的手感、這次 POV 在傾斜駕駛座的表現，或其他玩家初始朝向的原生畫面。原生腳本的滑鼠測試使用合成事件。原有座位釋放只保留相機朝向、未保留座位相機眼睛位置的差異仍存在。

## 後續：雙手與音箱構圖

第一輪畫面只顯示音箱，未驗證雙手入鏡。正式 HOLD 幾何取樣顯示手腕約比眼睛低 0.62 m，部分手指在眼睛後下方，不能只靠降低仰角解決。

第二輪 Slender Speaker 提供獨立相機焦點：將實際音箱與雙掌中心到眼睛的單位方向相加，取角平分線，讓近處双手與較遠音箱共同入鏡。感知與音訊仍使用原音箱 socket。抓取後 0.55–1.4 秒漸增最多 0.7 m 的水平鏡頭後移，方向於接觸時固定為遠離巨人，不跟隨滑鼠；0.09 m 球形掃掠限制障礙前的位移。視野同時漸增至至少 90°，原設定更大則保留。一般 captor 不提供此焦點時不調整位置／FOV；解除時恢復接觸前基準。

本輪 `test_raker_grab`、`test_slender_speaker_acquisition`、`test_slender_speaker_behavior` 通過，日誌 `.godot/test-logs/20261010-131410-529-selected-50124/`。

新增相機構圖／清理回歸的 `test_slender_speaker_execution` 通過，最新日誌 `.godot/test-logs/20261010-131652-782-selected-44872/`。涵蓋延遲與漸增後移／FOV、相機焦點 provider、非預設基準恢复、重複抓取、保留原本 96° 視野、取消／轉場／移除 owner，以及真實牆面阻擋。中段後移 0.319153 m、FOV 78.03053°；牆面限制後移至 0.359570 m。初跑的測試語法與 fixture 問題已修正：獨立相機基準測試暫停普通 locomotion 對鏡頭的覆寫，牆面移至完整玩家膠囊之外，保留球形掃掠阻擋斷言。這些修正沒有改動正式遊戲相機邏輯。

原生 ground／driver 重播均以 `--capture --headless-check` 執行：

- `.godot/slender-pov-hands-replay.log`：HOLD 2.817 秒、CRUSH 4.817 秒、死亡 5.217 秒；`valid=true`。檢視 `.godot/slender-runtime-captures/mode-1-1791609213986/` 的 `frame_00021.png`、`frame_00035.png`，停留開始與末段都能看到音箱及雙手。
- `.godot/slender-pov-hands-driver.log`：自主拆一片屋頂後抓住駕駛，HOLD 14.233 秒、CRUSH 16.233 秒、死亡 16.633 秒；`valid=true`。檢視 `.godot/slender-runtime-captures/mode-8-1791609289072/` 的 `frame_00107.png`、`frame_00121.png`，末段音箱、雙手與被握住的玩家上身共同入鏡。剛進入 HOLD 時仍在緩慢轉向，構圖偏向左側；兩秒停留內完成引導。

兩次原生重播沒有 script error，完成後自行退出。未驗證極端傾斜座位、所有玩家觀看偏移，或真人連續滑鼠操作的手感。

## 最新：抓取第三人稱

按使用者要求，成功抓住時切換 `Player/ExecutionObserver`，以玩家真實胸部為支點，向遠離巨人的方向 5.5 m、斜側 3 m、上方 2.5 m 觀看，焦點取胸部到實際音箱的四分之一處。鏡頭使用 65° FOV、0.05 m near，包含完整玩家身體與頭部圖層、排除第一人稱複本；完整玩家、巨人雙手與三個音箱共同入鏡。原音箱感知／音訊位置保持既有契約。

滑鼠沿用左右 ±25°、上下 ±18° 的限制，改為環繞構圖；原第一人稱眼睛位置、FOV、near 與朝向在觀看期間保持基準。從胸部向鏡頭做 0.18 m 球形掃掠，限制環境碰撞；僅排除玩家、captor 及已釋放座位組件，不排除 RV 車殼。取消、死亡、轉場、換 World3D、owner／玩家移除均清除相機；其他系統已取得相機時保留其所有權。普通 captor 未提供 `execution_camera_frame` 時保留原引導。抬升 1.4 秒、HOLD 2 秒、CRUSH 0.4 秒保持不變。

最新自動檢查使用 Godot 4.7.2／`scripts/test.ps1 -SkipImport`：

- `test_raker_grab`、`test_slender_speaker_behavior` 通過，日誌 `.godot/test-logs/20261010-133047-010-selected-20952/`。同批 acquisition 兩個斷言仍要求第一人稱相機 current，已改成檢查真正第三人稱所有權後重跑。
- `test_slender_speaker_acquisition`、`test_slender_speaker_parked_attack` 通過，日誌 `.godot/test-logs/20261010-133140-634-selected-50128/`。停車測試同步更新相機所有權斷言。
- `test_slender_speaker_execution` 通過，日誌 `.godot/test-logs/20261010-133226-142-selected-9644/`。涵蓋完整玩家圖層、滑鼠限幅／環繞、眼睛基準、實體牆掃掠及所有清理情境；牆限制相機距離由 5.916 m 縮為 1.769 m，鏡頭球體不與固體交疊。保留一般 execution 的 30／60／120 Hz 第一人稱引導回歸。

有渲染的 Forward+／Vulkan 原生重播完成並自行退出：

- 車外 `.godot/slender-third-person-replay.log`：HOLD 2.817 秒、CRUSH 4.817 秒、死亡 5.217 秒，`valid=true`；檢視 `.godot/slender-runtime-captures/mode-1-1791610205302/frame_00024.png`，完整玩家、雙手、三個音箱都在畫面內。當次測試名稱仍顯示舊 First-person 字樣，現已更新為 Third-person。
- 駕駛 `.godot/slender-third-person-driver.log`：自主拆一片屋頂後抓取駕駛，HOLD 14.233 秒、CRUSH 16.233 秒、死亡 16.633 秒，`valid=true`；檢視 `.godot/slender-runtime-captures/mode-8-1791610262921/frame_00118.png`，停留末段完整玩家、双手與音箱共同入鏡。

有渲染的 execution suite 也通過，日誌 `.godot/slender-third-person-native-input.log`；實際走 `_input` 的滑鼠環繞路徑及清理斷言通過。`git diff --check` 通過。原生重播均無 script error。未跑 full suite，未驗證真人連續滑鼠手感、極端翻車姿勢或所有方向的密集障礙場景。擷取畫面及日誌保存於忽略的 `.godot/`。

## 後續調整：到達面前才切換，鏡頭拉近（未測試）

按使用者最新要求，Slender Speaker 抓住及 LIFT 抬升途中保留第一人稱，進入 HOLD 才切換第三人稱，並持續至 CRUSH。以正式 phase 的 `execution_camera_ready()` 控制切換，不以固定經過時間猜測是否到位；切換時重設環繞偏移。鏡頭由遠離巨人 5.5 m／側向 3 m／上方 2.5 m，縮為 3.2 m／1.8 m／1.5 m，胸部到鏡頭的無障礙距離由約 6.745 m 縮為約 3.966 m。兩秒 HOLD 保留，取消及死亡沿用原清理。

本次同步更新接觸時應保留第一人稱的測試斷言，但依使用者要求沒有執行測試、原生回放或畫面驗證，交由使用者自行檢查。上方測試及畫面僅代表先前立即切換、較遠鏡頭的版本。
## 最新調整：更近的鏡頭與第三人稱死亡（未測試）

鏡頭改為遠離巨人 2.2 m／側向 1.2 m／上方 1 m，無障礙胸部距離約 2.7 m。仍在 HOLD 開始才由第一人稱切換，停留 2 秒再 CRUSH。

當已啟用的第三人稱相機仍持有視角時，死亡釋放抓取所有權，保留相機，記住最後構圖相對胸部的位置及焦點，接著跟隨玩家實際骨架胸部。死亡物理啟動不再強制啟用第一人稱；巨人收手不改變死亡構圖。成功復活才清除第三人稱相機，恢復正常視角；復活空間受阻時繼續保留。換世界、玩家移除仍清理，其他系統取得鏡頭所有權時停止跟隨。

同步更新 execution 死亡／復活相機斷言。依使用者前一輪要求，本輪未執行測試、Godot 或畫面驗證。先前通過的測試及截圖僅代表當時版本。
## 最新修正：第三人稱跟隨角色（未測試）

第三人稱構圖改用玩家自身水平朝向，鏡頭位於玩家背後 2.2 m／右側 1.2 m／上方 1 m，追蹤支點與視線焦點均為玩家真實胸部。移除玩家到巨人的方位計算，以及胸部到音箱的混合焦點，因此巨人移動、轉向及音箱動畫不再牽動第三人稱構圖。死亡後保持最後的鏡頭相對位置，繼續對準玩家胸部，直到成功復活。

保留到 HOLD 才切換、近距離鏡頭、滑鼠環繞、環境碰撞與兩秒停留。依使用者要求沒有執行測試、Godot 或畫面驗證。
## 最新修正：CRUSH 後跟隨下落的物理身體（未測試）

使用者回報死亡後鏡頭留在抓取高度。前次使用 `execution_contact_position()` 讀取骨架動畫姿勢；布娃娃透過 PhysicalBoneSimulator 的骨架 modifier 下落時，此查詢仍可能保留原抓取高度。

新增 `PlayerRagdoll.third_person_anchor_position()`，死亡物理啟動後直接使用 `spine_02` 的 PhysicalBone3D 世界變換，乘回 `body_offset` 的反變換取得對應胸部骨架原點。死亡第三人稱的鏡頭位置與焦點改由此物理支點驅動，跟隨軀幹下落至地面；物理尚未啟動的短暫期間才使用原胸部位置。保留約 2.7 m 構圖、第三人稱至復活及环境碰撞。

依使用者要求，本次未執行測試、Godot 或畫面驗證；下落效果由使用者自行檢查。
## 2026-10-10：取消第三人稱角度限制，預設看音箱

進入 HOLD 的第三人稱相機以玩家胸部為支點，初始位置依胸部到實際音箱的相對水平位置決定，維持 2.2 m／1.2 m／1 m 的近距離取景，視線對準實際音箱；玩家身體朝向不再決定預設觀看方向。第三人稱滑鼠水平與垂直都可完整轉圈，移除 ±25°／±18° 限幅；等價角度 wrapping 不限制可觀看的方位。相機上方向隨垂直環繞旋轉，並避免 look_at 的上方向與視線共線。抬升第一人稱、0.18 m 相機碰撞掃掠、身體所有權、死亡與復活清理沿用既有流程。

依使用者要求，未使用 computer use、互動視窗或原生畫面測試。本輪 Godot 4.7.2 headless 檢查：

- `test_raker_grab`、`test_slender_speaker_acquisition` 通過，日誌 `.godot/test-logs/20261010-153447-346-selected-29604/`。同批新增 execution 測試的型別推斷錯誤已修正。
- `test_slender_speaker_execution` 通過，日誌 `.godot/test-logs/20261010-153507-858-selected-30204/`。新增正式 Slender Speaker 四種玩家朝向、LIFT 保留第一人稱／HOLD 重設偏移並朝向音箱；第三人稱兩軸正／反轉 Y 的 45°–360° 轉圈、大幅滑鼠輸入及有效相機 basis。既有牆面掃掠、第一人稱限幅、取消／死亡／復活／移除／換世界清理仍通過。測試設定反轉 Y 不寫入使用者設定檔。
- `git diff --check` 通過。未跑 full suite；未驗證真人滑鼠手感及渲染構圖。

上方紀錄與截圖代表當時版本，本段才是此次相機行為與驗證範圍。
