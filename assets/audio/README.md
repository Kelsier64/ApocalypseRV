# RV 音效

車門與引擎試點的來源和重製方式見 [RV 錄音](rv/README.md)。

`rv/vehicle_audio.gd` 的原創合成聲仍用於多數操作回饋、撞擊、滑移和刮地。試點場景的 A/B 切換也會播放舊引擎與舊車門聲。合成聲可隨專案散布，沒有外部素材。

`rv/panel_damage_effect.gd` also synthesizes two original 22,050 Hz mono PCM cues for shell impact and destruction, combining decaying metallic harmonics with deterministic noise and staggered tearing transients. These use no external samples. Streams are shared. Each burst has one initial spatial source and at most three quieter, rate-limited landing cues (higher pitch for glass), freed on completion or with the burst. A vehicle has at most six bursts; impact bursts last 2.4 seconds and destruction debris lasts 7 seconds. Snapshot restoration and repairs are silent.

# Slender Speaker loudspeaker music

`slender_speaker/patrol.wav` is the giant's head loudspeaker: Beethoven's *Für Elise* (public domain) arranged as an electronic garbage-truck melody. It was synthesized in REAPER with Surge XT (a narrow 25% pulse wave through a mild horn-speaker saturation and EQ), with no recordings or samples. It may be distributed with this project under its source terms, and no attribution is required.

The file is mono 16-bit PCM at 44.1 kHz, 42.1875 s long, at 64 BPM. It is cut from the pickup to exactly one repeat later, so it loops seamlessly; the import loop mode is Forward. The giant plays it from spawn to removal, including capture and execution. Its audible distance follows the actor removal distance, `RoadSpawns.SAFE_DISTANCE`. The source project, notes and loop script are in `art_source/music/slender_speaker/`.
