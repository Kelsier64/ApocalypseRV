# 畫面、時間、天氣與設定

戶外的時間、太陽、天氣與霧，暗處怎麼顯示，以及 Esc 設定選單與 HUD。這些都只影響玩家看到與聽到的東西；時間另外驅動休息與部分怪物的出現時段。暗部顯示的調整方式見[暗部顯示指南](../guides/night-vision.md)，偏離公路時起的霧見 [enemies](enemies.md)。

## 功能一覽

| 功能 | 範圍 | 來源 | 測試場 |
|---|---|---|---|
| 時間與太陽 | 遊戲時鐘、日夜光照、畫面右上的日期時間 | [WorldClock](../../world/world_clock.gd) | [day_night](../../tests/playgrounds/day_night_playground.tscn) |
| 天氣 | 晴、陰、兩級雨、三級霧，隨時間自然變化 | [WorldWeather](../../world/world_weather.gd) | [weather](../../tests/playgrounds/weather_playground.tscn) |
| 風與沙塵 | 四級風力、風向、陣風；地貌決定乾燥度與沙塵量。沙塵拉近視野、染黃天色，強風時有飛沙與貼地的沙團；雨幕隨風傾斜。還沒有風聲與側風 | [WorldWind](../../world/world_wind.gd)、[WeatherDust](../../world/weather_dust.gd) | [weather](../../tests/playgrounds/weather_playground.tscn) |
| 霧的外觀 | 常駐的遠景霧、天氣霧、林間的局部霧 | [WorldAtmosphereProfile](../../world/world_atmosphere_profile.gd)、[world_atmosphere_profile.tres](../../world/world_atmosphere_profile.tres)、[ForestFog](../../world/terrain/forest_fog.gd) | [volumetric_fog](../../tests/playgrounds/volumetric_fog_playground.tscn) |
| 載入時的視野保護 | 地景還沒生成完的地方用霧遮住 | [WorldStreamVisibility](../../world/stream_visibility_guard.gd) | |
| 雨 | 雨幕、水花、雨聲、屋頂遮雨 | [WeatherRain](../../world/weather_rain.gd)、[RainCover](../../world/rain_cover.gd) | [weather](../../tests/playgrounds/weather_playground.tscn) |
| 環境音 | 寂靜為主，依時段與位置零星播放的遠處聲音；室內副本的微弱嗡聲與偶發聲 | [WorldAmbience](../../world/world_ambience.gd)、[素材](../../assets/audio/ambience/README.md) | [ambience](../../tests/playgrounds/ambience_playground.tscn) |
| 暗部顯示 | 沒有光的地方用灰階補出近處的輪廓 | [NightVisionEffect](../../world/night_vision_effect.gd)、[DarkAdaptationProfile](../../world/dark_adaptation_profile.gd) | [outdoor_horror](../../tests/playgrounds/outdoor_horror_playground.tscn) |
| 設定 | 顯示、操作、音量的偏好與存檔 | [GameSettings](../../core/game_settings.gd)（autoload）、[settings_menu.gd](../../player/settings_menu.gd) | |
| HUD 與介面縮放 | HUD 的顯示開關、介面隨視窗大小縮放 | [HUDVisibility](../../core/hud_visibility.gd)、[UILayout](../../core/ui_layout.gd)、[IndustrialTheme](../../core/industrial_theme.gd) | |
| 戶外美術 | 戶外建築與 RV 的共用材質 | [IndustrialArt](../../world/industrial_art.gd) | [industrial_style](../../tests/playgrounds/industrial_style_playground.tscn) |

