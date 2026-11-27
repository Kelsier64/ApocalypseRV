# 主管詞庫語音

主管廣播用的英文詞庫：每個詞一段錄音，遊戲中由[廣播排程](../../../core/audio/broadcast_schedule.tscn)的模板查表、以固定間隔接起來念，字幕由同一串詞產生。`words/` 與 `word_bank.tres` 都由腳本產生，不要手改；要加詞，改 [words.json](../../../scripts/audio/dispatch_voice/words.json) 後重跑。

| 項目 | 內容 |
| --- | --- |
| 模型 | [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) v1.0，Apache-2.0；以 `onnx-community/Kokoro-82M-v1.0-ONNX` 的 fp32 權重，經 npm 套件 `kokoro-js` 1.2.1（Apache-2.0）在 Node 執行 |
| 聲音 | `am_adam`，語速 1.0。2026-11-26 試聽 Kokoro 全部男聲後選定；原本的 `am_michael` 處理後聽起來帶口音 |
| 合成 | 每個詞單獨呼叫一次，文字為該詞加句點；開頭在峰值 −40 dB 處起算以保留輕的子音，結尾在 −30 dB 處截斷單字常見的拖長尾音，頭留 20 ms、尾留 30 ms |
| 壓平音高 | [Praat](https://www.fon.hum.uva.nl/praat/) 7.0.03（GPL，只當工具用，不隨遊戲發佈）以 PSOLA 把每個詞的音高換成同一條直線，高度取全部詞的中位音高平均（`am_adam` 約 125 Hz） |
| 音色 | 同一 Praat 腳本做 300–3400 Hz 帶通與 tanh 輕度飽和，重取樣成 16 kHz |
| 響度 | 每個詞 RMS 對齊 −20 dBFS，峰值上限 0.95，頭尾 6 ms 淡入淡出 |
| 格式 | 16 kHz、16-bit 單聲道 WAV，匯入設為未壓縮 PCM（`compress/mode=0`），拼接時直接複製樣本 |

短波的起伏、斷續與底噪由收音裝置依當下收訊在遊戲中加上，不做進詞裡。

## 重新產生

```powershell
node scripts/audio/dispatch_voice/generate.mjs
```

需要 `%USERPROFILE%\Apps\kokoro-tts` 裡已 `npm install kokoro-js@1.2.1`（或設 `KOKORO_DIR`），以及 `%USERPROFILE%\Apps\praat\Praat.exe`（或設 `PRAAT_EXE`）。首次執行會下載約 326 MB 的模型。中間檔放在 `.godot/dispatch_voice/`。試聽其他聲音：

```powershell
node scripts/audio/dispatch_voice/generate.mjs --audition am_adam,bm_george --text "attention unit kilo four seven"
```
