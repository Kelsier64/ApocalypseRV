# Slender Speaker：垃圾車給愛麗絲

ApocalypseRV 的 Slender Speaker 頭頂喇叭播出的聲音。**不是 BGM**：是遊戲世界裡的聲源，
遊戲會做 3D 定位、距離、殘響，其他音效（腳步等）也由遊戲的機制加入。
目標：單純的台灣垃圾車電子《給愛麗絲》，音色越像越好；乾聲、單聲道內容。

- 專案：`SlenderSpeaker_FurElise.rpp`（REAPER），render 在 `renders/`，送進 REAPER 的指令在 `cmds/`。
- 音符：`furelise_notes.lua`，從 `FurElise_GarbageTruck.rpp` 唯讀取出的右手 131 音、左手 65 音（Beethoven，公版）。
- 75 BPM（四分音符），3/8，31 小節，約 38 秒：Pickup (1) | A (2–9) | A' (10–17) | B (18–23) | A'' (24–31)。
  遊戲要更長就循環播放（垃圾車本來就是一直重播）。

## 訊號流程（v3 起）
```
Tone A square ─┐
Tone B music box ─┼─> Loudspeaker (JS Saturation 39%, ReaEQ 喇叭頻寬) ─> master (JS Master Limiter -1 dB)
Tone C pulse ──┘   同一時間只開一軌（cmds/08a/b/c 切換）
```
- Loudspeaker ReaEQ：HP 400 Hz、low shelf 200 Hz -6 dB、1.5 kHz +5 dB（BW 1.5）、high shelf 6 kHz -12 dB。沒有 reverb/delay。
- 右手力度 100、左手 85，三軌是同一份音符。

## 候選音色
| 軌 | Surge XT 設定 | 想像中的來源 | 音量 |
|---|---|---|---|
| Tone A square | Classic 方波 50%，drift 2%；Amp A 0 / D 600 ms / S 40% / R 80 ms | 單純方波旋律 IC | +3 dB |
| Tone B music box | Sine + Sine +1 oct (-8 dB) + Sine +1 oct +7 st (-16 dB)；A 0 / D 1.1 s / S 0 / R 400 ms | 音樂盒 IC，像鐘琴一樣衰減 | -6.5 dB |
| Tone C pulse | Classic 窄脈波 25%，drift 2%；A 0 / D 250 ms / S 75% / R 60 ms | 鼻音重、帶嗡嗡聲的電子琴 | +1 dB |

## 版本
### v1、v2（作廢）
誤解成 BGM：工業 dark ambient、三支音箱不同步、霧、腳步、殘響和遠近 automation（cmds 01–05）。
使用者回饋：「Slender Speaker 是頭頂上有喇叭的怪物，只要做單純的類似台灣垃圾車的電子給愛麗絲，音樂從喇叭播放，不是 BGM，其他音效用遊戲內的機制加入」。
cmds/06 刪掉這些軌，改回原速。`renders/..._v1.wav`、`_v2.wav` 留著當紀錄。

### v3（`_v3_toneA/B/C.wav`）：三個候選，響度沒對齊
A：RMS -21.0 dBFS；B：-12.5（peak -0.1，頂到 limiter）；C：-19.1。響度差太多，不適合比較。

### v4（`_v4_toneA/B/C.wav`）：響度對齊（cmds/09）
| | peak | RMS | crest | 頻段形狀 | 頻譜峰 |
|---|---|---|---|---|---|
| A 方波 | -1.4 | -18.0 | 16.6 | 1–2 kHz 最強，2–4 kHz -6，4–8 kHz -16 | 1319 Hz (E6，方波泛音) |
| B 音樂盒 | -5.0 | -18.9 | 13.8 | 500–1000 Hz 最強，2–4 kHz -25，4 kHz 以上幾乎沒有 | 657 Hz (E5，基音) |
| C 脈波 | -3.3 | -18.2 | 14.9 | 300 Hz–2 kHz 很平，2–4 kHz -5，4–8 kHz -14 | 657 / 495 / 441 Hz |
- 三個都是單聲道（side/mid ≈ -180 dB）、每 3 秒的響度很平穩、結尾在 39 秒收乾淨。
- 預期：A 最尖、最「電子」；B 最圓、最柔，像音樂盒；C 中頻最滿、最像便宜電子琴。
- 疑慮：A 的 20–150 Hz 比 B、C 低了約 20 dB（左手低音很弱），原因還沒查。

## 使用者回饋
- v4：「A 最像，但還是有點差別，感覺主要是 BPM」。
  上網查不到台灣垃圾車版的實際速度（只有文化背景報導；查到的 128–129 BPM 是不相干的錄音），所以改做速度候選。

### v5（`_v5_toneA_64bpm / 84bpm / 96bpm.wav`）：音色 A，不同速度（cmds/10_tempo_NN.lua）
| 速度（四分音符） | 八分音符 | 長度 | peak / RMS |
|---|---|---|---|
| 64 | 128 | 46.5 s | -1.1 / -18.4 |
| 75（= v4_toneA） | 150 | 39.9 s | -1.4 / -18.0 |
| 84 | 168 | 35.8 s | -0.7 / -17.7 |
| 96 | 192 | 31.5 s | -1.3 / -17.4 |
- MIDI item 會跟著速度變（item 一樣是 1–33 小節），音符不用重寫。
- 使用者想聽音色 C 的 64 BPM 版本 → `_v5_toneC_64bpm.wav`（cmds/11）：peak -2.8、RMS -18.2 dBFS、crest 15.4 dB，46.5 s。
- **使用者的選擇：C 64 BPM 最接近垃圾車**（比 A 64 BPM 更像）。

## 遊戲版本（v6 loop → `assets/audio/slender_speaker/patrol.wav`）
- 使用者決定：很遠就聽得到（遠的時候小聲）；不要處刑曲，從頭到尾都是給愛麗絲。
- `make_loop.py` 從 `_v5_toneC_64bpm.wav` 裁出循環段：從第一個 E 前 2 ms 開始，長度剛好 45 QN（42.1875 s），
  下一圈的 E 落在最後一個 A 之後一拍，跟譜上的反覆一樣。結尾的延長 A 在接縫前 15 ms 用 cosine 淡出。
  轉成單聲道 16-bit 44.1 kHz，+1.5 dB。
- 分析：peak -1.3 dBFS、RMS -16.3 dBFS、crest 15.0 dB；頻段跟 v5 C 一樣；接縫兩端 < 0.0004。
- 沒有用 REAPER 重新 render：當時 REAPER 的作用中分頁是別的 session 的專案，skill 規定不能自己切分頁。
- 遊戲以 Forward 模式循環播放。喇叭的距離與音量設定見 [Slender Speaker 場景](../../../enemies/slender_speaker/slender_speaker.tscn) 和[敵人系統](../../../docs/systems/enemies.md#slender-speaker)。
  ExecutionMusic 和 `execution.wav` 已經刪除。

## 目前狀態（2026-11-18）
- 專案設定：**Tone C pulse、64 BPM**；Tone A、B 靜音保留，用來比較。目前最好的版本：`renders/SlenderSpeaker_FurElise_v5_toneC_64bpm.wav`。
- 遊戲用的注意事項：render 出來是 44.1 kHz 24-bit stereo，但內容是單聲道；遊戲裡現有的 patrol.wav 是 48 kHz mono。
  要放進遊戲時再決定格式、要不要做循環接縫（垃圾車本來就是一直重播）。
- 還沒做：跟真的垃圾車錄音逐項比較（音高/調性、裝飾音、伴奏型態、喇叭音色）；使用者還沒指出 C 64 BPM 剩下的差異。
