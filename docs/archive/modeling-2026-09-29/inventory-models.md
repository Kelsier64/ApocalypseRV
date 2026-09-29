# 匯入模型與製作來源盤點

> 歷史快照：2026-09-29 封存，保留當時觀察與規則，不再日常更新。現行流程見 [建模入口](../../modeling/README.md)。

後續狀態（2026-09-29）：油桶／汽油罐已改灰盒並收存原檔，下方兩款模型及 `.import` 的連結改指保存位置；本報告的數量、引用與風險描述保留為 2026-09-28 盤點結果。當前狀態見 [來源 manifest 說明](asset-provenance.md)，舊 Raker 建置及掃描腳本已移除，目前入口見 [建置指南](../../guides/asset-builds.md)。

盤點日期：2026-09-28。範圍為目前工作樹的 `assets/` 匯入模型、`art_source/` Blender／GLB 與製作腳本，以及場景、程式、資產 README 和歷史驗收的依賴關係。本次僅唯讀盤點並建立此文件；未重建模型、未執行 Godot／Blender、未搬移或刪除任何資產。

依據：[目錄指南](../../guides/codebase.md)、[架構](../../../architecture.md)、[專案規則](../../../AGENTS.md)。`test`、版本號、沒有主場景直接引用，都不是刪除依據。以下「正式匯入」指放在 `assets/`、由遊戲 actor／場景／動畫程式消費的交付資產；不表示所有模型品質和遊戲情境均已驗收。

## 可重現的總量與邊界

| 位置／種類 | 檔案數 | 原始檔案 bytes | 意義 |
|---|---:|---:|---|
| `assets/**/*.glb` | 7 | 43,477,928 | 正式匯入交付；其中玩家 v021 只供執行期擷取動畫 |
| `art_source/**/*.glb` | 12 | 62,854,536 | Raker v010–v021 的來源匯出快照，不能再算成 12 個正式角色 |
| `art_source/**/*.blend` | 15 | 273,487,263 | Raker v009 的兩份、v010–v021 各一份、玩家動畫 v021 一份 |
| `art_source/**/*.blend1` | 6 | 83,208,153 | v010／v011／v012／v015／v016／v017 的 Blender 備份 |
| `art_source/**/*.py` | 48 | 187,542 | 版本製作、匯出、稽核及預覽腳本；不是 48 個模型 |
| `assets/` 與 `art_source/` 的 `.gltf`／`.obj`／`.fbx` | 0 | 0 | 本次副檔名掃描未發現 |

`art_source/.gdignore` 將來源樹與 Godot 一般匯入分開；玩家動畫來源目錄另有自己的 `.gdignore`。`.blend1` 並非正式匯入檔，也不能只憑副檔名推定與 `.blend` 內容相同。本次未開啟 Blender 檢查備份內部場景／未保存工作差異，全部保留。

下列命令在專案根目錄重現數量及容量，包含隱藏檔；不讀取 `.godot/` 快取：

```powershell
$extensions = '.glb','.gltf','.obj','.fbx','.blend','.blend1','.py'
foreach ($root in 'assets','art_source') {
    Get-ChildItem -LiteralPath $root -Recurse -Force -File |
        Where-Object { $_.Extension -in $extensions } |
        Group-Object Extension |
        ForEach-Object {
            [pscustomobject]@{
                Root = $root
                Extension = $_.Name
                Count = $_.Count
                Bytes = ($_.Group | Measure-Object Length -Sum).Sum
            }
        }
}
rg -n --no-ignore '\.glb' player enemies props world tests scripts art_source -g '*.gd' -g '*.tscn' -g '*.tres' -g '*.py'
```

## 正式匯入清單與 GLB 內容

本表數值直接唯讀解析七個 GLB 的 JSON chunk。三角面為**所有 mesh primitive 的索引數／3 加總**，不是 scene 節點實例數、Godot 匯入後 LOD 或當幀繪製數。七檔的 primitive 都是 `mode=4`（TRIANGLES，省略 mode 時也按規格預設 4）；沒有把 strip／fan 誤當三角清單。表中骨數為 skin joints 數，並非 Blender 控制骨總量。

