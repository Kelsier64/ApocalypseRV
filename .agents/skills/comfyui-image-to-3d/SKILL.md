---
name: comfyui-image-to-3d
description: Generate a textured 3D asset from a reference image with local ComfyUI, inspect and edit it, then use it in the project. Useful for static props and decoration when the main agent wants a direct, flexible workflow.
---

# Image to 3D：生成、檢查、修整、使用

由主 agent 按任務需要直接處理。需求清楚就開始做

## 適合哪些模型

適合靜態道具、裝飾、箱桶、零部件、設備，以及輪廓清楚、細節容許近似的物件。簡單牆板、地板、精確開孔通常直接建模更省事。

細桿／網格、完全筆直的機架、精密機械、必須準確配合的零件、可動接口與需要骨架動畫的角色，往往需要較多人工處理。可讓模型生成外觀，再另外做結構、活動零件或 rig。

## 常見限制

單圖未拍到的背面會由模型猜測，可能多件、缺件、融合或歪斜；高面數也不保證平直、平行或共面。GLB 通常還要調尺寸、朝向、原點，拆分零件／材質；動畫、碰撞、轉軸與遊戲接口要另外處理。後期降面用來控制成本。

## 大概流程

1. 先看用途、風格、場景尺寸與必要接口，挑適合生成的部分。
2. 沿用原圖或用 imagegen 製作參考圖：透明 PNG、單件完整物體、弱透視三分之四視角，重要孔洞與接點清楚，保持原配色與材質風格。
3. 用現成腳本或直接操作 ComfyUI 生成。目前腳本的起點是單圖 TRELLIS.2、1024、seed 42、約 50k 三角面；這是生成設定，不代表遊戲面數預算。需要調設定時可用原生 graph/API。
4. 在 Godot、Blender 或可用檢視器轉著看，包含側面、背面和底部；檢查比例、彎曲、缺件、孔洞、材質與接口。外觀有疑問時用素色顯示分辨幾何與貼圖。
5. 按問題調旋轉／尺寸／原點，修局部網格、拆材質或零件；大結構錯誤可改參考圖再生成。接入前依尺寸、觀看距離及同屏數量評估面數預算；成本偏高就先試降面，保留較高面數時簡述理由。方法見[降面方法與實測](references/decimation.md)。可先用 meshoptimizer／gltfpack 快速試減面；若保留 UV 的設定降不下去，或出現變形／貼圖碎裂，再按需要用 Blender 修整、重新展 UV 並烘焙原模型細節。保留原 GLB，修改另存，修完再看。
6. 可用就接入場景，確認實際尺度、光照、碰撞和互動；保留既有遊戲功能。按下述規則整理交付，再簡短說明結果與剩餘問題。主 agent 自行判斷處理方法，卡住或需要使用者選擇時再問。

## 工作產物與 Git 交付

生成 job／完整 history、各輪降面候選、批次檢查圖、失敗輸出、臨時日誌與工具依賴預設放已忽略的 `.godot/art-work/<asset>/<run>/`，每次用新資料夾。完整檢查仍在本機執行；不要因為產生過檔案就全數提交。

Git 只保留正式模型／貼圖、必要原始及可編輯來源、重建腳本與精簡參數／來源摘要，以及少量最終代表圖和驗證報告。避免重複備份與完整測試工作目錄；不要全域忽略 `art_source/` 或 `*.glb`／`*.png` 等正式資產副檔名。

提交前檢查 staged 路徑、檔案數與大小，明確挑選必要檔案。已追蹤產物需取消追蹤或移到忽略目錄，新增 gitignore 規則不會自動移除它們。本機證據先保留；不預設刪除原始模型、提交結果不明的 job 或使用者檔案。

## 本機操作

服務入口為 `http://127.0.0.1:8000/health`，腳本從這裡找到 ComfyUI 後端（通常是 `8188`）。Python 需要 Pillow；若 PATH 沒有 Python，可用 Codex 的 `load_workspace_dependencies` 找內建 runtime，以完整路徑執行，不必全域安裝。在專案根目錄執行：

```powershell
$skill = '.agents/skills/comfyui-image-to-3d'
python "$skill/scripts/generate.py" preflight
python "$skill/scripts/generate.py" submit --image 'reference.png' --asset-id 'prop_name' --output '.godot/art-work/prop_name/run_01'
python "$skill/scripts/generate.py" collect --output '.godot/art-work/prop_name/run_01'
```

輸出使用新資料夾；`collect` 還在 RUNNING／QUEUED 時稍後再收，完成會有 `raw.glb`。提交 timeout 時先查同一工作的 queue/history，避免重複提交。工具自動保存的工作資料直接沿用。

要快速產生檢查圖時，執行 `python "$skill/scripts/review.py" --source <raw.glb> --output <新檢查資料夾> --godot <Godot.exe>`，會產生六視角的材質／受光素色圖，含底部；也可直接在場景裡檢查。Godot 可用 PATH 上的執行檔或 `--godot` 指定實際位置。模型／貼圖通常放 `assets/models/<名稱>/`，原圖與修改來源放 `art_source/<名稱>/`，沿用既有位置也可以。
