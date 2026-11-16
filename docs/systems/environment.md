# 畫面、時間、天氣與設定

戶外的時間、太陽、天氣與霧，暗處怎麼顯示，以及 Esc 設定選單與 HUD。這些都只影響玩家看到與聽到的東西；時間另外驅動休息與部分怪物的出現時段。暗部顯示的調整方式見[暗部顯示指南](../guides/night-vision.md)，偏離公路時起的霧見 [enemies](enemies.md)。

## 功能一覽

| 功能 | 範圍 | 來源 | 測試場 |
|---|---|---|---|
| 時間與太陽 | 遊戲時鐘、日夜光照、畫面右上的日期時間 | [WorldClock](../../world/world_clock.gd) | [day_night](../../tests/day_night_playground.tscn) |
| 天氣 | 晴、陰、兩級雨、三級霧，隨時間自然變化 | [WorldWeather](../../world/world_weather.gd) | [weather](../../tests/weather_playground.tscn) |
| 霧的外觀 | 常駐的遠景霧、天氣霧、林間的局部霧 | [WorldAtmosphereProfile](../../world/world_atmosphere_profile.gd)、[world_atmosphere_profile.tres](../../world/world_atmosphere_profile.tres)、[ForestFog](../../world/terrain/forest_fog.gd) | [volumetric_fog](../../tests/volumetric_fog_playground.tscn) |
| 載入時的視野保護 | 地景還沒生成完的地方用霧遮住 | [WorldStreamVisibility](../../world/stream_visibility_guard.gd) | |
| 雨 | 雨幕、水花、雨聲、屋頂遮雨 | [WeatherRain](../../world/weather_rain.gd)、[RainCover](../../world/rain_cover.gd) | [weather](../../tests/weather_playground.tscn) |
| 暗部顯示 | 沒有光的地方用灰階補出近處的輪廓 | [NightVisionEffect](../../world/night_vision_effect.gd)、[DarkAdaptationProfile](../../world/dark_adaptation_profile.gd) | [outdoor_horror](../../tests/outdoor_horror_playground.tscn) |
| 設定 | 顯示、操作、音量的偏好與存檔 | [GameSettings](../../core/game_settings.gd)（autoload）、[settings_menu.gd](../../player/settings_menu.gd) | |
| HUD 與介面縮放 | HUD 的顯示開關、介面隨視窗大小縮放 | [HUDVisibility](../../core/hud_visibility.gd)、[UILayout](../../core/ui_layout.gd)、[IndustrialTheme](../../core/industrial_theme.gd) | |
| 戶外美術 | 戶外建築與 RV 的共用材質 | [IndustrialArt](../../world/industrial_art.gd) | [industrial_style](../../tests/industrial_style_playground.tscn) |

自動測試：這個系統沒有專屬的測試檔。時間與天氣的存讀在 [test_checkpoint_failures.gd](../../tests/test_checkpoint_failures.gd)，設定的顯示檢查在 [validate_settings_display.gd](../../scripts/validate_settings_display.gd)。畫面、霧與雨的觀感只能實際看。

## 規則與數值

### 時間

