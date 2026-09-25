# 玩家衣服皺褶修正：2026-09-25

使用者指出粗織材質不符合參考圖，塑膠感主要來自衣服缺乏自然皺褶。本輪撤除版 4 的粗織格紋，重新調整服裝體積與折痕。這是外觀修正版本，不代表已達最終近景美術驗收。

## 實際修改

- 腰帶上方增加堆褶，調整軀幹環線分布以支撐輪廓；胸袋、袋蓋與前襟重新貼合。
- 袖子使用局部斜褶與肘部壓縮，收窄原本過度鼓起的前臂中段。褲子加入胯部拉褶、膝前與膝後折痕、小腿垂褶，避免整圈等距波紋。
- 大形寫入可編輯網格，次級折痕寫入 tangent Normal。細面布料使用較高粗糙度及微弱纖維，不把光照陰影烘入 Base Color；衣料仍以中性圖乘 tint。
- 衣料 Base Color／Roughness／Normal 恢復各 1024²；固定色圖集三張 1024²，切口 512²。完整 GLB 內嵌七張影像，不再引用歷史 2K 粗織圖。
- 衣服及對應封口使用一致的位移場，骨名、rest pose、權重與動畫維持原契約。完整角色及九份獨立斷肢均重新輸出。

## 本輪檢查

Blender 5.2.2 LTS，Blender MCP addon 1.7 / protocol 9。完整 GLB 在全新 Blender 場景重匯入，重新產生 32 張預覽；測試姿勢與分離圖仍使用來源場景，其他外觀及正式動畫圖使用實際重匯入場景。

- [GLB 結構結果](../../art_source/player_masked_survivor/glb_audit.json)：11,938 三角面、1.750 m、55 骨、5 材質、11 段獨立動畫、9 份獨立斷肢；無缺失 UV、缺權重或無效骨索引。最多三個有效權重，root 無位移，循環端點一致。
- [Blender 逐幀結果](../../art_source/player_masked_survivor/blender_audit.json)：全部正式 Action 頂點數值有限，切口邊緣最大誤差約 0.000000239 m；最大邊長比 2.648。這不是全面自交或任意動畫混合的證明，也不代表腋下拉伸已完全消除。
- 專案 runner 執行 `scripts/test.ps1 -TestFilter test_player_model.gd`，Godot 4.7.2 的 `import`、`test_player_model`、`main-scene` 全部 PASS。[本輪自動結果](../../art_source/player_masked_survivor/godot_review_folds/automated_asset_check.json)。沒有執行全部玩法測試。
- 實際 Godot Forward+ / RTX 4060 Laptop 視窗檢查：[A-pose 同鏡位](../../art_source/player_masked_survivor/godot_review_folds/05_same_view_folds.png)、[垂手](../../art_source/player_masked_survivor/godot_review_folds/06_idle.png)、[赭色](../../art_source/player_masked_survivor/godot_review_folds/07_ochre.png)。可辨認腰部堆褶和袖管折痕；換色後面具、頭套、反光條與手套維持固定色。
- 姿勢檢查：[坐姿近景](../../art_source/player_masked_survivor/godot_review_folds/01_sit.png)、[懸掛](../../art_source/player_masked_survivor/godot_review_folds/02_hang.png)、[攀爬](../../art_source/player_masked_survivor/godot_review_folds/03_climb.png)。觀察鏡位沒有新增明顯爆點或袖口內部紅色外露，仍可見低模形狀與前襟暗線。
- [左臂分離](../../art_source/player_masked_survivor/godot_review_folds/04_detached.png)：上臂連同前臂及手一起分離，身體端封口可見；此鏡位未正對斷肢端，不用此張圖宣稱目視檢查了兩端。
- [近景日誌](../../art_source/player_masked_survivor/godot_review_folds/inspection.log)、[姿勢日誌](../../art_source/player_masked_survivor/godot_review_folds/pose-inspection.log) 無腳本錯誤。僅關閉本次測試視窗，保留原有 Godot 編輯器。

來源與遊戲完整 GLB 的 SHA256 相同：`46B7467D2349CFE21D92B77F1DDF7615F22708C07DC8BE72DAC571F30A849E63`。

## 證據與限制

[舊粗織版](../../art_source/player_masked_survivor/godot_review_folds/before_coarse_weave.png)、[目前衣服近景](../../art_source/player_masked_survivor/previews/fabric_front.png)、[目前垂手全身](../../art_source/player_masked_survivor/previews/garment_idle.png)。歷史版報告的共享 `previews/` 連結會指向目前版本，歷史外觀應以各自 `godot_review_*` 目錄保存的截圖為準。

皺褶是 rest mesh 塑形與 Normal，隨蒙皮變形，沒有即時布料模擬或姿勢驅動皺褶。肩肘輪廓偏硬、胯部水平轉折、前襟及領片局部暗線仍需精修，離參考圖的自然服裝品質仍有差距。全身造型、動畫及引擎結構檢查通過不能替代使用者的美術驗收。正式玩家、RV、第一人稱、物理骨及斷肢玩法未在本輪接入或驗證。

可編輯來源、輸出設定、分件與骨骼表見 [資產 README](../../art_source/player_masked_survivor/README.md)。
