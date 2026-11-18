# 音效系統重做

**進度。** 混音基礎和第一輪 RV 試點已實作，等待使用者試聽。試點涵蓋車門、引擎和車外預警。

## 目標

- 每個聲音聽起來像實體：金屬是金屬，引擎是引擎，不再像 UI 嗶聲。
- 聲音是資訊：玩家能靠聲音判斷方向、距離、在車內或車外，以及怪物在做什麼。這是 [恐怖氛圍研究](../reference/research/lethal-company-horror-atmosphere.md#p1建立聲音資訊層) P1 的內容。
- 同一事件每次聽起來略有不同，但不消耗玩法用的亂數，固定種子重現的局不受影響。
- 新增一個聲音只需要做素材並寫一個資源檔，不必再寫合成程式。
- 混音分層，可以在設定裡分開調音樂、音效和環境音。

## 重做前的問題

| 問題 | 位置 | 後果 |
|---|---|---|
| 約十個模組各自在執行時用正弦波、白噪音和指數衰減合成 PCM | [vehicle_audio.gd](../../rv/vehicle_audio.gd)、[pistol.gd](../../props/pistol.gd)、[panel_damage_effect.gd](../../rv/panel_damage_effect.gd)、[monster_boarding_visual.gd](../../enemies/monster_boarding_visual.gd)、[player_gore.gd](../../player/player_gore.gd)、[raker_impact_effect.gd](../../enemies/raker_impact_effect.gd)、[scrapper_crush_effect.gd](../../equipment/scrapper_crush_effect.gd)、[weather_rain.gd](../../world/weather_rain.gd) | 音色單薄，缺少起音和質感；同樣的合成程式重複十份 |
| 合成取樣率 22,050 Hz 單聲道 | 同上 | 11 kHz 以上沒有內容，金屬、玻璃和槍聲發悶 |
| 引擎是一段 1 秒的 46 Hz 迴圈，靠 `pitch_scale` 0.85–1.7 變化 | [vehicle_audio.gd](../../rv/vehicle_audio.gd) `_process` | 高轉速像電子蜂鳴，聽不出負載 |
| `mechanical`、`complete`、`blocked` 三個嗶聲涵蓋所有車上操作 | [chassis.gd](../../rv/chassis.gd) `feedback`、[rv_door.gd](../../equipment/rv_door.gd)、[rear_ramp.gd](../../rv/rear_ramp.gd)、[engine_hatch.gd](../../rv/engine_hatch.gd)、[recovery_jack.gd](../../props/recovery_jack.gd) | 排檔、手煞車、車門、坡板、千斤頂聽起來一樣 |
| 合成種子固定，多數聲音沒有變體或隨機音高 | 各合成函式 | 重複感強 |
| 沒有 bus 配置，全部送 Master；設定只有主音量 | [game_settings.gd](../../core/game_settings.gd) `_apply_master_audio` | 無法分開混音 |
| 受傷悶聲濾波掛在 Master | [player_injury_effects.gd](../../player/player_injury_effects.gd) `set_consciousness_muffle` | 連 UI 與音樂一起悶掉 |
| 雨聲每個實例動態新增一條 bus | [weather_rain.gd](../../world/weather_rain.gd) `_ready` | bus 結構不固定 |
| 每個模組各自建立 `AudioStreamPlayer3D`，衰減參數各自寫死 | 同上 | 距離感不一致，同時發聲數沒有總上限 |
| 沒有車內外隔音；只有雨聲有遮蔽 | — | 在車裡聽外面的怪物和站在外面一樣 |
| POI 室內沒有殘響 | — | 室內外聽起來一樣 |
| 沒有玩家腳步、怪物移動或叫聲、環境音 | — | 無法靠聲音判斷威脅 |

已經做得好的部分保留：Slender Speaker 的《給愛麗絲》、短波收音機的人聲與載波、油桶爆炸與落地聲都是事先做好的檔案，只改成走新的 bus 與事件層。

## 已確認的設計決定

| 題目 | 決定 |
|---|---|
| 是否重做 | 重做；先寫完整計畫（2026-11-18） |
| 素材來源 | 允許原創及 CC0 錄音。逐個來源記錄作者、授權連結和處理方式。 |
| 首輪試聽 | 比較車門開鎖與關門、引擎怠速和拉轉、車外預警在車內外的差異。 |
| 設定滑桿 | 主音量、音樂、音效、環境音。世界內的聲音線索由音效滑桿控制。 |

以下是我代為決定、你可以否決的項目：

- **素材改為離線製作的音檔**，執行時不再合成。程序變化來自變體抽選、音高與音量抖動、依強度選層，以及依世界種子擺放的環境聲源。
- 素材規格：44.1 kHz、16 bit。3D 音源一律單聲道；環境底噪與音樂可用立體聲。短音用 WAV，超過 10 秒的迴圈用 Ogg Vorbis。
- 優先為腳步、撞擊等高頻事件準備多個變體。首輪車門各用一段錄音，配合小幅音高變化。
- 由音效服務持有專用亂數，直接抽取音檔與音高、音量變化。`AudioStreamRandomizer` 在 Godot 4.7.2 會消耗全域亂數，遊戲中仍有怪物行為使用同一來源。引擎用獨立播放器交叉淡化，可逐層調整音高。遠距發悶沿用 `AudioStreamPlayer3D` 的距離濾波。
- 遷移順序：先做基礎與 RV 試點，你聽過並同意方向後才推廣到其他模組。
- 跨模組改動使用獨立工作樹和分階段 PR。

## 待你決定

| 題目 | 選項 | 我的建議 |
|---|---|---|
| 怪物聲音特徵 | 每種怪物的聲音是否洩漏位置、何時洩漏 | 階段 5 開始前逐隻討論，因為這會改變遭遇規則 |

## 設計

### 1. Bus 配置

新增 `default_bus_layout.tres`，固定以下結構：

```
Master
├─ Music           背景配樂
├─ UI              畫面操作回饋，跟隨音效滑桿
└─ World           受傷與一般致死的悶聲濾波
   ├─ Effects      音效滑桿
   │  ├─ Exterior  車外聲源，含 Slender Speaker 的《給愛麗絲》
   │  ├─ Cabin     車內聲源，含引擎和車門
   │  └─ Voice     收音機人聲，保留既有空間距離
   └─ Ambience     環境音滑桿
      └─ Rain      只對下雨套用原有遮蔽濾波
```

- 受傷悶聲從 Master 移到 World，UI 與音樂不再受影響。
- 雨聲的固定 `Rain` bus 送往 `Ambience`，雨遮只濾掉雨聲。
- 一般致死在 `World` 變悶，斷頭致死沿用 `GameSettings` 暫時靜音 `Master` 的機制。見 [GDD](../../GDD.md)。

### 2. 音效事件層

新增 `core/audio/`：

- **`SoundEvent`（Resource）**：試點資源定義音檔候選、音量、音高變化、bus 與衰減。強度曲線、冷卻時間、優先度與事件各自的發聲限制，等遷移撞擊等事件時再依需求加入。
- **`SoundAttenuation`（Resource）**：距離衰減預設。至少分成 `near`（手邊操作，約 15 m）、`vehicle`（RV 與設備，約 50 m）、`loud`（槍聲、爆炸，約 80 m）、`landmark`（Slender Speaker）。統一 `unit_size`、`max_distance`、距離濾波頻率。
- **`Sfx`（autoload）**：試點用 `play(event, source, local_position)` 播放並跟隨一次性 3D 音效。池掛在目前聆聽的 viewport，POI 出入口會切換。首輪上限為 12，滿時略過下一個一次性音效。遷移大量撞擊聲前，再量測並設計依優先度搶占。
- **`SoundLoop`（Node3D 元件）**：持續聲源（引擎、輪胎滑移、刮地、絞碎機、雨），由擁有者每幀餵入參數。
- **亂數**：`Sfx` 使用自己的亂數產生器，絕不讀寫玩法或世界生成的亂數，固定種子重現的局不會因為播了一個聲音而改變。
- **事件檔位置**：`assets/audio/events/<domain>/<name>.tres`，例如 `rv/door_open.tres`。素材放在同一個 domain 的 `assets/audio/<domain>/`。

`Chassis.feedback(kind, ...)` 這類字串介面改成直接傳 `SoundEvent`。每個呼叫點各用自己的事件：排檔、手煞車、車門開關、坡板、維修蓋、千斤頂、安裝完成、受阻各自獨立。

### 3. 引擎與車輛

- 第一輪用同一輛柴油車的怠速和拉轉錄音，依 `Chassis.engine_rpm()` 交叉淡化。試聽後再決定需要的轉速分層及各層音高範圍。
- 另加一層負載：油門開度提高時加入進氣與排氣的粗糙聲，鬆油門時有減速的回火感。
- 啟動、熄火、啟動失敗各自是一次性事件。
- 輪胎依路面分柏油、路肩、越野三種滾動聲和滑移聲，路面判斷沿用 [tire_model.gd](../../rv/tire_model.gd) `surface_grip` 背後的 `WorldField.road_query`。
- 撞擊依強度選輕、中、重三層，重撞再疊一層玻璃或車殼撕裂聲。
- 車殼受怪物攻擊、面板毀壞、碎片落地沿用 [panel_damage_effect.gd](../../rv/panel_damage_effect.gd) 的時序，只換素材並改走事件層。

### 4. 空間與遮蔽

- **車內外**：用聆聽者在車身局部空間的位置判定，在車頂時歸為室外。在車廂內以約 0.3 秒過渡降低 Exterior 的音量與高頻。門片角度和缺失車板都會改變遮蔽。其餘車內聲源從車外聽見的程度留待試聽調整。
- **引擎遮蔽**：引擎轉速高時 Exterior 再小幅降低，讓「開車時聽不清外面」成為代價（研究 P1-2）。
- **POI 室內**：進入 POI 室內時，World 加上依室內大小設定的殘響。小房間、走廊、大廳三種預設，由 POI 設定資料提供。
- 非空間化的環境底噪保持很小聲，避免掩蓋方向判斷（研究 P1-4）。

### 5. 新增的聲音層

- **玩家腳步**：依路面（柏油、路肩、泥土、草地）、RV 車廂地板、車頂金屬、室內地板分別取變體。跑步更大聲，蹲下更小聲。玩家自己的腳步走 Cabin 或 Exterior，跟著遮蔽規則。
- **怪物特徵聲**：每種怪物有可以學習的移動聲與預兆聲（研究 P1-3）。具體規則要逐隻討論，見上方「待你決定」。
- **環境**：日、夜、霧、森林、公路各一層底噪，依時間與天氣交叉淡化。另外依世界種子在區塊內擺放少量空間化環境聲源，例如風吹樹梢、遠處金屬吱嘎、夜間蟲鳴，隨區塊串流載入與卸載。
- **操作**：撿起、放下、背包、製作台、平板各自有聲音。畫面操作聲走 UI bus。

### 6. 製作流程

- 有 REAPER 專案或可重製的剪輯腳本時，放入 `art_source/audio/<domain>/`。試點流程和來源見 [RV 錄音](../../assets/audio/rv/README.md)。
- 音量規格：一次性音效峰值 -1 dBFS；迴圈與環境底噪用響度對齊，同類事件之間的差距在 ±2 dB 內，最終以試玩為準。
- 每個素材資料夾的 README 記錄來源、授權和製作方式。
- 每批素材先檢查峰值、頻譜和迴圈接縫，再在試玩場景驗收辨位和聽感。

### 7. 測試

- 驗證所有 `assets/audio/events/` 下的事件：串流存在、引用的 bus 存在、數值範圍合理。數值從資源讀取，不寫死在測試裡。
- 驗證 `Sfx` 池的上限、安全切換到 POI 的 `World3D`，以及 POI 播放時拒絕公路世界的來源。加入優先度後再驗證搶占。
- 車內外切換時，Exterior 在車內的截止頻率低於車外（只比較相對關係）。
- 播放聲音不改變世界生成或遭遇用的亂數狀態。
- 現有測試繼續通過：[test_body_recovery.gd](../../tests/test_body_recovery.gd) 的主音量靜音、[test_slender_speaker_acquisition.gd](../../tests/test_slender_speaker_acquisition.gd) 的迴圈、[test_item_player.gd](../../tests/test_item_player.gd) 的收音機換台。

### 8. 試玩場景

用 [RV 音效試點](../../tests/playgrounds/rv_audio_playground.tscn) 比較車內外、開關門、怠速到拉轉及同一個車外預警聲。試聽時先試著指出警示聲的方向，再比較關門和開門，最後確認引擎拉轉時仍可辨認預警。試點驗收後移除 A/B 切換和被取代的合成聲。可駕駛和 POI 殘響測試追加在後續階段。

## 階段

| 階段 | 內容 | 完成條件 |
|---|---|---|
| 0 | Bus 配置、四條設定滑桿、受傷悶聲移到 World、雨聲改用固定 bus | 驗證既有遊戲音源與設定 |
| 1 | 基礎 `SoundEvent`、`Sfx`、POI 聆聽切換 | 驗證聲源池上限、RNG 隔離與室內外切換 |
| 2 | **RV 試點**：門、引擎怠速與拉轉、啟動與熄火、車外預警和車廂遮蔽 | **你在試玩場景比較新舊後同意方向** |
| 3 | 遷移剩餘 RV 聲音，再推廣至手槍、車殼受損、怪物抓握與攻擊、血肉、Raker 撞擊、絞碎機、油桶、吸氣、耳鳴、倒樹、雨 | 遊戲執行時的聲源全部播放離線製作的素材 |
| 4 | 空間：調整車內外混音、引擎遮蔽、POI 室內殘響 | 試玩驗收車內外與室內聽感 |
| 5 | 新聲音層：腳步、怪物特徵聲（先逐隻討論）、環境底噪與區塊環境聲源、操作聲 | 試玩驗收 |
| 6 | 文件：改寫 [assets/audio/README.md](../../assets/audio/README.md)、[rv.md](../systems/rv.md) 的音效段落與 [environment.md](../systems/environment.md) 的設定；在 [architecture.md](../../architecture.md) 加入共用音效層 | 計畫檔刪除，未結項目移到計畫總覽 |

第一個 PR 涵蓋階段 0 至 2。試聽確認方向後再擴大遷移。

## 風險

| 風險 | 對策 |
|---|---|
| 素材量大，製作時間主要花在聲音本身 | 階段 2 只做 RV；之後依遭遇與操作頻率排序 |
| 我無法親耳判斷好壞 | 每批先做客觀分析，再交給你試聽；必要時一次做兩三個版本讓你挑 |
| `AudioStreamPlayer3D` 太多造成效能負擔 | 全域聲源池與上限；試玩時量測 |
| 引擎分層的接縫或相位問題 | 用同一車輛的錄音剪輯迴圈，檢查接點並試聽不同轉速及淡化過程 |
| 車頂、破口或 POI 切換讓遮蔽與定位出錯 | 測試車頂判定、門片角度、車板破損和不同 `World3D` 的聆聽切換 |
| 遷移期間新舊兩套系統並存 | 每個階段結束時刪掉該階段取代的舊程式，不留相容分支 |
