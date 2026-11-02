# 副本局部照明與黑暗

2026-11-03。地堡、巨型避難所與勤務樓梯間改為零環境底光、黑色背景，關閉環境反射填光。固定燈具強化衰減、柔和陰影與 Forward+ 接觸遮蔽。室內使用獨立灰階 profile（參考能量 0.012、0～5 m 區間、曲線在 3 m 起為零）；室外資源與房間熄燈抽選不變。參數見[灰階指南](../guides/night-vision.md#副本的短距離灰階與黑暗)。

本次檢查：

- Godot 4.7.2 匯入完成，無腳本／資源錯誤。
- `scripts/test.ps1 -TestFilter test_poi_transition_persistence.gd -SkipImport` 通過，包含正式副本專用環境及 profile 接線；涵蓋地面層、樓梯間與地堡往返保存。日誌批次：`.godot/test-logs/20261103-012518-184-selected-38244/`。
- `tests/support/night_vision_lighting_checks.gd -- --interior-only --diagnostics` 在 Forward+ 與 Compatibility 通過：近身淡灰比室外更暗、遠處全黑、關閉灰階後無原生底光、正式手電筒可照亮灰階範圍外目標、關閉後恢復黑暗；室外 profile／Curve 檔案保持原樣。
- Forward+ 中性白色測試表面的輸出 RGB：0.75／1／2／4.5 m 約為 0.055／0.051／0.012／0；同距離室外近處約 0.271。這是測試畫面像素值，並非實際照度或所有材質的固定亮度。Compatibility 的極暗輸出較早量化成黑，0.75 m 約 0.008，其餘測點為 0；兩者均保留真實手電筒照明。
- 已直接檢視 seed 42 避難所、八模組地堡及勤務樓梯間的完整天花板渲染。暗房關閉手電筒接近全黑，開啟後可辨識桌椅、床與牆面；亮燈處及樓梯平台保有可見度。截圖／檢查腳本／日誌都在 gitignored `.godot/art-work/interior-lighting/`。未進行本輪人工步行或全 seed 驗收。

完整灰階 GPU 檢查另有兩個既有失敗：固定原生照明下的日夜一致性，以及手電筒體積霧亮度。以 HEAD 原版檢查程式重跑同樣失敗；本輪未修改室外光照、霧或共用灰階演算法。原版與修改版日誌分別為上述目錄內的 `gpu-baseline.log`／`gpu-forward.log`，不能將副本專項通過解讀成完整 GPU 回歸全數通過。