| 家族／執行期檔 | Mesh／三角面 | 材質／內嵌圖像 | Skin joints／動畫 | 直接消費者與角色 |
|---|---|---|---|---|
| 油桶 [oil_barrel.glb（已收存）](../../../art_source/retired_props/2026-09-29/oil_barrel.glb) | 1／499,846 | 1／2 WebP | 0／0 | [oil_barrel.tscn](../../../props/oil_barrel.tscn)，大型可搬運物件 |
| 油罐 [gas_can.glb（已收存）](../../../art_source/retired_props/2026-09-29/gas_can.glb) | 1／495,317 | 1／2 WebP | 0／0 | [gas_can.tscn](../../../props/gas_can.tscn)、[gas_can_empty.tscn](../../../props/gas_can_empty.tscn)，共用外觀 |
| 加油機 [fuel_pump.glb](../../../assets/models/gas_station/fuel_pump.glb) | 1／1,400 | 6／0 | 0／0 | [fuel_pump.tscn](../../../world/poi_kit/furniture/fuel_pump.tscn) 的 `Visuals/Model` |
| Zombie [monster_export_test.glb](../../../assets/models/monster/monster_export_test.glb) | 1／3,146 | 2／0 | 45／2 | [zombie.tscn](../../../enemies/zombie.tscn) 的 `BodyMesh/Model` |
| Raker [raker.glb](../../../assets/models/raker/raker.glb) | 1／30,242 | 6／3 PNG | 54／41 | [raker.tscn](../../../enemies/raker.tscn) 的 `BodyMesh/Model` |
| 玩家模型 [player_export_test_v020.glb](../../../assets/models/player_test_v020/player_export_test_v020.glb) | 11／16,222 | 5／1 PNG | 41／1 | [player_model_visual.tscn](../../../player/player_model_visual.tscn)，正式玩家外觀 |
| 玩家動作 [player_animations_v021.glb](../../../assets/models/player_animations_v021/player_animations_v021.glb) | 11／16,222 | 5／1 PNG | 41／17 | [player_locomotion_visual.gd](../../../player/player_locomotion_visual.gd) 擷取動畫後釋放來源實例 |

玩家兩份 GLB 均有完整幾何，不能因此把正式玩家渲染面數直接算兩倍。Raker 三張內嵌 PNG 為身體污垢、口內牙齒色圖及手部圖集；README 強調的 2K 身體和 1K 手部圖集不是全部 image 條目的枚舉。

唯讀量測方式如下；未呼叫匯入器或重寫 GLB：

```powershell
foreach ($f in Get-ChildItem assets -Recurse -File -Filter *.glb) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $jsonLength = [BitConverter]::ToUInt32($bytes, 12)
    $j = [Text.Encoding]::UTF8.GetString($bytes, 20, $jsonLength) | ConvertFrom-Json
    $triangles = 0
    $modes = @()
    foreach ($mesh in $j.meshes) {
        foreach ($primitive in $mesh.primitives) {
            $mode = if ($null -eq $primitive.mode) { 4 } else { $primitive.mode }
            $modes += $mode
            if ($mode -ne 4) { throw "Non-TRIANGLES primitive: $($f.FullName)" }
            $accessor = if ($null -ne $primitive.indices) {
                $primitive.indices
            } else { $primitive.attributes.POSITION }
            $triangles += $j.accessors[$accessor].count / 3
        }
    }
    [pscustomobject]@{
        File = $f.FullName
        Triangles = $triangles
        Modes = ($modes | Sort-Object -Unique) -join ','
        Meshes = @($j.meshes | Where-Object { $null -ne $_ }).Count
        Materials = @($j.materials | Where-Object { $null -ne $_ }).Count
        Images = @($j.images | Where-Object { $null -ne $_ }).Count
        Joints = @($j.skins.joints | Where-Object { $null -ne $_ }).Count
        Animations = @($j.animations | Where-Object { $null -ne $_ }).Count
    }
}
```

