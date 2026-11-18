# 架構重構計畫

| 狀態 | 盤點完成，測試基準已全綠，擬真操控分支已合回 main，小清理已完成 |
|---|---|
| 前提 | 完整測試全綠、`codex/rv-handling-rollover` 合回 main（皆已達成）；之後每個切片直接在 main 上提交 |
| 痛點 | 高層設計不清、大檔案難改、agent 容易迷路且耗 token、執行效能 |

[計畫總覽](README.md) · [技術架構](../../architecture.md) · [程式碼規範](../guides/codebase.md)

本文件整理 2026-11-16 的三份唯讀盤點，全部是靜態閱讀程式的結果，沒有跑測試、遊戲或 profiler。行號會漂移，動手前先對照程式。

## 現況

- **模組沒有分層。** `core/`、`props/`、`equipment/`、`rv/`、`player/`、`enemies/`、`world/` 互相引用；`core/` 本該是底層，卻因存檔驗證與快照轉換（`core/checkpoint_schema.gd`、`core/item_state.gd`、`core/world_actor_snapshot.gd`）反向依賴各遊戲模組。
- **存檔協調放在 `rv/`。** `Checkpoint` autoload（`rv/checkpoint.gd`）負責整個世界的保存與還原，觸及每個模組。存檔開發凍結到專案後期，見 CLAUDE.md Hard Rule 3。
- **基底類別承擔子類別的行為。** `Monster`（`enemies/monster.gd`）四個子類別中，只有 Raker 與 Crawler 用到攀爬、選敵、導航與登車；BarrelMan 與 SlenderSpeaker 覆寫 `_physics_process` 且不呼叫 super，只用到基底很小的一部分。外部真正依賴的介面只有 `is_dead`、`take_damage`、`current_health`、`receive_vehicle_body_contact` 與群組。
- **RV 車殼程式分散在兩個資料夾。** `rv/structure_slots.gd`、`rv/battery_socket.gd` 在 `rv/`，`equipment/rv_panel.gd`、`rv_door.gd`、`rv_ladder.gd` 在 `equipment/`。
- **手動登錄清單重複。** 新增一件物品要改 `core/save_scene_catalog.gd`、`core/inventory_item_icons.gd`、`core/item_names.gd`、`equipment/rv_terminal_presenter.gd`，有自訂狀態再加 `core/item_state.gd` 與 `rv/vehicle_snapshot.gd`。新增配方要在 `equipment/recipe_catalog.gd` 手動 preload；新增 POI 要登錄在 `world/poi_config.gd`。

## 大檔案拆分縫

依「共用變數少、測試覆蓋夠」排序。共用變數是粗略的字詞比對，不是讀寫分析。

| 檔案 | 切片 | 乾淨度 | 測試覆蓋 |
|---|---|---|---|
| `equipment/tablet_ui.gd` | 與 `training_terminal_ui.gd` 共用終端元件工廠 | 乾淨 | 無 UI 測試，要人工看 |
| `rv/chassis.gd` | 撞擊處理（`_integrate_forces`、懸吊撞擊取樣、`queue_*_impact`、`_settle_vehicle_impact`）抽成獨立元件，沿用 drivetrain／crash_damage 的模式 | 乾淨，只共用 4 個變數 | 間接；先補撞樹與撞怪的測試 |
| `enemies/slender_speaker/slender_speaker.gd` | 抓取與處決抽成 RefCounted helper，沿用既有 `update(actor, ...)` 模式 | 中等 | `test_slender_speaker_acquisition` 直接呼叫約 23 個私有方法，要加轉接或改測試 |
| `enemies/monster.gd` | 選敵併入既有的 `enemies/combat_targeting.gd` | 中等 | 偏薄；先補選敵測試 |
| `player/player.gd` | 爬梯抽成 `PlayerLadder` | 中等 | `test_moving_rv_climbing`、`test_item_player`、`test_pistol` |

暫緩：`monster.gd` 的攀爬與導航、SlenderSpeaker 的存活與重新定位、`player.gd` 的生命與死亡。三者都糾纏且覆蓋很少或沒有。

## 需要先決定的大改

以下都屬於大型架構變更，動手前要先問使用者：

- `Monster` 拆成只有共用介面的薄基底，加上給 Raker／Crawler 的地面怪物類別。
- `core/` 只留純規則與常數，存檔驗證與快照搬到獨立的保存層；存檔凍結到專案後期，這項要等凍結解除才能做。
- RV 車殼模組集中到一個資料夾。
- 物品、配方與 POI 的名稱、圖示、場景路徑收斂到定義資源或單一產生的目錄。

## 執行效能

