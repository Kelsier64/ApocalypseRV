# RV 試點錄音

| 遊戲檔案 | 原始錄音 | 授權與處理 |
| --- | --- | --- |
| `door_open.wav`、`door_close.wav` | [Car Door open and close.wav，NachtmahrTV](https://freesound.org/people/NachtmahrTV/sounds/556689/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。從公開高品質試聽檔剪出開門與關門，各自去除直流偏移、加短淡入淡出並調整峰值。 |
| `engine_idle.wav`、`engine_mid.wav`、`engine_rev.wav` | Joseph Sardin 記錄同一輛 Iveco Daily 3.0 柴油廂車的[怠速](https://bigsoundbank.com/truck-engine-s1145.html)、[低轉](https://bigsoundbank.com/truck-engine-small-accelerations-s1146.html)與[高轉](https://bigsoundbank.com/truck-engine-big-accelerations-s1147.html) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。選取原地拉轉片段，以重取樣穩定各段脈衝頻率，對齊脈衝後交叉淡化接縫，並按均方根電平匹配音量。 |
| `engine_start.wav`、`engine_stop.wav` | [Diesel engine Startup and Stutdown，roboroo](https://freesound.org/people/roboroo/sounds/436793/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。由公開高品質試聽檔剪出起動馬達到點火，以及熄火後的短尾音。 |

將 Freesound 的公開試聽檔和 BigSoundBank 的原始 WAV 轉成 44.1 kHz、16-bit 單聲道 WAV。將輸入依來源順序存為 `door.wav`、`iveco_idle.wav`、`iveco_lo.wav`、`iveco_hi.wav` 和 `start_stop.wav`，放在忽略的工作資料夾，再執行下方指令。腳本需要 NumPy。只重製引擎時可加 `--engine-only`。

```powershell
python art_source/audio/rv/make_pilot_wavs.py .godot/audio-source assets/audio/rv
```

[剪輯腳本](../../../art_source/audio/rv/make_pilot_wavs.py) · [音效試點場景](../../../tests/playgrounds/rv_audio_playground.tscn)
