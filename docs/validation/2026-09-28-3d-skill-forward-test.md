# 3D 場景 skill 獨立實際演練

日期：2026-09-28。此紀錄先完成實際規劃與建模交接，再評估 skill；不是只做文字審查。測試對象：[apocalypse-rv-3d-scenes](../../.agents/skills/apocalypse-rv-3d-scenes/SKILL.md)，搭配 [prompt 範本](../modeling/TEMPLATE.md)、[建模索引](../modeling/README.md)、[POI 規範](../guides/poi-authoring.md)。基準 HEAD 為 `e877cc799d5079d9208252ac671d3c5efd6efe42`；skill 與相關新文件以當時工作樹內容為準。

## 演練要求與實際交付

需求：規劃一座小型維修棚，使用簡單牆／地板，放一台現有燃油發電機，預留尚未製作的機械維修設備，準備建模 AI 交接。本次限定只交付規劃與 prompt，不修改遊戲、不啟動其他 AI、不寫入正式建模佇列。

以下演練檔案已實際寫出，全部位於忽略目錄 `.godot/skill-eval-3d/`；它們是臨時文件，未加入正式資產或正式建模索引。清理 `.godot/` 後檔案可能消失，本報告保留精簡結果而不依赖臨時連結。

| 實際檔案 | 內容與完成狀態 |
|---|---|
| `README.md` | 演練索引、狀態與非正式產物聲明 |
| `planning.md` | 分類、棚體尺寸／布局、材料重用、節點責任、發電機功能限制、後續驗收；規劃完成 |
| `repair_press.md` | 逐欄填妥範本的獨立壓床 prompt；保存等待後續安排，沒有啟動建模 |
| `checks.txt` | 17 個來源路徑存在、4 個 planned 路徑尚未建立、演練文件連結与人工來源核對紀錄 |

未建立任何 mesh、灰盒、GLB、碰撞、遊戲 marker 或腳本。只有本報告位於正式 `docs/validation/`；未修改正式 `docs/modeling/`、場景或 skill。預先存在的其他工作樹變更保持原狀。

## 實際決策與採用假設

| 部分 | 分類／處理 | 理由 |
|---|---|---|
| 牆、地板、屋頂、門楣 | 簡單元件，未來直接用少量規則 mesh 與既有材質完成 | 不需要為統一格式匯出 GLB；本次只有規劃 |
| 發電機 | 完整重用既有 `equipment/generator.tscn` | 保留 Mesh／Collision／Details 與脚本；沒有把現成資產降級成灰盒或重新排程建模 |
| 新機械維修設備 | 採用小型 H 型壓床；複雜資產、單獨 prompt | 機架、液壓缸與壓頭輪廓、UV／材質需要獨立製作；未來灰盒只表達占用量與開口 |
| 整座棚 | 混合場景 | 棚體與壓床分開處理，不把整棟建築標成等待建模 |

壓床是本次合理設計假設，不是需求原文已指定的型號。棚採 WALK_IN，+Y 向上、+Z 正面；地板 6×5 m，門洞淨寬 3.2 m／高 2.8 m，屋頂底面 3 m。建築 AABB min=(-3.2,-0.2,-2.7)、max=(3.2,3.2,2.7)；site AABB min=(-4.5,-0.2,-3.5)、max=(4.5,3.2,5.5)。這些均為新設計值，沒有量測或遊戲驗收聲明；場址只規劃步行進出，不宣稱 RV 停放或迴轉空間已足夠。

壓床設計 1.6×2.2×1.0 m，底面中心原點，+Z 操作面，棚內根位置 (1.5,0,-1.5)。外觀分 Frame／Table／CylinderHousing／Ram，Ram 保留独立 pivot、目前不要求動畫；骨架與事件欄位明列不適用。遊戲側 Collision 與 Operator marker 保留在 wrapper，不能帶入 GLB。推薦预算為 6,000 triangles、最多 3 材質與一組 1024px atlas；是建議目標，不是量測值。模型檔、來源檔與 wrapper 路徑全部標記 planned。

