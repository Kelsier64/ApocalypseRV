# 可動 3D 角色製作與接入規格

現況核對：2026-10-05。適用正式玩家與 Raker，依目前工作樹的場景、腳本、GLB 及匯入設定整理。本文件定義共通接入原則與各角色的個別規格；尺寸、骨骼數、動畫集合與物理配置由角色需求決定。

[玩家資產](../../assets/models/player_test_v020/README.md) · [玩家動畫](../../assets/models/player_animations_v021/README.md) · [玩家分件與受傷動畫](../../assets/models/player_dismemberment/README.md) · [Raker 資產](../../assets/models/raker/README.md) · [歷史 v2 提案與試接快照](../archive/modeling-2026-10-05/character-modeling-v2.md)

## 1. 共通接入契約

| 項目 | 現行契約 |
| --- | --- |
| 單位與座標 | 1 單位 = 1 m；交付 GLB 為 +Y 向上、+Z 正面，模型腳底原點為零。角色控制器朝前為 -Z，由外觀包裝轉 Y 180° 對齊 |
| 角色根節點 | 使用 `CharacterBody3D`；生命、輸入／AI、移動、碰撞和導航屬於角色控制器 |
| 外觀與動畫 | GLB 放在外觀子節點，使用 `Skeleton3D`、Skin 與 `AnimationPlayer`。根角色不以縮放適配模型；外觀縮放及其物理補償列在角色規格 |
| 動畫位移 | 交付移動片段採原地動畫，root 不累積世界平移或旋轉；世界位移由控制器、導航、攀爬與 RV 支撐處理 |
| 執行期姿態 | 持物、駕駛、抓咬 IK 及攀爬對位可以調整骨姿勢；玩家攀爬的局部 root／視點修正只影響外觀，不移動碰撞體 |
| 骨架相容 | 替換既有角色時保留其骨名、父子階層、rest pose 與 Skin 綁定；新增角色另列必要骨骼用途，現有程式尚無共通骨骼映射配置 |
| 蒙皮 | 現有玩家蒙皮計算按每頂點 4 個骨影響讀取；相容交付維持最多 4 個有效影響、正規化權重，分件轉換按骨名對應 bind index |
| 資源所有權 | 動畫播放狀態與傷害外觀回饋屬各 actor；共用資源保持不可變。Raker 複製片段建立自己的 library，玩家共用快取片段、各自持有播放狀態 |
| 車上支撐 | 玩家與 Monster 共用 `RVSupport`；位移與車速繼承由遊戲程式處理，動畫不可另加一次車速 |
| 布娃娃 | Godot 建立 `PhysicalBoneSimulator3D`／`PhysicalBone3D`、碰撞與關節限制，從當下姿態及速度交接；模擬期間避免動畫繼續覆寫物理骨 |
| 交付 | GLB、必要貼圖、可重建的 Blender 來源與資產 README；正式檔放 `assets/models/`，專案內來源放 `art_source/`，外部來源須在 README 記明路徑 |

新角色採工業恐怖、低彩度與清楚輪廓，在實際遊戲解析度、霧與車燈下檢查。面數、材質與骨骼數需分角色記錄並依使用情境量測；目前沒有已驗證的全角色統一效能上限。

## 2. 玩家與 Raker 個別規格

### 2.1 場景、尺寸與碰撞

