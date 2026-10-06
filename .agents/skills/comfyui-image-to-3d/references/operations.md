# 提交、降面與驗收協議

從 repo 根目錄執行；`$skill = '.agents/skills/comfyui-image-to-3d'`。安裝見[操作指南](../../../../docs/guides/image-to-3d-workflow.md)。Python 需 Pillow；HTTP 用標準函式庫。以下資料夾均應為本次專用新路徑，不能覆蓋已有輸出。

```powershell
python "$skill/scripts/generate.py" preflight
python "$skill/scripts/generate.py" submit --image '<reference.png>' --asset-id '<asset_id>' --output '<generation-folder>'
python "$skill/scripts/generate.py" status --output '<generation-folder>'
python "$skill/scripts/generate.py" collect --output '<generation-folder>'
python "$skill/scripts/generate.py" inspect --glb '<generation-folder>/raw.glb'
python "$skill/scripts/review.py" --source '<generation-folder>/raw.glb' --output '<raw-review-folder>' --godot '<Godot.exe>'
```

每個命令只提交／查詢一次。未完成時做其他獨立工作後再查。只用 ComfyUI 時 `preflight`／`submit` 明確加 `--backend http://127.0.0.1:8188`，會略過 8000；一般由 8000 `/health` 發現後端並確認 API／Comfy queue 都空閒。不是跨程序鎖，其他 client 仍可能同時提交。工具不啟停服務、不下載權重、不改 preset。固定 graph／seed 不提供臨時調參入口。

`submit` 必須新資料夾。檔案包含 `job.json`（client ID、backend、prompt ID、SHA／狀態）、原 bytes `reference.png`、`prompt.json`／`submission.json`／`history.json`、真正 1024 conditioning.png、raw.glb 及 result.json。`READY` 只表示生成必要資源可用；`ART_REVIEW_REQUIRED` 只表示收檔／技術檢查成功。

## 提交結果不明

`SUBMISSION_INTENT`／`SUBMISSION_UNKNOWN` 不刪除、不重送。讀相同 backend `/queue` 或 `/history?max_items=100`，查確切 client ID＋graph。找到既有 prompt ID 才執行：

```powershell
python "$skill/scripts/generate.py" reconcile --output '<generation-folder>' --prompt-id '<existing-prompt-id>'
python "$skill/scripts/generate.py" collect --output '<generation-folder>'
```

`reconcile` 只核對並記錄既有 ID，沒有 POST。找不到就保持 UNKNOWN 並停止回報。`NOT_SUBMITTED` 表示 POST 前失敗，也停止批次。收檔失敗可對同一 prompt 再 collect；相同 SHA 舊檔沿用，內容不同立刻停止。

## Raw 通過後降面

```powershell
$module = '.godot/mesh-decimation/node_modules/meshoptimizer/meshopt_simplifier.js'
node "$skill/scripts/simplify.mjs" '<generation-folder>/raw.glb' '<reduced-folder>' 20000 $module
if ($LASTEXITCODE -ne 0) { throw '減面停止：檢查錯誤與 simplification.json，回報使用者' }
python "$skill/scripts/review.py" --source '<generation-folder>/raw.glb' --candidate '<reduced-folder>/raw.glb' --output '<comparison-folder>' --godot '<Godot.exe>'
```

目標沿用 request，否則 20k；誤差上限 0.002。讀 `simplification.json` 的 requested／actual／target_reached；未達時保存 `TARGET_NOT_REACHED` 摘要且 exit 2，立即停止報告。源模型已 <=目標則保存原 bytes、不降面。只有人明確授權本工作放棄誤差上限才在 node 命令最後加 `--force-target`。該模式仍保留 LockBorder／tuple 等限制，拓樸阻止達標會 exit 非零；不自動改 flags。輸出新 raw.glb、vertex_mapping.json、simplification.json，`acceptance` 保持 false。詳見[方法](decimation.md)。

## 五視角與 review.json

`review.py` 使用獨立臨時 Godot project，完成或失敗後釋放 viewer；Windows 隱藏啟動並保存 stdout.log／stderr.log／godot.log。不開／操作 editor。面數／SHA／保全錯誤停止；渲染錯誤保持 UNKNOWN，查看日誌。

- 新 review 資料夾包含 manifest.json、framing.json、review.json，以及 source／candidate 下各自 godot_review.json、textured 與 clay 的 front.png、side.png、back.png、oblique.png、top.png。raw-only 沒有 candidate。
- 相機／光線／framing 取 source，各版本完全相同；預設來源 up。不讀模型旁的 pose.json 暗中正位。確定需要剛體正位時明確傳 `--pose '<pose.json>'`；其內容只有 `rotation_rows` 的右手正交 3×3旋轉，不能分軸縮放、鏡射或 shear，並保留另一組來源 up 檢查。
- front 為顯示座標 +Z；遊戲指定 front／origin 仍需依 request 確認。檔案／畫面產生 PASS 不等於外觀 PASS。
- 3D agent 看完每個模型 textured＋clay 的全部五視角後，補寫 review.json 的 views_inspected、checks、defects、limitations 和最終 state。checks 記錄方法、測量值、單位、需求容差與 PASS／FAIL／UNKNOWN；沒有數值證據時使用明確觀察，不編造精度。
- 任何歪斜、缺件、風格變化、預算未達或必要 UNKNOWN 都停止，不繼續下一件。整合由主 agent 依任務與通過結果處理。
