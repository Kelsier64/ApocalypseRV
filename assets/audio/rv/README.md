# RV 試點錄音

| 遊戲檔案 | 原始錄音 | 授權與處理 |
| --- | --- | --- |
| `door_open.wav`、`door_close.wav` | [Car Door open and close.wav，NachtmahrTV](https://freesound.org/people/NachtmahrTV/sounds/556689/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。從公開高品質試聽檔剪出開門與關門，各自去除直流偏移、加短淡入淡出並調整峰值。 |
| `engine_idle.wav`、`engine_mid.wav`、`engine_rev.wav` | Joseph Sardin 記錄同一輛 Iveco Daily 3.0 柴油廂車的[怠速](https://bigsoundbank.com/truck-engine-s1145.html)、[低轉](https://bigsoundbank.com/truck-engine-small-accelerations-s1146.html)與[高轉](https://bigsoundbank.com/truck-engine-big-accelerations-s1147.html) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。選取原地拉轉片段，以重取樣穩定各段脈衝頻率，對齊脈衝後交叉淡化接縫，並按均方根電平匹配音量。 |
| `engine_grains.wav`、`engine_grains.tres` | 同上三段 Iveco Daily 錄音 | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。追蹤爆發頻率後，在每次爆發前的低點切開，每顆含一個爆發週期與兩側淡化，依加油、收油、怠速分類並保留連續的片段。WAV 以未壓縮 PCM 匯入，遊戲直接讀取樣本。 |
| `gear_shift_a.wav`、`gear_shift_b.wav` | [gear select.wav，greatsoundstube](https://freesound.org/people/greatsoundstube/sounds/629324/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。從公開高品質試聽檔剪出兩次排檔桿動作，各自去除直流偏移並加淡出。 |
| `engine_start.wav`、`engine_stop.wav` | [Diesel engine Startup and Stutdown，roboroo](https://freesound.org/people/roboroo/sounds/436793/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。由公開高品質試聽檔剪出起動馬達到點火，以及熄火後的短尾音。 |

將 Freesound 的公開試聽檔和 BigSoundBank 的原始 WAV 轉成 44.1 kHz、16-bit 單聲道 WAV。將輸入依來源順序存為 `door.wav`、`gear_select.wav`、`iveco_idle.wav`、`iveco_lo.wav`、`iveco_hi.wav` 和 `start_stop.wav`，放在忽略的工作資料夾，再執行下方指令。腳本需要 NumPy。只重製引擎迴圈時可加 `--engine-only`。

```powershell
python art_source/audio/rv/make_pilot_wavs.py .godot/audio-source assets/audio/rv
python art_source/audio/rv/make_engine_grains.py .godot/audio-source assets/audio/rv
```

[剪輯腳本](../../../art_source/audio/rv/make_pilot_wavs.py) · [顆粒腳本](../../../art_source/audio/rv/make_engine_grains.py) · [音效試點場景](../../../tests/playgrounds/rv_audio_playground.tscn)
