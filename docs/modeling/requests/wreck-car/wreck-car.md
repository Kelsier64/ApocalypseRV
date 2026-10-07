# 路旁事故車共用車體 — 建模 prompt

- **要做什麼**：製作一款可重用的廢棄事故車外觀，用於單車、雙車與翻覆擺放；不製作可駕駛車輛，不新增車門或輪胎動畫。
- **替換位置與尺寸方向**：[wreck_0](../../../../world/roadside_pois/wreck_0.tscn)、[wreck_1](../../../../world/roadside_pois/wreck_1.tscn)、[wreck_2](../../../../world/roadside_pois/wreck_2.tscn)，以及 [checkpoint_2](../../../../world/roadside_pois/checkpoint_2.tscn)、[cargo_0](../../../../world/roadside_pois/cargo_0.tscn) 的 `Visuals` 內車體零件；不替換整個 POI。基準是 [build_minor_pois.gd 的 car()](../../../../scripts/build_minor_pois.gd)；`wreck_0` 對應 `Part001`–`Part017` 與同組 8 個圓柱輪胎／輪圈 Mesh。保留其餘場址外觀；`wreck_0/Visuals/Part018` 是額外掀起的鈑件，沿用。局部原點在地面車體中心、Y 向上、車頭 +Z；車身盒體設定 **2.05 × 0.58 × 4.5 m**（不是整車尺寸）。依既有零件範圍設定整車設計包圍盒：X **[-1.22,1.22]**、Y **[0,2.00]**、Z **[-2.34,2.39] m**，包含輪胎、保險桿與牌照。
- **外觀要求**：低彩度工業恐怖風格、破舊鈑金、車窗及四輪有清楚輪廓；主要凹損收在上述體積內。翻覆時底盤也要完整可見；翻覆由遊戲擺放，不另烘一個倒置模型。烤漆表面獨立成 mesh，可掛 `RoadsidePaint` 材質供現有場址色差使用，其餘金屬／玻璃／輪胎分開。
- **交付位置**（規劃）：`assets/models/wreck_car/wreck_car.glb` 與必要貼圖，可編輯來源放 `art_source/wreck_car/`。只交付美術，不含碰撞／遊戲腳本。整合時保留各場址碰撞、標記、物資與導航，保留現有位置與旋轉；首次建置腳本拒絕覆寫，應直接編輯既有場景。

整合要點：`minor_appearance.gd` 讀取 `MeshInstance3D.material_override` 的 `resource_name == "RoadsidePaint"`，GLB 材質名稱本身不足；整合時為獨立烤漆 mesh 接上同名 override。翻覆沿用 car() 的偏航、Z 軸翻轉與 Y+2.1 擺放；同一模型支援各場景，不移動既有碰撞來遷就新外觀。

起始封路也使用同一份 request：替換 [reused_wreck.tscn](../../../../world/starting_shelter/reused_wreck.tscn) 的 `Visuals` 車體；[roadblock.tscn](../../../../world/starting_shelter/roadblock.tscn) 引用它組成 28 輛廢車（14 輛底層、14 輛上層，其中 4 輛翻覆）。沿用 wrapper 內的實際車體偏移，模型地面中心與 +Z 車頭規範不變；不得直接替換或移動 wrapper 根節點。底盤在翻覆與堆疊時必須完整，保留車身金屬、烤漆、玻璃和輪胎的清楚區分。封路堆疊屬遊戲場景配置，不烘成一個大型廢車堆模型；保留每輛車的碰撞、擺位及後方低矮支撐。接入後檢查路中央及兩侧輪驅接近、車體間隙、翻覆底盤和約 3.5 m 高的車堆輪廓。

起始 wrapper 的實測接入轉換：`Visuals.position = (5,0,5)`，現有車體中心在該節點下 `(-5,0,-5)`、偏航 Y=-0.2 rad。以地面中心為原點的新 `Model` 應沿用此位置與偏航，不直接放在 `Visuals` 的零點。碰撞保留於獨立的 `Collision` 層。

完成情況：2026-10-07 TRELLIS.2／1024／seed 42／50k 參數已生成 1 個原始候選：[whole](../../../../assets/models/wreck_car/trellis_50k_20261007/wreck_car.glb)；未做後期降面，檢查 FAIL（含必要未驗項），未替換正式外觀。詳見 [逐件分析](../../../research/2026-10-07-trellis-50k-requests.md)。
