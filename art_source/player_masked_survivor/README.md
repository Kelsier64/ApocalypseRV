# Masked Survivor — 玩家全身資產

2026-09-25 防水工作服／微蹲步態版。透過 Blender MCP 編輯，保留 1.60 m 矮寬比例、修正後的拇指與手肘方向、後腰修形；沒有對講機。

衣料改為 PU 塗層工作服的柔和反光，使用中性灰階 Base Color、約 0.52 的局部粗糙度與方向性皺褶 Normal。袖肘、膝後及腰側增加皺褶，部分輪廓直接修改網格；沒有增加三角面。這是靜態衣褶配合蒙皮，不是即時布料模擬。

walk 重做為微蹲警戒步態：骨盆比綁定姿勢低 6.7–7.3 cm，身體略前傾、膝蓋全程微彎，腳步行程 21 cm、抬腳 3.8 cm；上下起伏約 6 mm。依使用者提出的 CS:GO 感覺調整，並非複製遊戲動畫或動作擷取資料。idle 保持上輪自然待機。

## 目前檔案

- [可編輯 Blender 原檔](player_masked_survivor.blend)：主場景 PLAYER_MASKED_SURVIVOR；九個 DETACHED_CURRENT 場景；VERIFY_CURRENT 為本輪實際 GLB 重匯入。
- [Godot 正式 GLB](../../assets/models/player/player_masked_survivor.glb)、[独立面具](../../assets/models/player/mask_default.glb)、[九份斷肢](../../assets/models/player/detached/)。
- [七張 PNG 原檔](textures/)、[切口對照](cut_map.json)、[動畫與接地紀錄](animation_manifest.json)。
- [本輪驗證及清理紀錄](../../docs/validation/2026-09-25-player-waterproof-walk.md)。

正式資產只保留單一路徑。history、revisions、work、previews、godot_review*、review 及 Blender 自動備份已被根目錄 .gitignore 排除；art_source/.gdignore 使製作檔與歷史檔不被 Godot 掃描。舊版本保留在本機歷史目錄，沒有刪除遊戲程式或原始參考圖。

## 尺寸、預算與來源

| 項目 | 本版 |
|---|---|
| Blender | 5.2.2 LTS，MCP addon 1.7 / protocol 9 |
| Godot 實際匯入 | 4.7.2 stable official |
| 尺寸 | 1.600 m，腳底 Z=0，地面兩腳中心為 root 原點 |
| 單位／變換 | Metric、Unit Scale 1；Mesh／Armature Scale 1、Rotation 0，無負縮放 |
| 朝向 | Blender -Y / +Z 上；GLB +Z / +Y 上；遊戲外觀節點需轉 Y 180° |
| 三角面 | **12,066**，含全部配件與封口；肩部新增 128 面，比原 12,000 上限多 66 面（0.55%） |
| 骨架 | 55 根，包含 root；每手五指三節及拇指掌骨 |
| 蒙皮 | 最多 3 個有效骨權重，本版未達 4 根上限；所有頂點有正規化權重 |
| 材質 | 5 種：suit_dye / equipment_atlas / reflective_orange / mask_default / cut_tissue |
| UV | 完整 UV0；衣料與各材質分開打包，固定色圖集分區，無刻意鏡像共用 |
| 貼圖 | 衣料中性 Base Color／Roughness／Normal 各 1024²；固定色圖集 Base Color／Roughness／Normal 各 1024²；切口 512²；GLB 內嵌七張 |

模型沒有烘入舊玩家的 0.25 m 腳底偏移，沒有執行時骨架縮放。原始參考圖及既有使用者文件未修改。

## 換色與面具

`suit_dye` 的 Base Color 貼圖是中性灰階，Blender 使用 **Mix / Color / Multiply**，Factor=1，B Color 是染色值；GLB 保存為 texture × `baseColorFactor`。預設線性色彩 `(0.043, 0.071, 0.051, 1)`，另以 `(0.16, 0.09, 0.035, 1)` 完成赭色展示。請改整個共享衣料材質；若不同玩家需不同色，遊戲端需先複製材質，避免修改其他角色。

