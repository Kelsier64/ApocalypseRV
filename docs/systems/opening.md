# 開局與教學基地

新的一局從一座封閉的基地開始：玩家在裡面修好一輛故障的 RV，開出大門後世界才開始運轉。這份文件說明教學基地的流程、出庫的判定，以及展示用的單間車庫。存檔的整體規則見 [saves](saves.md)，RV 的維修操作見 [rv](rv.md)。

## 功能一覽

| 功能 | 範圍 | 來源 | 測試場 |
|---|---|---|---|
| 開場階段 | 準備、開門、啟程、封閉四個階段；啟程前時間、天氣與怪物都停住 | [StartRun](../../world/starting_shelter/start_run.gd)、[ShelterGarageGate](../../world/starting_shelter/garage_gate.gd) | |
| 兩室教學基地 | 接待室拿終端，倉庫整備 RV，開車出庫 | [OrientationController](../../world/tutorial_shelter/orientation_controller.gd)、[資產說明](../../world/tutorial_shelter/README.md) | [orientation](../../tests/orientation_playground.tscn) |
| 故障車與倉庫指南 | 新局的 RV 帶著故障；倉庫有備品與一份選做的指南 | [OrientationWorkshop](../../world/tutorial_shelter/orientation_workshop.gd)、[OpeningSiteContent](../../world/tutorial_shelter/opening_site_content.gd) | |
| 教學終端 | 開機、帶走、閱讀指南；離開基地後變成說明書 | [TrainingTerminal](../../equipment/training_terminal.gd)、[training_manual.gd](../../equipment/training_manual.gd) | |
| 階段重來與略過 | 設定選單的 Restart Stage 與 Skip Tutorial | [OrientationRecovery](../../world/tutorial_shelter/orientation_recovery.gd)、[settings_menu.gd](../../player/settings_menu.gd) | |
| 單間車庫 | 按鈕開門的舊開場，給 Demo 與作弊測試世界用 | [garage_button.gd](../../world/starting_shelter/garage_button.gd)、[資產說明](../../world/starting_shelter/README.md) | [starting_shelter](../../tests/starting_shelter_playground.tscn) |

自動測試：[test_orientation_departure.gd](../../tests/test_orientation_departure.gd) 開車走完出庫流程；[test_checkpoint_failures.gd](../../tests/test_checkpoint_failures.gd) 涵蓋教學狀態的存讀與階段重來。

## 規則與數值

### 用哪一座建築開場

