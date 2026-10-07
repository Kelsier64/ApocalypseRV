# 油桶人爆炸特效來源

`barrel_blast.blend` 是 Blender MCP 製作及驗視的可編輯來源，不修改原油桶或油桶人模型。包含 `BARREL_VFX_AUTHORING` 燃料／煙霧流體場景與 `BARREL_FRAGMENT_AUTHORING` 桶蓋、七片彎曲鐵皮。最終流體及材質參數以這份 blend 為準。

## 火煙重建

在 Blender MCP 開啟來源並切到 `BARREL_VFX_AUTHORING`。選取 `BlastVolume`，清除舊快取後執行 `bpy.ops.fluid.bake_all()`。快取在專案忽略目錄 `.godot/art-work/barrel-vfx/realism/cache-final/`；不需要隨遊戲交付。解析度 96、二倍噪聲細化、96 幀；五個燃料來源只在 1–4 幀噴發。

透過 Blender MCP 執行 `render_frames.py`，輸出 64 張煙霧畫面（使用模擬的 1–76 幀），另為前 24 格火焰輸出同取景的有火／無火畫面，每張 256×256；後 40 格已無火，直接填透明。火焰使用 4 m 取景、中心高 1 m，煙霧使用 8 m 取景、中心高 3 m，提升火焰有效解析度。腳本中的專案絕對路徑在換電腦時需更新。再從專案根目錄執行 `python art_source/barrel_vfx/pack_frames.py`（Pillow、numpy），產生兩張 2048×2048、8×8、straight-alpha RGBA 圖集。火焰層由線性空間的含火畫面與煙霧畫面分離，覆於煙層上；遊戲 shader 在相鄰幀間做預乘 alpha 插值。

中間影格、快取和草稿全部留在 `.godot/art-work/barrel-vfx/realism/`。GLB 碎片也可由 MCP 在乾淨的暫存檔執行 `build_fragments.py` 重建；它另外儲存 `fragments_rebuild.blend` 到忽略目錄，保留正式的流體／碎片整合來源。

## 音效與遊戲端

`bake_resources.gd` 可重建固定種子的噪聲貼圖、3 秒爆炸聲，以及三段 0.42 秒金屬落地聲，皆為 22,050 Hz／16-bit mono 程序合成音訊，不含外部錄音。從根目錄執行：

```powershell
godot --headless --path . --script res://art_source/barrel_vfx/bake_resources.gd
godot --headless --editor --path . --import
```

遊戲效果在 `enemies/barrel_explosion_effect.gd`：兩個有界火煙體積、地面揚塵、少量火星、八片無遊戲碰撞體的碎片；射線提供視覺反彈與落地聲。`barrel_blast_flipbook.gdshader` 把圖集輪廓配上深度密度，在 BoxMesh 邊界內沿視線取樣 12 次，以場景不透明深度限制可見區間，讓駕駛鏡頭進入體積仍看得到火煙。燃料火焰快速膨脹與上升，煙霧緩升；這是預烘焙輪廓的體積近似，不在遊戲中模擬流體。完整效果 8 秒後釋放，煙霧 3.8–8 秒漸淡；沒有持續燃燒傷害或可拾取殘骸。普通油桶與油桶人沿用相同效果。駕駛 POV 修正與驗證見[紀錄](../../docs/validation/2026-10-08-barrel-driver-explosion.md)。
