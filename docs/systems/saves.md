# 存檔

單一檢查點：F6 存、F9 讀。存檔開發凍結到專案後期，現有內容維持可用，但不為新功能擴充。

## 功能一覽

| 功能 | 範圍 | 來源 |
|---|---|---|
| 檢查點 | 主世界的 F6／F9，一份檔案，沒有多槽 | [Checkpoint](../../rv/checkpoint.gd)（autoload） |
| 寫檔與備份 | 先寫暫存檔並讀回比對，再換掉正式檔；上一份有效檔留作備份 | [CheckpointFiles](../../core/checkpoint_files.gd) |
| 車輛快照 | 車體、引擎、油料、材料、車上物品、車殼槽位、車輪 | [VehicleSnapshot](../../rv/vehicle_snapshot.gd)、[RVStructureSlots](../../rv/structure_slots.gd) |
| 世界中的物品與怪物 | 逐一保存並還原，含物品之間的支撐關係 | [WorldActorSnapshot](../../core/world_actor_snapshot.gd)、[ItemState](../../core/item_state.gd) |
| 資料驗證 | 存檔前與讀檔後跑同一套檢查 | `Checkpoint.validation_error`、[CheckpointSchema](../../core/checkpoint_schema.gd) |
| 場景白名單 | 存檔只能生成登錄過的 Item、Monster 與車輛場景 | [SaveSceneCatalog](../../core/save_scene_catalog.gd) |
| 教學階段重來 | 設定選單的「Restart this stage」與教學步驟恢復，共用檢查點的快照 | [orientation_recovery.gd](../../world/tutorial_shelter/orientation_recovery.gd)、[settings_menu.gd](../../player/settings_menu.gd) |

自動測試：[test_checkpoint_failures.gd](../../tests/test_checkpoint_failures.gd) 是檢查點的主要測試，涵蓋寫檔失敗、被拒絕的資料，以及生存、蹲姿、地堡、巨型避難所與教學的存讀；其他系統的測試在各自的檔案裡順帶驗證存讀。

## 規則與數值

### 什麼時候能存、能讀

F6 與 F9 只在主世界（`world/main_world.tscn`）與教學測試場（`tests/orientation_playground.tscn`）有反應，設定選單開著時不反應。讀檔一律載入主世界。

存檔會被以下狀況擋下，畫面左側顯示原因：

- 玩家在 POI 室內或正在轉場。
- 玩家不在一般操作狀態：坐在座位上、操作介面、躺床休息或已死亡。
- 地形還在生成，或已載入的區塊還沒發布導航。
- 玩家被怪物抓住，或有怪物正在抓取、處決。
- 作弊飛行開啟中。
- 正在放置物品或設備的預覽。
- 車殼施工中、引擎艙蓋或後坡道還在動。
- 出庫閘門或整備區閘門還在動。

讀檔要求玩家在室外且處於一般操作狀態。

### 存了什麼

存下的欄位以 `Checkpoint.capture_world` 與 `VehicleSnapshot.capture` 為準，大致是：

- **玩家**：位置、背包與選取格、生命、體力、蹲姿、身體部位狀態、飢餓與 SAN。
- **車輛**：位置與速度、引擎與檔位、手煞車、油料、材料與車上物品、車燈與舒適設定、充電狀態、每個車殼槽位的型態、耐久與門角度、四個車輪、固定在車上的設備。
- **世界**：種子與生成設定、已生成的區段、世界中的物品與怪物、未載入區段裡的物品、被撞倒的樹、戶外場址、POI 室內的狀態、偏行壓迫、時間與天氣。
- **開場**：出庫階段、閘門與教學進度。

空的車殼槽位與空的引擎槽讀檔後仍然是空的，不會補發設備。

### 不相容的存檔

檔案版本、車輛快照版本或世界生成版本與目前程式不同時，存檔會被拒絕並提示重新開局。沒有資料遷移，也不會去找舊路徑的檔案。版本與路徑見 `rv/checkpoint.gd` 的 `VERSION`、`PATH`，`rv/vehicle_snapshot.gd` 的 `VERSION`，以及 `WorldProfile.CURRENT_GENERATION`。

凍結之後加入的功能不接進存檔，讀檔後它們的狀態回到初始值。

## 實作契約

### 寫檔

- 資料先寫到 `PATH + ".tmp"`，讀回後與原資料逐位元組比對，通過才動正式檔。
- 正式檔已存在且仍能通過完整讀檔驗證時，先複製成 `PATH + ".bak"`；壞掉的舊檔不會蓋掉備份。
- 任何一步失敗都刪掉暫存檔，正式檔保持原樣，並回報 `open`、`write`、`backup` 或 `rename`。
- 遊戲不會自動讀 `.bak`。它只是給人手動救回上一份檔案用的。

### 讀檔與驗證

- `read_checkpoint` 先擋掉超過 `CheckpointSchema.MAX_BYTES` 的檔案與超過 `MAX_ENTRIES` 的巢狀資料，再比對版本，最後跑 `validation_error`。
- `validation_error` 要求所有頂層欄位齊全，逐項檢查型別與值域，並回傳第一個不合格的欄位路徑。它只接受 `world_id` 為 `shelter`、世界生成版本等於 `WorldProfile.CURRENT_GENERATION` 的資料。
- 車殼快照的槽位數必須等於 `RVStructureSlots.layout()`，車上設備的支撐必須指向這輛車上存在的槽位。
- 所有 Item 的 ID 在整份存檔裡唯一；物品之間的支撐關係必須成立（`WorldActorSnapshot.graph_error`）。
- `capture_world` 在回傳前對自己產生的資料跑同一套驗證，不合格就不寫檔。

### 載入不會弄壞目前的世界

- `load_snapshot` 在獨立的 `SubViewport` 與獨立的物理空間裡建立新的主世界，等它 `wait_for_play`（逾時見 `world_timeout_ms`），再還原車輛、物品、怪物與玩家。
- 全部成功才把新世界換成目前場景並釋放舊世界；驗證失敗、逾時或車輛還原失敗時，舊世界恢復執行，新世界丟棄。
- 還原車輛時先還原車殼槽位，再接回設備；還原物品時先生成全部物品，再接回支撐關係。
- 把還原好的車輛與物品搬進新世界時用 `WorldEntities.transfer`，搬移期間設備不會掉落、退還材料或失去支撐。

### 場景白名單

`SaveSceneCatalog.resolve` 只回傳登錄過、而且實際型別相符的場景。存檔裡出現未登錄的場景路徑時，整份存檔被拒絕。

教學的階段重來走同一條路：`orientation_recovery.gd` 用 `Checkpoint.capture_world` 在記憶體中拍下階段入口的快照，重來時交給 `Checkpoint.load_snapshot`。所以世界裡只要有一個未登錄的場景，教學重來也會失敗。

教學快照有一個手動存檔沒有的放寬：玩家正在讀教學終端或平板時也能拍。其他阻擋條件照舊。

### 凍結政策

- 現有 F6／F9 的保存內容與測試維持可用。
- 新功能不接進存檔、不新增必要欄位、不升版本。
- 唯一例外：每個新的 Item 或 Monster 場景都要登錄到 `SaveSceneCatalog`，原因見上一節。
- 改存檔格式時直接改，不留相容分支；舊檔直接作廢。
