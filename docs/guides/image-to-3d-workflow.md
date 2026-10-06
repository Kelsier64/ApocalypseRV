# 單圖 → 3D → 減面 → 驗收操作指南

## 1. 安裝與確認工具

需要 [Python 3.11 以上](https://www.python.org/downloads/windows/)及 Pillow、[Node.js 24 LTS](https://nodejs.org/en/download)（Windows x64 安裝程式包含 npm）、固定版本 meshoptimizer，以及 [Godot 4.7.2](https://godotengine.org/download/archive/)。用官方安裝程式裝好後重新開啟 PowerShell；Python 安裝時選擇加入 PATH。已有相容工具就沿用；Codex 可先用 `load_workspace_dependencies` 找內建 Python／Node 執行檔，以完整路徑執行，不必重複安裝。

以下 PowerShell 命令從 repository root 執行：

```powershell
python --version
python -m pip install Pillow
node --version
npm.cmd --version
npm.cmd install --prefix .godot/mesh-decimation --no-save --ignore-scripts meshoptimizer@1.3.0
$godot = (Get-Command godot -ErrorAction SilentlyContinue).Source
if (-not $godot) { $godot = 'C:/Program Files/godot/godot.exe' } # 此機目前路徑；其他電腦換成實際執行檔
& $godot --version
$skill = '.agents/skills/comfyui-image-to-3d'
```

`.godot/mesh-decimation` 是忽略的本機依賴，不提交 node_modules 或產物。缺工具時停止並向使用者說明需要安裝什麼；不要偷偷改全域環境。

本機生成服務及權重已由使用者裝在 `C:/Users/evan4/Apps`。本流程只檢查及使用現有服務，不自動更新、下載權重、啟停或改服務。8000 的 `/health` 用於發現 8188 ComfyUI 後端；生成使用固定 TRELLIS.2 原生 graph 直接提交到後端，並非 8000 的 API preset。

## 2. 確認需求及子代理

先讀 [3D scene skill](../../.agents/skills/apocalypse-rv-3d-scenes/SKILL.md)、[建模需求 skill](../../.agents/skills/apocalypse-rv-image-to-3d-request/SKILL.md) 及 [生成 skill](../../.agents/skills/comfyui-image-to-3d/SKILL.md)。需求沿用 `docs/modeling/requests/<name>/<name>.md`；用 [短模板](../modeling/TEMPLATE.md) 記錄尺寸（公尺）、up／front、原點、必要接口、可動部件、原風格／材質與交付位置。區分實測值、設計值及未確認值。

授權此流程後，主代理逐件交接：

1. [image_to_3d_reference](../../.codex/agents/image-to-3d-reference.toml) 只負責選用或製作參考圖，回傳圖檔、風格、尺寸、軸向、接口與未知事項。
2. [image_to_3d_model](../../.codex/agents/image-to-3d-model.toml) 負責單次生成、原始驗收、減面及減面後驗收。
3. 主代理收取證據；只有任務包含場景整合且候選通過必要驗收時，才進行整合。

一次一件，上一件完整驗收通過後才開始下一件。發生問題就停止並詢問使用者，不自動換圖、改 seed／graph、強制減面或繼續批次。一般場景建模仍由主代理處理。

自訂角色放在 `.codex/agents/*.toml`，包含 `name`、`description` 與 `developer_instructions`；不需另建角色 registry，見 [OpenAI 子代理文件](https://learn.chatgpt.com/docs/agent-configuration/subagents)。本次寫入設定不代表目前工作階段已載入新角色。若角色選單沒有 `image_to_3d_model`，重啟或開新工作階段後確認，再執行流程。

## 3. 參考圖先過關

優先沿用合適的原始參考圖。只有缺圖、不適用或使用者明確要求重畫時才產生新圖；保留原風格、材質配色、比例與必要幾何，不為了方便生成而改成卡通、方塊或添加零件。

輸入是一張含可見內容及透明 alpha 的靜態 PNG；每張恰好一件物體、一個視角。採正交或長焦的輕微三分之四視角，高大剛體接近水平鏡頭。完整輪廓、腳與接點應可辨識，避免重疊、裁切、強俯視和廣角。無地板、投影、背景場景、文字、符號、拼圖或三視圖。需要獨立可動零件時，依需求逐件隔離並逐件跑流程。

先實際看圖再交接。角度、缺件、風格、透明度等有問題就回報圖檔與缺陷，等待使用者決定；不要自行反覆修圖。圖像不證明精確尺寸、pivot、拓撲或 rigging 已正確。

## 4. 單次生成與收檔

每個工作使用全新輸出資料夾，保留原圖及原始 GLB。以下路徑只是示例，執行時換成該工作尚不存在的路徑：

```powershell
$reference = 'docs/modeling/requests/example/example-reference.png'
$job = '.godot/image-to-3d/example-job-001'
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
python "$skill/scripts/review.py" --source "$job/raw.glb" --output "$job/raw-review" --godot $godot
```

檢視工具建立並釋放獨立臨時 Godot project；此例的圖片位於忽略的 `.godot` 工作區。工具對每個 GLB 輸出 front、side、back、oblique、top 各一張材質圖與 clay 圖，共十張。逐張看實際圖像，對照需求檢查直柱／橫桿、缺件、腳底支撐、比例、朝向、原風格、材質及接口。缺少必要幾何、既有歪斜、錯誤比例或風格改變時，立即停止；減面不會拉直模型。

預設保持來源 up，不旋轉。如必須正位，先核實軸向，再用 `--pose '<rigid-pose.json>'` 明確提供剛體姿勢；原始與候選必須採同一姿勢與同一來源基準相機。不得用 bbox 分軸拉伸掩蓋缺陷，也不能分別重新取景讓候選看起來相同。

`review.json` 初始狀態為 UNKNOWN。代理實際看過圖、檢查必要數值／接口後才填入 PASS／FAIL／UNKNOWN 與證據。遮擋或未量測就是 UNKNOWN；床研究中的 2° 是特定警示，並非所有物件的合格容差。原始幾何／風格／必要源接口通過，才可減面；此處 raw PASS 不要求最終面數預算，20k 預算於降面後的 final review 才檢查，不能以 raw 約 50k 在降面前判失敗。

## 6. 有界減面與比較

預設目標 20,000 三角面：

```powershell
$reduced = "$job/reduced-20k"
node "$skill/scripts/simplify.mjs" "$job/raw.glb" $reduced 20000 '.godot/mesh-decimation/node_modules/meshoptimizer/meshopt_simplifier.js'
if ($LASTEXITCODE -ne 0) { throw "減面停止：檢查錯誤與 simplification.json，再回報使用者" }
python "$skill/scripts/generate.py" inspect --glb "$reduced/raw.glb"
python "$skill/scripts/review.py" --source "$job/raw.glb" --candidate "$reduced/raw.glb" --output "$job/reduced-review" --godot $godot
```

減面保留原始頂點屬性組（含材質相關 normal／UV）及內嵌 PNG，使用 LockBorder、normal 權重 1、UV 權重 10，組合誤差上限 0.002。來源已不超過目標時保留原檔，作為不需減面的結果。

誤差上限阻止達標時，工具保存 `TARGET_NOT_REACHED` 證據並 exit 2；回報來源／目標／實際三角面、誤差及輸出路徑，停止詢問使用者。**不自動使用 `--force-target`。** 只有使用者明確針對本工作放棄誤差上限時才追加此旗標；Infinity 上限仍不保證拓撲能降到目標，也不代表外觀通過。

逐視角比较原始與減面後圖像，檢查輪廓、柱向、孔洞、薄件、支撐、材質／UV 和必要接口。數值檢查及原始 PASS 不能代替候選的目視驗收。候選不合格或必要項目 UNKNOWN 就停止，保留兩者及失敗證據。

## 7. 交付與問題回報

交付原圖、原始／減面 GLB、生成摘要與 prompt ID、三角面數、渲染圖、review.json，以及必要尺寸／軸向／接口、未測項目與限制。可交付研究候選，但不可把 UNKNOWN 宣告為可整合或把生成成功宣告為美術 PASS。正式資產位置按原需求；本機 `.godot` 產物不提交。

問題回報附物件名稱、失敗階段、路徑／圖像證據、目前狀態與待使用者決定事項。不要越過失敗繼續下一件，也不要自行重畫、重生、修形或降低驗收標準。本指南及子代理設定的文件檢查不等於實際模型或遊戲驗收。