以下是靜態閱讀得出的假設，每項都要先用 Godot Profiler 或計時量測確認再改。依可能成本排序：

| 風險 | 位置 | 量測方式 |
|---|---|---|
| SlenderSpeaker 抓取時每手 16 根骨頭各做形狀掃掠，每次都新建 shape 與 query；腳掌接觸每幀約 20 次掃掠；手臂 IK 每寫一根骨頭就 `force_update_all_bone_transforms()` | `slender_speaker.gd`、`slender_speaker_foot_contact.gd`、`slender_speaker_arm_ik.gd` | `tests/playgrounds/slender_speaker_playground.tscn` 的 `_physics_process` 時間與物理查詢數 |
| 夜視效果每幀以全解析度多渲染一個 SubViewport（含 MSAA、SSAO、體積霧）；手持物品再多一個，駕駛時再加三面後照鏡 | `world/night_vision_effect.gd`、`player/player_first_person_carry.gd`、`rv/vehicle_mirrors.gd` | 夜間駕駛手持物品與空手的 GPU 幀時間比較 |
| chunk 載入在主執行緒同步做 trimesh 碰撞、導航幾何解析，還會實例化再釋放鄰近 POI 場景來取障礙物 | `world/chunk_generator.gd`、`world/world_generator.gd` | `scripts/benchmark_streaming.gd` 的 slice 峰值 |
| 每隻怪物每個物理幀呼叫 `ItemDetour.direction`，每次新建 query 做形狀查詢與掃掠 | `enemies/item_detour.gd`、`enemies/monster.gd` | `tests/playgrounds/monster_pursuit_playground.tscn` 多隻怪物 |
| 怪物每幀掃描玩家與可受傷群組兩三次，遠處閒置的怪物不停止處理 | `enemies/monster.gd` | 15 隻以上怪物時的腳本函式時間 |
| 偽裝中的油桶人每幀兩次形狀重疊查詢，每 0.2 秒走訪 RV 全部碰撞形狀 | `enemies/barrel_man.gd` | `tests/playgrounds/barrel_man_playground.tscn` 放 10 隻以上 |
| 撞倒樹會讓本 chunk 與相鄰 chunk 同步重解析導航幾何並重烘兩份 navmesh；每 chunk 可能有上千個樹幹碰撞形狀 | `world/terrain/tree_impact.gd`、`world/chunk_generator.gd` | `tests/playgrounds/tree_impact_playground.tscn` 連續撞樹 |
| 下雨時每幀掃五個群組、排序、上傳 shader 陣列並做遮蔽射線 | `world/weather_rain.gd` | `tests/playgrounds/weather_playground.tscn` 乾燥與大雨比較 |
| 黑影每 0.1 秒用 `find_children` 走訪整個世界找燈 | `core/apparition_light_exposure.gd` | 載入多個 band 時計時 |
| 每 chunk 新建 ShaderMaterial 與多個 FogVolume；路燈、車燈開陰影；車板碎片各有獨立 mesh 與材質 | `world/chunk_generator.gd`、`world/terrain/forest_fog.gd`、`world/roadside_kit/streetlight.gd`、`rv/panel_damage_effect.gd` | 主世界夜間的 Rendering 計數 |

共通方向：重用查詢物件、快取 RV 外形與燈光清單、遠處或閒置時停止處理、輪詢改成訊號驅動。

**測試時間。** `scripts/test.ps1` 每個測試開一個無頭 Godot 程序，本機預設逾時 240 秒。原本的 `test_streaming_generation` 不是卡住，是跑到 237–257 秒；實測時間幾乎都在純取樣的契約，chunk 建置與 navmesh 不到 12 秒。現在已拆成 `test_streaming_generation`（約 70 秒）與 `test_world_contracts`（約 170 秒）。之後再接近上限時，先量各階段再拆，不要調高逾時。

## 建議順序

1. ~~修好兩個失敗的測試，跑出全綠基準。~~ 完成：2026-11-16 完整測試 24 項全過（`7ada89e` 加上未提交的拆分）。`test_rv_resource_cycle` 已被先前的提交修好；壞掉的 `tests/slender_speaker_bend_review.*` 已刪除，它繼承的 workshop 腳本從未入庫，會讓匯入失敗。
2. ~~合併 `codex/rv-handling-rollover` 回 main。~~ 完成：2026-11-16 快轉合併。擬真操控的試玩驗收沒有先做，仍列在[擬真操控計畫](rv-handling-rollover.md)的未結項目。
3. 終端元件工廠、RV 撞擊元件、SlenderSpeaker 抓取，各自一個切片，先補缺的測試。
4. 大改逐項提案，使用者同意後再排。
