# 油桶人爆炸特效來源

火煙使用 Godot shader、粒子及原創程序資源；沿用既有 Blender 油桶人模型，不修改 `.blend` 或 GLB。

`bake_resources.gd` 是可重建的來源。從專案根目錄執行：

```powershell
godot --headless --path . --script res://art_source/barrel_vfx/bake_resources.gd
godot --headless --editor --path . --import
```

輸出至 `assets/effects/barrel_blast/`：128 × 128 無縫 turbulence PNG，以及 22,050 Hz、16-bit mono、1.65 秒的合成爆炸 WAV。固定 noise seed 保持結果可重現；聲音含短脈衝噪声、降頻低音、低通尾響及衰減金屬泛音，沒有外部錄音或素材。

遊戲直接 preload 烘焙檔，不在首次爆炸時生成圖像或音訊。火球翻捲與煙霧明暗由 `enemies/barrel_blast_cloud.gdshader` 負責，閃光／地面環由 `barrel_blast_flash.gdshader` 負責；生命週期與各層速度／大小位於 `barrel_explosion_effect.gd`。
