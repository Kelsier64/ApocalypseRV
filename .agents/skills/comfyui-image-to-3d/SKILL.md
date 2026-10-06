---
name: comfyui-image-to-3d
description: Generate, post-decimate and inspect textured 3D candidates from a single reference image through local ComfyUI. Use for modeling requests and sequential prop batches that stop on defects; not for scene logic, skeletal animation or simple native mesh construction.
---

# 單圖 3D 工作流

固定 **單圖、TRELLIS.2、1024、seed 42、約 50k 三角面 → raw 檢查 → 後期降面 → 對照檢查**。預設降面目標 20k、相對混合誤差上限 0.002；需求指定其他預算時沿用需求。不臨時研究設定、掃 seed、重畫原圖或自動修形。此流程會攔下歪斜候選，不能保證生成器每次產生筆直模型。

## 兩個角色

ApocalypseRV 使用專案內的 `image_to_3d_reference` 與 `image_to_3d_model`：前者交付參考圖，後者負責生成、raw 驗收、降面及最終檢查。主 agent 準備既有 request、協調順序及更新進度；3D subagent 不再把降面／檢查推回主 agent。角色尚未載入時在此 checkout 開新 session；只有工具確實提供該 role 才呼叫它。其他專案可由同一 agent 按本流程完成。

安裝、PowerShell 命令與委派範例見 [專案操作指南](../../../docs/guides/image-to-3d-workflow.md)。腳本協議見 [operations](references/operations.md)。修改專案前同步並保留既有編輯；不把實驗模型、整批舊成果或依賴放進只整理工作流的 commit。

## 需求與參考圖

- 先讀 AGENTS、3D scenes／modeling request skills 及該物件目前的 request；使用同一 request，不另建全域進度清單。確認尺寸、up／front、原點、必要介面及交付位置；未定的必要條件保留 UNKNOWN。
- 沿用合適的原風格單圖。缺圖、接點不清楚或使用者要求時才交給參考圖角色；使用 imagegen，編輯前看原圖，保留材質、配色、形狀及 alpha，另存新檔。不得為讓生成容易而方塊化、卡通化、刪件或變更美術風格。
- 一張透明 PNG、一件完整物體、一個弱透視三分之四視角，床腳／接點分離可见，直立物近水平相機，無文字、地板、陰影、拼圖或三視圖。提示中的「正交／水平」不是相機校準證據。詳見 [參考圖準則](references/reference-image.md)。

## 固定生成與 raw 檢查

1. `generate.py preflight`：由 8000 `/health` 發現後端，確認節點、既有權重與佇列空閒。只有 ComfyUI 時才明確指定 `--backend http://127.0.0.1:8188`。本工具向後端提交 [原生固定 graph](assets/trellis-single-1024-50k.json)，沒有假裝 8000 提供 TRELLIS preset。
2. `submit`：原 PNG＋全新資料夾，保存 intent 後只 POST 一次。`status`／`collect` 收同一工作，保留原圖、graph、conditioning、history、raw GLB 與摘要。timeout／無 prompt ID 停止並精確 reconcile，不重新提交，不 interrupt 共用服务。
3. `review.py --source <raw.glb>`：先保留來源 up 的五個 textured＋clay 視角；有確認的剛體正位可另產一組，不能分軸縮放或用看似筆直的構圖掩蓋局部彎斜。看完 raw 全部視角再決定是否降面；raw PASS 檢查幾何／風格／必要接口，最終面數預算延後到降面後，不以 raw 約 50k 判定 20k 預算失敗。
4. 按 request 檢查各直柱／橫桿、缺件、融合、腳底、比例、朝向、原風格與必要接口。使用已建立的資產檢查 profile；沒有時用實際視圖／需求數值，不能臨時創造通用修形器。遮擋為 UNKNOWN。床研究的 2°只屬警示，不能冒充正式容差。

## 後期降面與對照

Raw 通過才執行 [simplify.mjs](scripts/simplify.mjs)，降面不會修直壞模型。固定 meshoptimizer **1.3.0**、`simplifyWithAttributes`、`LockBorder`、normal weights 1/1/1、UV weights 10/10；只合併完整相同頂點 tuple，保留留下頂點的 POSITION／NORMAL／UV／TANGENT bytes、原圖片及材質，不重烘焙。詳見 [降面方法與限制](references/decimation.md)。

- 結果保存到新資料夾。若原面數已在預算內，原 GLB 不變；若誤差上限阻止達標，記錄實際面數並停止回報，不自行解除上限。
- 只有使用者對本工作明確授權「不管誤差強制達標」時使用 `--force-target`；仍可能受 topology 限制。不改其他 flags，不刪尾端三角面假裝降面，不自動多次嘗試。
- `review.py --source <raw> --candidate <reduced>` 驗證 SHA／實際面數、mapping／所有屬性／材質／圖片保全，渲染同姿態、同來源 framing 的正面、側面、背面、斜視、頂視 textured＋clay。逐張看 raw 與 reduced，核對直度、缺件、洞、接縫、輪廓與陰影劣化。renderer 的 front 為顯示座標 +Z，不能代替遊戲 front 確認。
- 降面器只支援固定 pipeline 的一個未變換 mesh／primitive、float32 POSITION／NORMAL／TEXCOORD_0／TANGENT、嵌入貼圖 GLB；動畫、skin、多 mesh、變換或其他属性一律停止。review 工具生成獨立臨時 Godot project，不載入遊戲 autoload。

## 驗收與批次停止

**`ART_REVIEW_REQUIRED`、檔案保全 PASS、渲染 PASS 都不是美術 PASS。** 3D subagent 負責填寫 raw／final 的 `review.json`，state 為 PASS／FAIL／UNKNOWN，記錄 GLB SHA、實際看過的圖片路徑、逐項量測／方法／限制、缺陷及未測必要介面。工具初始寫 UNKNOWN，禁止因 exit 0 就改 PASS。

逐件生成、raw 檢查、降面、最終檢查。第一個後端／格式錯誤、歪斜、缺件、風格變化、預算未達或必要 UNKNOWN 都立即停止後續工作並告知使用者：物件、階段、證據、下一步需要的決定。不要自行重試失敗模型、換圖／參數或掩蓋缺陷。只有 user 明確授權研究才另建有界對照。

交付 request／image、raw／reduced SHA、預算及實際面數、profile／誤差、review／五視角路徑與結果。任務包含整合且候選通過時才由主 agent 替換正式場景。預設生成物僅是候選；未通過不報整批完成。

## 依據

[固定 profile 來源](references/profile.md)保留床樣本與測試範圍：50k 比直接 10k 較不歪，強降 20k 會增加局部柱向及外觀誤差。這些實驗不代表床已驗收，也不代表其他物件有相同結果。
