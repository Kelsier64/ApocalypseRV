# 本機操作

所有指令在專案根目錄執行，變數沿用 [SKILL.md](../SKILL.md#環境) 的 `$skill`、`$py`、`$work`。

## 啟動服務

`preflight` 連線被拒時，先確認服務是否已開。使用者已要求生成時，可用本機既有啟動器（不重裝、不下載權重）：

```powershell
& "$env:USERPROFILE/Apps/Pixal3D-API-v2/start.ps1"
```

腳本會在背景啟動 ComfyUI（8188）與 API（8000），已在執行則直接返回。等 `/health` 回報 `backend.available=true` 再跑 preflight。約兩分鐘仍未就緒，查啟動器旁的 `deployment/comfy.stderr.log`、`deployment/api-8000.stderr.log`。API 已開但後端失效時另查後端，不要反覆重啟共用服務。其他電腦沿用實際安裝的啟動方式；只有 ComfyUI 時，preflight／submit／run 加 `--backend http://127.0.0.1:8188`。

## 分步指令

```powershell
$job = "$work/generation"
& $py "$skill/scripts/generate.py" preflight                       # 節點、權重、佇列空閒
& $py "$skill/scripts/generate.py" submit --image '<ref.png>' --asset-id '<asset>' --output $job
& $py "$skill/scripts/generate.py" status --output $job            # 查一次
& $py "$skill/scripts/generate.py" wait --output $job --timeout 900 # 輪詢直到完成並收檔
& $py "$skill/scripts/generate.py" collect --output $job           # 收一次
& $py "$skill/scripts/generate.py" inspect --glb "$job/raw.glb"     # 只做 GLB 技術檢查
```

| exit | 意義 |
|---|---|
| 0 | 完成（`READY`、`SUBMITTED`、`ART_REVIEW_REQUIRED` 等） |
| 1 | `STOPPED`，看 `error` |
| 2 | 後端找不到這個 prompt（`UNKNOWN`） |
| 3 | 仍在 `RUNNING`／`QUEUED` |

保證：

- `submit`／`run` 先檢查 API 與 ComfyUI 佇列都空閒才提交，同一輸出資料夾只會 POST 一次；沒有跨程序鎖，不要並行提交。
- `status`／`wait`／`collect`／`reconcile` 只讀後端，可重複執行。收檔會核對保存的參考圖、graph 與 client ID；同 SHA 舊檔沿用，內容不同則停止並保留舊檔。
- 腳本不啟停服務、不下載權重、不改 graph；`inspect` 只檢查不修改。拓樸（重複面、非流形邊）不在此檢查。

## 提交結果不明

`SUBMISSION_INTENT`／`SUBMISSION_UNKNOWN`（例如 POST timeout）：**不要刪資料夾、不要重送。** 到同一後端查 `/queue` 或 `/history?max_items=100`，用 `job.json` 的 `client_id` 與 `prompt.json` 找到既有 prompt ID，再：

```powershell
& $py "$skill/scripts/generate.py" reconcile --output $job --prompt-id '<prompt-id>'
& $py "$skill/scripts/generate.py" wait --output $job
```

`reconcile` 會核對 graph 與 client ID，不會提交新工作。找不到就保留 UNKNOWN 並回報使用者；`NOT_SUBMITTED`（上傳後失敗、沒有 POST）也停止批次並回報。

## 環境問題

- PATH 上的 `python` 是 Windows Store 佔位程式時，用 `$py` 的完整路徑。
- 缺 Pillow／numpy 又不想用 ComfyUI venv：`python -m pip install --target "$work/deps/python" Pillow numpy`，執行時設 `$env:PYTHONPATH = "$work/deps/python"`。
- Windows 暫存目錄被拒寫時，把本程序的 `TEMP`／`TMP` 改到 `.godot/` 下的忽略資料夾再跑測試或 review。
- Godot 不在 PATH：`review.py --godot 'C:/Program Files/godot/godot.exe'`。
