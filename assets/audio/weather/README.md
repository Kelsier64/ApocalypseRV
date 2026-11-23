# 天氣聲音素材

| 遊戲檔案 | 來源 | 處理 |
| --- | --- | --- |
| `rain_light.wav` | [Light Rain，soundrecorder7](https://freesound.org/people/soundrecorder7/sounds/167034/) | 立體聲，取 4 到 14.5 秒做成約 10 秒迴圈 |
| `rain_heavy.wav` | [Rain heavy 2 (rural)，jmbphilmes](https://freesound.org/people/jmbphilmes/sounds/200272/) | 立體聲，取 10 到 20.5 秒做成約 10 秒迴圈 |
| `wind_breeze.ogg` | [windy winter day, wind in trees, from distance.wav，lwdickens](https://freesound.org/people/lwdickens/sounds/259968/) | 微風的底層，取 23 秒起約 24 秒 |
| `wind_strong.ogg` | [Wind__Artic__Cold.wav，cobratronik](https://freesound.org/people/cobratronik/sounds/117136/) | 強風的底層，取 9 秒起約 24 秒 |
| `wind_gale.ogg` | [Wind - Hurricane Typhoon Storm，Vrymaa](https://freesound.org/people/Vrymaa/sounds/735350/) | 暴風的底層，取 18 秒起約 24 秒 |
| `tree_rush_a.wav`–`tree_rush_d.wav` | [wind in the trees，deleted_user_229898](https://freesound.org/people/deleted_user_229898/sounds/150174/) | 樹梢呼嘯，每段一陣風吹過樹冠，單聲道，緩起緩收 |

全部是 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)，剪自 Freesound 公開高品質試聽檔。以等功率交叉淡化接縫，再用柔和限幅壓住雨滴瞬態，大雨比小雨約響 4 dB。處理方式在 [make_cues.py](../../../art_source/audio/make_cues.py)。超過 10 秒的迴圈暫時仍是 WAV，原因見 [RV 錄音](../rv/README.md)。

風聲刻意做暗：切掉 50 Hz 以下的麥克風風切，再依強度在 650 Hz（微風）、1000 Hz（強風）或 1500 Hz（暴風）以上緩降，4 kHz 以上全部切掉，遊戲裡聽不到嘶聲。底層先壓平錄音本身的陣風起伏，陣風由遊戲依 `WorldWind.gust` 加上；左右聲道的相關度固定為 0.3，接縫以 2 秒等功率交叉淡化，響度對齊到 -24 dBFS RMS，輸出 Ogg Vorbis，迴圈旗標設在 `.ogg.import`。樹梢呼嘯在 1800 Hz 以上緩降。處理與試聽用的候選組合在 [make_wind.py](../../../art_source/audio/make_wind.py)。
