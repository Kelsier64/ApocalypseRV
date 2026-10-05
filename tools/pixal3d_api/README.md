# Pixal3D Local Asset API V2

部署：`C:\Users\evan4\Apps\Pixal3D-API-v2`。入口：<http://127.0.0.1:8000/docs>。
Python 3.12／FastAPI，沿用本機 ComfyUI `8188` 與既有 Pixal3D INT8 權重。

RV 內的 `tools/pixal3d_api/` 是可審查的程式來源；運行中的工作資料保存在 Apps 安裝，不加入 Git。此工具資料夾有 `.gdignore`，不進入 Godot 遊戲資源匯入。

## 啟動與停止

```powershell
cd C:\Users\evan4\Apps\Pixal3D-API-v2
.\start.ps1
.\stop.ps1
# 不占用正式入口的測試實例
.\start.ps1 -Port 8001
.\stop.ps1 -Port 8001
```

預設共用相鄰舊 API 的 `.venv`，不下載依賴或權重。可用 `-Python` 指定另建的環境，依賴版本見 `requirements.txt`。`-ComfyRuntime`、`-LegacyRoot` 可指定既有安裝位置。ComfyUI 未啟動時會使用既有 runtime／model paths 啟動，已啟動時直接共用。API 綁定 `127.0.0.1`。停止腳本只停止此安裝、此 port 的 API，保留 ComfyUI；有工作時需先等完成，或明確使用 `-Force`，下次啟動繼續追蹤已保存的 prompt。

`PIXAL3D_COMFY` 可在直接執行 uvicorn 時指定後端；`PIXAL3D_LEGACY_ROOT` 提供舊成功工作的 status／result／GLB 唯讀相容性。啟動腳本設定這兩個值。舊程式、工作與權重均保留，V2 不重跑舊工作。

## 上傳方式

`POST /jobs` 延續 `image`、`asset_id`、`preset`、`seed` 欄位。`preset` 可選：

| preset | 圖片 | 用途 |
| --- | --- | --- |
| preview512 | 單張 | 快速確認輪廓 |
| standard1024 | 單張 | 單圖較高解析度 |
| threeview512 | 三視圖 | 快速確認多視圖相容性 |
| threeview1024 | 三視圖 | 家具等需一致結構的候選模型 |

三視圖圖板必須是精確 **3:1**，依序為 **正面／左側／背面** 的三個相同正方形畫布。例如 2172×724。也可用 `POST /jobs/multiview` 分別上傳 `front`、`left`、`back` 和選填的 `right`，每張必須同尺寸且為正方形。兩種上傳都保留共同畫布，只以同一倍率轉成 1024×1024；不再逐張依輪廓裁切放大。

相機水平、物件中心高度、同一鏡頭與距離。物件同一根床柱在三張圖中應有相同像素高度，側面較窄是正常的。物件置中、四腳完整可見、留約 5% 邊界；結構畫直，磨損留在材質上。正面是長邊，左側繞物件轉 90°，背面轉 180°。請勿把獨立放大過的三張圖拼在一起：API 能檢查畫布尺寸，無法自動辨識物件實際比例是否一致。

`fov` 是 1–170 度的相機水平視角；多視圖預設 20，床測試使用 20。單圖不填時沿用 MoGe 估計，填入時使用指定值。用很廣的鏡頭不會讓床自動變直；先改善參考圖與共同尺度。

`background`：

- `auto`（預設）：非全不透明的 alpha 優先；黑底直接使用；其他背景透過 BirefNet 去背。
- `alpha`：要求圖片包含非不透明 alpha；多視圖合成至黑底，單圖使用原 alpha 作裁切 mask。
- `black`：你已準備好的黑底圖，可跳過去背。
- `remove`：強制去背。多視圖只套用 mask，保留原位置與尺度。

單圖仍使用既有物件裁切流程，因為沒有跨視圖相機一致性需求。每張上傳最多 25 MiB，最多 16 百萬像素；單圖／每個多視圖面板最長邊 4096；三視圖總圖最長邊受 8192 限制。錯誤圖板、尺寸、FOV 或圖片會在排隊前回傳 422／413。

```powershell
curl.exe -X POST http://127.0.0.1:8000/jobs `
  -H "Idempotency-Key: bed-shared-42" `
  -F "image=@C:/path/bed-front-left-back.png" `
  -F "asset_id=bunker_bunk_bed" -F "preset=threeview1024" `
  -F "seed=42" -F "fov=20" -F "background=black"

curl.exe -X POST http://127.0.0.1:8000/jobs/multiview `
  -F "front=@C:/path/front.png" -F "left=@C:/path/left.png" -F "back=@C:/path/back.png" `
  -F "asset_id=bunker_bunk_bed" -F "preset=threeview1024" -F "fov=20"
```

同一 `Idempotency-Key`、相同原圖與選項回傳同一 job；換圖或換選項使用同一 key 會回傳 409。改 seed／FOV 進行下一個試驗時使用新 key。

## 取得輸出與排查

- `GET /health`：API active／queued 與後端可用性，後端不可用時 HTTP 503。
- `GET /jobs/{job_id}`：`queued → running → succeeded`，或 `failed`；包含實際 prompt ID。
- `GET /jobs/{job_id}/result`：GLB SHA256、容器檢查、實際 conditioning 下載 URL。
- `GET /jobs/{job_id}/result.glb`：下載原始 GLB，每次檢查摘要。
- `GET /jobs/{job_id}/inputs`、`/inputs/{view}.png`：準備後的圖、原圖摘要、模式、尺度及 workflow revision。
- `GET /jobs/{job_id}/conditioning/{view}.png`：ComfyUI 真正輸入 conditioning 的圖，非上傳前的預覽。

每個 V2 job 都保存原始上傳、準備後的 PNG、精確 `prompt.json`、`history.json`、conditioning 和 GLB。所有視圖 conditioning 與 GLB 收齊且檢查通過後才標記成功。API 以單一 worker 排隊，等待共用 ComfyUI 佇列空閒後提交；不使用全域 interrupt。重啟時追蹤已保存的 prompt，不重新提交；提交結果未保存的極短時間內若斷線，標記失敗供人工查詢，避免重複 GPU 工作。

服務日誌在 `deployment/api-<port>.stdout.log`／`.stderr.log`。失敗請先看該 job 的 `history.json` 與 ComfyUI 狀態，再用新 key 提交；API 不自動重跑失敗的生成。舊成功 job 的結果明確標記 `service_revision=legacy`、`framing_verified=false`，不提供 V2 conditioning／inputs。

若生成已成功、只有下載或存檔失敗，可先停止 API，再執行 `python deployment/recover_completed.py <job_id>` 並重新啟動。此工具要求原 prompt 已成功，僅恢復收檔，不提交新的生成；收檔仍經過相同完整性檢查。

GLB 容器／SHA 檢查不等於結構筆直或遊戲驗收。結果預設 `needs_art_review=true`，Godot／Blender tested flags 維持 false；另行做過的床載入與渲染測試記在驗證報告中。此 API 不做自動修形、獨立軸拉伸或世界場景替換。

## 開發驗證

```powershell
& C:\Users\evan4\Apps\Pixal3D-API\.venv\Scripts\python.exe -m unittest discover -s tests -v
```

測試使用隔離 job 目錄與假後端，另有 requests／uvicorn 的真 HTTP 測試，不占 GPU。`deployment/bed_smoke.py` 提供對指定本機服務的床實測：`submit` 才會生成，`collect` 只收現有工作，`invalid` 驗證錯誤圖板。實測結果另存，不把舊研究測試列為本次測試。
