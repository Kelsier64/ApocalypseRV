# 調度喇叭聲音

廣播與手持短波收音機共用四段既有素材。車上機器的兩句拒絕回覆獨立播放，無旋律。

| 素材 | 來源與處理 |
| --- | --- |
| `receiver_static.wav` | JovianSounds 的對講機背景底噪，CC0。取公開試聽檔中段，混成單聲道，交叉淡化頭尾以供循環。[Radio Static](https://freesound.org/people/JovianSounds/sounds/524204/) |
| `receive_only.wav`、`unauthorized.wav` | 暫代機器聲。用 Windows SAPI 逐字產生英文，裁掉每字前後的空白，以固定 82 ms 間隔拼接，限制頻寬並加輕度飽和。兩段都是 44.1 kHz 單聲道。 |
| 旋鈕、發話鍵、拿起與掛回 | 四個空間音效事件引用既有的 CC0 開關與金屬搭扣錄音，重新調整音量和音高變化。[來源及授權](../rv/README.md) |
