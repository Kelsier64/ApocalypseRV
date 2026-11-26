# 生態與森林重構

[計畫總覽](README.md) · [世界系統](../systems/world.md) · [環境系統](../systems/environment.md) · [遊戲設計](../../GDD.md#section-9)

把地形的「形狀」和「生態」拆開，讓同一種地形能長出不同的森林，也能有不是草地的樹林，例如沙地上幾乎全是枯樹。施工在 worktree `claude/ecology-overhaul` 進行，分階段審查後以 PR 合回 main。本計畫接手[地形與道路改造](terrain-overhaul.md)階段 2 的植被部分。

## 問題

- 一個 landform 編號同時決定高度、地面顏色、濕度、樹種、樹密度、地被、粉塵、霧和風的遮蔽，表格都在 [TerrainLandforms](../../world/terrain/terrain_landforms.gd)。編號只沿公路方向（`s`）變化，橫向沒有差別。
- 六種地形照固定順序輪替（`appearance_at`），種子只決定起點。
- 每種地形的樹種組合寫死在 `tree_choice`，真正茂密的只有 basin。種子不影響任何森林配方。
- [ForestMeshes](../../world/terrain/forest_meshes.gd) 的 8 個編號實際只有 3 種樹形：0–3 是同一種針葉樹換葉色，4–5 是拔掉葉子的同一棵樹，6–7 是兩棵相近的闊葉樹。每個編號只有一個網格，沒有逐棵色差。
- [ForestScenery](../../world/terrain/forest_scenery.gd) 用抖動網格擺樹，再用一層叢集噪聲疏密化，沒有林緣、空地、樹下灌木與年齡層。
- 地表 shader 只有一張土壤貼圖加頂點色（[terrain_v14.gdshader](../../world/terrain/terrain_v14.gdshader)），沒有沙、灰燼這類材質。

## 已定案

- 生態是獨立於地形形狀的一層，生態區定義是資料資源，不寫死在程式表裡。
- 地形順序改成依種子洗牌，不連續重複。
- 沙地枯木林起風時揚沙。粉塵改由土質與植被覆蓋決定，不再是「森林裡幾乎沒有沙塵」。
- 起霧時，沙地枯木林算 Slender Speaker 能出沒的森林。枯樹遮不住巨人，所以這是高風險區。每個生態區用資料旗標決定算不算。
- 施工方式是 worktree 加 PR。

## 架構

由下往上，每一層只讀下一層。

| 層 | 責任 | 取代 |
|---|---|---|
| Landform | 只管高度形狀，提供生態偏好與上下限（濕地必濕、峽谷偏沙礫） | `TerrainLandforms` 裡顏色、密度、濕度、粉塵的表 |
| 環境場 | 世界座標上的連續場：濕度、土質（壤土、沙、礫、泥炭、灰燼）、擾動（火燒、枯萎、伐木） | `WorldField.surface` 的 `moisture` 與 `material_weights` |
| 生態區 | `.tres` 資源：地表材質、地被層、樹種池與健康比例、林分型態、密度範圍、粉塵、霧、環境音標籤、Slender 旗標 | `TREE_DENSITY`、`GROUND_DENSITY`、`DUST_COLORS`、`tree_choice` 與 `ScatterCatalog` 的六格地形權重 |
| 林分 | 生態區內 80–250 m 的區塊，有自己的主次樹種、年齡、密度與型態（密叢、疏林、殘存人工林列、火燒、空地）；邊界是林緣 | 叢集噪聲 `clusters` |
| 單株樹 | 群聚式擺放（母樹與子樹），記錄樹種、變體、年齡、健康、傾斜、色調 | 抖動網格 |

生態區由區域種子、環境場與 landform 相容性抽選，用洗牌避免連續重複。區域交界照現在的方式漸變。

樹種是參數化生成器（TreeSpecies），每種生成多個變體並快取。枯死、將死、焦黑、斷頂、半埋由同一樹種推導，所以「死松」和「死闊葉樹」長相不同。MultiMesh 開逐棵顏色，加輕微傾斜與不等比縮放。樹幹碰撞照樹種的實際粗細。

林分與單株以世界座標的林分種子生成，再篩出落在 band 內的樹。每個 band 的規劃陣列仍然確定，撞倒帳本保留 `TreeImpact.forest_id(band, index)` 的格式。

## 要改的讀取端

| 讀取端 | 現在讀 | 改成 |
|---|---|---|
| [ForestScenery](../../world/terrain/forest_scenery.gd) | `flora_weights`、`tree_choice` | 林分規劃 |
| [ScatterScenery](../../world/scatter/scatter_scenery.gd)、[ScatterCatalog](../../world/scatter/scatter_catalog.gd) | 地形權重陣列、`MOISTURE` | 生態區的地被層與環境場 |
| [ChunkGenerator](../../world/chunk_generator.gd) 地表網格 | `color_at`、`material_weights` | 土質權重與生態區色盤 |
| [WorldWind](../../world/world_wind.gd) 粉塵與遮蔽 | `MOISTURE`、`TREE_DENSITY`、`DUST_COLORS` | 土質、樹冠量、樹幹量 |
| [ForestFog](../../world/terrain/forest_fog.gd) | 地形濕度 | 環境場濕度 |
| [WorldAmbience](../../world/world_ambience.gd)、[WorldWindAudio](../../world/world_wind_audio.gd) | `flora_weights` 的樹密度 | 樹冠量決定葉響，樹幹量決定枯木吱嘎 |
| [SlenderSpeakerSpawns](../../world/terrain/slender_speaker_spawns.gd) | 附近有沒有樹 | 加上生態區的 Slender 旗標 |
| [FootstepSurface](../../core/audio/footstep_surface.gd) | 岩石比例 | 土質（沙需要自己的腳步聲） |
| [WorldClock](../../world/world_clock.gd)、[WorldFeatures](../../world/terrain/world_features.gd) | `appearance_at` | 視用途讀 landform 或生態區 |
| 測試 `terrain_v14_contracts`、`wind_contracts` | 地形表格 | 生態區資源 |

## 階段

| 階段 | 內容 | 完成條件 |
|---|---|---|
| 1a 生態資料層 | 環境場、生態區資源與區域抽選；現有六種地形改寫成六個生態區，所有讀取端改讀新層；生態地圖工具（沿路線俯視輸出生態區、林分、樹種色塊） | 同種子的樹、地被、粉塵、霧與重構前一致，不升 `generation_version` |
| 1b 地形洗牌 | 地形順序依種子洗牌、不連續重複；升 `generation_version` | 河川、橋、POI 避讓測試仍通過 |
| 2 樹種與林分 | TreeSpecies 與變體、健康狀態、逐棵顏色；林分規劃、群聚擺放、林緣與空地、樹下灌木 | 多樣性測試：相鄰區域配方不同、同區樹種多樣性有下限、路上沒有樹；draw call 與串流幀時間不比重構前差太多 |
| 3 地表土質 | 地表 shader 混合多種土質（沙有風紋與樹根積沙）；地被改讀生態區與土質；沙地腳步聲 | 生態試玩場裡每種土質看得出差別 |
| 4 其他讀取端 | 粉塵、霧、環境音、風聲、風遮蔽、Slender 旗標 | 對應的 `docs/systems/` 與 GDD 改寫完成 |
| 5 新生態區 | 先做沙地枯木林，接著火燒林、殘存人工林、針葉密林、白樺疏林 | 每個生態區都能在試玩場直接傳送去看 |

每個階段結束都停下來交給使用者檢查。試玩場在 Esc 的 Playground 頁提供「傳送到指定生態區」與「顯示林分邊界」。

## 沙地枯木林（第一個新生態區）

- 地表：淡黃灰色的沙，有風紋，夾少量礫石。
- 地被：稀疏的乾草叢、沙堆、半埋的倒木，沒有一般的草。
- 樹：大多是枯木（白化的松、裂開的闊葉樹骨架、斷頂、半埋），零星幾叢活的矮灌木。
- 密度中低、群聚弱：遠方視野開闊，近處樹幹林立。
- 大氣與聲音：起風揚沙，霧偏乾霾；枯木吱嘎多，沒有葉響。

## 風險

- 1b 之後同種子的世界整個重排，舊存檔與舊檢查點作廢，依存檔規則直接刪除。
- 樹種變體一多，每個 48 m 格子的 MultiMesh 數會暴增。每個生態區要限制同時使用的變體數；遠景可能要 impostor。
- 宣傳片鏡頭（`tests/playgrounds/promo/shots/`）與 `scripts/promo_scout.gd` 依賴現在的地形與樹位置，1b 之後要重新取景。

## 待決定

- 生態區清單與每種 landform 能出現哪些生態區，在階段 1a 用生態地圖對照後定案。
- 沙地腳步聲的素材來源。
- 遠景是否需要 impostor，看階段 2 的效能量測再決定。
