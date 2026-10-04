# 玩家斷肢與受傷動畫

2026-10-03，以現有玩家 v020 網格／41 根變形骨為來源，在 Blender 5.2.2 經 Blender MCP 製作。既有 v020 模型與 v021 正常移動動畫保持原檔。

- `player_dismemberment.glb`：頭、左右整臂、左右整腿、軀幹分件；原本 16,222 個衣服／身體三角面在頸部細分後共 16,366 面，保留原表面積。頸部固定於來源 Z=1.36 m 切開，單一封口取代穿過肩部的鋸齒權重分界。
- `Part_<part>__*`：可見身體；`Wound_<part>_*`：身體端封口；`Cap_<part>_*`：離體端封口。封口含衣布、肌肉、骨頭及骨髓四材質。
- `player_injury_animations.glb`：六組 60 fps 原地動畫，`prone_idle`、`crawl_missing_left_leg`、`crawl_missing_right_leg`、`crawl_no_legs`、`crawl_onearm_L`、`crawl_onearm_R`。最後兩組後綴指仍可用的手。
- `*_PLAYER_BaseColor_512.png`：Godot 從 GLB 擷取的既有玩家色圖，無新外部素材。

2026-10-04 使用本機 Blender 5.2.2 重製六段匍匐動作：胸腹保持低平，前臂交替撐地，剩餘腿部向後拖行。每手在循環前 67% 向後拉 0.34 m，後 33% 低抬向前換手；雙手相差半個循環，單手版本由存活手拉動。四肢採保持骨段長度的關節解算，地面高度計入衣服內襯、手套與靴子厚度；鏡頭與動畫步頻在 Godot 端配合調整。

可編輯來源：[player_dismemberment.blend](../../../art_source/player_dismemberment/player_dismemberment.blend)。目前 `Player_Dismemberment_Refined` scene 預覽缺左腿的匍匐姿勢；六組受傷動作保留於暫時靜音的 NLA tracks。前一製作 scene 保留作對照，其物件加上 `Previous_` 前綴。

重新建置時先在獨立 Blender scene 匯入正式玩家 v020 GLB，再執行 [分件腳本](../../../scripts/build_player_dismemberment.py)，接著執行 [動畫腳本](../../../scripts/build_player_injury_animations.py)。兩支腳本使用目前選取的製作場景與 `PLAYER_Rig`；分件腳本的 `ROOT` 在不同 checkout 需調整，動畫腳本由自身檔案位置解析專案路徑。不要對含有其他工作的場景執行。若只重做動畫，直接在本來源 scene 執行第二支即可；動畫腳本僅匯出受傷動畫 GLB，不覆寫已修整的分件 GLB。

遊戲保留正式 Skeleton3D 與 Skin，分件僅作網格來源，bind index 按骨名映射。動畫以全域 rest 差異轉換後快取；glTF 省略的固定通道回填 rest，父子矩陣直接計算，避免未入樹骨架的延遲快取。轉換後所有軌道仍指向正式 41 骨。

離體件以當下姿勢建立獨立骨架，跨切口權重重新綁到離體根骨，保持頂點世界位置。手臂 2、腿 3、頭 1 個物理碰撞體，根部不連回不可見軀幹。細節及證據見 [驗收紀錄](../../../docs/validation/2026-10-03-player-dismemberment.md)。

地面血泊使用 [濕潤紅色材質](../../../player/player_blood_pool.gdshader)：平滑合併的液面輪廓、隨機濺滴、薄邊／厚處色差、低粗糙度、微法線及漸退透明度。採有限尺寸平面貼地，跟隨命中的承載物，沒有自發光；不模擬跨階梯的液體流動。近景修正見 [頭顱與血泊驗收](../../../docs/validation/2026-10-03-player-gore-refinement.md)。
