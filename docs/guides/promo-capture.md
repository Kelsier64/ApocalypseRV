# 宣傳影片錄影

錄影世界建在正式主世界上：固定種子、跳過開局，每個鏡頭依 [shots/](../../tests/playgrounds/promo/shots/) 的設定擺好場面。程式在 [tests/playgrounds/promo/](../../tests/playgrounds/promo/)。

## 兩種錄法

| 錄法 | 用在哪裡 | 怎麼錄 |
|---|---|---|
| **即時錄影** | 你親自操作的鏡頭：第一人稱、開車、被抓、搜刮 | 開啟錄影世界，用 OBS 或其他即時錄影軟體錄視窗或全螢幕 |
| **自動演出** | 運鏡、縮時、腳本駕駛等不需要操作的鏡頭 | `-Preview -Movie`，Godot Movie Maker 逐幀輸出 |

Movie Maker 每一幀都要編碼，實際只跑十幾 fps，遊戲時間跟著變慢，所以**不能拿來錄人在操作的鏡頭**。啟動腳本會擋下沒有 `-Preview` 的 `-Movie`。

## 即時錄影

```powershell
./scripts/promo-capture.ps1
./scripts/promo-capture.ps1 -Shot B3 -Fullscreen
```

不帶參數會開 R2。進遊戲後按 **F2** 打開錄影面板，之後都在同一個視窗裡切換鏡頭，不必重開。面板開著時遊戲暫停。

1. F2 開面板，在左邊選鏡頭、選變體，按 `Load shot`（或雙擊）。
2. 等左上角出現 `Ready`。面板右邊有這個鏡頭 F3 會做什麼與拍攝步驟。
3. 選鏡頭模式、調好位置，按 F12 切乾淨畫面。
4. OBS 開始錄，按 F3 觸發，演完停止錄影。剪輯時裁掉頭尾。
5. 重來按面板的 `Restart shot`。

| 按鍵 | 操作 |
|---|---|
| F2 | 開關錄影面板（Esc 也能關） |
| F3 | 觸發這個鏡頭的動作 |
| F4 | 依序切換：玩家視角 → 自由鏡頭 → 跟拍 → 玩家視角 |
| F8 | 遊戲速度 1 → 0.5 → 0.25 倍 |
| F12 | 乾淨畫面：隱藏 HUD 與左上角狀態列 |

失敗時不會關閉遊戲：狀態列顯示原因，按 F2 換一個鏡頭或重開。

### 鏡頭模式

- **玩家視角**：正式的第一人稱或駕駛座相機。
- **自由鏡頭**：滑鼠轉向、WASD 移動、Space／Shift 升降、滾輪調速度、Z／X 拉近拉遠，轉向與移動都有平滑。自由鏡頭會接管鍵盤，玩家停在原地。
- **跟拍**：鏡頭只跟目標的水平朝向，車體顛簸、側傾與翻覆都不會傳到鏡頭上。**跟拍時鍵盤與滑鼠仍是玩家的**，可以一邊開車一邊從車外拍。目標是鏡頭的主角（怪物、油桶），沒有主角時跟 RV。
  - `Follow: keep framing`：保持你用自由鏡頭擺好的相對位置。
  - `chase`、`side`、`front`、`high`：車後、側面、前方低角度、高空的預設位置。
- 怪物判斷「有沒有被看見」一律用玩家自己的視線，不管畫面用哪個鏡頭。

### 運鏡路徑

路徑是一條通過關鍵點的平滑曲線，全程等速，只在頭尾加減速，中途不會在關鍵點停頓。

1. 切到自由鏡頭，飛到起點，按 **Enter** 加一個關鍵點（Backspace 刪掉最後一個）。
2. 依序加完其他關鍵點。視角（FOV）也會記進去。
3. F2 開面板，設定總秒數與要不要頭尾加減速，按 `Play rail` 試看。
4. 滿意後按 `Save rail`，存到 `tests/playgrounds/promo/rails/<鏡頭>[-<變體>].json`。這些檔案要提交，之後重開與自動演出都用同一條路徑。

B5、W1–W3 沒有存過路徑時，會自動產生一條預設路徑；存過之後就改用存下來的。

## 自動演出

```powershell
./scripts/promo-capture.ps1 -Shot W1 -Variant 4 -Preview -Movie
./scripts/promo-capture.ps1 -Shot D3 -Preview -Movie -Exterior
```