橘條、銀灰反光中心、黑手套／靴、米色頭套及白面具不使用衣料染色。固定色圖集由黑色、頭套、銀灰、骨截面四個 UV 帶組成；重排 UV 時需保留分區或重烘貼圖。

`mask_default` 為獨立 Mesh、獨立材質，純白 `#FFFFFF`，無眼孔、鼻嘴、紋樣或污漬，100% 跟隨 `head`。Blender 穩定插槽原點為 `(0, -0.088, 1.485)` m，旋轉 0、縮放 1；面具頂點相對此原點。GLB 的節點位置相應為 `(0, 1.485, 0.088)`。替換時使用此位置或以 head 骨插槽保留相對變換。頭套及面具可各自隱藏。

## 分件與雙端封口

完整角色的封口已內縮，邊緣與對應切口頂點一致。封口包含布料厚度環、簡化暗紅組織及米色骨截面。完整角色時不要移動封口；分離時根據下表保留／移走對應端。

| 切口 | 身體端主分件 | 斷肢端主分件 | 封口（身體端 / 斷肢端） | 分離骨鏈起點 |
|---|---|---|---|---|
| neck | body_torso | body_head + mask_default | cap_neck_body / cap_neck_limb | neck → head |
| shoulder.L | body_torso | body_upper_arm.L + body_forearm.L | cap_shoulder.L_body / cap_shoulder.L_limb | upper_arm.L |
| elbow.L | body_upper_arm.L | body_forearm.L（含手套與手） | cap_elbow.L_body / cap_elbow.L_limb | forearm.L |
| shoulder.R | body_torso | body_upper_arm.R + body_forearm.R | cap_shoulder.R_body / cap_shoulder.R_limb | upper_arm.R |
| elbow.R | body_upper_arm.R | body_forearm.R（含手套與手） | cap_elbow.R_body / cap_elbow.R_limb | forearm.R |
| hip.L | body_torso | body_thigh.L + body_shin.L | cap_hip.L_body / cap_hip.L_limb | thigh.L |
| knee.L | body_thigh.L | body_shin.L（含靴與腳） | cap_knee.L_body / cap_knee.L_limb | shin.L |
| hip.R | body_torso | body_thigh.R + body_shin.R | cap_hip.R_body / cap_hip.R_limb | thigh.R |
| knee.R | body_thigh.R | body_shin.R（含靴與腳） | cap_knee.R_body / cap_knee.R_limb | shin.R |

肩切面位於三角肌下方的袖子根部，約比 upper_arm 骨頭端向肘部延伸 10.5 cm，使完整肩線能包住封口。髖切面位於骨盆接大腿处；沒有腰斬。

獨立 GLB 檔名為 `detached_<cut>.glb`，`.` 以 `_` 取代。每份保留 `root` 與分離端子樹；已移除其他祖先骨，跨切口權重重分配到分離骨鏈起點。上臂檔包含前臂、手、五指；大腿檔包含小腿、靴、腳、腳趾。下段尚完整時，其兩個封口也隨上段一起輸出。資產仍使用全身地面座標，不自行搬到切口原點；遊戲生成時需套用角色當下姿態與變換。這些檔案沒有碰撞或剛體模擬。

物理骨規劃為 pelvis / chest / head，加左右 upper_arm、forearm、hand、thigh、shin、foot，共 15 個。骨骼 local Y 沿骨長；左右採一致 roll 參考。`root`、手指、面具及衣物不建立 Blender 剛體。

## 動畫

30 fps，逐幀 FK 烘焙，不依賴 IK、約束或 driver。11 個獨立 Action／NLA track，GLB 每段從 0 秒開始；root 位移、旋轉、縮放固定。世界移動由遊戲控制器負責。