發電機棚內位置 (-1.8,0.3,-1.25) 由中心式碰撞底面對齊地板；保留為可搬回 RV 的未安裝設備。壓床暫不運作，沒有假造棚內燃油／供電契約。若要讓棚內固定發電，需後續另行設計功能，不能靠外觀接線取得既有 RV 行為。

## 從來源核對的資料

| 來源 | 本次讀取並核對的事實 | 對規劃的影響 |
|---|---|---|
| [generator.tscn](../../equipment/generator.tscn)、[definition](../../equipment/generator_definition.tres) | BoxMesh／BoxShape3D 為 0.8×0.6×1.2 m，mass／weight=50；節點為 Mesh、Collision、Details | 以配置碰撞盒規劃落地高度；不把它當完整渲染 AABB |
| [generator visuals](../../rv/visuals/generator.tscn) | FanHub X=-0.399、圓柱高 0.028 且 Z 旋轉 90°，推算網格 X min 約 -0.413；Vent Z max=0.606；Label 中心 Z=0.607 | 視覺略超出碰撞盒，Label 外框未量測；不宣稱已量完整模型 bounds |
| [equipment.gd](../../equipment/equipment.gd) | `can_operate()` 要求有效 RV 連線與設備可用狀態 | 棚內放置不等於可供電；動態實例由 WorldEntities 管理 |
| [generator.gd](../../equipment/generator.gd)、[vehicle_energy.gd](../../rv/vehicle_energy.gd) | 引擎運轉才排程發電；最高 +1.8 power/s、0.6 fuel/s、保留燃油 5、recharge_below=0.8；電池為實際儲能處 | 說明遊戲單位，沒有把 power 當 kW 或 fuel 當 L；不承諾棚內發電 |
| [concrete.tres](../../world/poi_kit/materials/concrete.tres) | triplanar=true、uv1_scale=(0.5,0.5,0.5)、roughness=0.9，引用既有 concrete_albedo.png | 延用材質及原尺度，未来檢查紋理密度；不誤稱實測 texel/m |
| [floor.tres](../../world/poi_kit/materials/floor.tres)、[steel.tres](../../world/poi_kit/materials/steel.tres) | 現有純色材質；steel metallic=0.65、roughness=0.9 | 可直接重用，不宣稱已有複雜貼圖 |
| [POI 規範](../guides/poi-authoring.md) | 新建築 +Z 正面，AccessPoints local -Z 朝外；Visuals 不持有碰撞／狀態；註冊不等於加入生成 | 前入口 marker Y 轉 180°，保持遊戲節點獨立；生成與保存另列後續驗收 |

## 檢查結果與未完成項目

本次演練執行文件來源存在檢查、planned 路徑未存在檢查、演練與本報告相對 Markdown 連結檢查；人工核對來源數值、AABB 算術、發電機與壓床之間 2.1 m 幾何間距。來源核對是靜態讀取，無執行遊戲行為。

沒有執行 Godot、`scripts/test.ps1`、遊戲視覺或物理測試；本次演練限定文件產出，未修改程式。尚未完成灰盒、正式玩家／大型物品通行、碰撞／導航、壓床玩法、供電接口、POI 定義、正式生成、串流／保存、模型製作與模型驗收。這些不因 prompt 齊全而算完成。

另列主代理提供的本輪格式檢查證據：官方 `skill-creator/scripts/quick_validate.py` 回傳 `Skill is valid!`。執行環境為 uv Python 3.13.15，於忽略目錄 `.godot/skill-validation-deps` 安裝 PyYAML 6.0.3，透過暫態 PYTHONPATH 執行。這是主代理執行的格式驗證，獨立於本代理的行為演練；前次缺 PyYAML 的限制不代表本輪仍未通過。

## 完成交付後的 skill 使用觀察

