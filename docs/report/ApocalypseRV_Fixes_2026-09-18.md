# R01–R07 修正與驗收

對照報告：`ApocalypseRV_Review_2026-09-18.md`。原報告保留不改。

起始 commit：`377dfdb32e102e0e7c8d4f02fc74dd40f611e163`。以下驗證對象為此 commit 加上本次工作目錄修改，尚未建立提交。

## 修正對照

| 項目 | 修改後行為 | 驗證入口 |
|---|---|---|
| R01 | F9 先驗證，再於獨立 World3D 重建完整候選世界；暫停原世界的邏輯與物理，只有就緒及所有車輛成功套用後才提交。失敗、就緒逾時保留原世界。回傳錯誤階段與車輛 ID。 | `test_checkpoint_failures.gd`：第二台車失敗、世界就緒逾時、失敗後再次成功；`test_rv_checkpoint.gd`：電池、引擎、製作、回收輸入 round trip |
| R02 | `SaveSceneCatalog` 只接受明列的玩法場景，並確認 PackedScene 與根類別。玩家物品、車載／地面設備、怪物與 POI 都使用同一契約。 | 錯場景、非場景資源、kind 不符與非 Equipment 場景負向測試 |
| R03 | 驗證有限／可逆變換、有限速度、物理欄位型別、profile 範圍／關係、POI 巢狀內容、設備 service、背包槽與版本；錯誤帶欄位路徑。 | 非有限值、奇異矩陣、錯型 profile、越界 slot、殘缺 physics／POI／service；既有 migration 與 overflow 測試 |
| R04 | `.godot-version` 固定 4.7.2 stable，README、架構文件、AGENTS 與 CI 一致；runner 拒絕版本不符並保存完整版本、commit、工作目錄狀態、OS、渲染方式及測試清單。 | 實際引擎 `4.7.2.stable.official.ed1daf0bf`；不符版本注入測試 |
| R05 | 明確的 OUTDOOR／ENTERING／INDOOR／LEAVING／FAILED 狀態、操作序號取消、建立成功結果、60 秒逾時與共用清理。失敗恢復玩家控制；原生導航烘焙完成後才釋放其節點。 | 建立失敗、永不完成、取消、連按、死亡；既有正式進出、副本回訪與導航測試 |
| R06 | 頂層 test discovery 列出數量，零測試即失敗。主場景必須確認地形／導航同步／玩家就緒並實際移動，才輸出專屬成功標記；不再以 120 frames 當通過。 | 零測試注入、never-ready 逾時、`main_scene_smoke.gd` |
| R07 | 分開狀態限制、開檔、寫入、備份、替換、格式與版本錯誤。先寫 `.tmp`、讀回比對，再備份上一份有效檔為 `.bak` 並替換；失敗清理暫存。 | 受控開檔／寫入／備份／rename 失敗與內容損壞，確認原檔未變 |

## 相容性與維護契約

- 保留存檔版本 3 與既有 v1／v2 migration。migration 在記憶體進行，不覆寫來源。
- 庫存容量不是驗證上限；合法 legacy 超額材料不會被 clamp。選取槽維持既有 0–5 hotbar 語義，空槽也合法。
- 解碼上限為 256 MiB；巢狀結構最多 32 層、1,000,000 個值，活動 bands 最多 256。這些是防止失控分配的安全上限，並非長局容量／效能承諾。
- 增加可保存場景時，需要更新 `core/save_scene_catalog.gd`。搬移既有場景應增加 migration，不接受任意存檔路徑。
- `WorldEntities.transfer()` 將完整 hierarchy 移至另一個 World3D 時，暫時抑制設備拆除、退款與掉落回呼，保留支撐關係及設備登記。一般拆除仍走原流程。
- 玩家轉場與 checkpoint 恢復改走玩家的公開方法。世界時鐘繼承所屬世界的處理狀態，避免 staging 或 rollback 期間偷跑時間。
- 就緒檢查不跨 await 保留可能被 streaming 回收的導航節點。

## 執行環境與驗證

Windows 11（10.0.26200），Godot 4.7.2 stable official，headless／dummy renderer。

本機 Godot 原本不在 PATH，且沙箱不允許寫入使用者的 editor settings。驗證使用同一安裝版本複製到 `.godot/runtime/` 並啟用 self-contained mode；不修改使用者編輯器設定。

```powershell
./scripts/test.ps1 -Godot "$PWD/.godot/runtime/Godot_console.exe"
```

結果：35 個 `test_*.gd` 套件均通過。完整執行過程中發現的問題修正後，重跑受影響套件；最後補跑 `test_rv_s*.gd`、`test_world*.gd` 與完整 checkpoint 故障套件。不是宣稱一次從頭到尾零失敗的執行。最新 35 份套件日誌已逐一檢查成功標記、更新時間與錯誤，彙總為 `.godot/test-logs/verification-summary.txt`。

主場景 `WORLD_READY_FOR_PLAY` 與水平移動檢查通過；另在 `.godot/clean-review-20260918/` 的無匯入快取來源副本完成匯入與主場景檢查。零測試 discovery 與錯誤引擎版本注入均按預期失敗。`git diff --check` 通過。

日誌與各次執行 manifest 在 `.godot/test-logs/`；最新故障注入日誌為 `.godot/final-checkpoint-failures.log`，乾淨環境日誌為 `.godot/clean-review-import.log` 與 `.godot/clean-review-smoke.log`。runner 只忽略環境既有的 `Failed to read the root certificate store` 訊息，不忽略 script/runtime errors。

## 邊界

本次是可靠性修正與 headless 行為驗證；沒有把它當作 GPU 畫面、幀時間、極端翻車、怪物群、正式發行匯出包或斷電安全的驗收。遠端 GitHub Actions 的 YAML 已更新，遠端執行結果仍需推送後取得。原報告中的多人、玩法里程碑與美術擴充屬後續產品工作，未混入本次修正。

官方版本來源：[Godot 4.7.2 release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable)。
