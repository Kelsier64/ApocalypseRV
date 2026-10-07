# 單圖 → 3D → 減面 → 驗收操作指南

目前日常入口是 [image-to-3D skill](../../.agents/skills/comfyui-image-to-3d/SKILL.md)：主 agent 按需要生成、檢查、修整並直接接入。以下提供工具操作範例；子代理、request、固定後期降面和完整驗收包均為可選流程。

## 1. 安裝與確認工具

需要 [Python 3.11 以上](https://www.python.org/downloads/windows/)及 Pillow、[Node.js 24 LTS](https://nodejs.org/en/download)（Windows x64 安裝程式包含 npm）、固定版本 meshoptimizer，以及 [Godot 4.7.2](https://godotengine.org/download/archive/)。用官方安裝程式裝好後重新開啟 PowerShell；Python 安裝時選擇加入 PATH。已有相容工具就沿用；Codex 可先用 `load_workspace_dependencies` 找內建 Python／Node 執行檔，以完整路徑執行，不必重複安裝。缺少 Pillow 時，裝到本 run 的 `deps/python` 並在執行時加入 `PYTHONPATH`，不要全域安裝。

以下 PowerShell 命令從 repository root 執行：

```powershell
$work = '.godot/art-work/example-asset/run-001'
python --version
node --version
npm.cmd --version
npm.cmd install --prefix "$work/deps/meshoptimizer" --no-save --ignore-scripts meshoptimizer@1.3.0
# 只有缺少 Pillow 時執行：
python -m pip install --target "$work/deps/python" Pillow
$env:PYTHONPATH = "$work/deps/python"
$godot = (Get-Command godot -ErrorAction SilentlyContinue).Source
if (-not $godot) { $godot = 'C:/Program Files/godot/godot.exe' } # 範例 fallback；先確認此路徑存在，否則換成實際執行檔
& $godot --version
$skill = '.agents/skills/comfyui-image-to-3d'
```

每次工作建立新的 `.godot/art-work/<asset>/<run>/`；把依賴放在該 run 的 `deps/`，不提交 node_modules 或其他產物。缺工具時停止並向使用者說明需要安裝什麼；不要偷偷改全域環境。

生成 job 與完整 history、各輪候選、批次渲染圖、失敗輸出、臨時 logs 和依賴預設都留在這個忽略的本機工作目錄。技術檢查與目視驗收仍完整執行，檢查證據留在本機供除錯。提交時選入必要原始來源、editable／重建腳本、精簡參數與來源摘要、正式模型／貼圖，以及少量最終代表圖和報告；不要求整套驗收檔都進 Git，也不預設清理原始或使用者檔案。

本機生成服務及權重已由使用者裝在 `C:/Users/evan4/Apps`。本流程只檢查及使用現有服務，不自動更新、下載權重、啟停或改服務。8000 的 `/health` 用於發現 8188 ComfyUI 後端；生成使用固定 TRELLIS.2 原生 graph 直接提交到後端，並非 8000 的 API preset。

## 2. 確認需求

先讀 [3D scene skill](../../.agents/skills/apocalypse-rv-3d-scenes/SKILL.md) 及 [生成 skill](../../.agents/skills/comfyui-image-to-3d/SKILL.md)。依任務確認尺寸（公尺）、up／front、原點、必要接口、可動部件、原風格／材質與交付位置。需求清楚就開始；需要交接時可用 [短模板](../modeling/TEMPLATE.md) 記錄，並區分實測值、設計值及未確認值。

主 agent 直接處理參考圖、生成、檢查、修整與整合。需要交接時才準備 request 或委派適合的工作；不依賴已移除的自訂角色設定。服務忙碌或提交結果不明時停止新提交，保留既有工作查證；模型外觀問題可按 skill 修整，卡住或需要使用者選擇時再問。

## 3. 參考圖先過關

優先沿用合適的原始參考圖。只有缺圖、不適用或使用者明確要求重畫時才產生新圖；保留原風格、材質配色、比例與必要幾何，不為了方便生成而改成卡通、方塊或添加零件。

輸入是一張含可見內容及透明 alpha 的靜態 PNG；每張恰好一件物體、一個視角。採正交或長焦的輕微三分之四視角，高大剛體接近水平鏡頭。完整輪廓、腳與接點應可辨識，避免重疊、裁切、強俯視和廣角。無地板、投影、背景場景、文字、符號、拼圖或三視圖。需要獨立可動零件時，依需求逐件隔離並逐件跑流程。

先實際看圖再生成。角度、缺件、風格、透明度等有問題時，按用途修圖或改參考圖；圖像不證明精確尺寸、pivot、拓撲或 rigging 已正確。

## 4. 單次生成與收檔

每個工作使用全新輸出資料夾，保留原圖及原始 GLB。以下路徑只是示例，執行時換成該工作尚不存在的路徑：

```powershell
$reference = 'docs/modeling/requests/example/example-reference.png'
$work = '.godot/art-work/example-asset/run-001'
$job = "$work/generation"
python "$skill/scripts/generate.py" preflight
python "$skill/scripts/generate.py" submit --image $reference --asset-id example --output $job
python "$skill/scripts/generate.py" status --output $job
python "$skill/scripts/generate.py" collect --output $job
python "$skill/scripts/generate.py" inspect --glb "$job/raw.glb"
```

`preflight` 檢查服務、節點、權重與空閒佇列；失敗或忙碌就停止。只有明確使用 ComfyUI 而沒有 8000 wrapper 時，對 `preflight`／`submit` 加 `--backend http://127.0.0.1:8188`。預設 graph 是 TRELLIS.2、1024、seed 42、約 50k 面；不自行改節點、換 preset 或掃參數。

`status` 每次只查一次，未完成時先做其他工作再查。`collect` 只收既有工作，保留 prompt、history、conditioning、原圖、raw GLB 與摘要；同一工作收檔失敗可重試 collect。技術成功狀態 `ART_REVIEW_REQUIRED` 仍需美術驗收。

**POST timeout、無 prompt ID 或提交結果不明時，不可再次 submit。** 保存 intent 及錯誤，查既有 queue／history；無法確認同一工作就停止並詢問使用者。不得全域 interrupt 共用 ComfyUI，也不以重送測試服務。

## 5. 先驗原始 GLB，再減面

先在獨立 Godot 檢視專案渲染 raw，避免遊戲 autoload 影響結果：

```powershell
python "$skill/scripts/review.py" --source "$job/raw.glb" --output "$work/reviews/raw" --godot $godot
```

檢視工具建立並釋放獨立臨時 Godot project；此例的圖片位於忽略的 `.godot` 工作區。工具對每個 GLB 輸出 front、side、back、oblique、top、underside 各一張材質圖與受光灰色 clay 圖，共十二張。逐張看實際圖像，對照需求檢查直柱／橫桿、缺件、腳底支撐、比例、朝向、原風格、材質及接口。缺少必要幾何、歪斜、錯誤比例或風格改變時，先修整；減面不會拉直模型。

預設保持來源 up，不旋轉。如必須正位，先核實軸向，再用 `--pose '<rigid-pose.json>'` 明確提供剛體姿勢；原始與候選必須採同一姿勢與同一來源基準相機。不得用 bbox 分軸拉伸掩蓋缺陷，也不能分別重新取景讓候選看起來相同。

`review.json` 初始狀態為 UNKNOWN。代理實際看過圖、檢查必要數值／接口後才填入 PASS／FAIL／UNKNOWN 與證據。遮擋或未量測就是 UNKNOWN；床研究中的 2° 是特定警示，並非所有物件的合格容差。原始幾何／風格／必要源接口通過，才可減面；此處 raw PASS 不要求最終面數預算，20k 預算於降面後的 final review 才檢查，不能以 raw 約 50k 在降面前判失敗。

## 6. 有界減面與比較

接入前依尺寸、觀看距離及同屏數量評估面數預算；成本偏高先試降面，保留較高面數時說明理由。以下以 20,000 三角面示範，不要求每個資產都固定降到 20k：

```powershell
$reduced = "$work/candidates/reduced-20k"
$meshopt = "$work/deps/meshoptimizer/node_modules/meshoptimizer/meshopt_simplifier.js"
node "$skill/scripts/simplify.mjs" "$job/raw.glb" $reduced 20000 $meshopt
if ($LASTEXITCODE -ne 0) { throw "減面停止：檢查錯誤與 simplification.json，再回報使用者" }
python "$skill/scripts/generate.py" inspect --glb "$reduced/raw.glb"
python "$skill/scripts/review.py" --source "$job/raw.glb" --candidate "$reduced/raw.glb" --output "$work/reviews/reduced-20k" --godot $godot
```

減面保留原始頂點屬性組（含材質相關 normal／UV）及內嵌 PNG，使用 LockBorder、normal 權重 1、UV 權重 10，組合誤差上限 0.002。來源已不超過目標時保留原檔，作為不需減面的結果。

誤差上限阻止達標時，工具保存 `TARGET_NOT_REACHED` 證據並 exit 2；查來源／目標／實際三角面、誤差及輸出路徑，可依 [降面方法](../../.agents/skills/comfyui-image-to-3d/references/decimation.md) 改用其他工具修整副本。**不自動使用 `--force-target`。** 只有使用者明確針對本工作放棄誤差上限時才追加此旗標；Infinity 上限仍不保證拓撲能降到目標，也不代表外觀通過。

逐視角比较原始與減面後圖像，檢查輪廓、柱向、孔洞、薄件、支撐、材質／UV 和必要接口。數值檢查及原始 PASS 不能代替候選的目視驗收。候選不合格或必要項目 UNKNOWN 就停止，保留兩者及失敗證據。

上述 `--candidate` 只驗證 `simplify.mjs` 的 tuple-preserving 輸出。gltfpack `-sv` 等其他方法會更新屬性，應另外用相同來源基準取景比較，依 [降面方法](../../.agents/skills/comfyui-image-to-3d/references/decimation.md) 核對材質／圖片及幾何，不能套用原頂點 mapping 檢查。

## 7. 交付與問題回報

交付需要的原始來源、editable／重建資料、精簡參數／來源摘要、正式資產和少量最終代表圖／報告。完整生成 history、各輪候選、批次渲染圖和檢查細節留在 `.godot/art-work/<asset>/<run>/` 供本機除錯，不要求整套驗收檔進 Git。可交付研究候選，但不可把 UNKNOWN 宣告為可整合或把生成成功宣告為美術 PASS。正式資產位置按原需求；工作目錄產物不提交。

提交前明確檢查 staged 清單、檔案數與總大小，再逐項挑選必要檔案：

```powershell
$staged = @(git diff --cached --name-only)
$totalBytes = 0L
foreach ($path in $staged) {
    $blobSize = git cat-file -s ":$path" 2>$null
    if ($LASTEXITCODE -eq 0) { $totalBytes += [long]$blobSize }
}
"Staged files: $($staged.Count); bytes: $totalBytes"
git diff --cached --stat
```

`.gitignore` 的忽略規則不會移出已追蹤檔案；不要全域忽略 `art_source/` 或 `*.glb`／`*.png`／`*.gd`，也不要為精簡提交而預設刪除本機原始、使用者或除錯產物。

問題回報附物件名稱、失敗階段、路徑／圖像證據、目前狀態與剩餘問題。保留原圖／raw GLB，修改另存，修完重新檢查；必要 UNKNOWN 不當作合格。本指南的文件檢查不等於實際模型或遊戲驗收。