## 油罐／油桶家族

目前兩個 GLB 都直接進入 [主世界](../../../world/test_world.tscn)，也由 [加油站建築](../../../world/poi_kit/buildings/gas_station.tscn) 使用。油罐另見 [世界物資抽選](../../../world/terrain/world_field.gd) 與 `world/roadside_pois/` 的 wreck／cargo 系列；空罐、滿罐及油桶皆在 [SaveSceneCatalog](../../../core/save_scene_catalog.gd) 白名單內，存檔相容也是保留理由。GLB 僅提供外觀，Box／Cylinder 碰撞和物件行為由外層 `.tscn`／`interactable_item.gd` 管理。

本次在 `art_source/` 和 `scripts/` 未找到可對應的 Blender 原檔或生成腳本，也沒有專屬來源 README／授權紀錄。GLB `asset.generator` 是 `https://github.com/mikedh/trimesh`；這只是生成工具欄位，不能證明作者、下載來源、授權或 AI 製作方式。這些來源資訊仍待補。

相鄰 `gas_can_0.webp`／`gas_can_1.webp`、`oil_barrel_0.webp`／`oil_barrel_1.webp` 及 `.import` 均應保留。GLB 有內嵌圖像，且 [gas_can.glb.import（已收存）](../../../art_source/retired_props/2026-09-29/gas_can.glb.import)、[oil_barrel.glb.import（已收存）](../../../art_source/retired_props/2026-09-29/oil_barrel.glb.import) 使用 embedded image handling；文字找不到 WebP 引用不足以判定可刪。先前 [架構審查](../../report/ApocalypseRV_Architecture_Audit_2026-09-22.md) 也列出相同依賴風險。

兩份原始 GLB 分別為 16,261,168／16,769,764 bytes，原始 mesh 約各五十萬三角面，是後續美術預算檢查優先候選。目前匯入設定已開啟 `meshes/generate_lods=true`，本次沒有量測實際 LOD、近距離多實例成本、GPU 記憶體或場景瓶頸，不能直接宣稱它們造成卡頓。建議先補來源清單與可編輯副本，再以獨立候選製作減面／烘焙版本，比較輪廓與貼圖；原件、物件路徑和碰撞契約保留。

## 加油機家族

[資產 README](../../../assets/models/gas_station/README.md) 與 [build_fuel_pump_glb.py](../../../scripts/build_fuel_pump_glb.py) 提供完整來源：專案自製、僅用 Python 標準庫組建 GLB，沒有第三方模型或 Blender 原始工程。高度 2.255 m、Y-up、展示面 +Z、地面底座中心為原點；沒有模型自帶碰撞。

目前引用鏈為 [gas_station 定義](../../../world/poi_definitions/gas_station.tres) → [gas_station.tscn](../../../world/poi_kit/buildings/gas_station.tscn) → [fuel_pump.tscn](../../../world/poi_kit/furniture/fuel_pump.tscn) → GLB。四座共用外觀，字樣與三塊碰撞仍由 Godot 外層管理；正式 v5／v6 可步入加油站已接入世界生成，**加油機本身仍是停用造景，沒有燃油交易**。

[灰盒](../../../world/poi_kit/furniture/fuel_pump_graybox.tscn) 是 [加油站展示場](../../../tests/gas_station_playground.tscn) 的 F7 外觀 A/B 對照，不能因 GLB 已替換就刪除。歷史 [2026-09-19 匯入驗收](../../validation/2026-09-19-fuel-pump-import.md) 記錄可重建雜湊、尺寸、碰撞、A/B、步行回歸和可見回放；[2026-09-20 正式接入](../../validation/2026-09-20-production-gas-station.md) 才是後續主世界整合證據。這些結果未於本次重跑。

