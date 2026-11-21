# 環境音素材

| 遊戲檔案 | 來源 | 用途與處理 |
| --- | --- | --- |
| `crow_a.wav` | [Crow Call，qubodup](https://freesound.org/people/qubodup/sounds/813114/) | 白天遠處的烏鴉，一聲 |
| `crow_b.wav`、`crow_c.wav` | [Crows In Cornwall-3.aiff，kiefspoon](https://freesound.org/people/kiefspoon/sounds/144553/) | 同上。背景有其他鳥的叫聲段落不採用 |
| `tree_creak_a.wav`–`tree_creak_d.wav` | [Tree creaks，Sacha.Julien](https://freesound.org/people/Sacha.Julien/sounds/726217/) | 樹林裡樹幹的吱嘎，每段一次 |
| `branch_snap_a.wav`、`branch_snap_b.wav` | [branch break snap crunch nice.wav，kyles](https://freesound.org/people/kyles/sounds/452109/) | 樹林裡樹枝斷裂 |
| `metal_creak_a.wav`–`metal_creak_d.wav` | [weathervane: A metal weathervane or pub sign creaking in the wind，Fenfright](https://freesound.org/people/Fenfright/sounds/759692/) | 公路邊金屬招牌的吱嘎 |
| `cricket_a.wav`–`cricket_c.wav` | [Single Cricket Chirping, Close Perspective 02，HECKFRICKER](https://freesound.org/people/HECKFRICKER/sounds/753272/) | 夜裡一隻蟋蟀，每段三聲 |
| `drip_a.wav`–`drip_f.wav` | [drops in a underground parking，heifara](https://freesound.org/people/heifara/sounds/262641/) | 室內副本的滴水，每段一滴 |
| `room_creak_a.wav`、`room_creak_b.wav` | [Metal creaks.mp3，hannahbelle144](https://freesound.org/people/hannahbelle144/sounds/625616/) | 室內副本的金屬冷縮聲 |
| `room_small.ogg` | [room tone medium basement industrial cyclical bg hum and rumble MS.wav，kyles](https://freesound.org/people/kyles/sounds/451064/) | 地堡的室內嗡聲。只留約 400 Hz 以下 |
| `room_hall.ogg` | [room tone large convention hall vent large almost empty.flac，kyles](https://freesound.org/people/kyles/sounds/451614/) | 樓梯間、無燈柱廳與巨型避難所的室內嗡聲。只留約 400 Hz 以下 |

全部是 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)，剪自 Freesound 公開高品質試聽檔。一次性聲音是單聲道 WAV，同一事件的變體依起音後的響度對齊。室內嗡聲保留立體聲，取 20 秒，接縫以等功率交叉淡化，輸出 Ogg Vorbis，迴圈旗標設在 `.ogg.import`。剪輯點與處理都在 [make_cues.py](../../../art_source/audio/make_cues.py)，室內嗡聲的 Ogg 輸出需要 `soundfile` 套件。
