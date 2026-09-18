# ApocalypseRV 專案審查與修改建議

日期：2026-09-18（Asia/Taipei）  
目標：`Kelsier64/ApocalypseRV` 的 `main` 公開內容  
審查性質：關鍵程式碼靜態審查＋文件交叉核對＋修改／驗收計畫  
版本識別限制：本次未取得 commit SHA，這不是針對不可變提交的全庫認證。

## 0. 範圍、證據與限制

本次直接讀到並核對的完整實作／設定：

| 檔案 | 本次檢查內容 |
|---|---|
| `project.godot` | 主場景、引擎功能標記、autoload、輸入與物理設定 |
| `scripts/test.ps1` | 測試發現、逾時、錯誤日誌、PASS 判定、主場景 smoke test |
| `rv/checkpoint.gd` | 磁碟寫入、格式驗證、升級、世界保存與還原 |
| `rv/vehicle_snapshot.gd` | 車輛與設備快照、支撐關係驗證、設備重建、版本轉換 |
| `world/instances/poi_instance_manager.gd` | 室內外轉場、玩家移轉、輸入轉送與副本狀態 |

另讀取 repository 首頁／README 與 `architecture.md` 的可取得內容。世界生成、AI、能源、製作、放置及美術的全貌主要來自架構文件，**不能視為這些實作已逐行驗證**。[S1][S2]

完整 checkout／ZIP 下載未成功；後續部分 GitHub 與 raw 頁面讀取失敗。執行環境也沒有 `godot`、`godot4` 或 `pwsh`。因此未完成引擎匯入、編譯、實際遊玩、測試執行、GPU 效能量測、全庫搜尋、工作流程 YAML／最新 CI 結果核對與資產授權盤點。`GDD.md`、各 `tests/test_*.gd`、shader 與多個核心模組未成功取得，不從檔名推定內容。

下文的「已確認」是指**看得到的程式結構或驗證缺口**；不是宣稱已在遊戲中重現。重現與故障注入步驟都是待執行的驗收方案。函式名稱是定位主依據；行號依本次 raw 內容換算為一般編輯器的一起算行號，後續提交可能移動。

## 1. 整體判斷

**保留目前主要架構，不建議推倒重寫。下一個里程碑應是「穩定、可驗證的單人遊玩流程」，不是再擴張一批跨模組功能。**

README 將專案定位為單人末日 RV 生存沙盒；合作玩法、任務與正式長局進度尚不屬於完成項目。玩法主軸是駕車、探索、搬運、回收、製作與車輛維護。[S1]

已核對的程式顯示一些值得保留的工程習慣：獨立測試入口、保存版本、設備支撐圖檢查、車輛還原前先暫建設備、獨立室內 World3D。這些不是只有文件命名而沒有任何實作的外殼。[S4][S6][S7]

但可靠性目前有不對稱：局部操作已有保護，世界級還原與跨模組轉場卻沒有同等完整的失敗處理。建議優先把這些交界補齊。

### 優先級定義

P1：先修；可能造成不完整還原、資料／執行環境可信度問題。  
P2：下一輪修；失敗恢復、測試防線、可維護性與使用者診斷。  
P3：後續產品化與擴充。

本次沒有證實「正常遊玩必然觸發的 P0 致命缺陷」。這不代表全庫沒有 P0，而是本次沒有足夠證據支持該結論。

## 2. 架構地圖與評估

| 層級 | 文件／程式反映的責任 | 建議 |
|---|---|---|
| Player | 移動、互動、背包、UI 與座位／放置模式 | 保留玩家作為協調者，但透過公開方法管理轉場與恢復 |
| RV／Equipment | 車輛、能源、庫存、設備支撐、維修及工作 | 保留現有分工；將跨物件交易與設備保存契約收斂 |
| World | 地形串流、POI 入口、室內副本、動態物件容器 | 分清世界生命週期、遊戲邏輯與畫面呈現 |
| Persistence | 保存版本、migration、快照、磁碟存讀 | 區分資料驗證、資源解析、世界重建與提交 |
| Verification | headless runner、行為測試與視覺 playground | 分清自動測試、展示回放、正式遊玩及效能證據 |

