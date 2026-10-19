# 夜視曲線調整

夜視的距離淡出使用 Godot `Curve` 資源，預設為 [world/night_vision_curve.tres](../../world/night_vision_curve.tres)。選取正式世界的 `WorldClock`，可在 Inspector 調整：

| 欄位 | 預設 | 用途 |
|---|---:|---|
| `night_vision_fade_begin` | 0 m | 曲線 X＝0 對應的距離 |
| `night_vision_fade_end` | 60 m | 曲線 X＝1 對應的距離；須大於開始距離 |
| `night_vision_ambient_energy` | 0.06 | 夜間中性底光，獨立於距離曲線 |
| `night_vision_curve` | 上述 Curve 資源 | 控制各距離保留多少亮度 |

## 編輯控制點與切線

在 FileSystem 開啟 Curve 資源，展開 Inspector 的曲線編輯器。X 是距離區間內的比例，Y 是保留亮度：1 保留全部、0 完全黑暗。例如預設區間中，X＝0.5 對應 30 m；該點 Y＝0.3 代表保留原場景亮度的 30%。

新增或移動控制點可調整衰減位置；編輯點的左右切線可分別控制進入、離開該點的速度。想讓尾段緩慢收黑，可增加靠近右側的控制點，拉平接近 Y＝0 的切線。曲線可以先降再升，支援非單調形狀。亮度取樣會限制於 0～1，範圍外的切線過衝不會產生負亮度或超亮增益。

距離小於開始值時使用曲線左端值，大於結束值時使用右端值。保留左端 `(0, 1)`、右端 `(1, 0)`，即可維持近處完整底光、結束距離外全黑；若修改右端亮度，遠方就會保留該亮度。預設資源取樣自 `1 - pow(smoothstep(0, 1, t), 0.85)`，用來承接原有外觀，現在可直接修改整條曲線。

Y 是距離遮罩的保留比例，實際像素仍受物件材質、場景照明、天氣與畫面設定影響；暗色物件的辨識度須在遊戲畫面中檢查。

## 在測試場重載

```powershell
godot --path . --log-file .godot/day-night-playground.log res://tests/day_night_playground.tscn
```

F1 循環切換清晨／中午／黃昏／夜間，並固定時間。修改 Curve 後先儲存，再按 K，測試場會依目前 `Curve.resource_path` 重載並立即套用，即使時鐘停止也可觀察。使用另存的資源時，先將 `night_vision_curve` 指向該檔案；K 重載的是目前指定的已保存資源。

F8 是 Godot 編輯器的「停止執行」快捷鍵，從編輯器啟動時會結束遊戲，因此重載使用 K。

此測試場載入的是 `world/test_world.tscn`，共用預設 Curve 檔，但不會繼承 `main_world.tscn` 的 Inspector 設定。預覽距離、底光或其他 Curve 資源時，請調整測試世界的 `WorldClock`，或執行中的 Remote Inspector；正式效果則保存至 `main_world.tscn`。

## 畫面與限制

戶外夜視只影響 3D 世界，HUD 保留原色，獨立 POI 使用自身照明。白天不套用夜間曲線；自然霧仍可能更早遮住遠景。曲線與這些 Inspector 設定屬於場景／資源配置，沒有新增存檔欄位。

距離遮罩以不透明深度計算徑向距離。雨幕與水花另以自身片段距離取樣同一條曲線；其他透明物件依後方不透明表面的距離近似，玻璃或透明效果可能與自身實際距離不同。調整後應同時檢查路面、暗色建築／樹木、發光物，以及隔著車窗的畫面。Forward+ 與 Compatibility 使用同一曲線。

[文件索引](../README.md) · [遊玩與測試場](playgrounds.md) · [架構](../../architecture.md)