整理建議：保留現有家族目錄和 Python 來源，日後新外觀沿用外層場景；需要 Blender 工作檔時另建來源，不能把目前沒有 `.blend` 誤判為不可重建。

## Zombie 試接模型家族

[README](../../../assets/models/monster/README.md) 記錄外部來源為 `C:/Users/evan4/Projects/3d/exports/godot/monster_export_test.glb`，2026-09-22 複製。本倉庫內沒有對應 Blender 原檔或導出製作腳本；外部來源沒有在本次重新開啟或核對。名稱雖為 `monster_export_test`，它已被正式 `Zombie` actor 場景使用，不是可以移走的臨時測試檔。

[zombie.tscn](../../../enemies/zombie.tscn) 以約 `1.5 / 2.18` 比例縮放、轉 Y 180°，沿用原膠囊；[monster_model_visual.gd](../../../enemies/monster_model_visual.gd) 循環使用 `TEST_InPlace`，`TEST_RootMotion` 只保留在資產內。沒有完整走路、攻擊、攀爬、死亡動作，是仍存在的外觀缺口。

目前戶外新生成使用 Raker；Zombie 仍在 [存檔白名單](../../../core/save_scene_catalog.gd)、[模型展示場](../../../tests/monster_model_playground.tscn)、[雙角色攀爬場](../../../tests/rv_climb_playground.gd) 的預設分支及多個 `test_monster_*.gd` 內使用。[室內副本](../../../world/instances/poi_interior.gd) 可依保存的 actor scene 路徑還原，但本次未找到該目錄直接建立 Zombie 的自然生成路徑；Raker README 的「室內副本仍使用 Zombie」需與此現況分開，不宜擴大成已確認的生成規則。

[2026-09-22 歷史驗收](../../validation/2026-09-22-monster-model.md) 記錄匯入、測試姿勢、可見攀車和受傷顯示，也記錄當時 `test_monster_cabin.gd` 失敗及基準對照。該文件的「主世界使用 Zombie」描述是當日狀態，不能蓋過目前 Raker 生成程式。

整理建議：保留檔名、UID／import 和 actor 相容；補一份來源 manifest，標清「正式 actor 使用的試接美術」，日後替換只改外觀並保留存檔路徑。不要以重新命名來掩蓋動畫尚未完成的狀態。

## Raker 家族：正式 v021 與 v009–v020 製作歷史

正式 [raker.tscn](../../../enemies/raker.tscn) 消費 [raker.glb](../../../assets/models/raker/raker.glb)；[chunk_generator.gd](../../../world/chunk_generator.gd) 和 [walk_in_sites.gd](../../../world/terrain/walk_in_sites.gd) 建立它，後者包含 v6 小 POI。`test_main_world_monsters.gd` 名稱雖指主世界，其目前內容明確設定 v5 作為既有戶外遭遇回歸；不能單憑此測試名稱宣稱全部 v6 場址均已驗收。

[目前資產說明](../../../assets/models/raker/README.md) 記錄 v021 雙手重建、54 變形骨、41 段原地動畫、2.18 m 中立身高與 1.60 m 低姿態碰撞。遊戲移動、頸部追視及抓咬接觸修正屬 [Raker 行為](../../../enemies/raker.gd)／[姿勢修正器](../../../enemies/raker_pose_modifier.gd)，不等於 GLB 自帶所有功能。

本次 `Get-FileHash` 核對正式 GLB 與 [v021 來源匯出](../../../art_source/monster_refined_v021/raker_refined_v021.glb) 完全相同，SHA-256 為 `2CFB175A598CD107E10D7DA225630692CFB2EF880224B957BC7ED83D477A7B9F`。這證明交付對應，沒有證明重新跑腳本仍得到相同二進位。

各版來源目錄以 `monster_refined_vNNN.blend` 保存編輯場景，v010–v021 另有 `raker_refined_vNNN.glb`。下表链接到含完整交付／製作入口的 README；v009 沒有 README。版本說明中的「已複製到正式」是歷史整合記錄，**目前唯一正式 Raker GLB 對應 v021**。