自動測試：這個系統沒有專屬的測試檔。時間與天氣的存讀在 [test_checkpoint_failures.gd](../../tests/test_checkpoint_failures.gd)；霧、天氣亂數與風的契約在 [atmosphere_contracts.gd](../../tests/support/atmosphere_contracts.gd) 與 [wind_contracts.gd](../../tests/support/wind_contracts.gd)，由 [test_world_contracts.gd](../../tests/test_world_contracts.gd) 執行；設定的顯示檢查在 [validate_settings_display.gd](../../scripts/validate_settings_display.gd)，環境音的挑選、間隔、距離、車廂遮蔽與室內嗡聲在 [test_rv_audio.gd](../../tests/test_rv_audio.gd) 與 [test_poi_transition_persistence.gd](../../tests/test_poi_transition_persistence.gd)。畫面、霧與雨的觀感與環境音的聽感只能實際看、實際聽。

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
- 天氣只影響畫面與聲音，唯一的例外是霧量決定森林裡能不能出現 Slender Speaker（見 [enemies](enemies.md)）。它不影響怪物的感知、玩家的狀態或輪胎的抓地。沒有雷電與積水。

### 風

- 每段天氣有一級風力：平靜、微風、強風、暴風。霧在靜風裡形成，所以機率跟著這段的霧量走（`WorldWind.TIER_CHANCES` 每個霧量一列）：強風與暴風集中在晴天、無霧與薄霧的時段，中霧與濃霧最多是微風。大雨時有 `HEAVY_RAIN_STEP_UP` 的機會再往上一級，但不超過該霧量最強的一級。換段時風力和雨霧一樣用 `TRANSITION` 平滑過渡，所以起風的那一段看起來是風把霧吹散。
- 新局的第一段天氣固定平靜，所以教學出庫前天氣停住時風也是平靜。
- 每段有一個基準風向，段內隨時間緩慢偏轉，最多 `MAX_VEER`。陣風在平均風速上下起伏 `GUST_SPREAD`。
- 地貌決定乾燥度與受風係數：濕度與樹越多越不起沙，樹越多風越小。峽谷、山脊與懸崖最乾，草原居中，濕地與森林盆地幾乎不起沙。
- 沙塵量由當地風速與乾燥度算出，從 `DUST_LIFT_SPEED` 開始揚起，到 `DUST_STORM_SPEED` 成為沙塵暴。平靜時沒有沙塵；雨量達到小雨就完全沒有沙塵。
- 風還沒有聲音，也不推 RV。後續階段見[風與沙塵](../plans/wind-dust.md)。

### 沙塵

- 沙塵看的是攝影機所在的地貌與當下的風，所以從林子開進開闊乾燥的地方，視野會跟著縮。
- 沙塵把遠景拉近成一層淡淡的土褐色沙霧，暴風吹過最乾的地貌時約一百多公尺外就看不到（`dust_end`）。沙霧只是背景，近處擋視線靠沙幕；它從車廂長度之外才開始（`dust_begin`），密閉的車廂裡看不到沙霧。視野跟著平均風力變，不隨每陣風忽近忽遠。沙塵暴一波一波來，大約每分多鐘一波：湧上來時沙霧在十幾秒內收近（`dust_surge_reach`），沙牆也來得更頻繁，過了再慢慢退開。陣風只讓飛沙忽多忽少。它只會拉近，不會讓霧變遠；和霧同時出現時取較近的距離。
- 沙的顏色看地貌：峽谷揚起偏紅橙的沙，山脊與崖地偏灰白，草原偏黃褐（`TerrainLandforms.DUST_COLORS`），跨地貌時漸變。天色和遠景霧依沙塵與霧的比重染上這個顏色，地平線和霧仍是同一個顏色。沙塵也會稍微壓暗陽光與太陽（`dust_sun_dimming`），夜裡跟著變暗，不會自己發亮。
- 沙塵中車燈與門燈照得出光束。陽光在濃沙裡散成均勻的光，不會拉出陰影光柱。
- 近處有貼地飛的細沙，遠處有慢慢滾過的大片沙團，都順著風走，風越大越多。強風時近處還有一片片濃沙幕順風橫掃過去（`dust_sheet_*`），沙幕跟著空氣裡的濃淡一起移動，視野一下被吞掉、一下又打開。強陣風時沙幕變濃、空隙合起來，像一道沙牆壓過來再散開（`dust_gust_wall`）。晴天的沙幕被太陽照得偏亮偏暖，陰天偏灰暗，夜裡不發亮（`dust_sun_glow`）。
- 立體沙雲（`dust_billow_*`，貼地翻滾、人可以站在裡面）只在 Forward+ 而且霧品質開著時做得出來，遊戲裡預設關閉，只在天氣測試場比較用。擋視線靠沙霧與沙幕。有屋頂的地方沒有沙粒：建築下與車頂完整的 RV 車廂內看不到，車頂被拆掉的地方沙會進來。
- 下雨時沒有沙塵。沙塵只是畫面，不改變天氣的霧量，也不影響怪物。

