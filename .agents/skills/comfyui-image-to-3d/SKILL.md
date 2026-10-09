---
name: comfyui-image-to-3d
description: Generate a textured 3D asset from a reference image with local ComfyUI, inspect and edit it, then use it in the project. Useful for static props and decoration when the main agent wants a direct, flexible workflow.
---

# Image to 3D：生成、檢查、修整、使用

預設採「必要製作 → 一次情境檢查 → 相關驗證 → 精簡回報」。小修改只做局部檢查；有新變更、失敗或未解疑慮才擴大或重跑。優先沿用現有工具，僅在必要或使用者要求時新增腳本、委派、長報告或交付包。

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
4. 在 Godot、Blender 或可用檢視器轉著看，包含側面、背面和底部；檢查比例、彎曲、缺件、孔洞、材質與接口。外觀有疑問時用素色顯示分辨幾何與貼圖；必要時另查重複面／非流形邊並修復或回報限制，不把流形當所有靜態道具的通用門檻。
5. 按問題調旋轉／尺寸／原點，修局部網格、拆材質或零件；大結構錯誤可改參考圖再生成。接入前依尺寸、觀看距離及同屏數量評估面數預算；成本偏高就先試降面，保留較高面數時簡述理由。方法見[降面方法與實測](references/decimation.md)。可先用 meshoptimizer／gltfpack 快速試減面；若保留 UV 的設定降不下去，或出現變形／貼圖碎裂，再按需要用 Blender 修整、重新展 UV 並烘焙原模型細節。保留原 GLB，修改另存，修完再看。
6. 可用就接入場景，確認實際尺度、光照、碰撞和互動；保留既有遊戲功能。按下述規則整理交付，再簡短說明結果與剩餘問題。主 agent 自行判斷處理方法，卡住或需要使用者選擇時再問。


## 本機操作

服務入口為 `http://127.0.0.1:8000/health`，腳本從這裡找到 ComfyUI 後端（通常是 `8188`）。連線被拒絕時先確認既有服務是否啟動，沿用已確認的本機啟動方式；不要將服務未啟動判為 graph 故障。Python 需要 Pillow；若 PATH 沒有 Python，可用 Codex 的 `load_workspace_dependencies` 找內建 runtime，以完整路徑執行，不必全域安裝。在專案根目錄執行：

```powershell
$skill = '.agents/skills/comfyui-image-to-3d'
python "$skill/scripts/generate.py" preflight
python "$skill/scripts/generate.py" submit --image 'reference.png' --asset-id 'prop_name' --output '.godot/art-work/prop_name/run_01'
python "$skill/scripts/generate.py" collect --output '.godot/art-work/prop_name/run_01'
```

輸出使用新資料夾；`collect` 還在 RUNNING／QUEUED 時稍後再收，完成會有 `raw.glb`。提交 timeout 時先查同一工作的 queue/history，避免重複提交。工具自動保存的工作資料直接沿用。

`collect` 會保留原始 `raw.glb`，並在 `technical_checks.attribute_issues` 列出法線／切線的零長度、長度或方向異常。收檔腳本只檢查與回報，不修改模型或重新提交生成工作；後續由 agent 用建模工具或腳本修復工作副本，再檢查結果。重複面、非流形邊等拓樸問題需另行檢查。Windows 暫存目錄被拒寫時，可將本次程序的 `TEMP`／`TMP` 改到可寫的忽略工作資料夾，再執行離線測試或 review。

要快速產生檢查圖時，執行 `python "$skill/scripts/review.py" --source <raw.glb> --output <新檢查資料夾> --godot <Godot.exe>`，會產生六視角的材質／受光素色圖，含底部；也可直接在場景裡檢查。Godot 可用 PATH 上的執行檔或 `--godot` 指定實際位置。模型／貼圖通常放 `assets/models/<名稱>/`，原圖與修改來源放 `art_source/<名稱>/`，沿用既有位置也可以。
