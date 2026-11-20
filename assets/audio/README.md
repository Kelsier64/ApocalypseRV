# RV 音效

車門、排檔、引擎、路噪與風聲試點的來源和重製方式見 [RV 聲音素材](rv/README.md)。

`rv/vehicle_audio.gd` 的操作回饋、撞擊、滑移和刮地都改用 CC0 錄音。它仍保留耳鳴與甦醒吸氣兩個原創合成聲，等玩家音效遷移時一併替換。

`rv/panel_damage_effect.gd` also synthesizes two original 22,050 Hz mono PCM cues for shell impact and destruction, combining decaying metallic harmonics with deterministic noise and staggered tearing transients. These use no external samples. Streams are shared. Each burst has one initial spatial source and at most three quieter, rate-limited landing cues (higher pitch for glass), freed on completion or with the burst. A vehicle has at most six bursts; impact bursts last 2.4 seconds and destruction debris lasts 7 seconds. Snapshot restoration and repairs are silent.

# Slender Speaker loudspeaker music

`slender_speaker/patrol.wav` is the giant's head loudspeaker: Beethoven's *Für Elise* (public domain) arranged as an electronic garbage-truck melody. It was synthesized in REAPER with Surge XT (a narrow 25% pulse wave through a mild horn-speaker saturation and EQ), with no recordings or samples. It may be distributed with this project under its source terms, and no attribution is required.

The file is mono 16-bit PCM at 44.1 kHz, 42.1875 s long, at 64 BPM. It is cut from the pickup to exactly one repeat later, so it loops seamlessly; the import loop mode is Forward. The giant plays it from spawn to removal, including capture and execution. Its audible distance follows the actor removal distance, `RoadSpawns.SAFE_DISTANCE`. The source project, notes and loop script are in `art_source/music/slender_speaker/`.
