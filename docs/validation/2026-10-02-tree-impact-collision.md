# 倒樹實體碰撞修正

日期：2026-10-02，Godot 4.7.2／60 Hz／Jolt。本輪修正上一版 [動量與倒塌效果](2026-10-02-tree-impact-momentum.md) 的車身穿入倒樹問題；前一版紀錄保留為歷史結果。

## 修正

原靜態樹一破壞就停用碰撞，倒樹只有動畫網格，車子會在樹尚未讓開時穿入。現在 TreeFall 接手實體 RigidBody3D：樹幹圓柱與樹冠膠囊碰撞跟隨同一剛體外觀，layer／mask 1、CCD，不排除底盤或安裝車板。

折斷處用短暫 HingeJoint3D 約束向前傾倒，約 27° 或最長 0.25 秒後解除，之後由物理推動、旋轉、落地與回彈；沒有透過動畫改剛體 transform。支點期限避免地面或牆壁把落木長時間鎖住。落木質量 35–140 kg，額外接觸會自然損失車速；既有第一下保留動量、引擎受傷及硬牆阻擋仍存在。

塵土由實際地面接觸觸發；落木保留至約 21 秒淡出完成，隨 chunk 卸載或效果上限回收。碰撞不是永久地景，checkpoint 仍只保存樹木破壞帳本。

## 本輪檢查

- `.godot/test-logs/20261002-095658-387-selected-39416/`：test_tree_impact PASS，16.23 秒。三個朝向初撞約 9.63–9.64 m/s；150 幀後仍約 5.83–6.32 m/s，前進 19.06–20.42 m。雙樹最後 5.31 m/s、17.97 m，沒有改短原動量觀察窗口。
- 落木直接物理狀態觀察到與底盤或已安裝 Equipment 的接觸，單樹接觸 impulse 約 158–170，接觸後落木移動 13–19 m；雙樹均有接觸 impulse。檢查碰撞遮罩、無 RV collision exception、初次向前傾倒及實際地面接觸。安裝車板可先於底盤接觸，所以不只查 Chassis 的 contact report。
- 同幀牆／新毀樹仍不補向牆速度；低速拒絕、每樹傷害一次、導航、checkpoint、重新生成及外觀 RNG 回歸通過。牆可能支撐落木，該情境不要求倒木必須落地。
- `.godot/test-logs/20261002-095846-405-selected-15012/`：test_moving_rv_climbing、test_rv_physics_regression PASS，共 9.16 秒。
- `.godot/tree-physical-import.log`：匯入退出 0，無 script parse error；Windows sandbox root certificate store 訊息屬既有平台訊息。
- `.godot/tree-impact-physical-gpu.log`：非 headless Forward+／Vulkan 執行 test_tree_impact，有 PASS，沒有 script／shader error；實際落木碰撞與 GPU 單樹隱藏檢查通過。

## 實機觀察

computer-use 選取唯一輪驅測試遊戲、F6 啟動。Forward+／Vulkan／RTX 4060 Laptop：車頭接觸後樹向前倒開並移動，倒木與 RV 分離；第一段撞後畫面約 18 km/h，後續仍加速至約 23 km/h，再由重播主動煞車。引擎 450 → 約 435.45，鄰樹保留。日誌 `.godot/tree-impact-physical-final.log` 的 TREE_REPLAY speed=6.48、TREE_VISUAL hidden=true／neighbour_solid=true，無 script／shader error。

互動測試遊戲及 GPU 回歸均已退出，原 Godot 編輯器保留。

先前自由落木會被車頭頂得往後翻，長時間支點則會把車擋住；本輪中間失敗測試促成支點方向與期限修正，最終結果使用上列 PASS 批次。

## 限制

碰撞使用簡化樹幹／樹冠體積，細小枝葉不是逐三角形碰撞。沒有本輪 full、正式主世界 smoke、大量連撞效能、陡坡或翻車驗收；前一輪主世界 smoke 屬歷史結果。