| 項目 | 玩家 | Raker |
| --- | --- | --- |
| 正式場景 | [player.tscn](../../player/player.tscn) | [raker.tscn](../../enemies/raker.tscn) |
| 外觀控制入口 | `Visuals`，由 [PlayerModelVisual](../../player/player_model_visual.gd) 管理 | `BodyMesh`，由 [raker_visual.gd](../../enemies/raker_visual.gd) 管理 |
| 模型／骨架路徑 | `Visuals/Model/PLAYER_Rig/Skeleton3D` | `BodyMesh/Model`，腳本向下查找 `Skeleton3D` |
| 原始中立身高 | 1.60 m | 2.18 m |
| 接入變換 | `Visuals` Y=0.25、轉 Y 180°；模型 scale=1 | `BodyMesh` Y=0.25；`Model` 轉 Y 180°、等比 scale=1.2，顯示高 2.616 m |
| 站立碰撞 | 膠囊 radius=0.40、height=1.50 m，中心 Y=1.00；上下端 Y=0.25／1.75 | 膠囊 radius=0.40、height=2.616 m，中心 Y=1.558；上下端 Y=0.25／2.866 |
| 低姿態碰撞 | 缺腿時水平膠囊 radius=0.24 m；有一腿長 1.40、無腿長 0.95 m | 蹲姿膠囊高 1.85 m；站起須通過實際淨空檢查 |
| 導航 | 玩家由輸入控制，場景沒有 NavigationAgent3D | NavigationAgent3D radius=0.40、height=2.616 m；車內另用 MonsterCabinRoute |
| 視點 | 站立相機根座標 `(0,1.78,-0.20)`；本機去頭顯示，外部／鏡面模型與影子完整 | 完整世界模型；頸部追視與抓咬姿態由 SkeletonModifier3D 修正 |
| 完整布娃娃 | 14 個物理骨；缺失部位停用對應物理骨 | 15 個物理骨；死亡與強烈車撞可接管 |
| 模擬中物理碰撞 | layer=128、mask=129（環境 1＋布娃娃 128），相鄰骨另設碰撞例外 | layer=128、mask=1，只與環境接觸；尺寸與 body_offset 補償模型 1.2 倍縮放 |

玩家 1.60 m 模型與 1.50 m 膠囊是目前已接入配置，並非要求模型必須與膠囊等高。新尺寸要同時校對眼高、RV 門洞／走道、座椅、方向盤、攀爬與布娃娃，不能只改模型比例。

物理來源：[玩家布娃娃](../../player/player_ragdoll.gd)、[Raker 布娃娃](../../enemies/raker_ragdoll.gd)。屍體轉為 [CorpseProp](../../props/corpse.gd) 後有自己的碰撞及搬運配置，上表只描述原 actor 的布娃娃模擬。

### 2.2 資產與匯入設定

下列網格／三角面／材質／骨數取自本輪實際 GLB JSON。這些是檔案內容數量，不代表同時可見面數、draw calls 或效能預算。

| GLB | 網格 | 三角面 | 材質 | 變形骨 | 片段與執行期用途 |
| --- | ---: | ---: | ---: | ---: | --- |
| [玩家 v020](../../assets/models/player_test_v020/player_export_test_v020.glb) | 11 | 16,222 | 5 | 41 | 正式模型；1 段 TEST 驗證動畫，正式外觀會移除其 library 引用 |
| [玩家 v021](../../assets/models/player_animations_v021/player_animations_v021.glb) | 11 | 16,222 | 5 | 41 | 17 段正式動作，只擷取動畫，不替換 v020 網格／骨架 |
| [玩家分件](../../assets/models/player_dismemberment/player_dismemberment.glb) | 27 | 19,822 | 9 | 41 | 0 段；作部位及兩端封口的網格來源，保留正式骨架／Skin |
| [玩家受傷動畫](../../assets/models/player_dismemberment/player_injury_animations.glb) | 27 | 19,822 | 9 | 41 | 6 段；只擷取並轉換動畫至正式骨架 |
| [Raker](../../assets/models/raker/raker.glb) | 1 | 30,242 | 6 | 54 | 正式模型及 41 段動作 |

玩家分件的 19,822 面包含封口等匯出幾何；資產 README 的 16,366 面是分件後衣服／身體表面子集，兩者統計範圍不同。第一人稱副本、陰影副本與斷肢會另增加執行期成本。

