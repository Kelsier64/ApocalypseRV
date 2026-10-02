# 落葉保留與輕量斷木

2026-10-02，Godot 4.7.2／60 Hz／Jolt。取代前階段樹冠快速淡出與整棵重落木；先前驗證文件保留歷史結果。

## 行為

重用現有樹網格、材質與頂點色。木質部分完整保留，分成最長 3.2 m、每段 2–4 kg 的實體斷木，低摩擦、CCD，與底盤／車板雙向碰撞；初始接回原外觀，向車外側散開並傾倒。葉面拆成小簇，重力與旋轉落地後形成薄層，沒有定時透明或消失。斷樁、木材及葉簇的世界 AABB 全部離開目前相機視錐連續 2 秒，且所有葉簇落地、生成至少 6 秒後才清理；回望會重設計時，沒有相機不清理。不再按最多 24 個效果淘汰可見碎片。仍隨 chunk 卸載釋放，臨時碎片不保存，樹木破壞帳本與引擎損傷沿用既有保存。

## 本輪自動檢查

- `.godot/test-logs/20261002-105833-674-selected-4888/`：`test_tree_impact.gd` PASS，24.62 秒。葉樹案例 27 個實際葉簇、5 段斷木；葉簇下降並全部落地，elapsed 30 秒仍保留完整不透明外觀。葉片或斷樁單獨可見均保護整棵碎片。年齡、未落地、缺相機、回望重設、連續離開視野及真正 runtime queue_free 通過。
- 輪驅連撞 16／16 棵，最低 7.19 m/s（25.9 km/h），引擎剩 221.73；接觸峰值 24、未截斷。既有三朝向、雙樹、同幀硬牆不補速、真實鬆散木材接觸、每樹傷害一次、導航、checkpoint 與重新生成通過。
- `.godot/tree-leaf-import.log`：匯入退出 0，無腳本解析錯誤；root certificate store 訊息屬既有 sandbox 平台訊息。
- `.godot/tree-leaves-gpu.log`：非 headless Forward+／Vulkan 執行同一測試，PASS，無 script／shader error；實際 GPU 批次 instance 移除及相機視錐檢查通過。

## 本輪實機觀察

computer-use 選取唯一 `ApocalypseRV - Tree Impact (DEBUG)` 遊戲，保留 Godot 編輯器。Forward+／Vulkan／RTX 4060 Laptop：F6 單樹回放後，落葉在地面持續可見，原木質部分散落、鄰樹保留；引擎 450 → 435。F7 連撞完成 16／16 棵，最低顯示 25.9 km/h，地面留有葉層、輕量斷木與斷樁。最後零速由回放主動煞車。`.godot/tree-leaves-visible.log`：TREE_CHAIN_REPLAY min_speed=7.19、distance=65.01、engine=221.19、seconds=8.88，沒有 script／shader error。

## 範圍

自動測試驗證真實相機 frustum 與離開視野清理；實機目視驗證落地後保留和連續撞樹。沒有本輪 full、正式主世界 smoke、陡坡、翻車或大量可見碎片效能量測。葉片不帶剛體碰撞，樹幹碰撞用簡化圓柱；細枝不逐三角形碰撞。
