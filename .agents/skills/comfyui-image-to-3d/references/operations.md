# 本機操作

專案根目錄執行，Python 需 Pillow。PATH 沒有 Python 時可用 Codex `load_workspace_dependencies` 找內建 runtime，改以完整路徑執行；工具說明見[操作指南](../../../../docs/guides/image-to-3d-workflow.md)。生成、降面與檢查各用新資料夾，保留原檔。

## 生成與收檔

```powershell
$skill = '.agents/skills/comfyui-image-to-3d'
python "$skill/scripts/generate.py" preflight
python "$skill/scripts/generate.py" submit --image '<reference.png>' --asset-id '<asset_id>' --output '<generation-folder>'
python "$skill/scripts/generate.py" status --output '<generation-folder>'
python "$skill/scripts/generate.py" collect --output '<generation-folder>'
python "$skill/scripts/generate.py" inspect --glb '<generation-folder>/raw.glb'
```

預設由 8000 `/health` 找後端；只用 ComfyUI 時，preflight／submit 加 `--backend http://127.0.0.1:8188`。會檢查 API／Comfy queue 空閒，但沒有跨程序鎖；腳本不啟停服務、下載權重或改 preset。

每次命令只操作一次，未完成稍後再查。沿用自動保存的 job、原圖、conditioning、prompt／history 與結果。`READY` 表示資源可用，`ART_REVIEW_REQUIRED` 表示技術檢查成功，仍需看模型。

## 提交結果不明

`SUBMISSION_INTENT`／`SUBMISSION_UNKNOWN` 不刪除、不重送。查同一 backend 的 `/queue` 或 `/history?max_items=100`，以確切 client ID＋graph 找既有 prompt ID：

```powershell
python "$skill/scripts/generate.py" reconcile --output '<generation-folder>' --prompt-id '<existing-prompt-id>'
python "$skill/scripts/generate.py" collect --output '<generation-folder>'
```

reconcile 不提交新工作。找不到就保留 UNKNOWN 並回報；`NOT_SUBMITTED` 也停止批次。collect 可對同一工作重試；同 SHA 舊檔沿用，內容不同則停止。

## 降面

先讀[方法與限制](decimation.md)。固定 profile 腳本範例：

```powershell
$module = '.godot/mesh-decimation/node_modules/meshoptimizer/meshopt_simplifier.js'
node "$skill/scripts/simplify.mjs" '<generation-folder>/raw.glb' '<reduced-folder>' 20000 $module
if ($LASTEXITCODE -ne 0) { throw '降面未通過，查看 simplification.json' }
```

查摘要的 requested／actual／target_reached；未達標 exit 2，不能當作通過，可另用副本修整。只有使用者明確授權放棄誤差上限才加 `--force-target`，勿暗改 flags。輸出 GLB、頂點 mapping 與摘要，`acceptance` 仍為 false。

## 檢查圖

```powershell
python "$skill/scripts/review.py" --source '<generation-folder>/raw.glb' --output '<review-folder>' --godot '<Godot.exe>'
```

比較時加 `--candidate '<reduced-folder>/raw.glb'`。

- viewer 使用臨時 Godot project，Windows 隱藏啟動，結束後關閉；日誌保存在輸出資料夾。
- 產生 textured／受光灰色 clay 的 front、side、back、oblique、top、underside 六視角及 review JSON；比較共用 source 的鏡頭、光照與 framing。
- 預設來源 up、front 為 +Z，不自動讀 pose。正位明確加 `--pose '<pose.json>'`，只接受右手正交 `rotation_rows` 3×3 旋轉，並保留來源 up 檢查；遊戲朝向／原點另確認。
- 看完全部圖再填 `review.json` 的 views_inspected、checks、defects、limitations、state；測量附方法、單位與容差，觀察不冒充精度。
- 技術 PASS 不等於外觀合格。面數／SHA／保全錯誤停止，渲染錯誤標 UNKNOWN；缺件、歪斜、預算未達或必要 UNKNOWN 時修整或回報。

## 離線工具回歸

`python "$skill/scripts/test_client.py" -v` 不連服務、不提交 GPU 工作；檢查忙碌拒收、提交 timeout 不重送、輸入綁定、唯讀重收、錯誤 history、原檔保全與剛體姿態限制。實際生成、渲染與美術驗收另做。
