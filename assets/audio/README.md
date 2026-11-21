# 聲音素材

車門、排檔、引擎、路噪與風聲試點的來源和重製方式見 [RV 聲音素材](rv/README.md)。

遊戲執行時不合成任何聲音。各資料夾的 README 記錄錄音來源、授權與處理方式，可重製的剪輯腳本是 [make_cues.py](../../art_source/audio/make_cues.py)。

# Slender Speaker loudspeaker music

`slender_speaker/patrol.wav` is the giant's head loudspeaker: Beethoven's *Für Elise* (public domain) arranged as an electronic garbage-truck melody. It was synthesized in REAPER with Surge XT (a narrow 25% pulse wave through a mild horn-speaker saturation and EQ), with no recordings or samples. It may be distributed with this project under its source terms, and no attribution is required.

The file is mono 16-bit PCM at 44.1 kHz, 42.1875 s long, at 64 BPM. It is cut from the pickup to exactly one repeat later, so it loops seamlessly; the import loop mode is Forward. The giant plays it from spawn to removal, including capture and execution. Its audible distance follows the actor removal distance, `RoadSpawns.SAFE_DISTANCE`. The source project, notes and loop script are in `art_source/music/slender_speaker/`.