| Action | 秒 | Blender 影格 | 循環 | 腳底位於地面高度的影格 L / R |
|---|---:|---|---|---|
| idle | 2.4 | 1–73 | 是 | 全段 / 全段 |
| walk | 1.2 | 1–37 | 是 | 1–21、35–37 / 1–3、17–37 |
| jump | 0.7 | 1–22 | 否 | 1–9 / 1–9 |
| fall_loop | 0.8 | 1–25 | 是 | 無 / 無 |
| land | 0.4 | 1–13 | 否 | 全段 / 全段 |
| climb_loop | 1.2 | 1–37 | 是 | 無 / 無 |
| hang_idle | 1.6 | 1–49 | 是 | 無 / 無 |
| sit_driver | 2.0 | 1–61 | 是 | 全段 / 全段 |
| hold_small | 2.0 | 1–61 | 是 | 全段 / 全段 |
| carry_large | 2.0 | 1–61 | 是 | 全段 / 全段 |
| injured_idle | 2.4 | 1–73 | 是 | 全段 / 全段 |

接地資料由實際變形後鞋底高度 ±6 mm 測得；時間為 `(frame - 1) / 30`。不是物理接觸事件，坐姿的腳仍在地面高度；在空中或爬牆時是否接觸物體由遊戲判定。

另保留 `QA_overhead`、`QA_grip`、`QA_fists`、`QA_deep_bend`、`QA_prone`、`QA_side_fall`、`QA_missing_arm_L/R`、`QA_missing_leg_L/R` 測試 Action，未混入正式 GLB 動畫。缺肢測試 Action 為中立姿勢；隱藏清單和截图由 `render_review.py` 的 `cut` / `missing` 參數套用，Action 本身不驅動可見性。

glTF 沒有通用循環旗標。隨附 Godot 匯入腳本只恢復 `fall_loop` / `climb_loop` 名稱並設定上述循環旗標，不更動玩家控制、骨架比例或遊戲規則。

## 本轮驗證與限制

本輪 actual GLB 結構檢查、Blender 全 11 段 Action 逐幀變形檢查均無失敗。Godot 4.7.2 統一 runner 的 import、test_player_model、main-scene 通過；檢查包含 1.60 m、55 骨、29 Mesh、5 材質、11 段獨立動畫、九份斷肢、換色、固定色、idle/walk 手肘方向，以及 walk 持續降低重心和彎膝。詳細結果見本輪驗證紀錄，原始機器輸出位於本機 work 與 .godot/test-logs。

已在 Godot Forward+ 模型測試場觀看走路、換色與室內低光效果。此資產仍未接入 player/player.tscn，也未做本輪 RV／第一人稱玩法驗收。衣褶屬低面數手工高度場 Normal，並非高模布料雕刻烘焙；褲襠、衣領與手掌仍較簡化。極端抬臂腋下仍可能拉伸，部分攀爬角度可見細微封口差異；不宣稱所有自穿或動畫混合均已驗收。完整受傷爬行與 death_start 未製作。

## 編輯與重驗

可編輯 .blend 是製作來源；assets/models/player/ 是唯一遊戲交付目錄。保留當前流程脚本：waterproof_fields.py + refine_waterproof_geometry.py（以保留的 REV9_BASE 網格為基準）→ setup_joint_shading.py；waterproof_fields.py + bake_waterproof_material.py 烘貼圖；build_cautious_walk.py 重建 walk；export_current.py 輸出至 work/export 供檢查，再更新正式路徑。以上使用 Blender MCP 分段執行，先確認現有場景，勿對不同尺寸版本直接套用。

Blender MCP 執行 audit_blender.py；Node 執行 audit_glb.mjs（可傳入相對製作目錄的輸出路徑，預設正式資產）。專案 runner 使用 -TestFilter test_player_model.gd。render_review.py 預設來源場景供美術預覽，最終材質與動畫仍以 Godot 的實際 GLB 為準。舊建模腳本已整理到本機 history/cleanup_before_waterproof/legacy_scripts，不是遊戲依賴。