`-Preview` 會自動觸發、演完後結束。`-Movie` 預設輸出 1920×1080、60 FPS 的 AVI；`-Fps`、`-WindowResolution` 可以調，`-Format Png` 改成影格序列。`-Exterior` 讓 O2、O4、D1、D2、D3 的腳本駕駛改用車後跟拍。

Movie Maker 從啟動就開始錄，載入畫面也在檔案裡。每次錄影的資料夾在 `.godot/promo-captures/`，裡面的 `take.json` 記錄正式開演的影格與秒數，剪輯時從那裡開始。

## 鏡頭

每個鏡頭的 F3 動作與拍攝步驟在錄影面板上，內容來自 [shots/](../../tests/playgrounds/promo/shots/) 各檔的 `title`、`action`、`steps`。分組如下：

| 編號 | 內容 |
|---|---|
| B1–B6 | 地堡：手電筒探索、黑影、Raker 抓人、油桶人、樓層俯瞰、扛引擎 |
| O1–O5 | 戶外：路邊油桶人、撞油桶、白影、Slender Speaker 追車與抓司機 |
| D1–D6 | 駕駛：撞樹、釘帶與廢車、換檔、翻車與千斤頂、溜車、越野 |
| R1–R3 | 車內：分解機、合成站、修車與安裝設備 |
| W1–W3 | 主世界：公路空拍、不同種子對照、日夜與天氣縮時 |
| T1 | 宣傳片：駕駛座錨點（開場；變體 1 是結尾）。加 `-Exterior` 錄第一段的車外跟拍 |
| T2 | 宣傳片第三段：經過路肩的前任 RV、旁白第 12 到 15 句、起霧與斷訊、霧裡的巨人，最後急轉撞上電線桿 |
| T3 | 宣傳片第三段：撞車後趴在路上，睜眼先看到自己趴著的手臂，抬頭看巨人拆車頂；巨人轉身走過來時盯著它往後爬（現場錄影用 S，自動演出不爬），巨人的手抓到主角時切到第三人稱，主角在手裡站直、被舉到喇叭前處決 |

T 組的鏡頭照[宣傳片劇本](../plans/promo-trailer.md)拍，F3 開始鏡頭檔裡的時間軸。

