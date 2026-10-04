# 屍體搬運與分解

日期：2026-10-04。引擎：Godot 4.7.2／Jolt／60 Hz。沿用現有角色模型及物理骨，沒有新建或替換美術資產。

## 行為

- 怪物死亡後，正在模擬的完整骨架轉交獨立 `CorpseProp`，不重播或重設致命撞擊動量。原怪物控制節點的 18 秒清理不會帶走屍體。
- 玩家確認安全復活位置後，先擷取死亡骨姿勢與缺肢狀態，再留下玩家屍體、恢復玩家本體。受阻的復活重試不產生重複屍體。
- E 拾取軀幹、G 丟棄。需要雙手，遵循六格背包及最多一件大型物品的限制。手持只驅動骨盆，四肢繼續使用關節／重力模擬；丟棄從目前手持姿勢繼續落下。
- 分解機料斗會偵測屍體代理；處理時停止全部物理骨。取消處理恢復物理，材料入庫成功後才刪除。每具回收 Unknown Material 2–4 與 Unrefined Fuel 1–2。
- `state.corpse` 保存物種類型、部位完整性、相對框架及骨姿勢，沿用 Prop 的背包、倉庫、世界、副本與分解輸入保存路徑。存檔拒絕非法拓樸、非有限變換及把屍體偽裝為小物品的狀態。

## 初版實作歷史驗收

以下自動測試與桌面觀察記錄初版實作，不代表後續手持支撐修正已完成視覺或回歸驗收。初版採手持關節／重力模擬，曾觀察到身體拉伸與高度不正確；現行修正內容及待補驗證另見下節。

新增 [test_corpse.gd](../../tests/test_corpse.gd)，歸 integration。涵蓋死亡轉交、舊控制節點回收後持續存在、正式射線遮罩、拾取／大型限制、手持關節穩定與晃動、原姿勢丟棄、重新定位讀檔、非法姿勢拒絕、料斗真實 body_entered、分解輸入快照還原、分解中恢復／取消／完成、玩家缺肢屍體與手持轉場重建。

手持移動測量：90 個物理步，最大關節分離約 0.0077 m、最大骨速度約 5.69 m/s，前臂相對骨盆位置改變約 0.92 m。這是單一受控情境，並非所有搬運速度的上限。

下列 12 支不同測試在本輪通過；修正後重跑受影響子集，沒有將舊驗收結果當成本輪結果：

`test_corpse`、`test_player_inventory`、`test_player_carry`、`test_player_death`、`test_player_dismemberment`、`test_player_head_camera`、`test_raker`、`test_raker_ragdoll`、`test_rv_systems`、`test_rv_resource_cycle`、`test_rv_checkpoint`、`test_poi_transition_persistence`。

日誌位於 `.godot/test-logs/20261004-134909-018-selected-20872/`、`20261004-134923-196-selected-8364/`、`20261004-135710-451-selected-35236/`；補齊分解輸入快照案例後的屍體測試為 `20261004-140359-067-selected-7988/`。受限環境的 Windows 憑證讀取診斷由既有 runner 明確忽略；相關測試無腳本錯誤。最後的編輯器匯入成功、無錯誤，日誌 `.godot/corpse-final-import.log`；本次修改的 diff 空白檢查與新增驗收文件相對連結檢查通過。

## 初版桌面觀察（歷史）

透過 computer-use 選取獨立遊戲視窗；沒有操作 Godot 編輯器。以第一人稱及旁觀視角觀察怪物屍體搬運，執行持續行走／轉彎重播，四肢姿勢隨移動改變。觸發分解後屍體消失、材料計數由 0 增加至 2。再觸發玩家死亡，觀察復活後地上的獨立玩家屍體，拿起後再次執行搬運重播。

桌面拾取及分解使用測試場 F2／F6 快捷入口；正式 E 射線與料斗觸發另由自動測試覆蓋。沒有將這些快捷入口視為正式主世界的完整操作驗收。

## 測試場

[corpse_playground.tscn](../../tests/corpse_playground.tscn)：

