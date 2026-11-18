# RV 試點錄音

| 遊戲檔案 | 原始錄音 | 授權與處理 |
| --- | --- | --- |
| `door_open.wav`、`door_close.wav` | [Car Door open and close.wav，NachtmahrTV](https://freesound.org/people/NachtmahrTV/sounds/556689/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。從公開高品質試聽檔剪出開門與關門，各自去除直流偏移、加短淡入淡出並調整峰值。 |
| `engine_idle.wav`、`engine_mid.wav`、`engine_rev.wav` | Mihacappy 的 MAN／Solaris 柴油公車錄音，[bus_idle_long.wav](https://freesound.org/people/Mihacappy/sounds/803762/)、[buslow2.wav](https://freesound.org/people/Mihacappy/sounds/803767/)、[busmid.wav](https://freesound.org/people/Mihacappy/sounds/803761/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。剪自公開高品質試聽檔。削弱次聲、麥克風或傳動的固定共鳴，按均方根電平匹配音量，再對齊引擎脈衝後交叉淡化接縫。 |
| `engine_start.wav`、`engine_stop.wav` | [Diesel engine Startup and Stutdown，roboroo](https://freesound.org/people/roboroo/sounds/436793/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。由公開高品質試聽檔剪出起動馬達到點火，以及熄火後的短尾音。 |

將公開試聽檔解碼成 44.1 kHz、16-bit 單聲道 WAV。將輸入依來源順序存為 `door.wav`、`bus_idle.wav`、`bus_low.wav`、`bus_mid.wav` 和 `start_stop.wav`，放在忽略的工作資料夾，再執行下方指令。腳本需要 NumPy。只重製引擎時可加 `--engine-only`。

```powershell
python art_source/audio/rv/make_pilot_wavs.py .godot/audio-source assets/audio/rv
```

[剪輯腳本](../../../art_source/audio/rv/make_pilot_wavs.py) · [音效試點場景](../../../tests/playgrounds/rv_audio_playground.tscn)