上表的廣泛模組分工依架構文件；Persistence、runner 與副本管理器則有直接實作交叉核對。[S2][S4][S5][S6][S7]

「有 `core/`」不等於已經低耦合。更實際的判準是：新增一種設備，是否需要修改中央保存器；修改玩家模式，是否需要同步修改多個轉場呼叫者；還原失敗時，是否每個模組都能得到一致的結果。這些應成為後續重構的判斷基準，而不是先追求資料夾數量或設計模式名稱。

## 3. 主要發現

### R01｜P1：世界還原忽略車輛套用失敗，且缺少整體回復策略

**定位**：`rv/checkpoint.gd::restore_world()`，約 L144–194；`rv/vehicle_snapshot.gd::apply()`，約 L130–188。

**證據**：世界還原會先清掉舊 actors，再建立新車並呼叫 `VehicleSnapshot.apply()`，但未處理它的 bool 回傳值。後者在場景無法成為 Equipment 時確實可能回傳 false。[S5][S6]

**風險推論**：若某台車套用失敗，流程可能繼續處理後續物件並到達成功提示；若中途發生腳本錯誤，也沒有一致的恢復出口。這是「載入失敗如何處置」的問題，不是已證明正常存檔一定載入失敗。

**建議修改**：

1. 第一個小 PR 先檢查每次套用的結果；失敗停止、保留診斷，不再走成功分支。
2. 讓世界還原回傳結構化結果，包括失敗的 vehicle／actor ID 與階段。
3. 下一個 PR 才導入世界級的準備與切換：先解析、驗證、暫建，再切換正式世界；舊世界直到新世界成功才釋放，或提供清楚的 rollback。
4. 不要以為只加 `if not apply(): return` 就完成修復：舊世界可能早已刪除，玩家物理也可能尚未恢復。
5. 暫建區須隔離物理、群組查找及服務副作用；單純停用 process 並不能取代生命週期設計。

**驗收**：在第二台車的套用處注入失敗；不得顯示成功、留下半套物件或永久鎖住玩家。使用者應保有舊世界，或收到可操作的安全恢復畫面。檢查來源存檔未被改寫。

### R02｜P1：資源存在，不等於場景類別正確

**定位**：`checkpoint.gd::read_checkpoint()`／`restore_world()`；`vehicle_snapshot.gd::validate()`／`valid_item()`／`valid_prop_state()`。

**證據**：若干讀檔分支只檢查資源存在；loose actor 還原直接 instantiate，並按實際類型取用狀態。車載設備雖在 apply 階段有 Equipment 轉型檢查，讀檔預檢仍不充分。[S5][S6]

`ResourceLoader.exists()` 回答的是資源是否可識別且存在，不保證它是預期的 PackedScene，更不保證其根節點是 Prop、Equipment 或 Monster。[S8][S9]

**風險推論**：錯誤版本、資源搬移後不一致或被修改的存檔，可能直到開始重建世界才失敗；也可能讓保存的 `kind` 與實際場景類型不一致。

**建議修改**：建立由程式掌握的 scene catalog，保存穩定 type ID，或至少以允許清單解析原有 scene path；預檢 PackedScene 與預期根節點類別。未知資源必須在破壞目前世界前被拒絕。不要只是加一個副檔名 `.tscn` 判斷。

**驗收**：測試存在但非場景的資源、Prop 場景被標成 Monster、非 Equipment 的場景被放進設備列表，以及舊版本已搬移的資源。都應明確拒絕或經過指定 migration，不能靜默變成另一種物件。

**界線**：這裡首先是本機存檔健全性問題，不能據此宣稱存在已驗證的遠端程式執行漏洞。現有 `get_var(false)` 選擇值得保留；禁止反序列化 Object 與限制後續載入哪些資源，是不同的防線。[S10]

### R03｜P2：完整資料結構與值域驗證尚未一致

**定位**：`checkpoint.gd::read_checkpoint()`／`prepare_world()`；`vehicle_snapshot.gd::validate()`。