| 來源家族 | 製作／匯出／檢查腳本（同目錄） | 保留內容與目前角色 |
|---|---|---|
| [v009 來源](../../../art_source/monster_refined_v009/monster_refined_v009.blend)、[細化前來源](../../../art_source/monster_refined_v009/source_before_refinement.blend) | 本目錄沒有 `.py`、README 或 GLB | 兩份 Blender 和 `before.png`；前期來源／對照，內部版本差異本次未開檔確認 |
| [v010](../../../art_source/monster_refined_v010/README.md) | `refine.py` → `audit.py` → `finish.py` | 5,056 面／22 動畫，局部細化及膚色圖；README 定位獨立交付、當時未正式替換；有 `.blend1` |
| [v011](../../../art_source/monster_refined_v011/README.md) | `refine.py`、`audit.py`、`finish.py` | 5,928 面／22 動畫，污垢、深眼窩、嘴；歷史正式接入；有 `.blend1` |
| [v012](../../../art_source/monster_refined_v012/README.md) | `refine.py`、`audit.py`、`finish.py` | 16,116 面／22 動畫，頭部／軀幹加密；後續身體基底；有 `.blend1` |
| [v013](../../../art_source/monster_refined_v013/README.md) | `author.py`、`audit.py`、`finish.py` | 16,116 面／23 動畫，走、跑、追車 sprint；保留先前 actions |
| [v014](../../../art_source/monster_refined_v014/README.md) | `author.py`、`audit.py`、`finish.py` | 16,116 面／23 動畫，駝背、頸部前彎、收肘與手姿的歷史版本 |
| [v015](../../../art_source/monster_refined_v015/README.md) | `author.py`、`audit.py`、`finish.py` | 16,116 面／23 動畫，小幅抬頭；v016 的前置來源；有 `.blend1` |
| [v016](../../../art_source/monster_refined_v016/README.md) | `author.py`、`refine_skin.py`、`rebake.py`、`audit.py`、`finish.py` | 16,116 面／41 動畫，46 骨、下顎與抓咬；`rebake.py` 不能代替首次建模；有 `.blend1` |
| [v017](../../../art_source/monster_refined_v017/README.md) | `refine_mouth.py`、`audit.py`、`finish.py` | 17,556 面／41 動畫，唇緣／牙齒歷史嘗試；保留 v016 場景供 v018 重建；有 `.blend1` |
| [v018](../../../art_source/monster_refined_v018/README.md) | `build.py`、`audit.py`、`finish.py`、`render_review.py` | 18,182 面／41 動畫，從 v017 檔內 v016 網格重建原生嘴縫和內藏牙齒 |
| [v019](../../../art_source/monster_refined_v019/README.md) | `build.py`、`audit.py`、`finish.py`、`render_review.py`、`review_workspace.py` | 18,182 面／41 動畫，來源掌向修正；v020 前置來源 |
| [v020](../../../art_source/monster_refined_v020/README.md) | `build.py`、`audit.py`、`audit_fingers.py`、`finish.py`、`render_review.py`、`review_workspace.py` | 18,182 面／41 動畫，四指屈曲／bind 修正；v021 前置來源；另有 `render_runtime.gd` |
| [v021](../../../art_source/monster_refined_v021/README.md) | `build.py`、`audit.py`、`audit_hands.py`、`inspect_geometry.py`、`finish.py`、`render_review.py`、`review_workspace.py` | 30,242 面／41 動畫，完整新雙手與 54 骨；目前正式來源；另有 `render_runtime.gd`、`render_playground.gd` |

上述 12 個 GLB 的面數／動畫數也由 JSON chunk 核對，Blender 內的來源頂點數與 GLB 因 UV／材質拆分的頂點數不能混用。六份 `.blend1` 都位於表列家族並與 `.blend` 同 basename，保留為當版恢復點；未比對內容前不稱為可安全去重的副本。

