# 玩家可見布紋修正：2026-09-25

> 歷史版本：使用者後續指出此粗織材質不符合參考圖，主要問題是衣服缺少自然皺褶。此版不作為已通過外觀驗收的版本；後續改以服裝體積、局部折痕與細面布料修正。

使用者指出上一輪「完全看不出來衣服紋理」。上一輪低對比、以 Normal 為主的細節在寬廣照明與 1K 全身圖集中消失；結構測試通過不能代表這個外觀要求已達成。

本版把衣料改為交錯經緯線的織紋，降低雲狀色斑。紗線色差、表面高度與粗糙度分別烘進 Base Color、OpenGL tangent Normal、Roughness。底圖依然是中性灰，預設 tint 不變。面具、頭套、反光條與黑色部位保留固定色。沒有新增幾何、骨骼或動畫。

## 貼圖預算例外

衣料三張貼圖由 1024² 提升到 **2048²**，每張像素數為前版四倍，目的是让近景織紋有足夠取樣。這超出原委託首版 1K 圖集目標，已明确記錄；並非零成本增強。頭套與其他固定色圖集仍是三張 1024²，切口一張 512²。GLB 使用七張影像；三角面仍為 11,938、55 骨、5 材質、11 段動畫。

## 實際檢查

- 完整角色及九份斷肢重新匯出；實際完整 GLB 在新 Blender 場景重匯入並更新預覽。
- [GLB 結構檢查](../../art_source/player_masked_survivor/glb_audit.json) 無失敗。未修改 rest pose、頂點或權重，本輪未重跑來源網格切口誤差遍歷；前輪幾何結果仍屬前輪檢查。
- 專案 runner 的 `import`、`test_player_model`、`main-scene` 全部 PASS；材質檢查更新為 suit 2K、equipment 1K Normal。既有逐幀骨姿態、換色隔離、白面具、動畫與九份斷肢檢查通過。[本輪自動結果](../../art_source/player_masked_survivor/godot_review_weave/automated_asset_check.json)。
- Godot 4.7.2 / Forward+ / RTX 4060 Laptop 實際視窗：[同鏡位](../../art_source/player_masked_survivor/godot_review_weave/01_same_view.png)、[近景](../../art_source/player_masked_survivor/godot_review_weave/02_close_weave.png)、[赭色](../../art_source/player_masked_survivor/godot_review_weave/03_ochre_weave.png)。上衣、領片、口袋與袖子可辨認重複交錯織紋，未靠只放大圖片交付。
- 開啟待機動作查看不同時刻的材質：[待機](../../art_source/player_masked_survivor/godot_review_weave/04_idle.png)。這是有限的固定鏡位觀察，不是所有移動距離／角度的抗閃爍保證。
- [視窗日誌](../../art_source/player_masked_survivor/godot_review_weave/inspection.log) 無腳本錯誤。測試視窗完成後關閉，原有編輯器保持開啟。

來源／遊戲 GLB 的 SHA256 相同：`FF7CC8CFA4B1581D68B365DFA839FABBD51081CF9A97D578860940E644EFB4BE`。

相同 Blender 鏡位的 [上一版](../../art_source/player_masked_survivor/godot_review_materials/fabric_front_before_weave.png) 與 [修正版](../../art_source/player_masked_survivor/previews/fabric_front.png) 可作比較；[細節圖](../../art_source/player_masked_survivor/previews/fabric_detail.png) 使用實際 GLB 重匯入。

這是一版刻意加強可讀性的粗織工作服材質。肩部變形、低模輪廓、薄領片與前襟暗線仍是既有待精修項目，沒有因布紋變強就視為解決。正式第一人稱、RV、布娃娃與玩法接入未包含在本輪驗證。