**證據**：可見分支未完整檢查 POI 巢狀資料、profile 欄位型別與值域、玩家選取槽範圍、所有物理子欄位；變換及速度多處只驗證型別。部分其他數值已有有限值檢查，因此不是完全沒有 validation。[S5][S6]

**建議修改**：集中一份 schema 規範與 validator，涵蓋頂層、玩家、世界 profile、POI、物品、設備與工作。所有要進入物理世界的變換／速度應為有限值；需要求逆的 basis 還應可逆。Godot 提供 `Transform3D.is_finite()`；它不會替你檢查遊戲座標範圍或矩陣可逆性。[S11]

對選取槽應明訂空背包時的合法值；對庫存容量則須保留既有 migration 允許的溢出契約，不能用粗暴 clamp 偷刪玩家資源。對 profile 不合法輸入應拒絕或明確 migration，避免默默改值後破壞 seed 重現語義。

加入檔案大小與集合數量的合理上限，並提供欄位路徑式錯誤，例如 `actors[3].physics.linear`，而不是只有 false。不要在未量測前寫任意非常小的上限，使正常長局存檔不能讀取。

**驗收**：負向 fixtures 覆蓋 NaN／Infinity、不可逆變換、錯型 profile、越界 slot、殘缺 physics、錯型 POI actor，以及合法的舊版超額資源。壞資料應在正式還原前被拒絕；合法 legacy 資料仍可保留。

### R04｜P1（對外測試前）：版本來源不一致

**定位**：`project.godot` 約 L15；README 啟動說明；`architecture.md` 執行環境章節。

**證據**：專案功能標記為 4.7；文件指定開發／CI 4.6.1，另記錄部分本機測試使用 4.7.2。文件也承認尚未證明跨版本一致。[S1][S2][S3]

**注意**：本次未讀到 workflow YAML／CI 結果，因此「CI 是 4.6.1」是文件記載，不是本次查核已運行的 runner。本次也沒有獨立驗證文件提及之每個版本的發布狀態。不應把功能標記當成必然不能在舊版開啟的證據。

**建議修改**：選定團隊實際驗證的一版，統一本機說明、測試、CI、匯出模板與發行資訊；runner 啟動時輸出且檢查 `godot --version`。若確實維護兩版，才建立兩版的 CI matrix，不要留下只靠口頭相容的狀態。[S12]

**驗收**：乾淨 checkout、移除匯入快取後，指定版本可匯入、跑測試、啟動及匯出。測試紀錄需附 commit SHA、完整引擎版本、作業系統與渲染方式。

### R05｜P2／待故障注入：轉場沒有明確取消與失敗出口

**定位**：`world/instances/poi_instance_manager.gd::enter()`／`leave()`，約 L41–95。

**證據**：管理器有 busy 防重入，但在設定轉場狀態後等待 build，未在這一層看到 build 成敗結果、逾時或取消統一處理。[S7]

**風險推論**：若 build 發生錯誤、永不完成或轉場期間世界重載，狀態清理可能不完整。這不是已重現的「必然卡死」，且本次未讀到 `PoiInterior.build()` 的完整實作。

**建議修改**：把 busy 改為可觀察的狀態（OUTDOOR／ENTERING／INDOOR／LEAVING／FAILED）；增加操作序號作取消 token。每次 await 回來核對操作仍有效、節點仍存在，並把成功／失敗／取消都導向統一清理方法。build 應回傳結果或發出成功／失敗訊號，不能只靠等待結束當作成功。

**驗收**：進出各連按多次、載入中重載世界、建立失敗、逾時、轉場時玩家死亡、出口被動態物件阻塞。不得留下殘存 SubViewport、重複玩家、錯誤輸入接收者或永久 busy。

### R06｜P2：測試入口有基礎，但缺少兩個明確防線

**定位**：`scripts/test.ps1` 約 L27–35。

**證據**：runner 逐一找頂層 `test_*.gd`，但沒有「發現零測試就失敗」的檢查；最後 main-scene 以 `--quit-after 120` 結束，沒有要求場景完成訊號。[S4]