- 一天的長度是 `WorldClock.day_length_minutes`（現實分鐘）。新局從第 1 天的 `DEFAULT_TIME` 開始。畫面右上顯示 `DAY n  HH:MM`。
- 太陽 06:00 升起、18:00 落下。清晨與黃昏的光偏暖，夜裡沒有自然光。
- 玩家在室內副本、開背包或用平板時，時間照樣走。
- 教學基地出庫前時間與天氣停住，見 [opening](opening.md#開場階段)。
- 在床上休息可以跳過幾個小時，見 [player](player.md)。部分怪物只在白天或夜晚出現，見 [enemies](enemies.md)。
- 沒有季節與月相。

### 天氣

- 天氣一段一段地換。每段的長度在 `WorldWeather.MIN_DURATION` 到 `MAX_DURATION` 之間（遊戲秒），換的時候用 `TRANSITION` 的時間平滑過渡。
- 新局從陰天、無雨、無霧開始。
- 每換一段先抽是不是晴天（`CLEAR_CHANCE`）。晴天沒有雨也沒有霧。
- 不是晴天時，雨勢與霧量各自獨立抽：雨有無雨、小雨、大雨三級；霧有無、小、中、大四級。門檻是同一個檔案裡的常數。所以大雨加大霧、連續兩段一樣的天氣都可能出現。
- 天氣只影響畫面與聲音。它不影響怪物的感知、玩家的狀態或輪胎的抓地。沒有雷電、積水與風。

### 霧

- **常駐的遠景霧**：不管什麼天氣，遠處都會被霧完全遮住。陰天從比較近的地方開始起霧，晴天比較遠。
- **天氣霧**：小霧、中霧、大霧把完全遮蔽的距離一級一級拉近。
- **林間的局部霧**：陰天時低處與林間有飄動的霧塊，太陽、門燈與車燈能照亮它。起天氣霧時局部霧淡出，由天氣霧接手。
- 距離、密度與顏色都在 [world_atmosphere_profile.tres](../../world/world_atmosphere_profile.tres)。
- 夜裡霧跟著變暗，不會自己發亮。
- 車頂完整的 RV 車廂內沒有霧。室內副本用自己的環境，沒有戶外的霧。
- 霧只是視覺。它不提供潛行，也不改變怪物的感知。

**視野受限是美術上的硬要求**，見 [GDD](../../GDD.md#section-7)。霧是其中一層，地形、樹冠與灌叢是另一層。

### 載入時的視野保護

玩家看得到的範圍內如果有地景還沒生成完，霧會立刻收近到已完成的範圍內，蓋住空白的地方；生成完之後再慢慢放開。這個收近不算天氣，不存檔，也不影響天氣的抽選。

### 雨

- 雨幕跟著攝影機，分近、遠兩層。有屋頂的地方不下雨：建築、地形與 RV 的車頂都會遮雨，車頂被拆掉的地方雨會落進車裡。
- 雨滴打到的地方有水花。頭頂有遮蔽時雨聲變悶。
- 大雨會壓暗陽光。
- 玩家在室內副本時看不到雨，只聽得到小聲的雨聲；外面的天氣照常變化。

### 暗部顯示

- 沒有光的地方不是全黑：畫面會用灰階補出近處物體的輪廓，越遠補得越少，超過一段距離就完全不補。
- 有真實光源的地方保留原本的顏色與陰影。手電筒、車燈與車內燈不受影響。
- 這和時段無關，只看那個位置實際有多暗，所以白天的室內暗處也適用。
- 戶外與室內副本各用一份設定。室內的補光距離短得多，所以地堡裡熄燈的房間要靠手電筒。
- 設定檔與曲線的調法見[暗部顯示指南](../guides/night-vision.md)。

### 戶外的畫面風格

- 低面數的模型、冷灰與低飽和的綠、土褐與鏽色、偏陰的光。
- 預設用較低的 3D 解析度（高度約 540 像素）搭配復古色調。HUD、選單與文字永遠是原生解析度。
- 不使用像素格、抖色、雜訊干擾或頭盔框。
- 室內副本不套用低解析度與復古色調。

### 設定選單

按 Esc 開啟，分四頁：

| 頁 | 內容 |
|---|---|
| Video | 畫質組合、3D 解析度、抗鋸齒、陰影品質、霧品質；視窗或全螢幕、垂直同步、幀率上限；復古色調、飽和度、顯示校準 |
| Controls | 滑鼠靈敏度、反轉 Y 軸、步行與駕駛的視野角度 |
| Audio | 主音量 |
| Key Bindings | 按鍵說明（只能看，不能改鍵） |

- **畫質組合**：遊戲預設、低、中、高、自訂。組合只改解析度、抗鋸齒、陰影與霧四項（`GameSettings.PRESETS`）。手動改過其中一項就變成自訂。
- **3D 解析度**：「依場景自動」在戶外用低解析度、室內用原生解析度；「自訂比例」讓戶外與室內用同一個比例。
- **霧品質**：只影響局部霧的精細度，不改變看得多遠。相容模式的渲染器沒有局部霧，這個選項不能用。
- **視窗模式**：切換後要在倒數結束前確認，否則自動還原。
- **顯示校準**：`Calibrate Display` 用灰階色塊與即時畫面調整暗部細節，Apply 儲存，Cancel 或 Esc 還原。
- 各項的預設值與範圍在 `GameSettings.DEFAULTS` 與 `RANGES`。

設定選單**不會暫停遊戲**：

- 重力、怪物、傷害、時間與 RV 的油電照常進行。
- 選單開著時玩家不能操作。駕駛中車子繼續滑行，引擎、檔位與手煞車不變。
- 關閉選單後，原本按住的鍵要放開再按才有作用。
- 被抓住、死亡、讀檔與進出副本時不能開選單。
- 平板開著時 Esc 先關平板；放置預覽中 Esc 先取消預覽。

教學進行中，選單另外提供階段重來與略過，見 [opening](opening.md#重來略過與說明書)。

### HUD

- F12 開關整個 HUD。
- 介面以 1280×720 為基準隨視窗放大；視窗很小時整體縮小，但保留至少 960×540 的排版空間。3D 解析度怎麼調都不影響介面的清晰度。
- 背包欄、生命與駕駛資訊用同一套暗底、灰白字、暗黃選取框的樣式。平板用自己的等寬終端樣式。
- 快捷欄見 [items](items.md#快捷欄)。

## 實作契約

### 時鐘是戶外光照的唯一寫入者

- 每個戶外世界有一個 `WorldClock`。只有它能寫戶外的 `Environment`、太陽與天空材質；其他系統要改畫面，就改時鐘讀取的輸入（天氣、偏行霧、設定），不直接寫環境。
- `apply_time` 每次把時間、天氣、霧的外觀與載入保護合成一次，再寫進環境。天空的地平線顏色與霧的顏色用同一個值，否則被霧完全遮住的遠物會在天空前面露出輪廓。
- 時鐘的處理模式跟著所屬的世界：場景樹暫停或世界被停用（讀檔時的暫存世界）時，時鐘跟著停。
- `running = false` 只停住時間與天氣的推進，畫面照常更新。教學準備期間就是這個狀態，所以載入保護的霧仍然會隨地景生成而放開。
- `set_time` 是調時的入口（終端指令與測試場用），不會重抽天氣。

### 天氣與外觀分開

- `WorldWeather` 只管自然天氣：目前與目標的狀態、過渡進度、剩餘時間與自己的亂數。它的亂數從世界種子衍生，但和世界生成的亂數流分開。
- `WorldAtmosphereProfile` 只管外觀：給它一組天氣條件，回傳霧的距離與密度。它是沒有副作用的純取樣。
- 偏離公路的霧經由 `set_deviation_fog` 進來，在 `visual_conditions` 裡和自然天氣合成。它只改畫面，不產生自然天氣，也不消耗天氣的亂數。
- 要讀「現在的自然天氣」用 `weather.sample()`；要讀「畫面上實際的狀況」用 `effective_visual_weather()`。
- 天氣只能讓霧變近，不能讓常駐遠景霧的終點變遠（`mist` 裡的 `minf`）。地景的裁切距離是照這個終點設計的。

### 霧與地景的配合

- 林間的霧塊由 `ForestFog` 隨區塊建立，建立時向時鐘登記材質（`register_fog`），區塊卸載時解除。密度由時鐘統一更新。
- 植被在被霧完全遮住之後才整批裁切，裁切距離在生成時依霧的終點決定。所以改霧的距離要在生成前改，已經生成的區塊要重建才會跟上；密度與顏色則是即時生效。
- `WorldGenerator.completed_scenery_clearance` 回報攝影機周圍連續完成的地景範圍，`WorldStreamVisibility` 據此收近霧的終點。收近是立即的，放開有速度上限（`stream_reveal_speed`）。
- 局部霧只在 Forward+ 渲染器存在。相容模式保留一樣的距離霧，只是沒有霧塊。

### 雨的成本

- 雨滴不是逐顆更新的物件。兩層雨幕各是一個固定種子的 `MultiMesh`，位置由著色器依時間與世界座標計算；每一幀只更新攝影機、時間與天氣參數。粒子數量是 `WeatherRain` 開頭的常數。
- 遮雨用兩張以世界座標定位的高度圖（`RainCover`），每個物理步只更新固定數量的格子。RV 車頂另外以碰撞盒傳給著色器逐粒子判斷，上限是 `MAX_ROOF_SHAPES`。
- 每個物理步的射線總數有上限（`MAX_RAYS`），和雨量無關。

### 暗部顯示

- `NightVisionEffect` 掛在各自的世界裡，戶外與每個室內副本各有一個，用各自的 `DarkAdaptationProfile`。
- 它需要額外渲染一次參考畫面，成本隨 3D 解析度增減。
- 它只補缺少的亮度，不改真實光源的顏色、陰影與霧的遮蔽。
- 細節與限制（透明材質、鏡面、相機圖層）見[暗部顯示指南](../guides/night-vision.md)。

### 設定

- `GameSettings` 是偏好的唯一寫入者。其他系統讀 `get_setting`，或接 `setting_changed`。
- 偏好存在獨立的檔案（`storage_path`），不進檢查點，也不跟著角色或車輛。讀取與寫入時逐項檢查型別與範圍，不合格的欄位各自回到預設值。沒有舊格式的轉換。
- 連續拖動滑桿時，存檔會合併成一次；關閉選單時強制寫入。寫入失敗時選單顯示錯誤與重試按鈕。
- 每個要顯示 3D 的視窗都要呼叫 `register_viewport`，室內副本的子視窗也是。解析度、抗鋸齒、陰影與色調從這裡套用。
- 復古色調、飽和度與低 SAN 的畫面效果是同一個後製著色器（`retro.gdshader`），畫在 3D 之上、介面之下。
- 啟動時預設全螢幕。視窗模式超出螢幕可用範圍時會等比例縮小並置中。

### 輸入遮罩

- 設定選單不設 `SceneTree.paused`。它靠玩家的 `settings_open` 擋輸入。
- 玩家、互動射線、駕駛座與車體都用同一個判斷 `is_gameplay_input_blocked`，事件與按住的鍵都涵蓋。新增會讀輸入的系統要用同一個判斷，否則選單開著時它還會動。

### HUD 的顯示

- 每個 HUD 用的 `CanvasLayer` 建立時呼叫 `HUDVisibility.attach`，F12 才關得掉它。
- 需要隨視窗縮放的介面用 `UILayout.attach`。它每幀只比較視窗尺寸，變了才重排，所以玩家搬進室內副本的子視窗後仍然正確。

### 存檔

檢查點存時鐘（累積秒數與一天的長度）與天氣（目前與目標的狀態、過渡進度、剩餘時間、亂數狀態），兩者都是必要欄位，由 `WorldClock.valid_state` 與 `WorldWeather.valid_state` 檢查。讀檔時在世界的子節點就緒之前還原。不計算離線時間。