| 資產 | 來源動畫採樣 | Godot 匯入設定 |
| --- | --- | --- |
| 玩家 v020 | TEST 姿勢驗證，非正式移動動作 | [24 fps](../../assets/models/player_test_v020/player_export_test_v020.glb.import)，動畫 optimizer／compression 關閉 |
| 玩家 v021 | 60 fps 烘焙 | [60 fps](../../assets/models/player_animations_v021/player_animations_v021.glb.import)，動畫 optimizer／compression 關閉 |
| 玩家分件 | 無動畫 | [30 fps 欄位](../../assets/models/player_dismemberment/player_dismemberment.glb.import)保留匯入設定，不代表有 30 fps 動畫 |
| 玩家受傷動畫 | 60 fps | [60 fps](../../assets/models/player_dismemberment/player_injury_animations.glb.import)，動畫 optimizer／compression 關閉 |
| Raker | 資產 README 記載 60 fps 烘焙 | [.import 為 30 fps](../../assets/models/raker/raker.glb.import)，沒有自訂關閉 optimizer／compression 的設定 |

動畫來源採樣、Godot 匯入採樣與物理 tick 分別管理；專案物理為 60 Hz。替換資產時保留各自已接受的匯入設定，必要調整須另驗證。此文件整理不更改上述設定。

來源位置：玩家原始及 v020 匯出工作檔在資產 README 記載的外部 `Projects/3d/`；玩家動作／分件來源在 [player_animations_v021](../../art_source/player_animations_v021/player_animations_v021.blend) 與 [player_dismemberment](../../art_source/player_dismemberment/player_dismemberment.blend)；Raker 目前來源為 [monster_refined_v021](../../art_source/monster_refined_v021/monster_refined_v021.blend)。外部工作檔的位置依 README 記錄，本輪未檢查其存在或內容。

### 2.3 骨名與動作接口

現有兩角色左右骨用 `_L/_R`，依角色自身左右判定。共用用途名稱含 `root`、`pelvis`、`spine_01/02`、`neck_01/02`、`head`、`clavicle_L/R`、`upper_arm_L/R`、`forearm_L/R`、`hand_L/R`、`thigh_L/R`、`shin_L/R`、`foot_L/R`。玩家手指各兩節；Raker 四指各三節、拇指兩節，另有 `spine_03`、`hump`、`jaw`、`toe_L/R`。骨名相近不代表可直接互換動畫或 rest pose。

| 用途 | 玩家 | Raker |
| --- | --- | --- |
| 基本移動 | `idle`、`jog_{forward,back,left,right}`、`run_{forward,back,left,right}` | `idle`、`walk`、`chase`、`sprint`、`crouch_idle/walk` |
| 跳躍／落地 | `jump_rise/fall/land` | `fall_loop`、`land`、`crouch_land` |
| 攀車 | `climb_hold/up/left/right/exit` | `climb_loop`、`hang_idle`、`mantle`、`roof_settle`、`slip_loop` |
| 戰鬥／反應 | 被抓、持物與駕駛由程序姿態處理；沒有玩家攻擊動畫交付 | `attack_left/right`、`crouch_attack`、`attack_door/down`、`hit_react`、`crouch_hit_react` |
| 特殊動作 | `prone_idle`、`crawl_missing_left_leg/right_leg`、`crawl_no_legs`、`crawl_onearm_L/R` | `grab_{stand,low,seat}_{reach,hold,bite,release,escape,miss}`，共 18 段 |
| 死亡 | 布娃娃接管，完整安全重生 | 布娃娃接管；GLB 的 `death/crouch_death` 保留作預覽 |

玩家正式 library 為 `locomotion`／`injury`；Raker 在各 actor 的 `game` library 還原 Godot 匯入時消耗的 `_loop` 名稱。GLB 只有同名動畫不會自動接入狀態切換。Raker 的攻擊及咬合由角色程式同步播放與命中時間，傷害只能結算一次；詳細時序見 [Raker 資產說明](../../assets/models/raker/README.md)。

## 3. 玩家五切口接口

<a id="player-five-cuts"></a>

固定部位為 `head`、`left_arm`、`right_arm`、`left_leg`、`right_leg`；頭從頸、整臂從肩、整腿從髖分離。Raker 本身沒有玩家斷肢系統。任意平面切割、肘膝再次切斷與九切口均為歷史擴充提案。

