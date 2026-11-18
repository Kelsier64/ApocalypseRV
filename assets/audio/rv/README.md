# RV 試點錄音

| 遊戲檔案 | 原始錄音 | 授權與處理 |
| --- | --- | --- |
| `door_open.wav`、`door_close.wav` | [Car Door open and close.wav，NachtmahrTV](https://freesound.org/people/NachtmahrTV/sounds/556689/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。從公開高品質試聽檔剪出開門與關門，各自去除直流偏移、加短淡入淡出並調整峰值。 |
| `engine_idle.wav`、`engine_rev.wav`、`engine_start.wav`、`engine_stop.wav` | [3008-start-idle-rev-shutoff.wav，Mihacappy](https://freesound.org/people/Mihacappy/sounds/815853/) | [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)。從同一柴油車錄音的公開高品質試聽檔剪輯。啟停片段做短淡入淡出，迴圈用重疊淡化接合。 |

公開試聽檔用 FFmpeg 解碼成 44.1 kHz、16-bit 單聲道 WAV。將車門和引擎輸入存成 `door.wav` 和 `diesel.wav`，放在忽略的工作資料夾，再執行下方指令。腳本需要 NumPy，剪輯時間點和增益設定收在腳本中。原始試聽檔留在工作資料夾。

```powershell
python art_source/audio/rv/make_pilot_wavs.py .godot/audio-source assets/audio/rv
```

[剪輯腳本](../../../art_source/audio/rv/make_pilot_wavs.py) · [音效試點場景](../../../tests/playgrounds/rv_audio_playground.tscn)
