# 天氣聲音素材

| 遊戲檔案 | 來源 | 處理 |
| --- | --- | --- |
| `rain_light.wav` | [Light Rain，soundrecorder7](https://freesound.org/people/soundrecorder7/sounds/167034/) | 立體聲，取 4 到 14.5 秒做成約 10 秒迴圈 |
| `rain_heavy.wav` | [Rain heavy 2 (rural)，jmbphilmes](https://freesound.org/people/jmbphilmes/sounds/200272/) | 立體聲，取 10 到 20.5 秒做成約 10 秒迴圈 |

兩者都是 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)，剪自 Freesound 公開高品質試聽檔。以等功率交叉淡化接縫，再用柔和限幅壓住雨滴瞬態，大雨比小雨約響 4 dB。處理方式在 [make_cues.py](../../../art_source/audio/make_cues.py)。超過 10 秒的迴圈暫時仍是 WAV，原因見 [RV 錄音](../rv/README.md)。
