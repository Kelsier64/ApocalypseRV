# RV 試點錄音

| 遊戲檔案 | 原始錄音 | 授權與處理 |
| --- | --- | --- |
| `door_open.wav`、`door_close.wav` | [Car Door open and close.wav，NachtmahrTV](https://freesound.org/people/NachtmahrTV/sounds/556689/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。從公開高品質試聽檔剪出開門與關門，各自去除直流偏移、加短淡入淡出並調整峰值。 |
| `engine_grains.wav`、`engine_grains.tres` | Joseph Sardin 記錄同一輛 Iveco Daily 3.0 柴油廂車的[怠速](https://bigsoundbank.com/truck-engine-s1145.html)、[低轉](https://bigsoundbank.com/truck-engine-small-accelerations-s1146.html)與[高轉](https://bigsoundbank.com/truck-engine-big-accelerations-s1147.html) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。追蹤爆發頻率後，在每次爆發前的低點切開，相鄰顆粒共用切點與固定長度的交疊淡化。所有可信的脈衝都保留成連續片段，依加油、收油、持平分類，並記錄音量、高頻比例與怠速的汽缸順序供跳接配對；各片段的慢速音量起伏拉近同轉速、同類顆粒的中位數。WAV 以未壓縮 PCM 匯入，遊戲直接讀取樣本。 |
| `gear_shift_a.wav`、`gear_shift_b.wav` | [gear select.wav，greatsoundstube](https://freesound.org/people/greatsoundstube/sounds/629324/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。從公開高品質試聽檔剪出兩次排檔桿動作，各自去除直流偏移並加淡出。 |
| `road_asphalt.wav`、`road_rough.wav` | [VW_T5_TRANSPORTER_INTERIOR_BUMPY SEALED ROAD.wav，DangerLaef](https://freesound.org/people/DangerLaef/sounds/690388/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。柴油廂車的車內行駛錄音，剪自公開高品質試聽檔。柏油取引擎聲被路噪蓋過的平穩路段，路肩取顛簸路段，去除次聲後做成迴圈。 |
| `road_gravel.wav`、`wind.wav` | 原創 | 沒有找到不含引擎的 CC0 錄音，以固定種子離線生成：碎石是帶斜率的噪音加上石子拍打與車輪落坑，風聲是帶通噪音加陣風起伏。兩者都以環狀方式生成，迴圈沒有接縫。 |
| `engine_start.wav`、`engine_stop.wav` | [Diesel engine Startup and Stutdown，roboroo](https://freesound.org/people/roboroo/sounds/436793/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。由公開高品質試聽檔剪出起動馬達到點火，以及熄火後的短尾音。 |

將 Freesound 的公開試聽檔和 BigSoundBank 的原始 WAV 轉成 44.1 kHz、16-bit 單聲道 WAV。將輸入依來源順序存為 `door.wav`、`gear_select.wav`、`vw_t5_road.wav`、`iveco_idle.wav`、`iveco_lo.wav`、`iveco_hi.wav` 和 `start_stop.wav`，放在忽略的工作資料夾，再執行下方指令。腳本需要 NumPy。

```powershell
python art_source/audio/rv/make_pilot_wavs.py .godot/audio-source assets/audio/rv
python art_source/audio/rv/make_engine_grains.py .godot/audio-source assets/audio/rv
python art_source/audio/rv/make_road_wind.py .godot/audio-source assets/audio/rv
```

超過 10 秒的迴圈暫時仍是 WAV：目前的工具鏈沒有 Vorbis 編碼器，Godot 匯入時會壓成 QOA。

[剪輯腳本](../../../art_source/audio/rv/make_pilot_wavs.py) · [顆粒腳本](../../../art_source/audio/rv/make_engine_grains.py) · [路噪與風聲腳本](../../../art_source/audio/rv/make_road_wind.py) · [音效試點場景](../../../tests/playgrounds/rv_audio_playground.tscn)