### 霧

- **常駐的遠景霧**：不管什麼天氣，遠處都會被霧完全遮住。陰天從比較近的地方開始起霧，晴天比較遠。
- **天氣霧**：小霧、中霧、大霧把完全遮蔽的距離一級一級拉近。
- **林間的局部霧**：陰天時低處與林間有飄動的霧塊，太陽、門燈與車燈能照亮它。霧塊順著風往下風處飄，靜風時也慢慢移動；風越大飄得越快，強風把它撕成一縷一縷、變淡。起天氣霧時局部霧淡出，由天氣霧接手。
- 距離、密度與顏色都在 [world_atmosphere_profile.tres](../../world/world_atmosphere_profile.tres)。
- 夜裡霧跟著變暗，不會自己發亮。
- 車頂完整的 RV 車廂內沒有霧。室內副本用自己的環境，沒有戶外的霧。
- 霧只是視覺。它不提供潛行，也不改變怪物的感知。

**視野受限是美術上的硬要求**，見 [GDD](../../GDD.md#section-7)。霧是其中一層，地形、樹冠與灌叢是另一層。

### 載入時的視野保護

玩家看得到的範圍內如果有地景還沒生成完，霧會立刻收近到已完成的範圍內，蓋住空白的地方；生成完之後再慢慢放開。這個收近不算天氣，不存檔，也不影響天氣的抽選。

### 雨

- 雨幕跟著攝影機，分近、遠兩層，隨風傾斜：風越大斜得越多，陣風時雨幕慢慢擺動。有屋頂的地方不下雨：建築、地形與 RV 的車頂都會遮雨，車頂被拆掉的地方雨會落進車裡。
- 雨滴打到的地方有水花。雨聲是小雨與大雨兩段立體聲錄音，依雨量交叉淡化。頭頂有遮蔽時雨聲變悶。
- 大雨會壓暗陽光。
- 玩家在室內副本時看不到雨，只聽得到小聲的雨聲；外面的天氣照常變化。

### 環境音

- 戶外沒有持續的底噪，空曠處就是安靜的。大約每 30 到 90 秒，玩家周圍 25 到 60 m 外的隨機方向響起一聲。
- 挑哪一種聲音看時段與位置：白天是烏鴉，夜裡是一隻蟋蟀，樹多的地方有樹幹吱嘎和樹枝斷裂，靠近公路時有金屬招牌吱嘎。日夜跟著太陽高度變化，和光照同步。
- 起霧或下雨時聲音變少；起霧時聲音也更遠、更小、更悶。偏離公路時起的霧也算。
- 在 RV 車廂內，這些聲音和其他車外聲一樣變小、變悶，引擎轉速高時也被蓋過。頭頂有屋頂時（建築內、棚子下）也變悶，但沒有車廂那麼多。
- 進入室內副本後只有極微弱、只有低頻的室內嗡聲，同樣每 30 到 90 秒在附近響一聲滴水或金屬冷縮聲，帶著房間的殘響。
- 戶外的聲音與室內嗡聲跟隨設定裡的環境音滑桿；室內的滴水與冷縮聲跟隨音效。

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
| Audio | 主音量、音樂、音效、環境音。世界內的預警聲、收音機、介面回饋，以及玩家自己的耳鳴跟隨音效，雨聲與戶外環境音跟隨環境音。 |
| Key Bindings | 按鍵說明（只能看，不能改鍵） |

測試場另有第五頁 Playground，開選單時先顯示這一頁；正式遊戲沒有這一頁，見[測試場指南](../guides/playgrounds.md)。

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
- 沙塵是 `mist(conditions, dust, surge)` 的第二個輸入，同樣只取較近的終點；第三個輸入是湧浪（`WorldWind.surge`，由種子與遊戲時間決定，不必存檔），把沙塵的終點再拉近 `dust_surge_reach`，沒有沙塵時沒有作用，拉到最近仍在白色幽影最小生成距離之外。回傳的 `dust_mix` 是沙塵在霧色裡的比重，`apply_time` 用它把地平線、天頂與體積霧的顏色往土褐色拉；地平線與霧仍寫同一個值。沙塵不改霧的曲線：曲線小於 1 會在起點附近立刻變濃，看起來像一道牆，所以近處的遮擋交給沙幕。深度霧沒有遮蔽，`CabinAir` 只抵消體積霧，所以 `dust_begin` 要大於 RV 車廂的長度。遊戲邏輯（怪物生成距離）只讀 `fog_depth_end`，所以 `dust_end` 不低於白色幽影的最小生成距離。體積霧在沙塵中只加一點散射（`dust_volume_density`），讓車燈照出光束，Forward+ 與 Compatibility 的沙霧因此看起來差不多。沙塵不進 `visual_conditions`，所以不改變天氣的霧量。

### 風由天氣段推得

- `WorldWind`（RefCounted）由 `WorldClock` 擁有（`clock.wind`），在時鐘的 `_ready` 以世界種子初始化。它只讀 `WorldWeather`，不寫天氣，也不讀寫任何亂數產生器。
- 風力與基準風向是世界種子與 `weather.rng.state` 的雜湊（`WorldWind.roll`）。天氣的亂數只在換段時抽取，段內狀態不變且已存檔，所以同一段天氣永遠得到同樣的風。第一段的判斷是 `rng.state` 等於 `WorldWeather.initial_rng_state(seed)`。
- 陣風與風向偏轉是遊戲秒數的平滑雜訊（`FastNoiseLite`），種子從世界種子衍生。畫面、聲音與物理都讀同一個 `gust(seconds)`。
- 過渡進度直接讀 `weather.transition_elapsed`。`WorldWeather` 在換段前發出 `changing`，`WorldWind` 在那時記下即將離開的風力與風向當作過渡起點。這個起點只在記憶體裡：讀檔或第一次讀取時，風直接停在這一段的風力與風向，所以在過渡中讀檔會跳過剩下的風力過渡。
- 風不進檢查點，天氣的存檔格式不變。`override_tier` 與 `override_heading` 是終端機與測試場用的暫時設定，讀檔後回到自然值。
- 對外讀取：`strength()`（0 到 3 的連續風力）、`speed(seconds, exposure)`、`velocity()`、`gust()`、`heading()`；地貌用 `dryness_for`、`exposure_for` 與 `dust_amount` 三個純函式，輸入是 `TerrainLandforms.appearance_at()` 的值，直接混合 `MOISTURE` 與 `TREE_DENSITY`，測試不必建世界。
- 沙塵不寫進天氣的霧量，Slender Speaker 的霧量判斷不受影響。

### 沙塵的取樣與成本

- `apply_time` 每次在攝影機的位置取一次風與沙塵，存成 `clock.wind_velocity`、`clock.dust`、`clock.haze_dust`、湧浪 `clock.dust_surge` 與地貌的沙色 `clock.dust_color`（`_sample_wind`；沒有地形時用 `dust_day_color`）。`dust` 含陣風，給沙粒、沙團與之後的聲音用；`haze_dust` 用平均風速（`WorldWind.mean_dust_at`），給霧、天色與陽光用，所以遠景不會隨每陣風一收一放。畫面與聲音都讀這些值，不自己取樣。攝影機在別的世界（室內副本）或沒有地形時，沙塵是零。`landform_override` 是測試場用的地貌替換。
- 沙粒、遠處沙團與近處沙幕各是一個固定種子的 `MultiMesh`（`WeatherDust.FIELDS`），位置由著色器依時間、累積的風與攝影機計算；每一幀只更新參數，顯示數量隨沙塵增減（`field_share`），上限是開頭的常數。沙幕的濃淡由跟著風移動的雜訊決定。`WeatherDust.wall` 由陣風（`WorldWind.gust`）超過門檻的部分平滑而來，湧浪時門檻降低（建立 `WALL_RISE`、散去 `WALL_FALL`），放大沙幕不透明度並收起空隙。沙幕與沙團的自發光是霧色加上太陽光色乘能量與 `dust_sun_glow`，所以會隨晴陰與時間變。
- 沙雲是一個跟著攝影機的 `FogVolume`，`WeatherDust.show_billows` 預設關閉，第一次打開時才建立，所以遊戲不會編譯霧著色器。它的霧著色器 [dust_billows.gdshader](../../world/dust_billows.gdshader) 以減去風的累積位移後的世界座標取 3D 雜訊，所以沙雲跟著空氣走；高度從粗格遮蔽快取算起，屋頂或遮棚表面以下沒有沙雲。密度讀 `haze_dust`，不隨陣風起伏；RV 車廂的 `CabinAir`（-1.0）可以抵消，所以 `dust_billow_density` 上限低於 1。沙塵時體積霧的範圍拉長到 `dust_volume_end_ratio`，仍在霧的終點之內。
- 遮蔽共用雨的高度圖與 RV 車頂碰撞盒：`WeatherRain` 在有雨或有沙塵時（`sheltering`）維持更新，並把車頂資料也寫給 `shelter_materials`。沙塵不另外打射線。兩邊的著色器共用 [weather_shelter.gdshaderinc](../../world/weather_shelter.gdshaderinc)。

### 霧與地景的配合

- 林間的霧塊由 `ForestFog` 隨區塊建立，建立時向時鐘登記材質（`register_fog`），區塊卸載時解除。密度、風的位移（`drift`）與撕裂程度（`torn`）由時鐘統一更新。
- 霧塊的飄移速度是 `mist_drift_floor` 加上當地風速乘 `mist_drift_share`，時鐘把位移累積在 `mist_drift`，換風向時不跳動。風速在 `mist_tear_start` 到 `mist_tear_full` 之間把密度最多減少 `mist_tear`。這些只屬於畫面，不存檔；距離霧不隨風變，遊戲規則讀到的霧不受影響。
- 植被在被霧完全遮住之後才整批裁切，裁切距離在生成時依霧的終點決定。所以改霧的距離要在生成前改，已經生成的區塊要重建才會跟上；密度與顏色則是即時生效。
- `WorldGenerator.completed_scenery_clearance` 回報攝影機周圍連續完成的地景範圍，`WorldStreamVisibility` 據此收近霧的終點。收近是立即的，放開有速度上限（`stream_reveal_speed`）。
- 局部霧只在 Forward+ 渲染器存在。相容模式保留一樣的距離霧，只是沒有霧塊。

### 雨的成本

- 雨滴不是逐顆更新的物件。兩層雨幕各是一個固定種子的 `MultiMesh`，位置由著色器依時間與世界座標計算；每一幀只更新攝影機、時間與天氣參數。粒子數量是 `WeatherRain` 開頭的常數。
- 遮雨用兩張以世界座標定位的高度圖（`RainCover`），每個物理步只更新固定數量的格子。RV 車頂另外以碰撞盒傳給著色器逐粒子判斷，上限是 `MAX_ROOF_SHAPES`。
- 每個物理步的射線總數有上限（`MAX_RAYS`），和雨量無關。

### 環境音

- `WorldClock` 建立 `WorldAmbience`，和 `WeatherRain` 同一個生命週期。它自己的亂數只決定挑哪個聲音、放在哪裡、隔多久，不碰玩法或世界生成的亂數。
- 每次間隔從 `INTERVAL` 均勻抽取，`next_wait` 依 `effective_visual_weather()` 的霧與雨乘上 `FOG_SPARSER`、`RAIN_SPARSER`。到時呼叫 `play_next`。
- 戶外聲音由純函式 `WorldAmbience.weights` 依日光（`WorldClock.daylight()`，和光照共用）、森林與公路權重加權抽選，放在攝影機周圍 `OUTDOOR_DISTANCE` 內的隨機方位；霧讓距離拉遠 `FOG_DISTANCE`、音量降低 `FOG_GAIN_DB`。事件在 `assets/audio/events/ambience/`，走 `Outdoors` bus（送往 `Ambience`），衰減用 `distant`，遠處由 `AudioStreamPlayer3D` 的距離濾波變悶。
- 每 `SAMPLE_SECONDS` 在攝影機位置取樣一次：森林權重來自 `landforms.flora_weights` 在周圍五點的樹木機率，公路權重來自 `road_query` 的距離；沒有 `WorldGenerator` 時兩者為零，測試場可用 `forest_override` 與 `road_override` 指定。同時向上打一條射線，碰到東西就把 `Sfx.outdoor_shelter` 設為 `ROOF_SHELTER`。
- `Outdoors` 的音量與截止頻率由 `Sfx` 寫入：遮蔽值取 `Exterior` 的車廂遮蔽與 `outdoor_shelter` 的較大者，曲線和引擎遮蔽都和 `Exterior` 相同。
- 聲音經 `Sfx.play_at` 播在聆聽世界的固定點：聲源是位在原點、不會移動的聲源池。
- 室內判斷看 `Sfx.listening_outdoors()`，不看 `PoiInstanceManager.active_id`：死亡後的戶外回放鏡頭雖然仍在副本裡，聽的是戶外。室內的滴水與冷縮聲依位置走 `Exterior`，所以會套上房間殘響。`InteriorProfile.room_tone` 經 `Sfx.set_listener_viewport` 傳入，`Sfx.room_tone()` 讀出，以 `ROOM_TONE_DB` 直接走 `Ambience`；換到不同的嗡聲時先淡出舊的再播新的。

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
- 選單第一次開啟時，若場景樹裡有 `playground_controls` 群組的節點，就多建一頁 Playground，交給該節點的 `build(page)` 填內容。這個節點只有測試場會放（[PlaygroundControls](../../tests/playgrounds/support/playground_controls.gd)），選單本身不依賴測試程式。

### 輸入遮罩

- 設定選單不設 `SceneTree.paused`。它靠玩家的 `settings_open` 擋輸入。
- 玩家、互動射線、駕駛座與車體都用同一個判斷 `is_gameplay_input_blocked`，事件與按住的鍵都涵蓋。新增會讀輸入的系統要用同一個判斷，否則選單開著時它還會動。

### HUD 的顯示

- 每個 HUD 用的 `CanvasLayer` 建立時呼叫 `HUDVisibility.attach`，F12 才關得掉它。
- 需要隨視窗縮放的介面用 `UILayout.attach`。它每幀只比較視窗尺寸，變了才重排，所以玩家搬進室內副本的子視窗後仍然正確。

### 存檔

檢查點存時鐘（累積秒數與一天的長度）與天氣（目前與目標的狀態、過渡進度、剩餘時間、亂數狀態），兩者都是必要欄位，由 `WorldClock.valid_state` 與 `WorldWeather.valid_state` 檢查。讀檔時在世界的子節點就緒之前還原。不計算離線時間。風不存檔，由還原後的天氣段推得。
