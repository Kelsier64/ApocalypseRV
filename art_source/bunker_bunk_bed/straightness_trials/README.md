# 床平直度實驗來源

研究與建議：[Pixal3D 床模型平直度](../../../docs/research/pixal3d-bed-straightness.md)。[正面／側面／斜角對照](comparison.png)；[完整對照數據](comparison.json)。

本輪產生 7 個有效的新 raw 模型，加上 1 個因混入鄰圖床柱而無效的輸入對照；另外保留既有床的 raw／fitted 副本供相同相機渲染。全部是研究候選，沒有接入正式場景，沒有通過接口或完整美術驗收。

## 參考圖來源

- [平視單圖](level_reference.png)：內建 imagegen 工具生成，1536×1024 RGBA。原始生成檔由 Codex generated_images 複製至此；不是外部下載素材。
- [三視圖草稿](threeview_draft.png)、[排版修正版](threeview_reference.png)：以平視單圖為設計參考，用同一內建工具生成／編輯；仍未遵守精確等寬格子，所以需要 conditioning 圖面整理。
- [完整生成 prompts](reference_prompts.json)、[排版修正 prompt](reference_fix_prompt.txt)。
- [實際共同畫布](framed_v2/framed_reference.png)：三個 724×724 黑底格，正面／左端／背面，保留共同倍率；由 ComfyUI 原生 ImageCrop、ImageCompositeMasked、ImageStitch 準備，節點紀錄在 [prompt](framed_v2/prompt.json)。
- `framed/` 是第一次 conditioning 裁切，端面格混入鄰圖柱子，**不可作有效輸入**；其 `mv_api_1024` 輸出只保存失敗案例。

新圖改用了少量毯子和較清楚的框架，也改了視角，因此單圖與舊圖比較不是純相機角度 ablation。API 與共同畫布比較同時略過二次去背和逐格裁切，也不是只有裁切一個變數。

## 模型與原始紀錄

| Case | 內容 |
|---|---|
| `original_rigid` | 既有 raw，只在預覽套用舊 OBB 的剛體旋轉；不拉伸 |
| `original_fitted` | 既有 fitted 候選，分軸縮放早已烘焙；作歷史對照 |
| `level_512`、`level_1024` | 平視單圖，API preview512／standard1024，seed 42 |
| `level_fov20_1024` | 同單圖，FOV 改為 20°，直接 ComfyUI standard1024，seed 42 |
| `mv_api_v2_1024` | 三視圖，API 現有獨立去背裁切 workflow，seed 42 |
| `mv_fixed_512`、`mv_fixed_1024` | 同圖，保留共同畫布，直接 ComfyUI multiview weights，seed 42 |
| `mv_fixed_1024_seed43` | 同共同畫布／1024，seed 43，檢查變異 |
| `mv_api_1024` | 第一次錯誤裁切輸入，**排除結論** |
| `api_preprocessing` | API 實際送入模型的三張圖：端面被放大約 14.5% |
| `single_fov_diagnostic` | 原生 MoGe 的 FOV 輸出 26.155°，沒有另外生成模型 |

新生成模型 case 含 unchanged `raw.glb`、`generation.json`。兩個原模型副本的生成紀錄沿用上層 `generation.json`／preparation JSON。直接後端 case 額外保留 `prompt.json` 和 `history.json`；API case 的確切 prompt 可從 API job_id 對應 Apps job folder查閱。有效模型的 `pose.json` 只供檢視相機方向，沒有寫回 GLB；`measurements.json` 記錄比例與開放床架區段的近似柱向診斷；`review/` 含 Godot 4.7.2 真正載入後的正面、側面、背面、斜角、俯視 PNG 及 SHA256／網格數據。無效輸入 case 不做美術結論，沒有渲染驗收紀錄。

現有 Pixal3D INT8、Pixal3D multiview INT8、Trellis2 shape／texture VAE、DINOv3 NAF 權重沿用本機版本；沒有下載新模型。生成結果保留完整 PBR 貼圖與 GLB metadata。模型權重授權沿用原試作紀錄，本輪沒有另行審核。

## 工具

- `run_trial.py`：8000 API 提交／收取，每個 case 獨立保存，不覆蓋既有來源。
- `comfy_trial.py`：8188 圖面整理、共同畫布／固定 FOV 對照及 preprocessing 診斷；保存確切 graph。使用前讓生成 queue 清空。
- `measure_trials.py`：NumPy 量測、yaw 檢視姿態、按三角形表面積取樣做床柱區段診斷；不修改模型。
- `render_trials.gd`：真實正交方向與等比構圖；所有 mesh 載入／渲染數據寫入 review。
- `summarize_trials.py`：Pillow 組合 QA 截圖及數據，不重畫模型或參考圖。

來源受上層 `.gdignore` 保護，不自動匯入遊戲資產。用法、設定、限制與重現指令見研究文件。實驗腳本使用目前 Apps workflow 模板；重跑前應核對保存的 prompt，不能假設未來模板和本輪完全相同。

本輪驗證摘要：[validation.json](validation.json)。8 個新輸出的 SHA256 相符（含排除的錯誤輸入）；7 個有效新模型加 2 個原模型對照由 Godot 載入，45 張預覽成功，最後渲染 exit code 0、無腳本錯誤。Python 語法及文件相對連結檢查通過。
