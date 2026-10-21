# 晴天、陰天與小霧外觀修正

2026-10-21，`codex/terrain-overhaul`，接續 `448c33d`。使用者回報三種天氣看起來相同；修正後停止供畫面檢查。

原本三者都使用同一終端白霧色，小霧終點只從 230 m 收近至 220 m。天空也被原生霧完全混合，既有藍色天頂與雲層差異無法呈現（引擎合成見 [Godot sky shader](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/renderer_rd/shaders/environment/sky.glsl#L255)）。這次保留天空／完全遮蔽物體的一致合成，透過距離、色調和直射光拉開差異。

| 天氣 | 距離霧 | 白天終端色 | 正午直射光能量 |
| --- | --- | --- | --- |
| 晴天 | 64–230 m | 暖灰 `d0cbb8` | 1.3 |
| 陰天 | 24–230 m | 冷灰 `a4afb0` | 0.45 |
| 小霧 | 8–150 m | 灰白 `c3cbc8` | 約 0.354 |

設定集中於 `WorldAtmosphereProfile`。天氣過渡連續混合霧起點、終點、終端色與直射光；夜間仍回到原有暗霧色。中／大霧終點維持 110／38 m。最遠 230 m、載入落後立即收近、完成後每真實秒恢復 20 m，以及植被 AABB／裁切緩衝維持原契約。自然天氣機率、RNG、存檔及生成版本未變。

## 本次驗證

- Godot 4.7.2，`scripts/test.ps1 -TestFilter test_streaming_generation.gd -Smoke -SkipImport`：串流 21.77 s、主場景 10.52 s，皆 PASS、退出碼 0。覆蓋四種子地形／道路、橋梁／河岸／導航、各畫質霧設定、天氣過渡與偏行、自然 RNG／保存，以及晴天在載入保護下的起終點順序。日誌 `.godot/test-logs/20261021-131915-443-selected-36368/`。
- 原生 Forward+／Vulkan 與 Compatibility／OpenGL，固定 seed 42、正午、1280×720，同一森林盆地路面鏡頭，使用正式地形、道路、植被、ForestFog 及 WorldClock。檢視晴天暖光與近景對比、陰天冷暗及小霧較近的灰白遮蔽；另保留大霧畫面。
- 在 270 m 突然加入紅色物件：Forward+ 晴天 RGB 最大通道差 0、陰天與 FOV 100° 角落 ≤2/255；Compatibility 三項皆為 0。原生完整 AABB 檢查及各次遮蔽斷言通過。

實際渲染、工具及日誌位於 gitignored `.godot/weather-readability-review/`，`gallery.md` 可並列檢查三種天氣。未進行完整長途串流、輪驅或整體 FPS 驗收。原有 `project.godot` 修改保留並排除本次提交。