```powershell
godot --path . --log-file .godot/corpse-playground.log res://tests/corpse_playground.tscn
```

E／G 為正常拾取／丟棄，WASD 移動。F1 第一人稱、F2 拾取附近屍體（測試捷徑）、F3 旁觀、F4 持續行走轉彎、F5 玩家死亡、F6 分解手持屍體（測試捷徑）、Esc 關閉。加 `-- --replay` 自動開始怪物屍體搬運重播。

## 範圍限制

手持骨架為搬運表現，不與環境碰撞；鬆散屍體仍與環境碰撞。不保存每個肢體角速度。屍體仍服從現有戶外距離清理與場址保存規則，並非全世界永久殘留。未驗收大量屍體堆疊、行進車輛載運、翻車或完整主世界長時間遊玩。

## 已取代的剛性支撐實驗（歷史）

初版修正曾停止手持物理骨模擬，將軀幹固定於抓握局部框架，再用 SkeletonModifier 旋轉四肢／頭部。其自動測試使用平移速度 6 m/s、每幀轉向 0.06 rad、鏡頭俯仰 ±0.7 rad；`.godot/test-logs/20261004-142252-041-selected-16544/test_corpse.log` 記錄通過及 anchor_error 0.000001438 m、length_error 0、swing 0.252632 m、palm_error 0.007375 m。後續軀幹微擺實驗以固定中心角度擺動取代部分剛性外觀，測試 `.godot/test-logs/20261004-143033-342-selected-14360/` 的 `test_corpse` 與 `test_player_carry` 均通過，anchor_error 0.000001941 m、length_error 0、swing 0.260100 m、palm_error 0.014658 m、torso_degrees 2.8715°，rest settling assertion 通過。兩種固定軀幹方案均已被目前恢復物理骨架的實作取代；這些結果不代表目前實作驗證。

## 單點支撐調校（已由下節取代）

此階段手持期間持續模擬 PhysicalBone、關節及重力，支撐中心為玩家局部 `(0, 1.32, -0.42)`。玩家手部目標採頻率 34 的臨界阻尼速度追隨，並加入移動目標前饋；手持骨盆質量提高為 6 倍，全部手持骨線性阻尼設為 0.6、角阻尼至少 2.8。掉落、保存與分解流程保持原有物理姿勢處理。此階段實作由下方雙點支撐更新取代。

最終 `test_corpse` 在 `.godot/test-logs/20261004-144857-689-selected-20744/` 通過，runner exit 0（測試 6.832 秒）。CORPSE_STOP overshoot 為 0.057382 m；快速移動量測 anchor_error 0.223212 m、joint_gap 0.012616 m、limb swing 1.599314 m、palm_error 0.001010 m；落定時 pelvis_speed 為 0.016796 m/s。`test_player_carry` 在 `.godot/test-logs/20261004-144616-490-selected-23680/` 通過（6.392 秒）；該次同組的 `test_corpse` 失敗，故屍體通過結果以較新的 144857 執行為準。本次沒有桌面視覺驗證。

## 骨盆／胸部雙點支撐

目前以骨盆及胸部實際物理骨中點作軀幹支撐中心，玩家局部座標為 `(0, 1.52, -0.42)`，相較前一階段上移。手部頻率改為 36；骨盆與胸部都套用阻尼跟隨並將質量提高 6 倍，其餘骨骼阻尼不變。抓握標記即時跟隨髖部、胸部底緣，並在玩家手臂 IK 前更新，不再依賴靜態代理點。

`.godot/test-logs/20261004-145917-201-selected-11012/` 的 `test_corpse`（5.684 秒）與 `test_player_carry`（4.375 秒）均通過，runner exit 0。記錄的 CORPSE_SUPPORT center 為 `(-0.001128, 1.514148, -0.418080)`；急停 overshoot 0.059355 m；搬運 anchor_error 0.207825 m、joint_gap 0.008675 m、limb swing 1.164468 m、palm_error 0.001909 m；落定 pelvis_speed 0.002950 m/s。沒有完成桌面視覺驗證。

