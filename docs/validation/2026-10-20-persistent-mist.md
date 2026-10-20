# 常駐白霧與載入遮蔽

2026-10-20，沿用 `codex/terrain-overhaul`，接續路側接地與天氣整合。使用者偏好整合前較厚的白霧，並回報遠處物件突然載入；本輪完成後停止供畫面檢查，不推送。

## 變更

- v14 恢復常駐 24–230 m 距離白霧、curve 1，晴天、體積霧關閉及 Compatibility 同樣保留。陰天的全域／局部低霧密度恢復 0.0025／0.14；天氣加濃時平滑淡出局部散射，由 220／110／38 m 天氣霧接手。夜間仍跟隨原生照明變暗。
- v14 天空與物體一起參與原生距離、體積霧合成；共享 `overcast_sky.gdshaderinc`，v2–v13 保留原天空分支。原先只匹配天空／霧的輸入色，仍會因物體額外接受體積合成而透出輪廓。新的整合讓最終顏色一致，天空也融入白霧；體積取樣長度隨終點縮短，避免廣角角落取到不同深度。
- 48 m 植被 MultiMesh 使用 CPU 計算的完整 AABB；裁切距離包含終點 230 m、包圍盒半徑、16 m 遲滯及 8 m 緩衝。草叢不再在視野內整批出現，保留原密度、位置及樹木碰撞／倒塌。
- `completed_scenery_clearance` 只計算相機所在連續已完成區帶，忽略施工中區帶與不相連的保護區。載入趕不上時，霧立即收進已完成邊界內 8 m，完成後以每真實秒 20 m 平滑恢復。未增加預載區帶、未變更怪物生成／回收或存檔狀態。

引擎合成順序參照 [Godot 4.7 天空 shader](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/renderer_rd/shaders/environment/sky.glsl) 與 [Forward+ 物體 shader](https://github.com/godotengine/godot/blob/4.7-stable/servers/rendering/renderer_rd/shaders/forward_clustered/scene_forward_clustered.glsl)。

## 檢查

- 匯入、`test_streaming_generation.gd`（35.39 s）及正式主世界 smoke（14.91 s）通過。日誌 `.godot/test-logs/20261020-215045-947-selected-48472/`。涵蓋常駐霧、各天氣／畫質、天空分支與體積取樣、完整 AABB 裁切、舊版契約、連續完成區帶／缺口／反向邊界／相機偏移，以及霧的即時收近與平滑恢復；保留道路、橋梁、河岸、導航與天氣還原檢查。
- 原生 Forward+，seed 42、正午、1280×720，使用正式地形、植被、WorldClock 與 ForestFog。另驗證原生 AABB。對照前一版的陰天／晴天，並檢查小霧、大霧及 Compatibility。
- 在 270 m 突然加入無陰影、紅色物件，比較前後畫面最大 RGB 差：前版晴天 0.722、陰天 0.404；新版本晴天 0、陰天 ≤2/255。FOV 100° 四角的遠處插入同樣 ≤2/255；測試凍結 shader 時間，差異在影像量化容許值內。
- 35 m/s 移動鏡頭，分幀建立下一帶地形／植被，刻意延遲發布到第 12 秒。霧終點由 230 m 收至約 101.8 m；完成後每秒恢復 20 m，約第 19 秒回到 230 m。全程維持在完成邊界內，沒有突然放開視野。此展示不含 RV 輪驅、POI 建築、敵人或完整導航生成；不代表長途串流驗收。

本輪 GPU 計時波動較大，無法據此確認 15% 效能增幅目標；未宣稱完整遊戲 FPS 已驗證。畫面、移動取樣、工具與日誌位於 gitignored `.godot/persistent-mist-review/`，入口 `gallery.md`。先前白霧紀錄保留當時結果，以本頁為目前設定。原四項使用者修改保留且不納入提交。[地形計畫](../plans/terrain-overhaul.md)。