鏡頭檔有 `timeline` 時（T 組與 D6），F3 開始時間軸，見[時間軸](#時間軸)。其他鏡頭用 `setup` 指定佈置與 F3 動作，例如 `tree_row`、`spike_strip`、`monster`、`recycler`，同一個 `setup` 可以給新鏡頭或變體重用；可用的名稱與各自讀取的欄位在 `promo_outdoor.gd`、`promo_bunker.gd`、`promo_workshop.gd` 的 `prepare` 裡。這些鏡頭的 F3 動作多半要等條件成立（Raker 抓到人、分解機處理完、第二次按 F3 放千斤頂），所以不寫成依秒數觸發的時間軸。其他共用欄位：`drives`（RV 保留物理，不凍結）、`rv_frozen`（保留物理但在動作前先固定）、`autoplay_seconds`（自動演出的錄影長度）、`autoplay_gears`（自動演出的換檔時間）、`dark_room` 與 `bunker_population`（地堡選點條件）、`player_camera`（F3 前切回玩家視角）。

B1–B6 共用種子 42 的同一座地堡。要找其他地點，用正式生成規則掃描種子，結果寫到 `.godot/promo/scout.json`：

```powershell
godot --headless --path . --script res://scripts/promo_scout.gd -- 42 43 44
```

## 時間軸

鏡頭檔可以有 `timeline`：一串依秒數排列的事件，F3 或 `-Preview` 開始計時。時間跟著遊戲的物理時間走，所以 F8 慢動作和 Movie Maker 都會同步。格式與每個動作需要的參數在 [promo_timeline.gd](../../tests/playgrounds/promo/promo_timeline.gd) 的 `ACTIONS`，做法在 [promo_trailer.gd](../../tests/playgrounds/promo/promo_trailer.gd)：

| 動作 | 做什麼 |
|---|---|
| `drive` | 沿公路巡航，`speed` 是時速（km/h），`lateral` 是離路中心的側向距離；給 `seconds` 時在這段時間內慢慢移到新的側向位置（D6 用來開下公路） |
| `gear`、`brake` | 換檔；剎停並結束巡航 |
| `line` | 車內調度喇叭播出旁白第 `id` 句 |
| `static` | 把收訊固定在 `level`（0–1），越低底噪越大；`cut` 立刻切斷正在播的句子 |
| `radio_off` | 喇叭完全安靜到鏡頭結束 |
| `weather` | 在 `seconds` 秒內把天氣變成 `to`（晴、雨、霧） |
| `look` | 在 `seconds` 秒內把駕駛座視角轉到 `yaw`、`pitch`（度）。只在自動演出生效，現場錄影由滑鼠控制 |
| `gaze` | 趴著的主角在 `seconds` 秒內轉頭看向 `target`（目前只有 `giant`）離地 `up` 公尺的位置，之後一直盯著它，直到被抓。只在自動演出生效 |
| `eyes` | 用遊戲的眼皮效果在 `seconds` 秒內睜眼或閉眼 |
| `giant` | 巨人站在撞擊電線桿後方 `beyond` 公尺（預設 12）的車道上，面向 RV。AI 關閉，頭上喇叭照遊戲的距離處理淡入 |
| `steer` | RV 離撞擊電線桿 `within` 公尺內時全油門轉向電線桿；撞上時留下 `impact` 標記並放開油門 |
| `giant_smash` | 巨人走到撞毀的 RV 旁砸車頂，之後由遊戲的 AI 接手 |
| `giant_release` | 這一下砸完以後，巨人不再理會 RV，轉向地上的主角，照遊戲原本的方式抓人、處決。不加這一步，巨人會一直檢查車頂，大約二十秒後才去抓人 |
| `crawl` | 自動演出時按住前進 `seconds` 秒，`back` 改成按住後退；現場錄影由鍵盤控制 |
| `marker` | 在 `take.json` 留一個標記 |
| `end` | 鏡頭在這裡結束；自動演出照這個時間停止錄影 |

`live_controls` 的鏡頭（回憶段，例如 D6）現場錄影時由玩家自己開車，`drive`、`gear`、`brake`、`steer` 只在自動演出生效。

鏡頭檔另有三個佈景欄位：`wreck` 是側翻的前任 RV（只有外觀，不參與物理，也不算 RV，可附 `corpse` 屍體），`crash_pole` 是放在路肩平地上的電線桿（遊戲生成的電線桿都在路堤上，RV 開不到），`invulnerable` 讓主角在撞擊中不受傷。T3 另有 `rv_at_pole`（RV 停在撞擊電線桿上的姿勢）、`prone`（主角四肢完整地趴在地上；`from_giant` 讓主角在巨人開始砸車時移到巨人那一側，車身才不會擋住巨人的視線，`pitch` 讓主角面向巨人但低頭往下看幾度）、`cut_away`（巨人的手抓到主角那一格切到一台固定的第三人稱鏡頭：在主角背向巨人那一側 `back` 公尺、橫向 `side` 公尺、離地 `up` 公尺，鏡頭一路對著主角上方 `aim_up` 公尺，`fov` 是視角）、`engine` 與 `radio`（關掉引擎與車內喇叭）。位置都是相對鏡頭 `distance` 的公路座標 `s` 與側向 `lateral`。

時間軸格式錯誤時，載入鏡頭就失敗並顯示原因。`line` 和 `marker` 會把影格編號寫進 `take.json` 的 `markers`，剪輯時用來對字幕與硬切點。T3 另外標記巨人的 `grab`、`lift`、`hold`、`crush` 與主角死亡的 `death`；硬切點就是 `death` 那一格。T3 在手抓到主角時另外標記 `cut_away`；舉到喇叭前、進入 `hold` 時，遊戲自己的處決鏡頭會接手，一直到死亡。

### 旁白

旁白的詞在 [narration.json](../../tests/playgrounds/promo/narration.json)，用遊戲的主管詞庫一個字一個字拼接，詞間與句間的停頓跟遊戲廣播相同。拍攝時車內喇叭的廣播排程停用、收訊固定，不會插播遊戲廣播。剪輯時另外上的句子用下面的指令匯出成 WAV，連同每句長度與字幕寫進 `.godot/promo/narration/`：

```powershell
godot --headless --path . --script res://scripts/promo_narration.gd
```

旁白用到的詞要先在詞庫裡，加詞的方法見[主管詞庫語音](../../assets/audio/dispatch_voice/README.md)。

## 測試

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test.ps1 -TestFilter test_promo_world.gd
godot --headless --fixed-fps 60 --path . --script res://tests/test_promo_world.gd -- --all-takes
```

第一條跑代表性鏡頭，以及面板、鏡頭與運鏡路徑的檢查；第二條逐一跑全部鏡頭，會重建正式世界很多次。