| 部位 | 分離根骨 | 斷肢物理骨 |
| --- | --- | ---: |
| head | head | 1 |
| left_arm／right_arm | upper_arm_L／upper_arm_R | 每臂 2 |
| left_leg／right_leg | thigh_L／thigh_R | 每腿 3 |

分件名稱為 `Part_<part>__*`、身體端 `Wound_<part>_*`、斷肢端 `Cap_<part>_*`。相容替換維持兩端封口、跨切口權重轉換、當下姿態／速度繼承、缺失物理骨停用及每部位一次分離。[分件外觀程式](../../player/player_dismemberment_visual.gd)以骨名重映射到正式 Skin；部位完整性由 [PlayerBodyState](../../player/player_body_state.gd)持有，不能只隱藏網格。

| 缺失狀況 | 現行能力 |
| --- | --- |
| 一臂 | 可用小物與維修；雙腿完整可駕駛；不能大型持物、搬設備及攀爬 |
| 雙臂 | 雙腿完整可走路；不能拾取、使用、維修、攀爬與駕駛；可環視、查看背包、丟棄／存入已有物品 |
| 任一腿 | 倒地過渡後爬行；不能衝刺、跳躍、攀爬與駕駛；雙臂時有一腿 0.8 m/s、無腿 0.55 m/s |
| 缺腿且缺臂 | 一臂爬行 0.35 m/s，無臂速度為 0；其他操作依可用手臂判定 |
| 頭 | 立即死亡；約 2 秒後找到完整站立淨空才恢復完整身體及能力 |

活體五部位狀態在檢查點與跨 World3D 保留。斷肢與血跡是暫態效果；完整屍體已透過 CorpseProp 保存類型、部位與 41／54 骨局部姿態，不保存各肢體角速度或手持暫態。保存格式與版本以 [目前架構](../../architecture.md)及 [CorpseProp](../../props/corpse.gd)為準。正式 Raker 咬擊可切左臂或頭，其餘固定切口由測試場觸發。

## 4. 替換、新增與驗收

替換模型前先確認其角色規格、外觀路徑、必要骨名、rest pose、Skin、動畫名稱、取樣設定及布娃娃尺寸；若更改任一接口，同步調整外觀、IK、物理與對應測試。現有角色尚無共通 Resource 配置或自動骨骼映射，規格文件不代表可直接插拔任意 GLB。

1. 匯出後核對單位、正面、腳底、變換、材質、網格與骨骼數；將實際數據記入資產 README。
2. 檢查蒙皮極端姿勢、循環接縫與 root 漂移，再檢查正式狀態切換、速度對應及攻擊命中。
3. 在真實 RV 中核對門洞、走道、站起淨空、攀爬、持物／駕駛或抓咬，以及車身移動時的支撐。
4. 布娃娃／斷肢檢查姿態交接、速度繼承、碰撞、復原及保存；各角色不同物理配置分別驗收。
5. 依 [測試指南](../../tests/README.md)選取適用回歸並使用統一 runner；物理與畫面改動另依 [AGENTS](../../AGENTS.md)及 [測試場指南](playgrounds.md)做實機觀察。

既有資產覆蓋包括 [玩家匯入](../../tests/test_player_import_v020.gd)、[玩家正式模型](../../tests/test_player_model.gd)、[逐幀蒙皮](../../tests/test_player_animation_skin.gd)、[玩家布娃娃](../../tests/test_player_ragdoll_v020.gd)、[玩家斷肢資產](../../tests/test_player_dismemberment_assets.gd)、[Raker](../../tests/test_raker.gd)及 [Raker 布娃娃](../../tests/test_raker_ragdoll.gd)。這些仍是角色專用測試，尚無所有新角色通用的資產驗證器。

本輪只重整文件、讀取實際 GLB JSON、核對場景／腳本／匯入設定及相對連結；沒有啟動引擎、重跑行為測試或做實機驗收。既有結果與限制見各資產 README 連結的歷史驗收；舊 Zombie、1.75 m 玩家提案、統一 30 fps 建議、低模預算與九切口完整保留在 [v2 歷史快照](../archive/modeling-2026-10-05/character-modeling-v2.md)，不作為目前交付要求。