`WorldProfile.opening_shelter` 決定開場建築，預設是兩室教學基地（`orientation_shelter`）。Demo 與作弊測試世界改用單間車庫（`starting_shelter`），見 [world](world.md#世界入口)。

### 開場階段

- **準備**（`preparing`）：玩家在基地裡。時間與天氣不走，怪物不動。
- **啟程**（`started`）：時間、天氣與怪物開始運作。
- **封閉**（`sealed`）：大門關上，回不去了。

教學基地在玩家和整輛 RV 都通過大門之後才進入啟程；單間車庫在大門完全打開時就進入啟程。兩者都在人車離開門口後自動關門。關門時被東西擋住會重新打開，並顯示 `Exit blocked. Move objects away from the gate.`。

### 接待室

1. 打開固定在座上的終端，按 Enter 開機，開機時間見 `training_terminal_boot.gd` 的 `DURATION`。
2. 開機完成後長按 F 把終端拆下來收進背包。沒開機前拆不下來。
3. 終端進了背包，通往倉庫的內門就會打開。
4. 帶著終端走進倉庫，終端的頁面換成倉庫指南。

### 故障的 RV

新局的 RV 在第一次準備時設定一次故障，之後讀檔或回到基地都不會重設：

- 引擎耐久歸零，引擎不能發動。
- 車上的電池電量歸零。
- 屋頂中段（`roof_1`）毀壞。
- 兩個不同的牆面或車門部位受損。
- 一個輪胎磨損，有三分之一的機會直接爆胎。

受損的部位、輪位與程度由世界種子決定（`OrientationWorkshop.prepare`）。終端上的指南會寫出實際受損的部位名稱。

### 倉庫的備品

倉庫裡的東西只在新局放一次（`OpeningSiteContent`）：

- 設備：拆解機與工作台各一台。
- 維修用：充滿電的備用電池、兩包引擎維修包、一個備胎。
- 材料：八件廢料與兩個油桶。每件廢料固定回收三份金屬，每個油桶固定回收兩份金屬與十份未精煉燃料。
- 一般補給：每種食物各一份、電子羅盤、野外終端、救援千斤頂。

沒有免費的油電：電要靠換上備用電池，油要自己回收油桶、用工作台做成汽油再加進去。

### 倉庫指南

指南列出十項整備（換電池、修引擎、裝拆解機、裝工作台、回收、製造汽油、修牆、重建屋頂、換輪胎、加油），全部是選做，可以用任何順序完成。終端會在每一項完成時打勾。

指南不決定能不能離開。能不能把車開出去只看 RV 自己的狀態：有電、引擎能發動、有油。

### 出庫

- 大門是感應式的。把原本那輛 RV 朝大門開過去，車頭對著門、在門前的車道上持續前進一小段，門就會打開。門檻見 `OrientationController` 的 `DEPARTURE_TRAVEL` 與 `DEPARTURE_MOTION_SECONDS`。
- 停著的車因懸吊晃動不算前進。換一輛車也不算，感應器只認原本的 RV。
- 還在接待室、沒帶終端進倉庫時，大門不會開。
- 門開了之後基地仍然是安全的。玩家與整輛 RV（含車上凸出的設備）都出了門口，世界才開始運作。

### 重來、略過與說明書

- **Restart Stage**：把世界退回目前階段的入口。只在教學進行中、已經有入口快照時出現。不影響 F6 的存檔。
- **Skip Tutorial**：打開內門，教學紀錄標為 Skipped。倉庫的東西照樣可以用，車還是要修好才開得走。
- 教學完成或略過後，終端解鎖說明書：一份可以搜尋的操作參考，之後整局都能右鍵拿在手上讀。

### 單間車庫

- 按牆上的按鈕開門，不需要教學。世界還沒準備好或玩家正在其他操作中時，按鈕只會顯示原因。
- 車庫裡有固定的起始物資：工作台、拆解機、手電筒、手槍與兩盒彈藥、電池、兩罐汽油、油桶、輪胎與六件廢料（`OpeningSiteContent._spawn_starter_actors`）。
- RV 是完整可開的，沒有故障設定。

## 實作契約

### 階段的擁有者

- `StartRun` 是開場階段唯一的擁有者，掛在世界底下，不隨區塊重建或檢查點載入而消失。開場建築重建時用 `bind_shelter` 重新接上大門、按鈕與內門。
- 新局才會把玩家與 RV 放到建築的出生點（`fresh_start`），而且只做一次。
- 怪物生成時向 `register_actor` 報到：準備階段一律停用，啟程後恢復。讀檔搬完物件後要再呼叫一次 `apply_actor_state`。
- 大門或內門還在移動時，`save_block_reason` 會擋下存檔。

### 教學的進度

- `OrientationController` 記錄終端的 ID、原本那輛 RV 的 ID、接待室的三個旗標與目前階段。所有判定都認 ID，不認「場上任何一台終端」或「任何一輛車」。
- 進度只在原生操作真的成功之後記錄：終端要從原本的座上、開機完成後進到背包才算帶走；打開或閱讀介面不算任何進度。
- `OrientationWorkshop` 監聽 RV 與設備的完成訊號（放置、回收、產出、施工、換輪、加油、換電池、修引擎），並核對 ID 與結果才打勾。`step` 只用來決定階段重來的邊界，不授權出庫。
- 內門的開關由 `StartRun.apply_tutorial_gates` 依 `inner_gate_unlocked` 套用。
- 教學只在準備階段、而且不是檢查點的暫存世界時運作（`_active_world`）。

### 階段重來

- `OrientationRecovery` 在進到新的邊界（接待室，或倉庫指南的下一步）後，等世界穩定半秒再拍快照：車停著、玩家不在其他操作中、沒有任何存檔阻擋條件。
- 快照用 `Checkpoint.capture_world` 拍在記憶體裡，不寫檔案；重來時交給 `Checkpoint.load_snapshot`，失敗時目前的世界保持原樣。細節見 [saves](saves.md#場景白名單)。
- 同一個邊界已經有快照時不會被後來的操作蓋掉。接待室的開機做到一半時不會補拍，免得把半完成的狀態當成入口。
- 教學完成或略過時清掉快照。

### 說明書解鎖

`unlock_manual` 要同時改到場上的終端，以及背包、車上庫存、未載入區塊的物品與已保存副本裡的終端紀錄。只改完成狀態，不動終端的 ID、電量與開機紀錄。

### 存檔

- `StartRun.capture` 存階段、內門狀態與教學進度；只接受穩定的階段（準備、啟程、封閉）。
- 教學進度由 `OrientationController.validation_error` 與 `OrientationWorkshop.validation_error` 檢查：版本、欄位、旗標之間的先後關係、ID 不得重複使用。不合格就拒絕整份存檔，沒有升級舊資料的路徑。
- 存檔沒有教學資料時，教學在這一局停用。
- 倉庫的每件備品有固定的 ID。放備品前會先在場上、背包、車上與休眠紀錄裡找這個 ID，找得到就不再放，所以讀檔不會補發。
