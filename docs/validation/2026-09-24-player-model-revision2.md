# 玩家模型修正版 2：Blender MCP 修正與 Godot 複查

2026-09-24。延續[前版實測](2026-09-24-player-model-godot.md)，本次直接用 Blender MCP 修改網格、蒙皮與動畫，重匯出完整 GLB 及九份獨立分件。新版 11,938 三角面；1.75 m、55 骨、5 材質、11 段動畫不變。

## 修正

- `hold_small` 的握物腕向原先套用到兩手；現在只有右手採握物方向，左手保持與 idle 一致的自然腕向。
- 坐姿及持物的肘部彎曲平面改為向下，避免前臂朝上時手腕反折。拇指仍在正確側邊。
- 袖口增加有厚度的內緣及深色內襯，手套根部與袖子末端使用連續的手腕權重；手指權重保持獨立。
- 手肘橫截面收窄，肩部增加一圈過渡環線，抬臂時加入鎖骨抬升；軀幹、袖子、反光條與切口封口共用連續的肩部權重分布。
- 重新打包 UV0、更新共享接縫法線；原檔中的 VERIFY 場景重新從實際新版 GLB 匯入。28 張 Blender 預覽全部更新。

## Godot 視窗實測

Godot 4.7.2／Forward+／RTX 4060 Laptop GPU。操作[同一模型測試場](../../tests/player_model_playground.tscn)，使用實際交付 GLB；測試後關閉本轮視窗，保留使用者原本的編輯器。

| 項目 | 本次看到的結果 |
|---|---|
| 坐姿左右手近景 | 未再重現袖口紅色內部面外露；[左手](../../art_source/player_masked_survivor/godot_review_revision2/01_sit_left.png)、[右手](../../art_source/player_masked_survivor/godot_review_revision2/02_sit_right.png) |
| hold_small | 非持物手自然垂放，未再看到指尖穿袖；[畫面](../../art_source/player_masked_survivor/godot_review_revision2/03_hold_small.png) |
| carry_large | 手腕朝向與袖口過渡改善；[畫面](../../art_source/player_masked_survivor/godot_review_revision2/04_carry_large.png) |
| 攀爬、雙手舉高 | 前版肩腋尖銳折角減輕，背面過渡較平順，仍有低模折面與拉伸；[攀爬背面](../../art_source/player_masked_survivor/godot_review_revision2/05_climb_back.png)、[舉手背面](../../art_source/player_masked_survivor/godot_review_revision2/06_hang_back.png)、[前側](../../art_source/player_masked_survivor/godot_review_revision2/07_hang_front.png) |
| 左臂分離 | 新版獨立資產正常顯示，身體端封口可見；[畫面](../../art_source/player_masked_survivor/godot_review_revision2/08_detached_arm.png) |
| 整套換色 | 新增袖口與肩部一起染色，固定色部位不變；[畫面](../../art_source/player_masked_survivor/godot_review_revision2/10_tint.png) |

視窗重現命令：

```powershell
godot --path . --log-file .godot/player-model-revision2.log res://tests/player_model_playground.tscn -- --clip=sit_driver --view=4
```

N 下一段、V 換視角、T 換色、D 分件；其餘控制見前版報告及測試場 HUD。[本輪截圖與原始日誌](../../art_source/player_masked_survivor/godot_review_revision2/)。

## 自動驗證

- 統一 runner `-TestFilter test_player_model.gd`：import、test_player_model、main-scene **PASS**。
- 新增兩個針對本次問題的回歸條件：hold_small 非持物手腕方向與 idle 差異低於 5°；坐姿左右前臂到掌骨彎角低於 80°。
- [GLB audit](../../art_source/player_masked_survivor/glb_audit.json)：11,938 三角面、55 骨、5 材質、11 動畫、9 個獨立分件，failures 空。
- [Blender 全動畫 audit](../../art_source/player_masked_survivor/blender_audit.json)：權重正規化、最多 3 個有效影響骨，所有變形頂點有限；最大切口邊緣偏差約 0.000000238 m。最大網格邊長比約 2.98，並非零拉伸或零自交保證。
- [Godot audit](../../art_source/player_masked_survivor/godot_audit.json)：519 幀骨姿態、尺寸、材質與動畫結構檢查通過。

## 剩餘範圍

本次修復了已重現的袖口紅面與 hold_small 手指穿袖問題，並改善肩肘變形；**不等於最終近景美術全部驗收通過**。近看衣領／肩上仍有局部暗縫，衣褶、手掌及肘部輪廓仍偏簡化，極端舉手仍有拉伸。沒有窮舉所有三角面自交及動畫過渡混合；未驗收實際道具握點、方向盤、RV 淨空、正式第一人稱、布娃娃與活體斷肢玩法。