這不表示現有測試全部沒用，也不能據此認定其他測試沒有覆蓋世界就緒。精確結論是：**該 runner 與最後的 smoke step 自身缺少上述保證。** `--quit-after` 限制的是迭代數，不是語義上的世界生成完成；`--fixed-fps` 也不等同跨機器物理完全決定性。[S12]

**建議修改**：收集測試清單後印出數量，零測試直接非零退出；明訂是否支援子目錄，對照實際清單防止不小心少跑。新增正式世界 `ready_for_play` 的測試契約，確認地形、導航與玩家準備好後，進行一段操作，再輸出專屬成功標記。保留目前 exit code、錯誤日誌與每支測試 PASS 檢查，不必先全面換測試框架。

**驗收**：對 discovery 注入無匹配規則時必須失敗；對世界就緒注入延遲與永不就緒狀態時，不得因為迭代數到了而被當成通過。實際測試名稱與新規則要保留在 CI artifact。

### R07｜P2：磁碟保存失敗的使用者訊息不準確

**定位**：`checkpoint.gd::_unhandled_input()`／`write_checkpoint()`，約 L18–34、L85–95。

**證據**：儲存回傳 false 一律使用遊玩狀態限制的提示；但寫檔／rename 失敗也會回傳 false。[S5]

**風險**：遇到權限、磁碟或檔案鎖定問題，玩家可能被誤導成只要等地形完成或離開互動就能保存。

**建議修改**：回傳可辨識的錯誤碼，至少分開狀態不允許、開檔失敗、寫入失敗、rename 失敗、版本不支援及資料不合法。UI 給可操作訊息，詳細 path／engine error 留在日誌。官方 FileAccess 提供開檔與 I/O 錯誤查詢。[S10]

保留現有 `.tmp` 寫入再替換的方向；另外加入上一次有效檔的備份、失敗清理與讀回驗證。不能只因為用了 rename 就宣稱所有 OS／斷電情境都已安全驗證。

**驗收**：用受控檔案操作替身注入開檔、寫入、rename 失敗；確認每個訊息正確且上一份有效檔仍在。不要用真的塞滿使用者硬碟來做測試。

## 4. 漸進重構建議

### 4.1 玩家狀態應有一個公開入口

可見的副本與保存器會直接設定玩家多個內部狀態，保存器也直接要求玩家更新內部 UI。這使呼叫者必須知道玩家新增的每一個旗標。[S5][S7]

建議逐步新增 `begin_transition()`、`complete_transition()`、`capture_state()`、`restore_state()` 等公開契約；以上是提議的新 API，不是宣稱目前已存在。玩家自己恢復生命、背包、攀爬、攝影機與輸入模式，外部不逐欄操作。

### 4.2 設備自己提供 service 保存／驗證契約

VehicleSnapshot 現在認識多種設備的特殊狀態與工作資料。[S6] 建議先挑一種設備，把 service 的 capture／validate／restore 收進該設備對應 codec。中央保存器仍負責版本、ID、支撐圖與總體重建順序。

不要在同一 PR 改掉所有設備、存檔格式、場景檔與命名。也不需要立即改 ECS、拆出幾十個 manager 或整套改成 C++。重構的驗收標準應是減少改動面、保留行為、讓錯誤更容易測到。

### 4.3 將測試／展示／正式流程分清楚

文件本身已提醒回放與實際遊玩並不完全相同。[S1] 建議測試產物記錄：使用哪些正式流程、哪些捷徑、哪些耗損被停用、是否真的使用物理車輪。這樣自動駕駛展示就不會被拿來證明資源經濟或完整生存難度已調平。

## 5. 建議補強的驗收矩陣

以下是待建立或核對的測試需求，**不是斷言 repo 現在沒有這些測試**。先檢查既有 suite，再補缺口，避免重複新增。

