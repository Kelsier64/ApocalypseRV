# v10 CI 導航發布修正

2026-10-09，Godot 4.7.2；本輪針對目前 `codex/slender-speaker-v10` 工作樹，不覆寫先前驗收結果。

## 失敗來源與重現

[PR CI](https://github.com/Kelsier64/ApocalypseRV/actions/runs/37890891721) 與[分支 CI](https://github.com/Kelsier64/ApocalypseRV/actions/runs/37890871014) 都有三組失敗：integration 的 `test_slender_speaker_world`、slow 的 `test_starting_checkpoint`／`test_starting_shelter`，以及 smoke 的正式世界。完整 artifact 顯示車庫門的後續失敗皆從世界尚未就緒開始，不能當作獨立的門碰撞問題。

以暫時 `override.cfg` 設定 `threading/worker_pool/max_threads=2` 並維持 `--fixed-fps 60` 重現：普通導航已發布，巨人網格已烘焙出 13,422–17,222 個多邊形，但巨人 region iteration 停在 1、map iteration 停在 7，持續未就緒。只延後一個 process frame 能解除初次啟動卡住，卻不足以修正多區塊 checkpoint 準備。

進一步核對 [Godot 4.7.2 區域同步實作](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/navigation_3d/nav_region_3d.cpp) 與[地圖邊界合併實作](https://github.com/godotengine/godot/blob/4.7.2-stable/modules/navigation_3d/3d/nav_map_builder_3d.cpp)：初次空區域同步尚未完成便發布新網格，可能漏掉更新；margin edge connections 另會逐對比較不同區域的開放邊界。依原始碼及本機診斷推論，密集森林與多個相距很遠的區塊讓這個比較成本成為 CI 瓶頸。

這是本機工作池限制重現，並非 GitHub runner 硬體的完整模擬。診斷日誌保留在 `.godot/navigation-startup-2workers.log` 及 `.godot/navigation-staging-*.log`，不提交。

## 修改

- 烘焙資源與作用中的導航區域分離，等待初次區域同步後才發布完成的網格；巨人查詢只在 map／iteration 改變時重試。
- 巨人 AABB 的南北邊界對齊全世界同一個 0.275 m voxel grid，保留 2.2 m border、15 m 高度及 1.1 m 半徑。戶外 chunk 使用對齊邊界直接合併，避免森林開放邊界的全量 margin 配對；其他 POI／室內導航區域沿用原設定。
- 世界就緒觀察改用具生命週期的 signal callback，避免啟動取消後恢復已釋放世界的 coroutine；保留導航完成及跨物理影格的就緒條件。
- 避難所測試在世界就緒失敗時清理並退出，保留原有開門、阻擋、關門與永久封閉檢查。
- 完整套件另找到 `test_bunker_extraction` 的時序問題：POI 返回完成時，戶外 streaming 仍可能建構新區塊。存檔前等待原有 `generator_idle` 條件；存檔被拒絕時立即退出，避免舊存檔讓後續重載檢查誤判。貨物、耐久、安裝、使用與重返檢查維持不變。
- runner 超時自測用 `Start-Sleep` 取代 ping；CI 的 quick job 分別執行 Windows PowerShell 5.1 與 PowerShell Core 契約自測。

沒有延長測試期限、降低導航精度或移除有效情境。引擎版本、生成版本及 checkpoint 格式維持原契約。

## 本輪驗證

Windows PowerShell 5.1 與 PowerShell Core runner 自測各通過 82 項斷言。原始 full 檢查在診斷前已完成 27 項（含匯入），全部通過；為優先重現 CI 問題而停止，不能稱為 full 通過。

限制為兩個 worker 的最後兩輪回歸全部通過：

| 檢查 | 耗時 |
| --- | ---: |
| `test_slender_speaker_world` | 14.87 s |
| `test_starting_checkpoint` | 21.63 s |
| `test_outdoor_gas_station` | 19.85 s |
| `test_world_generation` | 2.82 s |
| 正式世界 smoke | 6.35 s |
| `test_checkpoint_failures` | 10.68 s |
| `test_starting_shelter` | 6.91 s |

其中巨人世界涵蓋實際 checkpoint 重載、道路接縫、八條合法森林接縫、樹木重烘焙及卸載後回訪；新增啟動取消、移出樹與重新進入的回歸。日誌位於 `.godot/test-logs/20261009-153056-657-selected-34784` 及 `20261009-153214-319-selected-23692`。暫時 `override.cfg` 已移除。受限工作池啟動仍出現 Jolt maximum-jobs warning，本輪未修正這個獨立引擎警告；這些檢查沒有 script error 或 readiness timeout。

完整套件選取 130 項（含正式世界 smoke），加上匯入共 131 個結果，688.14 s 完成。匯入及 129 項檢查通過；唯一失敗是本輪新發現的 `test_bunker_extraction` 返回戶外後立即存檔競態。該輪執行中修正的只有此測試 fixture，其他正式程式碼未再變更；修正後單獨重跑通過，11.53 s。這是完整範圍加失敗項重跑的驗證，並非第二輪全套皆綠的執行紀錄。

地堡另在兩個 worker 下重跑通過，11.44 s；暫時設定透過 `finally` 清理，確認 `override.cfg` 不存在。合計八項受限工作池回歸均通過。

完整套件日誌：`.godot/test-logs/20261009-153547-062-full-16456`；地堡修正後重跑：`.godot/test-logs/20261009-154736-790-selected-6360`；地堡受限工作池重跑：`.godot/test-logs/20261009-154820-987-selected-21232`。`git diff --check` 及變更文件的相對連結檢查通過。

本輪未進行原生視窗或實機遊玩，沒有重新驗收 wheel-driven handling、翻車或群怪。GitHub 的修正後狀態仍須由交付後 CI 確認。
