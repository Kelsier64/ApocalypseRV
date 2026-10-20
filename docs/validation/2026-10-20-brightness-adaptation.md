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

以下為環境光門檻優化前的歷史量測。1280×720、3D scale 100%、Forward+、關閉 VSync，同一場景每組暖機 40 幀、取 180 幀平均，其他測試未同時執行：

| 固定視角 | 停用灰階 | 啟用灰階 | 額外時間 |
|---|---:|---:|---:|
| 中午 | 1.584 ms／幀、811 draw calls | 2.327 ms／幀、1109 draw calls | 0.744 ms／幀 |
| 夜間、車燈開 | 1.570 ms／幀、707 draw calls | 2.312 ms／幀、1005 draw calls | 0.742 ms／幀 |

此數字只代表該固定視角；正式 v12 教學建築、鏡面、不同解析度或濃霧可有不同成本。當時日間也需要參考圖以辨識暗處；後續門檻優化見本頁末段。複雜透明材質、微弱彩色照明及體積霧時間取樣仍可能有視覺估計差異，沒有宣稱精確光照分解。

## 同日後續：光源殘影修正

使用者回報移動光源在夜間留下殘影。已用正式手電筒逐幀重現：原生體積霧的 temporal reprojection 保留 80% 前幀光照；灰階重構恢復了夜間霧，讓這個原有累積設定開始顯露拖影。[Godot 說明](https://docs.godotengine.org/en/stable/tutorials/3d/volumetric_fog.html#volumetric-fog-properties) 亦列出動態光源的此項限制。

固定黑色接收面與相機、原手電筒能量、256×256、Forward+，只切換霧歷史設定：薄霧密度 0.0015 的關燈首幀平均紅色殘留為 0.003488，密度 0.06 時為 0.055527；關閉時間累積後兩者首幀均為 0，亮燈時散射則保持可見。直接檢視亮燈及關燈首幀擷取，確認舊光束殘留消失。紀錄：`.godot/light-ghost-probe.log`。

修正由 WorldClock 關閉正式室外體積霧的 temporal reprojection，灰階參考跟隨；霧、燈光互動、密度與使用者曲線不改。保留空間濾波，取樣平滑度仍受霧解析度限制。

新增首幀 GPU 回歸，直接使用正式 WorldClock 的環境及正式手電筒：確認霧中光束仍可見，移動光束／轉相機的首幀與穩定畫面一致，關燈首幀無餘光；同步確認參考圖不保留歷史。Forward+ 支援檢查全數 PASS，含原有灰階、霧遮蔽、室內轉移及曲線原檔保護。紀錄：`.godot/light-ghost-regression-forward.log`。Compatibility 沒有體積霧，本次未重跑未受影響的核心／Compatibility 套件。

## 同日後續：車身晃動的參考視圖錯位

使用者回報車身晃動仍有明顯殘影。已重現獨立於霧歷史的另一個問題：`frame_pre_draw` 更新參考相機與合成 Quad 時，SceneTree 一般變換通知已處理完，繪圖端姿勢未即時更新。前段純黑接收面的霧測試沒有參考輪廓，無法揭露這種錯位。

以共用車架的相機與正式 `vehicle_lights.gd`、黑色天空及白色輪廓比較晃動首幀與停住多幀後畫面。實際 runtime interpolation=false、TAA=false。256×256、使用原自訂距離曲線的診斷中，車燈關閉時最大 RGB 向量差為 0.407541，開燈時為 0.027730；參考相機及 Quad 定位後立即 `force_update_transform()`，兩種狀態差異均為 0。兩個 render-driven helper 同時明確停用自身 physics interpolation，避免將來源已插值的顯示姿勢再插值一次；專案插值設定不變。紀錄：`.godot/rig-pose-before.log`／`rig-pose-after.log`。

支援測試新增傾斜、側滾、平移與鏡面轉向的輪廓首幀檢查及可見性斷言；Forward+／Compatibility 全數 PASS。既有原生燈光、霧、相機轉移、暫停、staging 與曲線原檔檢查維持通過。紀錄：`.godot/vehicle-ghost-regression-forward.log`／`vehicle-ghost-regression-compatibility.log`。

另以正式 `rv/new_rv.tscn`、原玩家進入 DriverSeat、頭燈及 Jolt 車體／懸吊施加外部交變力矩，實際側滾最大 0.02702 rad、俯仰最大 0.00888 rad；檢視駕駛座與車外的當幀擷取，輪廓保持清楚。這是物理晃動場景與靜態擷取檢視，沒有宣稱輪驅行駛、轉彎、翻車或連續影片已驗收。紀錄：`.godot/rv-rocking-review.log`。曲線 SHA256 保持上述原值。

## 同日後續：環境光門檻與參考渲染停用

依使用者要求，在現有局部亮度效果外增加每視圖環境光門檻，不改照明架構或距離曲線。正式 Color 環境光按線性顏色亮度 × energy 判斷，與時間無關；預設 ≤0.04 完整啟用、0.04～0.06 平滑淡出、≥0.06 隱藏合成 Quad 並停止參考更新。Camera Environment override 優先，否則取 World3D Environment／fallback。Sky／Background 無法直接得知天空照度時維持局部效果。全域環境光明亮時不再補白天局部陰影；profile 可關閉 gate 恢復持續處理。

同世界有任一暗視圖時，明亮相機仍需看見共用實體燈光並排除其他視圖的合成 Quad；全部明亮才還原相機與燈光原始圖層。門檻過渡只改當幀補光強度，沒有引入時間累積。

本次 editor import、Forward+ 與 Compatibility GPU 支援檢查均 PASS。新增檢查直接觀察 pre-draw 排程，確認明亮視圖請求 0 次參考更新、變暗會恢復、全數變亮再停止；並涵蓋休眠期間相機移動後喚醒首幀的輪廓一致、線性顏色門檻、中點強度、漸變 GPU 畫面、零門檻／零寬度／非有限值、相機 override、主畫面／鏡面明暗相反、非預設相機／燈光圖層、停用 gate 及原生 Environment 不變。原有光源與車身晃動首幀、霧、室內外交接、暫停、staging 與曲線檔保護也維持通過。紀錄：`.godot/ambient-gate-import.log`、`.godot/ambient-gate-forward.log`、`.godot/ambient-gate-compatibility.log`。

另以 legacy `world/test_world.tscn`、v6 seed 42、前後各一 chunk 設定、固定道路相機、1280×720、3D scale 100%、Forward+、停用復古濾鏡與 VSync，暖機後凍結世界運動，再各取 180 幀繪製量：中午明亮環境下，停用效果為 1491 draw calls／幀，啟用 gate 同為 1491，強制持續參考則為 2077；本視角省去 586 次額外繪製。停用效果與啟用 gate 的全圖最大 RGB 向量差為 0。此處只驗證繪製量與像素一致，沒有用短期 process monitor 推算 GPU 毫秒或正式世界 FPS。

檢視本次日間／22:00 擷取：日間保留場景配色，夜間自動恢復原曲線控制的近處灰階。這是固定視角檢視，沒有重新驗收行駛或所有透明材質。紀錄與畫面：`.godot/ambient-gate-context.log`、`ambient-gate-day.png`、`ambient-gate-night.png`。曲線 SHA256 保持本頁開頭原值；本次未重跑未受影響的攀爬／車輛行為或整套核心測試。