| 範圍 | 測試情境 | 成功條件 |
|---|---|---|
| Restore failure | 第二台車或某件設備重建失敗 | 不假成功、不留半套世界，清楚恢復 |
| Scene contract | 非場景資源、錯 root type、kind 不匹配 | 正式世界變動前拒絕 |
| Data schema | NaN、錯型 profile、壞 slot、殘缺 physics／POI | 不將壞值送進物理與生成器 |
| Migration | v1／v2／v3 fixtures，空引擎槽、舊版溢出資源 | 已定義轉換正確，來源檔不被讀取覆寫 |
| Round trip | 製作一半、電池非滿電、設備已拆、門角度改變 | capture→write→read→restore 保留合法狀態 |
| Transaction | 拆工作站、掉支撐、停電、取消與滿倉 | 材料／物品不重複退款、不憑空生成或消失 |
| POI | 進出途中失敗／重載，回訪已搜刮房間 | 玩家與 UI 唯一，已消耗狀態不復活 |
| Streaming | 固定 seed、邊界、已訪 POI 與舊 generation version | 入口與碰撞一致，遵守已聲明回收規則 |
| Runner | 零匹配、測試失敗、timeout、錯誤日誌 | 真正失敗，產出清楚的測試清單 |
| Export | 乾淨匯出後啟動與存讀檔 | 不只在 editor 中成功 |

測試共用不變量應清楚：道具的同一 ID 不會同時屬於背包、世界與工作站；材料變化可由已完成交易解釋；取消不會重複退款；同一玩家只有一個有效控制模式。不能只驗證最後畫面「看起來還行」。

## 6. 效能、玩法與發行

### 效能：尚未量測，不下 FPS 結論

架構文件描述植被分區、MultiMesh、串流、導航烘焙及體積霧。[S2] 這些只是量測重點，不是「已證明效能差」的證據。

建議固定 seed 與操作路線，記錄初次進入、行駛生成新區塊、進副本、回室外與反覆切換後的 CPU／GPU frame time、p95／p99、記憶體、物件數、區塊數及導航成本。冷啟動與暖快取分開；有 GPU 的 Forward+ 與 Compatibility 各自驗收，不能用 headless 結果代替畫面檢查。

先建立瓶頸證據，再決定減少植被、調整導航精度、限制霧的範圍或分攤生成時間。不要一次把所有品質項目調低而不知道問題出在哪。

### 玩法：先完成有意義的一個循環

README 的目前限制包含無正式任務／勝敗、死亡恢復與單向地形回收。[S1] 這些是原型的設計範圍，不應被包裝成程式 bug。

建議下一個可玩里程碑明確描述：玩家知道要去哪裡、為何下車、取得什麼、如何帶回、如何讓車繼續前進，以及失敗怎麼處置。先驗收一次完整循環，再擴展更多房型、車體或敵人。

重要操作應在遊戲內逐步提示，不只存在 README。把暫停、返回／繼續、保存成功與失败原因、基本音量／滑鼠靈敏度列為產品化工作；是否暫停整個世界要明確定義，未來多人不能沿用單機假設。

### 發行與協作

對外發行前確認匯出設定、發行包內容、第三方素材來源與授權清單、測試版本及已知限制。本次未完成資產／授權盤點，不宣稱缺失或合規。

每個 PR 只解一個問題，附復現條件、修改範圍、測試與不支援情境。共享 `.tscn`、`project.godot` 與核心保存器的改動集中整合，避免多個人／AI agent 同時做跨模組大改。原始碼衝突少不代表資料契約沒有衝突。

## 7. 多人連線的專項評估

目前文件定位是單人，不能把「尚無多人」當成未履行的現成功能。[S1]

若團隊決定做合作，建議先定義主機權威：誰判定撿取成功、誰扣材料、誰擁有車輛物理、誰結算怪物傷害。Godot 高階多人 API 支援 authority、RPC、傳輸模式及 sender 身分，但不會替遊戲設計資源所有權與交易規則。[S13]

建議用極小原型驗證：兩個玩家、一台 RV、一件地面物品。兩人同時撿取只能成功一人；只能有一個駕駛；扣料只能結算一次。然後才加入移動車內站立、斷線與進出副本。

`PoiInstanceManager` 的單一 `_player`／`active_id`／viewport 是本機單人控制結構。[S7] 每個 client 仍只有一個畫面並沒有錯；問題是不要把它直接當成全體玩家的共享世界狀態。多人需分開每位玩家所處的邏輯實例與各 client 的呈現，允許一人留在戶外、另一人在室內。

