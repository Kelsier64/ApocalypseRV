# 路旁資產模組

九個可直接在 Godot 編輯的 `.tscn`：tree、dead_tree、rock、pole、sign、rail、wreck、camp、shed。根節點原點在地面，+Y 向上；sign 文字面與設施入口朝 +Z。大型物件含簡化靜態碰撞，植被小叢另用 MultiMesh 批次生成。

正式生成器透過 `RoadsideKit.instantiate_module()` 使用這些場景。可逐一替換 Mesh 和材質；保留碰撞合理尺寸，以及生成器預留的道路／停車／入口空間。地表顏色與細節材質在 `world/terrain/`。

[路燈](streetlight.tscn)由 `RoadsideStreetlights` 沿主公路分成單盞與連續燈列。每 900 公尺搜尋一段可容納完整燈列的路肩，開場優先從最近的位置開始找。每列有 11–16 盞暖白燈，沿道路中心線使用同一個 20–28 公尺的隨機間距，並放在同一側路肩。單盞獨立安排，和同區段的燈列至少相距 95 公尺，少數會採用琥珀色或淡冷白。燈頭朝本地 −Z，天黑後亮起。兩種模式都可能有短暫變暗或連閃後熄滅再恢復的故障燈。

`scripts/build_roadside_kit_20260915.gd` 是首次建立腳本，已有任一輸出時拒絕覆蓋。日常修改直接編輯場景，不要重跑產生器覆寫手動美術。
