# 車載終端作弊、時間與天氣

Godot 4.7.2；沿用目前分支。完整用法見 [README](../../README.md)。

## 行為

- 保留 Ctrl+D 進入 shell、`rvctl` 返回管理頁；`help` 與 Tab 補全包含新指令。
- `cheat true/false` 一次切換三項，也可分別切換 `fuel`、`power`、`materials`。旗標只屬目前 RV，平板重開保留；成功讀檔／新遊戲的新車輛預設關閉，載入失敗保留原世界。沒有新存檔欄位。
- 無限燃油支援空油箱啟動與充電；無限電力支援耗盡的已裝電池，涵蓋終端、設備、待機及照明。正常引擎、可用電池／插槽及設備仍為必要條件。
- 無限材料免數值材料費；實體消耗品、工作時間、容量及輸出空間沿用原規則。實際庫存保持有限，管理頁與 shell 標示 `UNLIMITED`。
- 佇列的既有 `costs` 記錄實際支付額，免費工作為空字典；取消、保存還原與施工失敗退款不依當下作弊旗標。直接出料失敗只退實付電量。
- `time set HH:MM [day]` 使用整分鐘秒數立即更新，不快轉製作或天氣。八種 `weather set` 預設立即套用，保留自然推進、教學暫停及偏行霧規則；現有檢查點仍保存時間與天氣結果。

## 本次自動檢查

- 相關五項核心測試加正式主場景 smoke：**6/6 PASS**，35.30 秒。包含 checkpoint failures、Item persistence、RV engine、resource cycle、structure modules。紀錄：`.godot/test-logs/20261019-180821-080-selected-16748`。
- 頁首排版調整後，補上自然天氣後續選擇與平板關閉／重開保留旗標斷言，最終 resource cycle：**PASS**，2.82 秒。紀錄：`.godot/test-logs/20261019-181155-693-selected-32176`。
- 命令測試透過既有資源流程執行，涵蓋嚴格布林／時間參數、全部天氣預設、讀取／補全不變更資源與 RNG、不同待載入世界的隔離、真實 Ctrl+D 輸入及失去 UI 所有權時拒絕修改。未新增測試程序。

## 本次原生觀察

使用 computer-use 技能選取唯一的 Terminal Cheat Review 遊戲視窗，觀察 Ctrl+D 的空命令列、實際輸入 `cheat true`、`time set 22:15 3`、`weather set storm`、`rvctl` 及 Esc。確認三種 UNLIMITED、右上第 3 天 22:15、立即大雨／大霧，以及退出平板後的夜間暴雨畫面。

最初頁首重複 UNLIMITED 與時鐘重疊，已縮回簡潔數值；最後 1280×720 原生檢查確認時鐘與內容區三項標示均清晰。兩次 review log 無 script errors：`.godot/terminal-cheat-review.log`、`.godot/terminal-cheat-review-final.log`。只關閉本次測試視窗，臨時 fixture 從建立起位於 gitignored `.godot/`，驗證後移除。

原生觀察使用固定車輛的獨立 fixture；正式教學完整旅程、其他視窗尺寸與長途駕駛未在本次重跑。正式主場景就緒及讀檔行為由上述自動檢查覆蓋。
