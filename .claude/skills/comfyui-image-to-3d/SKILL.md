---
name: comfyui-image-to-3d
description: Turn one reference image into a textured GLB with local ComfyUI (TRELLIS.2), review it in Godot, fit/decimate it, and wire it into the game. Use for static props, decoration, crates, barrels, components and equipment with clear silhouettes where approximate detail is acceptable.
---

# Image → 3D

主 agent 直接執行：準備參考圖 → 生成 → 看模型 → 校正／降面 → 接入。需求清楚就開始；只有需要使用者做選擇時才問。

## 何時用

- **適合**：靜態道具、裝飾、箱桶、零件、設備等輪廓清楚、細節可近似的物件。
- **不適合直接生成**：牆板、地板、精確開孔、需要準確配合的零件、可動接口、需骨架動畫的角色。可先生成外觀，結構／活動件／rig 另做；簡單幾何直接建模更快。
- **已知限制**：單圖看不到的背面靠模型猜，可能缺件、融合、歪斜；直線不保證平直。GLB 通常要調尺寸、朝向、原點，碰撞與互動另做。

## 環境

在專案根目錄執行。Python 需要 Pillow（`prepare_prop.py` 另需 numpy）；系統 Python 沒有時，用 ComfyUI runtime 的 venv，不要全域安裝：

```powershell
$skill = '.claude/skills/comfyui-image-to-3d'
$py = "$env:USERPROFILE/Apps/ComfyUI/pixal3d-runtime/.venv/Scripts/python.exe"   # 或任何有 Pillow+numpy 的 Python
$work = '.godot/art-work/<asset>/run-01'                                          # 每次用新的忽略資料夾
```

服務入口 `http://127.0.0.1:8000/health`，腳本由此找到 ComfyUI 後端（8188）。`preflight` 連線被拒代表服務沒開，不是 graph 壞了；啟動方式見[本機操作](references/operations.md)。

## 流程

### 1. 參考圖

沿用合適的原圖；缺圖或不適用時才用 imagegen 製作。要求：

- 透明背景靜態 PNG，一張只有一件完整物體，弱透視三分之四視角；高大物件接近水平鏡頭。
- 輪廓、腳、孔洞與接點清楚；保留原配色與材質風格。不要地板、投影、背景、拼圖或三視圖。
- 細線加粗或另做；磨損用貼圖表現，不加需求外的碎零件。
- **不得有**操作提示、按鍵、物品名稱、狀態標籤或白色／發光提示字（見 CLAUDE.md「In-Game Text」）。

先實際看過圖再生成。使用者要求先看圖時先給預覽。

### 2. 生成

```powershell
& $py "$skill/scripts/generate.py" preflight
& $py "$skill/scripts/generate.py" run --image '<reference.png>' --asset-id '<asset>' --output "$work/generation"
```

`run` = 提交一次 + 等待 + 收檔（預設等 30 分鐘，`--timeout` 調整）。單件約數分鐘（RTX 5070 Ti）。完成後 `$work/generation/` 有 `raw.glb`、`conditioning.png`、`result.json`，狀態 `ART_REVIEW_REQUIRED`（技術檢查通過，仍要看模型）。

| 結果 | 處理 |
|---|---|
| exit 3／`RUNNING`、`QUEUED` | 還沒完成：`generate.py wait --output <job>` 繼續等，**不要再 submit** |
| `STOPPED` busy | 共用佇列忙碌，稍後再試；不要清空或中斷別人的工作 |
| `SUBMISSION_UNKNOWN` | 提交結果不明，依[續跑與核對](references/operations.md#提交結果不明)處理，不重送 |
| `attribute_issues` 有數值 | 法線／切線異常；`prepare_prop.py` 會修切線，其他在副本處理 |

分步指令（`submit`／`status`／`collect`／`reconcile`／`inspect`）與生成參數見[本機操作](references/operations.md)及[生成設定](references/profile.md)。輸出資料夾已存在時腳本拒絕執行，避免覆蓋或重送。

### 3. 看模型

```powershell
& $py "$skill/scripts/review.py" --source "$work/generation/raw.glb" --output "$work/reviews/raw"
```

在隔離的臨時 Godot 專案產生六視角（front、side、back、oblique、top、underside）× 材質／受光灰模共 12 張圖，含 `review.json`（初始 `UNKNOWN`）。**逐張看**：比例、彎曲、缺件、孔洞、底部支撐、材質、接口。外觀疑問以灰模區分幾何與貼圖問題。

- 小問題（朝向、尺寸、原點）→ 下一步校正。
- 結構錯誤（缺件、融合、嚴重歪斜）→ 改參考圖重新生成；降面不能修直或補件。
- 需要時在 `review.json` 填 checks／defects；技術 PASS ≠ 外觀合格。

### 4. 校正與降面

依尺寸、觀看距離、同屏數量訂面數預算；生成的約 50k 面不是遊戲預算。可近看的小道具常落在 5k–13k 面。單 mesh 靜態道具用共用工具一次完成旋轉、尺寸、原點與 gltfpack 降面：

```powershell
& $py "$skill/scripts/prepare_prop.py" prepare --source "$work/generation/raw.glb" --output "$work/prepared" `
  --asset <asset> --size <X> <Y> <Z> --origin bottom-center --front +Z --rotation-y 0 --ratio 0.12
& $py "$skill/scripts/review.py" --source "$work/prepared/final.glb" --output "$work/reviews/final"
```

`--size` 為公尺、逐軸縮放（要保比例就自行等比計算）；`--rotation-y` 在縮放前套用；gltfpack 自動從 PATH 或 `.godot/gltfpack-1.3/bin/` 尋找。再看一次 12 張圖，確認朝向、輪廓與貼圖沒碎。詳見[靜態道具工具](references/static-props.md)；gltfpack 降不下去或貼圖碎裂時見[降面方法](references/decimation.md)（Blender 修整＋烘焙）。

`review.py --candidate <glb>` 只用於與 source **同座標系**的候選（例如同一 raw 的不同降面）；`final.glb` 已改尺寸，請像上面一樣單獨當 `--source` 檢查。

### 5. 接入與交付

- 灰盒 wrapper（`Visuals/Model` 為 Node3D）用 `prepare_prop.py publish` 接入，見[靜態道具工具](references/static-props.md#檢查後接入)；其他場景直接編輯，不移動碰撞遷就外觀。
- 在遊戲場景確認實際尺寸、光照、碰撞、互動與所有使用處，保留既有功能。
- 正式模型放 `assets/models/<asset>/`；參考圖、editable、`model_parameters.json` 與簡短 README（來源、prompt ID、參數、面數、已知問題）放 `art_source/<asset>/`。
- `.godot/art-work/` 的 job、候選、檢查圖與 log 留在本機，不進 Git。
- 回報：結果、面數、看過什麼、剩餘問題；未看過的不要說已驗證。

## 多件與工具測試

多件逐件生成：一件收妥 `raw.glb` 再提交下一件。修改腳本後跑離線測試（不連服務、不用 GPU）：

```powershell
& $py "$skill/scripts/test_client.py"
& $py "$skill/scripts/test_prepare_prop.py"
```