更早基底由 `scripts/build_raker_animations.py` 從外部 v007 工作場景產生 v008 動畫，`scripts/audit_raker_animations.py` 保存舊版掃描流程；這兩支腳本於盤點時存在，已於 2026-09-29 移除。資產 README 記錄原始動畫來源 `C:/Users/evan4/Projects/3d/raker_animated_v008.blend`，不在此次倉庫內盤點範圍。v010 起仍依靠既有 Blender 場景／命名；各版不是可任意單獨執行的無狀態生成器。

**重建風險：** 舊 `build_raker_animations.py` 的 `OUTPUT` 直接指向正式 `assets/models/raker/raker.glb`，執行可能把 v021 覆成舊動畫外觀；多份 `finish.py`／早期 authoring 腳本也硬編碼本機絕對路徑。先設定獨立暫存輸出、核對預期前置版本／場景，再重建和比對。v021 的 [來源 Blend](../../../art_source/monster_refined_v021/monster_refined_v021.blend)、[build.py](../../../art_source/monster_refined_v021/build.py) 和 [finish.py](../../../art_source/monster_refined_v021/finish.py) 是目前入口；不可跳過前置 v020／內嵌歷史場景契約。

歷史 [v021 驗收](../../validation/2026-09-23-raker-v021.md) 記錄手部替換、逐幀權重／穿插、15 組 Raker 回歸、固定近照與自動第一人稱流程；沒有重新人工駕駛或窮舉跨動畫混合。更晚 [固定抓取視角驗收](../../validation/2026-09-24-raker-fixed-grab-view.md) 屬執行期姿勢／鏡頭整合，不是又一份新的 GLB。舊版 `validation.json`、手部稽核、PNG 及 `.blend` 中保留場景，皆屬版本證據和後續製作依賴，不能按直接引用數移除。

整理建議：保留各版本，另補機器可讀 manifest 標記前置版本、source scene、輸出、SHA-256、正式指向與歷史日期；將有覆寫風險的腳本日後改為明確輸出參數和安全預設。本次只記錄建議，沒有修改腳本或搬檔。

## 玩家家族：v020 外觀、v021 動畫、獨立物理驗收

[player.tscn](../../../player/player.tscn) 實例化 [player_model_visual.tscn](../../../player/player_model_visual.tscn)，因此 `assets/models/player_test_v020/` 是目前正式模型目錄。檔名刻意保留以保持既有匯入／布娃娃驗收指向同一資產。[v020 README](../../../assets/models/player_test_v020/README.md) 記錄 1.60 m、11 個蒙皮 mesh、41 變形骨、16,222 面、5 材質及 512px 貼圖；正式呈現轉 Y 180° 對齊角色前方，不改來源軸向或比例。

來源紀錄為專案外的 `C:/Users/evan4/Projects/3d/player_textured_v019.blend`、匯出副本 `player_godot_export_v020.blend`、交付 `exports/godot/player_export_test_v020.glb`。本次未遍歷外部 `3d/`，不宣稱來源目前可完整重建；原始授權、來源控制 rig 和外部檔案可攜性應另建 manifest。專案內的 [player_animations_v021.blend](../../../art_source/player_animations_v021/player_animations_v021.blend) 是保留模型的動畫工作副本，不等於外部 v020 live-control 原檔。

[build_player_animations.py](../../../scripts/build_player_animations.py) 讀取使用者接受的 v020 Blender 工作檔，輸出本地 v021 `.blend` 和動畫 GLB；[render_player_animation_review.py](../../../scripts/render_player_animation_review.py) 產生審核畫面。[v021 README](../../../assets/models/player_animations_v021/README.md) 明列目前 17 段：idle、四向 jog、四向 run、三段 jump、五段 climb。正式 [動畫驅動](../../../player/player_locomotion_visual.gd) 建立來源實例、複製 clips 到快取 AnimationLibrary，再 `source.free()`；沒有把 v021 的 mesh／skin／材質取代 v020 外觀。v020 的 `TEST_v020_POSE_SAMPLES` 仍留在資產，正式角色另移除自己的 TEST library。

