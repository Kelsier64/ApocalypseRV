# 樹木撞毀與房車受傷驗收

日期：2026-10-02。引擎：Godot 4.7.2 stable；正式圖形：Forward+／Vulkan，RTX 4060 Laptop。這份紀錄只描述本輪檢查。

## 行為

實際底盤接觸樹幹、朝碰撞法線內的速度達 3 m/s 時，撞毀一棵樹並扣一次引擎耐久。傷害為速度平方 × 0.25、限制 3–80 HP；低速、離開樹幹、垂直落地不觸發。森林共用碰撞體與 MultiMesh 保留，只停用被撞中的 shape／instance。短暫倒樹外觀無碰撞，隨後移除；沒有木材掉落。

世界帳本與森林位置快取分開，串流重建及 checkpoint 保留破壞，舊檔缺欄位仍可載入。導航合併重烘焙，沿用原 region，更新鄰帶接縫及可被淘汰的位置快取。

## 自動檢查

以下七個不同檢查於本輪通過，屬多次相關範圍執行，沒有跑 full：

- test_tree_impact：三個車輛朝向的真實物理撞擊、單樹破壞、重複接觸不重扣、低速／反向／垂直拒絕、舊版活樹／枯樹、導航可通行中心、region 重用、磁碟 checkpoint、破壞資料驗證、森林與路邊樹重新生成、存活樹位置／外觀 RNG 保留。
- test_streaming_generation：分批與立即生成仍保留一致森林碰撞和地形。
- test_rv_engine：既有引擎故障、維修與更換。
- test_rv_checkpoint：既有車輛保存還原。
- test_rv_physics_regression：原車輛穩定及設備安裝。
- test_moving_rv_climbing：既有移動房車攀爬／支撐回歸。
- main-scene smoke：正式主世界就緒與移動。

最後匯入／撞樹批次：`.godot/test-logs/20261002-022650-252-selected-27472/`（兩項 PASS）。headless 撞樹／攀爬批次：`.godot/test-logs/20261002-022334-336-selected-22268/`。正式主世界及車輛保存批次：`.godot/test-logs/20261002-021355-219-selected-32016/`。日誌為本機忽略產物，未納入版控。

首次 sandbox 匯入完成資源掃描，但因無法寫入使用者 Godot editor_settings 而未通過 runner；後續使用專案內 `.godot/test-appdata` 作為測試 APPDATA，並沿用已匯入資源執行；最後重新匯入已通過。沒有修改使用者編輯器設定。

## 實機觀察

使用 [撞樹測試場](../guides/playgrounds.md#tree-impact)，透過 computer-use 選取唯一遊戲視窗並按 F6。正式輪驅撞到前方樹，畫面顯示撞毀 1 棵；引擎耐久從 450 降到 435.48，旁邊樹仍完整，房車撞後煞停。日誌 `.godot/tree-impact-playground.log` 記錄 TREE_REPLAY。最初 TREE_VISUAL 在 deferred 破壞執行前讀取，產生 hidden=false 的過早取樣；已移至 deferred 觀察。

另以非 headless、Forward+／Vulkan 執行 test_tree_impact.gd，日誌 `.godot/tree-impact-gpu.log` 有 PASS 且無 script error。這次涵蓋三個車輛朝向的 GPU MultiMesh 單棵隱藏斷言；headless 批次會跳過此 GPU readback 檢查。

另依 AGENTS 開啟 rv_climb_playground 回放，觀察玩家／怪物均進入 CLIMBING；debug 回放 3–6 秒兩者都在車頂（局部 y 約 2.45），車輛持續轉彎。之後 roof HP 達 DESTROYED，怪物落到車內 ItemBox 支撐（局部 y 約 0.85）。玩家被抓時按 F5 未完成乾淨的手動入座驗收；帶 --seat-after-climb 的回放也出現玩家死亡／重生，因此這段不算完整的手動操作通過。攀爬測試場及角色邏輯未修改。所有本輪互動測試視窗已關閉，原 Godot 編輯器保留。

## 範圍限制

沒有驗證密集連撞效能、翻車、外掛設備先碰樹的力矩，或長途引擎耐久平衡。撞樹測試場使用平地；導航與保存由自動測試驗證。headless dummy renderer 無法讀取真實 GPU MultiMesh transform，GPU 外觀另以可見遊戲與圖形回歸檢查。
