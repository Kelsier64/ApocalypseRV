# 音效系統重做

狀態：**計畫已寫好，等使用者決定素材來源後開工**。

## 目標

- 每個聲音聽起來像實體：金屬是金屬，引擎是引擎，不再像 UI 嗶聲。
- 聲音是資訊：玩家能靠聲音判斷方向、距離、在車內或車外，以及怪物在做什麼。這是 [恐怖氛圍研究](../reference/research/lethal-company-horror-atmosphere.md#p1建立聲音資訊層) P1 的內容。
- 同一事件每次聽起來略有不同，但不消耗玩法用的亂數，固定種子重現的局不受影響。
- 新增一個聲音只需要做素材並寫一個資源檔，不必再寫合成程式。
- 混音分層，可以在設定裡分開調音樂、音效和環境音。

## 現況與問題

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

以下是我代為決定、你可以否決的項目：

- **素材改為離線製作的音檔**，執行時不再合成。程序變化來自變體抽選、音高與音量抖動、依強度選層，以及依世界種子擺放的環境聲源。
- 素材規格：44.1 kHz、16 bit。3D 音源一律單聲道；環境底噪與音樂可用立體聲。短音用 WAV，超過 10 秒的迴圈用 Ogg Vorbis。
- 每個一次性事件至少 3 個變體，重要的（撞擊、腳步、車門）4–6 個。
- 盡量用 Godot 內建型別：`AudioStreamRandomizer` 處理變體與抖動，`AudioStreamSynchronized` 處理引擎分層，`AudioStreamPlayer3D` 的內建距離濾波處理遠距發悶。開工時先在 4.7.2 確認這些 API。
- 遷移順序：先做基礎與 RV 試點，你聽過並同意方向後才推廣到其他模組。
- 這是跨模組的工作：在 `claude/audio-overhaul` worktree 進行，每個階段一個 PR。

## 待你決定

| 題目 | 選項 | 我的建議 |
|---|---|---|
| 素材來源 | A：只用原創（REAPER 合成加自己錄音）；B：另外允許 CC0 錄音素材，每個資料夾的 README 記錄出處 | B。腳步、車門、金屬這類擬音幾乎只能靠真實錄音，純合成很難做到可信；CC0 不需要署名，現有「可隨專案散布」的授權條件不變 |
| 設定滑桿 | 主音量／音樂／音效／環境音四條，或只加音效與音樂 | 四條 |
| 怪物聲音特徵 | 每種怪物的聲音是否洩漏位置、何時洩漏 | 階段 5 開始前逐隻討論，因為這會改變遭遇規則 |

## 設計

### 1. Bus 配置

新增 `default_bus_layout.tres`，固定以下結構：

```
Master
├─ Music        Slender Speaker 這類樂曲
├─ UI           畫面操作回饋
└─ World        受傷悶聲濾波、死亡淡出
   ├─ Exterior  車外的世界聲源；玩家在車內時降低高頻與音量
   ├─ Cabin     車內聲源：引擎室、車門、設備；小空間殘響
   ├─ Ambience  環境底噪與雨聲
   └─ Voice     收音機人聲；永遠保持清楚
```

- 受傷悶聲從 Master 移到 World，UI 與音樂不再受影響。
- 雨聲改用固定的 Ambience bus，刪除動態新增 bus 的程式。
- 死亡時聲音變悶或切斷（[GDD](../../GDD.md) 生命與死亡）改作用在 World。`GameSettings` 現有的主音量靜音來源機制保留，製造台復活的測試沿用。
- 設定的音量各自對應一條 bus。

### 2. 音效事件層

新增 `core/audio/`：

- **`SoundEvent`（Resource）**：一個可播放的事件。欄位：串流（通常是 `AudioStreamRandomizer`）、音量、目標空間（Exterior／Cabin／Ambience／UI／Voice）、衰減預設、最大同時發聲數、冷卻時間、優先度，以及依強度（0–1）調整的音量和音高曲線。保留 `loudness` 欄位供將來的「槍聲引怪」使用（[GDD 第 9 節](../../GDD.md#section-9)），這次不接玩法。
- **`SoundAttenuation`（Resource）**：距離衰減預設。至少分成 `near`（手邊操作，約 15 m）、`vehicle`（RV 與設備，約 50 m）、`loud`（槍聲、爆炸，約 80 m）、`landmark`（Slender Speaker）。統一 `unit_size`、`max_distance`、距離濾波頻率。
- **`Sfx`（autoload）**：`play(event, position, strength)` 與 `play_attached(event, node, strength)`。用固定大小的 `AudioStreamPlayer3D` 池，全域上限約 32 個。池滿時依優先度和距離搶占最不重要的聲源。
- **`SoundLoop`（Node3D 元件）**：持續聲源（引擎、輪胎滑移、刮地、絞碎機、雨），由擁有者每幀餵入參數。
- **亂數**：`Sfx` 使用自己的亂數產生器，絕不讀寫玩法或世界生成的亂數，固定種子重現的局不會因為播了一個聲音而改變。
- **事件檔位置**：`assets/audio/events/<domain>/<name>.tres`，例如 `rv/door_open.tres`。素材放在同一個 domain 的 `assets/audio/<domain>/`。

`Chassis.feedback(kind, ...)` 這類字串介面改成直接傳 `SoundEvent`。每個呼叫點各用自己的事件：排檔、手煞車、車門開關、坡板、維修蓋、千斤頂、安裝完成、受阻各自獨立。

### 3. 引擎與車輛

- 引擎分成怠速、低、中、高轉速四層迴圈，依 `Chassis.engine_rpm()` 交叉淡化，每層只做小範圍的音高修正（約 ±15%）。
- 另加一層負載：油門開度提高時加入進氣與排氣的粗糙聲，鬆油門時有減速的回火感。
- 啟動、熄火、啟動失敗各自是一次性事件。
- 輪胎依路面分柏油、路肩、越野三種滾動聲和滑移聲，路面判斷沿用 [tire_model.gd](../../rv/tire_model.gd) `surface_grip` 背後的 `WorldField.road_query`。
- 撞擊依強度選輕、中、重三層，重撞再疊一層玻璃或車殼撕裂聲。
- 車殼受怪物攻擊、面板毀壞、碎片落地沿用 [panel_damage_effect.gd](../../rv/panel_damage_effect.gd) 的時序，只換素材並改走事件層。

### 4. 空間與遮蔽

- **車內外**：判斷聆聽者是否在 RV 車廂內（優先沿用 [RVSupport](../../core/rv_support.gd) 或座位狀態，開工時確認現有判斷）。在車內時 Exterior 加低通（約 1.5 kHz）並降 6–10 dB，Cabin 保持清楚；在車外時反過來輕微壓 Cabin。兩者用約 0.3 秒平滑過渡，門開著時遮蔽減半。
- **引擎遮蔽**：引擎轉速高時 Exterior 再小幅降低，讓「開車時聽不清外面」成為代價（研究 P1-2）。
- **POI 室內**：進入 POI 室內時，World 加上依室內大小設定的殘響。小房間、走廊、大廳三種預設，由 POI 設定資料提供。
- 非空間化的環境底噪保持很小聲，避免掩蓋方向判斷（研究 P1-4）。

### 5. 新增的聲音層

- **玩家腳步**：依路面（柏油、路肩、泥土、草地）、RV 車廂地板、車頂金屬、室內地板分別取變體。跑步更大聲，蹲下更小聲。玩家自己的腳步走 Cabin 或 Exterior，跟著遮蔽規則。
- **怪物特徵聲**：每種怪物有可以學習的移動聲與預兆聲（研究 P1-3）。具體規則要逐隻討論，見上方「待你決定」。
- **環境**：日、夜、霧、森林、公路各一層底噪，依時間與天氣交叉淡化。另外依世界種子在區塊內擺放少量空間化環境聲源，例如風吹樹梢、遠處金屬吱嘎、夜間蟲鳴，隨區塊串流載入與卸載。
- **操作**：撿起、放下、背包、製作台、平板各自有聲音。畫面操作聲走 UI bus。

### 6. 製作流程

- 合成與後製用 REAPER（`reaper-bridge`、`reaper-sound-design` skill），原始專案放 `art_source/audio/<domain>/`，與 Slender Speaker 的做法一致。
- 音量規格：一次性音效峰值 -1 dBFS；迴圈與環境底噪用響度對齊，同類事件之間的差距在 ±2 dB 內，最終以試玩為準。
- 每個素材資料夾的 README 記錄來源、授權和製作方式。
- 我聽不到聲音。每批素材都先用 render 與分析做客觀檢查（頻譜、峰值、迴圈接縫），再交給你在試玩場景中聽。

### 7. 測試

- 驗證所有 `assets/audio/events/` 下的事件：串流存在、引用的 bus 存在、數值範圍合理。數值從資源讀取，不寫死在測試裡。
- `Sfx` 池滿時搶占低優先度的聲源，且總數不超過上限。
- 車內外切換時，Exterior 在車內的截止頻率低於車外（只比較相對關係）。
- 播放聲音不改變世界生成或遭遇用的亂數狀態。
- 現有測試繼續通過：[test_body_recovery.gd](../../tests/test_body_recovery.gd) 的主音量靜音、[test_slender_speaker_acquisition.gd](../../tests/test_slender_speaker_acquisition.gd) 的迴圈、[test_item_player.gd](../../tests/test_item_player.gd) 的收音機換台。

### 8. 試玩場景

新增 `tests/playgrounds/audio_playground`：

- 一台靜止和一台可駕駛的 RV，一個可進入的 POI 室內。
- 螢幕上的面板可以逐一觸發每個事件、調整強度、在車內外之間切換聆聽位置。
- RV 試點期間保留一個「舊聲音」切換，讓你直接比較；試點驗收後連同舊合成程式一起刪除。

## 階段

| 階段 | 內容 | 完成條件 |
|---|---|---|
| 0 | Bus 配置、設定滑桿、受傷悶聲移到 World、雨聲改用固定 bus | 測試通過；聽感與現在一致 |
| 1 | 事件層：`SoundEvent`、`SoundAttenuation`、`Sfx`、`SoundLoop`；試玩場景骨架 | 事件驗證與聲源池測試通過 |
| 2 | **RV 試點**：引擎四層、啟動與熄火、所有車上操作、撞擊、輪胎、刮地；刪除 `vehicle_audio.gd` 的合成程式 | **你在試玩場景比較新舊後同意方向** |
| 3 | 推廣：手槍、車殼受損、怪物抓握與攻擊、血肉、Raker 撞擊、絞碎機、油桶、吸氣、耳鳴、倒樹、雨；刪除所有執行時合成 | 專案內沒有任何 `AudioStreamWAV.new()` 合成程式 |
| 4 | 空間：車內外遮蔽、引擎遮蔽、POI 室內殘響 | 試玩驗收車內外與室內聽感 |
| 5 | 新聲音層：腳步、怪物特徵聲（先逐隻討論）、環境底噪與區塊環境聲源、操作聲 | 試玩驗收 |
| 6 | 文件：改寫 [assets/audio/README.md](../../assets/audio/README.md)、[rv.md](../systems/rv.md) 的音效段落與 [environment.md](../systems/environment.md) 的設定；在 [architecture.md](../../architecture.md) 加入共用音效層 | 計畫檔刪除，未結項目移到計畫總覽 |

階段 0 與 1 可以合在同一個 PR。階段 2 是方向確認點，沒有通過就不往下做。

## 風險

| 風險 | 對策 |
|---|---|
| 素材量大，製作時間主要花在聲音本身 | 階段 2 只做 RV；之後依遭遇與操作頻率排序 |
| 我無法親耳判斷好壞 | 每批先做客觀分析，再交給你試聽；必要時一次做兩三個版本讓你挑 |
| `AudioStreamPlayer3D` 太多造成效能負擔 | 全域聲源池與上限；試玩時量測 |
| 引擎分層的接縫或相位問題 | 各層錄製與迴圈長度對齊，用 `AudioStreamSynchronized` 同步播放 |
| 車內判斷與現有 RV 支撐邏輯耦合 | 開工時先確認現有判斷；只讀取狀態，不改它 |
| 遷移期間新舊兩套系統並存 | 每個階段結束時刪掉該階段取代的舊程式，不留相容分支 |