固定 seed 可以減少某些生成資料傳輸，但不等於各機器的物理與 AI 會自動一致。不要把現有世界變成「每個 client 各跑一份，期待結果相同」。

## 8. 建議提交順序

| 階段 | 提交內容 | 驗收重點 |
|---|---|---|
| A | 固定 commit 與實際引擎基線、整理 runner 證據 | 乾淨環境可重現 |
| B | 測試 discovery guard、正式世界就緒 smoke | 測試自身能正確失敗 |
| C | 補 R01／R02 負向測試與錯誤回傳 | 不忽略失敗、不假成功 |
| D | 資源 catalog／完整 schema 與磁碟錯誤區分 | 壞檔不進正式世界 |
| E | 世界級還原 rollback、轉場取消與清理 | 中斷仍可恢復 |
| F | 玩家與設備保存契約的小步重構 | 減少跨模組欄位依賴 |
| G | 有 GPU 的遊玩／效能／匯出驗收 | 真正交給他人測試 |

若只有一輪修改預算，優先 A–D。多人、美術大量擴張與更多生產配方不應和這些可靠性修復混在同一批提交。

## 9. 可交給開發者或 AI agent 的工作單

> 先將目前分支固定到 commit SHA，記錄 Godot 版本，不修改任何檔案，列出既有測試入口與執行結果。核對本報告 R01–R07 是否仍符合該 commit。每一項先補失敗測試，再做最小修正；已有覆蓋就引用現有測試，不重複新增。先處理 restore_world 忽略套用結果及場景 type/kind 驗證，不把多人、美術、資料夾重新命名混進來。不得刪除原有版本 migration 或悄悄 clamp 掉合法存量。遇到無法執行測試，明確回報工具／引擎錯誤，不以檔案存在或 PASS 字串代替實際測試。每個提交回報修改檔案、缺陷原因、驗收結果與仍未涵蓋的情境。

這是新建的工作指示，不是已在 repository 執行的修改。

## 10. 結論

這個專案在已核對範圍內，值得繼續，而不是因為複雜就重寫；也不適合因為文件很多就視為可靠性已完成。

最重要的三件事是：**讓讀檔失敗不破壞狀態、讓測試真正證明指定版本的指定場景可用、讓跨模組狀態變化有一致契約。**

本次找到的主要風險集中在保存／還原、轉場與測試入口；未取得的玩家、AI、製作、物理與 shader 實作仍需另行逐檔和執行驗證，不能用本報告替它們背書。

---

## 來源定位

來源均於 2026-09-18 取得。repo 引用指向當時 main 公開內容；本次未取得 SHA，連結日後可能變動。官方 stable 文件也可能更新。

[S1] GitHub repository 首頁與 README：`https://github.com/Kelsier64/ApocalypseRV`

[S2] 架構文件：`https://raw.githubusercontent.com/Kelsier64/ApocalypseRV/main/architecture.md`

[S3] 專案設定：`https://raw.githubusercontent.com/Kelsier64/ApocalypseRV/main/project.godot`

[S4] 測試 runner：`https://raw.githubusercontent.com/Kelsier64/ApocalypseRV/main/scripts/test.ps1`

[S5] 世界檢查點：`https://raw.githubusercontent.com/Kelsier64/ApocalypseRV/main/rv/checkpoint.gd`

[S6] 車輛快照：`https://raw.githubusercontent.com/Kelsier64/ApocalypseRV/main/rv/vehicle_snapshot.gd`

[S7] 副本管理器：`https://raw.githubusercontent.com/Kelsier64/ApocalypseRV/main/world/instances/poi_instance_manager.gd`

[S8] Godot ResourceLoader：`https://docs.godotengine.org/en/stable/classes/class_resourceloader.html`

[S9] Godot PackedScene：`https://docs.godotengine.org/en/stable/classes/class_packedscene.html`

[S10] Godot FileAccess：`https://docs.godotengine.org/en/stable/classes/class_fileaccess.html`

[S11] Godot Transform3D：`https://docs.godotengine.org/en/stable/classes/class_transform3d.html`

[S12] Godot command line：`https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html`

[S13] Godot high-level multiplayer：`https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html`
