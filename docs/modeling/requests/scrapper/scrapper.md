# Scrapper — 建模 prompt

- **要做什麼**：製作 RV 用回收碎料機外觀：上方敞開的投料盆、厚實護邊，以及盆內兩支相向的壓碎滾輪。保留可從上方投入物件的開口。
- **替換位置與尺寸方向**：用於 `equipment/scrapper.tscn` 的 `BasinVisual` 外觀及 `Details`（來源 `rv/visuals/scrapper.tscn`）；現有盆體場景設定為寬 X 1.05 × 高 Y 0.70 × 深 Z 1.05 公尺，底面 Y=0，模型原點取盆底中心。+Y 向上；設計決定以 +Z 為正面（現有 ±Z 兩面都有警示字）。盆內開口寬／深 0.91 m、內高 0.63 m，底板厚 0.07 m；頂部保持敞開，勿遮擋 `HopperArea`。靜態模型以設備根原點掛載，勿再疊加原 `BasinVisual` 的 Y=0.35 位移。
- **外觀要求**：低彩度工業恐怖風格；暗青綠機殼、磨損金屬內壁、褪色橙色護邊及少量警示標記。輪廓厚重、可讀出進料方向，機械細節集中在滾輪與護邊。
- **交付位置**：GLB／貼圖規劃放 `assets/models/scrapper/`，可編輯來源規劃放 `art_source/scrapper/`。整合時只換外觀，保留 `equipment/scrapper.tscn` 的 `RigidBody3D`、五個 `Col*` 碰撞、`HopperArea` 及滾輪節點接口。

**活動零件接口**：另交付兩支獨立、以各自中心為原點的滾輪外觀；現有 `CSGCylinder3D` 與 `CSGCylinder3D2` 的中心分別在 X=+0.20／−0.20、Y=0.50、Z=0 公尺，圓柱直徑 0.40、公稱長 1.00 公尺，交付滾輪長軸沿模型本地 Y，直接以單位變換掛載；既有節點本地 Y 軸為滾輪轉軸（指向場景 −Z）。`scrapper.gd` 以明確的 `CSGCylinder3D` 型別取得這兩個節點並呼叫 `rotate_object_local(Vector3.UP, ...)`；不得直接以 GLB 節點取代。整合時將各滾輪外觀掛為對應 CSG 節點的子節點，並以透明材質隱藏原 CSG 外觀，保留節點型別、轉動及現有碰撞功能。

完成情況：2026-10-07 TRELLIS.2／1024／seed 42／50k 參數已生成 2 個原始候選：[body](../../../../assets/models/scrapper/trellis_50k_20261007/body.glb)、[roller](../../../../assets/models/scrapper/trellis_50k_20261007/roller.glb)；未做後期降面，檢查 UNKNOWN（含必要未驗項），未替換正式外觀。詳見 [逐件分析](../../../research/2026-10-07-trellis-50k-requests.md)。
