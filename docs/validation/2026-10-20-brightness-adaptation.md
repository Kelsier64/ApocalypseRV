# 依亮度的灰階暗部顯示驗證

2026-10-20，Godot 4.7.2，Windows／RTX 4060 Laptop GPU。此紀錄對應本次 WorldClock 與灰階顯示解耦；前次日夜切換檢查不能代表此版本。

## 變更與保留

- 每個世界的 `DarkAdaptation` 依原生／材質參考亮度估計局部缺光；不使用時段、太陽高度或整張圖平均值。
- 原生燈光、天空、環境光與霧由原本系統持有；參考保留霧遮蔽，雨與水花使用原生照明。
- 共用 [profile](../../world/dark_adaptation_profile.tres) 分開控制亮度反應與 0～60 m 距離；[曲線原檔](../../world/night_vision_curve.tres) 的 6 點、切線與檔案位元組未改。
- Curve SHA256：`1A07C7590EC7D3F4B2E6D893440E8C8DBCD4B8B879CFC4B8F8DF26FF6D622163`。
- 修正合成 Quad 忽略所有剔除而被參考拍入的回饋；保留 layer 剔除，跟隨來源視錐中心。相機與燈光各自保護跨世界所有權交接。

## 本次檢查

GPU 指令與診斷入口見[指南](../guides/night-vision.md)。

| 檢查 | 結果 |
|---|---|
| `tests/support/night_vision_lighting_checks.gd`，Forward+ | PASS |
| 同一 GPU 檢查，Compatibility | PASS；此渲染器沒有體積霧 |
| `test_checkpoint_failures` | PASS，12.11 秒 |
| `test_poi_transition_persistence` | PASS，2.82 秒 |
| 主場景啟動 | PASS，6.90 秒 |
| Godot editor import | PASS |

GPU 覆蓋：固定原生照明下中午／夜間一致、同時段開關燈、原生手電筒／車燈及透明水花、純黑材質、亮天空旁的暗處、陰影、距離霧與全域／局部體積霧、獨立室內、相機進出 World3D 與舊 owner 延後清理、遠座標／旋轉、相機 Environment override、鏡面、暫停與明確停用、曲線即時更新、HUD、staging 轉移、Environment 與曲線原檔不變。

核心檢查使用 `scripts/test.ps1 -TestFilter 'test_checkpoint_failures.gd,test_poi_transition_persistence.gd' -Smoke -SkipImport`（本輪 import 已先通過）。記錄位於 `.godot/test-logs/20261020-023120-697-selected-37492/`；GPU 記錄為 `.godot/dark-adaptation-forward.log` 與 `.godot/dark-adaptation-compatibility.log`。

## 場景觀察與成本

直接檢視本輪 GPU 擷取的 legacy `world/test_world.tscn` 畫面：seed 42、v6、前後各一 chunk、車前固定相機、使用未改動的使用者曲線。白天保留場景配色；夜間近處有灰階地表，車燈打出暖色；雨天及濃霧下遠景維持遮蔽。這是固定視角畫面檢視，並非手動遊玩或所有透明材質驗收。

1280×720、3D scale 100%、Forward+、關閉 VSync，同一場景每組暖機 40 幀、取 180 幀平均，其他測試未同時執行：

| 固定視角 | 停用灰階 | 啟用灰階 | 額外時間 |
|---|---:|---:|---:|
| 中午 | 1.584 ms／幀、811 draw calls | 2.327 ms／幀、1109 draw calls | 0.744 ms／幀 |
| 夜間、車燈開 | 1.570 ms／幀、707 draw calls | 2.312 ms／幀、1005 draw calls | 0.742 ms／幀 |

此數字只代表該固定視角；正式 v12 教學建築、鏡面、不同解析度或濃霧可有不同成本。日間現在也需要參考圖以辨識暗處。複雜透明材質、微弱彩色照明及體積霧時間取樣仍可能有視覺估計差異，沒有宣稱精確光照分解。

## 同日後續：光源殘影修正

使用者回報移動光源在夜間留下殘影。已用正式手電筒逐幀重現：原生體積霧的 temporal reprojection 保留 80% 前幀光照；灰階重構恢復了夜間霧，讓這個原有累積設定開始顯露拖影。[Godot 說明](https://docs.godotengine.org/en/stable/tutorials/3d/volumetric_fog.html#volumetric-fog-properties) 亦列出動態光源的此項限制。

固定黑色接收面與相機、原手電筒能量、256×256、Forward+，只切換霧歷史設定：薄霧密度 0.0015 的關燈首幀平均紅色殘留為 0.003488，密度 0.06 時為 0.055527；關閉時間累積後兩者首幀均為 0，亮燈時散射則保持可見。直接檢視亮燈及關燈首幀擷取，確認舊光束殘留消失。紀錄：`.godot/light-ghost-probe.log`。

修正由 WorldClock 關閉正式室外體積霧的 temporal reprojection，灰階參考跟隨；霧、燈光互動、密度與使用者曲線不改。保留空間濾波，取樣平滑度仍受霧解析度限制。

新增首幀 GPU 回歸，直接使用正式 WorldClock 的環境及正式手電筒：確認霧中光束仍可見，移動光束／轉相機的首幀與穩定畫面一致，關燈首幀無餘光；同步確認參考圖不保留歷史。Forward+ 支援檢查全數 PASS，含原有灰階、霧遮蔽、室內轉移及曲線原檔保護。紀錄：`.godot/light-ghost-regression-forward.log`。Compatibility 沒有體積霧，本次未重跑未受影響的核心／Compatibility 套件。
