# WAYFARER RV 模型原型

奶油白窗框／屋頂、深綠車殼、橘色維護標示。使用 Godot 原生 MeshInstance3D、共享材質與透明玻璃，無外部模型依賴。

## 場景與分工

- `rv/new_rv.tscn`：正式預設車；沿用 4 × 12 m 底盤與原輪槽物理。
- `rv/legacy/new_rv.tscn`：改造前的車殼／座椅對照，沿用目前系統和道具設備。
- `cockpit.tscn`：座椅、儀表台、方向盤、排檔桿、手煞車、踏板，一起掛在 DriverSeat 下。
- `rv/cockpit_visual.gd`：只讀已連接底盤狀態，更新轉向、排檔、手煞車、三個指針及讀數；沒有另一套引擎或電力狀態。
- `wheel.tscn`：胎面、輪圈和螺帽；由底盤依原輪胎尺寸縮放，跟隨 VehicleWheel3D。
- `chassis_trim.tscn`、`roof.tscn`：裝飾與結構設備的視覺子場景。
- 其餘同名場景：現有設備的外觀細節，不取代設備腳本。

## 模型規則

單位為公尺，車頭朝 -Z。設備保留各自的原點及安裝面。
碰撞形狀在 Equipment 根節點下，視覺可以任意分層；放置範圍由所有根層碰撞合併計算。
駕駛座的椅身、前控制台與側控制台共三組碰撞，一次搬移、一次保存。
側牆窗戶有碰撞；側門及後門具可轉動的門扇，開啟才可通行。
六片側牆／門、後門整組、前窗與屋頂各自為設備，使用底盤永久槽位。車頭朝 -Z，+X 為右側（牆／門／牆），-X 為左側（牆／牆／牆）。
`equipment/rv_side_panel.tscn`、`rv_side_door.tscn`、`rv_rear_door.tscn` 可直接編輯。門扇視覺在 Leaf0／Leaf1 下，CollisionShape3D 留在設備根層，由 rv_door.gd 同步旋轉。門扇厚度與門框齊平，避免攀爬撞到凸出的上緣。
後門整組寬 3.6 m，淨開口約 3.12 m；側門單扇淨開口約 1.2 m。門扇向外開至 100°，兩扇各別操作；不可在可動葉片上裝設備。
外觀子節點不可加入自己的獨立設備登錄或保存狀態。

## 查看

執行 `tests/rv_design_workshop.tscn`：
F2 外觀、F3 車內、F4 入座、F5 輪驅展示、F6 舊車殼、F7 控制台全貌。
F5 是測試場授權的底盤輸入；正式遊戲仍使用 B／Space／Z X C／R T／W A S D。

後續正式 GLB 可取代視覺子場景，保留原點、外形尺寸、Collider、Camera3D 及 cockpit_visual.gd 使用的動態節點。

## 新底盤、引擎與燈號

- 正式 rv/chassis.tscn 已用 MeshInstance3D 重新製作；Deck、Rail、Cross、Arch、Bumper 與各簡單 Collider 保留原 4 × 12 m、地板和輪槽座標。舊 CSG 只留 legacy 對照。
- rv/engine_bay.tscn 是前方固定服務槽；Hatch 為獨立 E 互動蓋，EngineVisual 顯示已裝引擎；空槽保留托架與提示。引擎道具場景在 props/engine_standard.tscn／engine_upgraded.tscn，原創原生網格，可直接編輯。
- rv/rear_ramp.tscn 的 Stowed 是收納兩折板，Deck 是展開兩半板；一片連續斜面 Collider 供行走，斜度與長度依地面計算。姿態即時切換，不含展開動畫。
- assets/rv_status 的 SVG 是本專案原創車用符號；rv/vehicle_status.gd 決定顏色和原因，實體 Sprite3D／HUD 共用。VehicleLights 使用原生燈罩與 SpotLight3D；原有裝飾 light.tres 不常亮。
- EngineAppearance 與 PanelWear 複製材質實現低耐久／故障或三級損壞；玻璃裂紋不影響碰撞，不添加獨立玻璃 HP。
- 預裝工作台左中、平板附在工作台；分解機右前、發電機左後、道具箱右後。中央走道至少 1 m，後門前方淨空。

引擎／坡板／夜間／輪驅展示：tests/rv_rebuild_playground.tscn。F8 引擎艙、F9 後門坡板、F10 警示燈、F11 夜間、F12 輪驅回放。

## 老舊工業材質（2026-09-17）

共享 paint 材質引用 `assets/materials/industrial/worn_paint.png`，採 512px 匯入限制與近鄰 mipmap；狀態燈、玻璃分開保留。磨損狀態透過額外 detail 層疊加，不抹掉底層掉漆貼圖。獨立燈條的 CabinLighting 跟著自身 Equipment 支撐、控制台請求與供電狀態運作，不能在拆下後繼續照明。新增儀表固定件只屬視覺，不改控制件運動、碰撞或安裝面。