1. **分工確實可用。** 按流程研究後，得到棚體自行製作、現有發電機重用、新壓床獨立交接三種決策；沒有因「機械」字眼把既有發電機重做，也沒有為了滿足交接要求建立大量裝飾灰盒。
2. **接口規則能暴露真實缺口。** 讀取目標腳本發現發電機依賴 RV，引導規劃保留未安裝狀態；節點保留規則也讓 prompt 沒有擅自把既有 Mesh／Details 改成 Visuals。
3. **範本足以建立自包含交接。** 尺寸、方向、設計值來源、零件 pivot、材料、预算、planned 路徑、無骨架／動畫、驗收與未知項都能直接寫進 prompt。不需圖片也能交付，未虛構截圖。
4. **規劃限定情境的狀態需要說清楚。** skill 說保存後設 queued，但正式索引把 queued 解釋為「graybox and prompt are ready」。本次不允許灰盒，所以演練索引採「演練 queued，未達正式 production-ready」，沒有污染正式佇列。建議日後明文區分 planning／draft 與 queued，或說明使用者限定規劃時的狀態例外。
5. **可補一個小型 mixed-scene 範例。** 此次 template 能完成，但建立較多合理的新設計值；一個「現成設備重用＋簡單棚體＋單件複雜設備」範例可更快教會使用者分別記錄既有接口和新規格。這是可用性建議，不是本輪必須改 skill 的阻塞。

結果：規劃與 prompt 演練完成，發現並記錄真實功能邊界及狀態語意差異；未聲稱新場景、灰盒、模型或玩法已完成。

## 修正後窄範圍重試（2026-09-28）

前節與原 `.godot/skill-eval-3d/` 四個檔案保留為**修正前證據**。本次重新讀取更新後 skill、範本及正式索引，只重試相同需求的「狀態與交付範圍」。沒有重做資產研究、尺寸布局或執行遊戲。

新版 skill 明確限定 planning-only／inventory-only 不建立遊戲場景、不為滿足工作流程而登錄正式建模任務；純設計、灰盒不存在或重要接口未確認時為 `draft`。只有灰盒存在、必要尺寸與接口已核對且 prompt 可用於建模時才是 `queued`。範本的起始狀態及正式索引均有相同條件。

實際交付位於 `.godot/skill-eval-3d/retest/`：`README.md` 為修訂演練索引，`repair_press.md` 為完整 v0.2 prompt，`checks.txt` 記錄原檔 SHA256、狀態檢查、planned 路徑不存在及相對連結檢查。壓床數值、材質與接口提案沿用第一次規劃，只修改版本、任務範圍、狀態及後續升級條件。

| 重試判斷 | 結果 | 實際觀察 |
|---|---|---|
| 純規劃狀態 | 通過 | 索引與 prompt 都是 `draft`；無需創造「演練 queued」例外 |
| Readiness 門檻 | 通過 | 無灰盒、玩法／供電接口未確認，因此不升級；`queued` 只描述後續條件 |
| 交付範圍 | 通過 | 只寫重試文件與本報告；沒有為完成 skill 而新建場景、替換模型、登錄正式佇列或啟動其他 AI |
| planned 與現有區分 | 通過 | 棚場景、壓床 wrapper、blend 來源、GLB 四個主要預定檔案均核對為不存在，仍明確標 planned |
| 原始證據保留 | 通過 | 原索引、規劃、prompt、checks 四檔 SHA256 在重試前後相同；舊 queued 問題仍保留 |

本次窄範圍重試沒有未通過項目。新版規則解決本演練遇到的狀態矛盾，足以在無灰盒的限制下給出一致交付。這不代表所有狀態轉換都已驗證：建立灰盒後的 `draft → queued`、模型到貨後 `delivered → integrated`、實際碰撞／互動／導航／視覺驗收、角色骨架／動畫交接，以及其他 inventory-only 案例均未在本次重試。
