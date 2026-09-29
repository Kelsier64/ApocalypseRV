# Generator — 建模 prompt

- **要做什麼**：製作 RV 用可攜式發電機外觀，包含機架、燃料箱、引擎機身、通風柵與側面散熱風扇。
- **替換位置與尺寸方向**：替換 `equipment/generator.tscn` 的 `Mesh` 外觀及 `Details`（來源 `rv/visuals/generator.tscn`）；現有主體與碰撞盒場景設定為寬 X 0.80 × 高 Y 0.60 × 深 Z 1.20 公尺，均以場景原點為中心（底面 Y=−0.30）。+Y 向上、+Z 為正面，依現有 +Z 側通風柵與 `GENERATOR` 標籤；左側 −X 有風扇。
- **外觀要求**：低彩度工業恐怖風格；暗青綠機殼、褪色橙色燃料箱、深色引擎與磨損金屬框架。清楚呈現正面通風、側面風扇及可搬動的緊湊輪廓。
- **交付位置**：GLB／貼圖規劃放 `assets/models/generator/`，可編輯來源規劃放 `art_source/generator/`。整合時只替換外觀，保留 `equipment/generator.tscn` 的 `RigidBody3D`、`Collision` 和設備功能；現有風扇沒有腳本驅動接口。

完成情況：建模需求已整理；模型尚待製作與接入。
