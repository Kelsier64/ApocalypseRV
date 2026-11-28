# 調度喇叭聲音

廣播與手持短波收音機共用[廣播排程](../../../core/audio/broadcast_schedule.tscn)：主管的話由[詞庫](../dispatch_voice/README.md)拼出，另有一段載波音。車上機器的兩句拒絕回覆也由同一詞庫念出，無旋律。

| 素材 | 來源與處理 |
| --- | --- |
| `dispatch_ident.wav` | 宣傳片開場的四音識別音。以正弦波與衰減泛音合成，模擬短促的機械鐘聲。在 T1 從車內調度喇叭實際播出。 |
| `receiver_static.wav` | JovianSounds 的對講機背景底噪，CC0。取公開試聽檔中段，混成單聲道，交叉淡化頭尾以供循環。[Radio Static](https://freesound.org/people/JovianSounds/sounds/524204/) |
| 旋鈕、發話鍵、拿起與掛回 | 四個空間音效事件引用既有的 CC0 開關與金屬搭扣錄音，重新調整音量和音高變化。[來源及授權](../rv/README.md) |
