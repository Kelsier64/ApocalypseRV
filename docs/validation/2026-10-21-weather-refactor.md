# 天氣與霧的職責拆分

2026-10-21，`codex/terrain-overhaul`，基準 `1c8efed`。本階段保留目前視覺與天氣規則，完成後停止供檢查；不推送。

- `WorldWeather` 保留自然天氣抽選、遊戲秒數過渡、獨立 RNG 及五欄位 capture／restore；移出景觀霧的距離與密度。
- `WorldAtmosphereProfile` Resource 集中常駐白霧、天氣霧距離、密度、顏色與體積取樣設定。預設資源仍為 24–230 m、curve 1；天氣霧終點 220／110／38 m。偏行霧只合成顯示條件。
- `WorldStreamVisibility` 管理暫態相機視野上限：已完成地景內保留 8 m 緩衝，立即收近，每真實秒恢復 20 m。WorldGenerator 保留連續完成區帶的幾何查詢；WorldClock 統一寫入最終環境、天空、光源及局部霧材質。
- 植被裁切在生成時讀取所屬時鐘的同一份 atmosphere，保留完整 AABB、遲滯與緩衝。距離／裁切設定於生成前配置；變更已生成地景的可見距離需重建區塊。天氣概率、雨幕、巨人判定與存檔版本均未調整。

## 本次檢查

Godot 4.7.2；選取 `test_checkpoint_failures.gd,test_streaming_generation.gd` 加正式主世界 smoke。匯入 8.54 s、存檔 25.11 s、串流 21.47 s、主場景 10.66 s，皆通過且正常退出。日誌：`.godot/test-logs/20261021-130529-995-selected-47244/`。

串流套件保留四種子地形／道路指紋、河岸、橋梁、碰撞及導航檢查。霧檢查涵蓋原有各天氣／畫質數值、轉換及還原、相機偏移、載入保護與完整植被邊界；新增不同世界的獨立／共用外觀 Resource、配置後裁切、無效時間／地景距離處理，以及兩個種子共 16 次自然抽選的獨立 RNG 與保存格式對照。沒有增加頂層測試程序。

原生 Forward+／Vulkan 實際渲染：seed 42、正午、1280×720，固定森林盆地路面鏡頭，使用正式地形、道路、植被、ForestFog 及 WorldClock。重構前後各擷取陰天、晴天、小霧、大霧，凍結 shader 時間。晴天、小霧、大霧的 RGB 像素完全相同；陰天最大通道差 2/255，平均每通道約 0.02/255。肉眼檢查陰天與大霧，保留近景清晰、遠景白霧遮蔽。四種設定的距離終點與體積密度一致。

畫面、像素比較 JSON 與渲染工具均在 gitignored `.godot/weather-refactor-review/`，`gallery.md` 提供前後對照。本輪未做長途輪驅、完整串流或遊戲 FPS 驗收，也未重新設計天氣美術。原有 `project.godot` 修改保留並排除提交。
