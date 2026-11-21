# 環境音素材

| 遊戲檔案 | 來源 | 用途與處理 |
| --- | --- | --- |
| `day.ogg` | [summer meadow with wind，Garuda1982](https://freesound.org/people/Garuda1982/sounds/639459/) | 白天底噪：草叢風聲與蟲鳴。削去 60 Hz 以下的風噪，7 kHz 以上漸進壓低最多 8 dB，左右聲道音量拉平 |
| `night.ogg` | [wind light desert day steady eerie with crickets.flac，kyles](https://freesound.org/people/kyles/sounds/454361/) | 夜晚底噪：低風聲與零星蟋蟀。削去 60 Hz 以下 |
| `forest.ogg` | [Soft Wind in the Trees - Leaves rustle，Borgory](https://freesound.org/people/Borgory/sounds/751473/) | 森林層：風吹樹葉。原始錄音左右聲道相同，維持雙單聲道。削去 60 Hz 以下 |
| `highway.ogg` | [Looping Gentle Wind Ambience on an Open Desert Plain.wav，dhallcomposer](https://freesound.org/people/dhallcomposer/sounds/697217/) | 公路層：空曠處的低沉風聲。削去 60 Hz 以下 |
| `fog.ogg` | [Forest after winter，dasebr](https://freesound.org/people/dasebr/sounds/212697/) | 霧層：潮濕的滴水聲。削去 60 Hz 以下，滴水的尖峰柔和限幅 |
| `room_small.ogg` | [room tone medium basement industrial cyclical bg hum and rumble MS.wav，kyles](https://freesound.org/people/kyles/sounds/451064/) | 地堡的室內底噪：機械嗡聲 |
| `room_corridor.ogg` | [drops in a underground parking，heifara](https://freesound.org/people/heifara/sounds/262641/) | 樓梯間的室內底噪：地下空間的滴水。滴水的尖峰柔和限幅 |
| `room_hall.ogg` | [room tone large convention hall vent large almost empty.flac，kyles](https://freesound.org/people/kyles/sounds/451614/) | 無燈柱廳與巨型避難所的室內底噪：大空間的通風聲 |

全部是 [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)，剪自 Freesound 公開高品質試聽檔，保留立體聲。戶外五層各取 30 秒、室內三種各取 20 秒，接縫以等功率交叉淡化，電平以 300 Hz–8 kHz 頻段的 RMS 對齊，讓低頻為主的錄音在小喇叭上也聽得到。輸出為 Ogg Vorbis，迴圈旗標設在 `.ogg.import`。剪輯點與處理都在 [make_cues.py](../../../art_source/audio/make_cues.py)，執行需要 `soundfile` 套件。