匯入設定是契約的一部分：[v020 `.import`](../../../assets/models/player_test_v020/player_export_test_v020.glb.import) 維持 24 fps、關閉動畫 optimizer；[v021 `.import`](../../../assets/models/player_animations_v021/player_animations_v021.glb.import) 為 60 fps、關閉動畫 optimizer／compression。README 記錄曲線簡化曾造成姿勢偏差／靴子穿地，因此不能在整理檔案時恢復預設。來源的 60 動畫 samples/s 與遊戲 60 Hz 物理是不同設定。

展示與歷史證據各有不同範圍：

- [匯入 playground](../../../tests/player_import_v020/playground.tscn) 與 [匯入驗收](../../validation/2026-09-27-player-v020-import.md)：來源尺寸、蒙皮、測試姿勢與材質。
- [布娃娃 playground](../../../tests/player_ragdoll_v020/playground.tscn) 與 [布娃娃驗收](../../validation/2026-09-27-player-v020-ragdoll.md)：獨立物理 rig；後續 [死亡整合](../../validation/2026-09-27-player-death-integration.md) 才描述正式 Player 接管。
- [正式外觀整合](../../validation/2026-09-27-player-model-integration.md)：第一人稱隱藏頭部、完整陰影與呈現副本，不修改來源幾何／權重。
- [動畫 playground](../../../tests/player_animation_playground.tscn)、[攀爬近照場](../../../tests/player_climb_animation_playground.tscn)、[動畫驗收](../../validation/2026-09-27-player-animations-v021.md) 和 [攀爬鏡頭修正](../../validation/2026-09-27-player-climb-camera.md)：地面／跳躍／攀爬及視點同步。動畫驗收同頁包含先前 9／12 段歷史，最新為 17 段，不能將舊段落當現行交付。

仍有明確缺口：沒有攻擊、蹲姿、入座動畫、逐手逐腳接觸 IK；攀爬外觀確認及斜壁／轉角尚未完整驗收。歷史高處死亡壓力案例記錄最大關節間隙 29.12 mm，高於 25 mm 門檻，不能以一般跳躍死亡通過結果掩蓋。本次未重新驗證任何動作或物理。

`art_source/player_masked_survivor/` 目前有 `history`、`work`、多個 `godot_review*` 等空子目錄，遞迴含隱藏檔計數為 **0 個檔案**；不能把目錄名當另一份已交付玩家模型。是否另有外部工作來源不在本次可確認範圍。

整理建議：保持 v020 正式模型與 v021 動畫分工，manifest 明確記錄同 rig／rest pose 相容性和外部來源；未取得額外驗證前不要合併／重命名兩份 GLB，也不刪除 TEST clip、獨立 playground 或歷史驗收圖。

## 本次檢查與後續優先序

本次完成副檔名／容量統計、GLB JSON 結構與 primitive 面數核對、目前 Raker 交付雜湊對照、場景／腳本引用搜尋、README／歷史驗收比對，以及本文件相對連結存在性檢查。這些是靜態檢查，沒有新的匯入、行為、畫面或效能驗收結果。

1. 先補來源 manifest：油罐／油桶作者授權與可編輯來源、外部 Zombie／玩家原檔位置及雜湊、Raker 版本鏈與正式指向。
2. 在日後程式修改工作中處理 Raker 舊建置腳本的正式覆寫預設及絕對路徑，保留歷史工作流程說明。
3. 為油罐／油桶安排實際 LOD／場景量測，再決定減面或重製；不要拿原始三角面直接當 GPU frame budget。
4. 保留所有歷史來源、`.blend1`、審核圖、匯入設定和遊戲外層路徑。要搬檔時必須另作 UID／路徑／動態載入／存檔相容與乾淨匯入驗證，並確認 source script 的輸出目的地。

來源檔、展示樣板和歷史驗收有各自用途；本清單沒有標示任何可立即刪除的模型。
