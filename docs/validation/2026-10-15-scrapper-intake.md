# 粉碎機大型物件接收修正

舊接收要求物件原點與幾何中心均在中央 ±0.30 m，足跡過大的物件底部還須高於 0.68 m；已歪斜卡入的物件會被持續拒絕。原感測區亦未覆蓋完整入口及槽底。

現在感測區覆蓋 0.87 m 開口、局部 Y 0.07–1.375 m。完整落在開口內的幾何可接收；過大的足跡須在兩軸有足夠中央重疊，且實際碰撞體接觸中央 0.6 m 料道。物件原點及幾何中心不再是接收門檻。活體仍保留中央 ±0.30 m 的中心檢查。

本次自動驗證（Godot 4.7.2，統一 runner）：

- `test_scrapper_motion`：歪斜卡入、偏移原點、長梯橫跨、槽底／入口邊緣小物、側面／斜跨角落拒收、缺電重試、進料保存／取消及單次產出。
- `test_scrapper_living`、`test_scrapper_effect`、`test_rv_resource_cycle`：全部通過。
- 最終日誌：`.godot/test-logs/20261015-021356-292-selected-38548/`；本次未跑完整套件。

實機觀察：專用測試窗放置偏斜且部分卡入的正式輪胎；開啟工作後開始進料，最後完整消失。Forward+ 日誌 `.godot/scrapper-review.log` 無腳本錯誤。接收後仍沿用既有安全進料抬升與表面變形；本次未調整該動畫。沒有在完整教學新局中手動重現所有物件姿勢。

來源：[接收流程](../../equipment/scrapper.gd)、[幾何與中央碰撞檢查](../../equipment/scrapper_feed_motion.gd)、[正式感測區](../../equipment/scrapper.tscn)、[回歸測試](../../tests/test_scrapper_motion.gd)。
