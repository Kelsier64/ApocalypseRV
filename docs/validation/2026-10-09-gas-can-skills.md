# 汽油罐與 3D／ComfyUI skill 實測

日期：2026-10-09。專案：`C:/Users/evan4/Projects/ApocalypseRV`。

已完成共用油罐外觀並接入 `props/gas_can.tscn`／`props/gas_can_empty.tscn`。正式模型在 `assets/models/gas_can/gas_can.glb`；來源在 `art_source/gas_can/`，包含可編輯 glTF、重建腳本、原圖、raw 和原始灰盒場景。沒有使用或改寫收存原件。

## 模型與整合

成品 8,280 三角面、8,777 頂點、單 mesh／材質、3 張內嵌 1024² PNG；相較 48,849 面 raw 減少約 83.05%。原圖由內建 imagegen 製作，最終提示詞保存在 `art_source/gas_can/reference_prompt.txt`。本機 ComfyUI 0.38.0、TRELLIS.2 INT8，seed 42、1024；只提交一次，prompt `2743e998-597f-441d-9c64-d41bcba75a62`，98.41 秒完成。

Godot 匯入抽出的 `gas_can_0.png`／`gas_can_1.png`／`gas_can_2.png` 與 `.import` 一併保留；三張 PNG bytes 與 GLB 內嵌圖片相同。

raw SHA：`817dfcc86fe89190d80df2bc8f5437bd91483adb63273fb1bddee962e5999976`。
正式 GLB SHA：`5763771e41607947addf2eabfc7a949d7904e40b1c13ec59fd5ae285b33f802a`。

raw 寬面原在 +Z，Y 軸旋轉 +90° 後烘焙到 +X，再置中及校正尺寸；場景位移沒有烘進模型。Godot 匯入兩場景均量得約 **0.397595227 × 0.845849633 × 0.823535144 m**，外觀中心等於既有局部位移 `(0.0022521876, -0.028735355, -0.0045410395)`，容差 10 µm。碰撞尺寸／位置、質量、layer／mask、兩個名稱、回收及保存路徑均保留；+X 射線仍命中原物品碰撞。

提把孔用灰模六視角及沿 X 的射線確認貫通；罐蓋封閉、X 壓紋保留。提把／蓋在尺寸內；無液面、rig、動畫或活動件。滿空罐共用形狀。兩場景保留隱藏的 `GasCanGraybox`，另保留原場景 bytes。

減面使用現有官方 gltfpack 1.3。`-se 0.01` 的 0.16／0.08 比例候選停在 11,104／11,118 面，沒有宣稱達到要求面數；選擇 `-si 0.12 -se 0.02 -sp -sv -noq -kn -km` 的 8,280 面版本。正位／尺寸校正後對照原模、候選的貼圖和受光灰模；六方向包含背面、頂部及底部。三張圖片 SHA 完全保留。面數預算以可近看的 .85 m 道具先取約 8k、上限 10k；尚未量測多罐 FPS。從 raw 在新資料夾重建，正式 GLB SHA 完全相同。

## 本次驗證

Godot 4.7.2，專案 runner 本次耗時 33.91 秒。匯入和以下檢查全部 PASS：

- `test_item_player`：實際加油生成空罐，新增空罐磁碟保存／讀取、場景路徑與 ID／完整狀態保留，重新持握與丟棄。
- `test_player_item_release`：新增滿／空罐，驗證實際拾取、持握／刷新／不同俯仰丟棄的尺寸、變換、ID、品質及物理連續性。
- `test_rv_interactions`、`test_rv_resource_cycle`、`test_rv_experience`、`test_item_persistence`。
- 正式主場景 smoke。

另擴充並執行 `test_rv_checkpoint`：滿／空罐經真實整世界檢查點寫入磁碟、釋放舊世界、重建後各只還原一次，保留 gameplay 場景路徑、ID、37% 品質與共享 GLB。該測試 PASS，23.91 秒（包含匯入，行為 19.54 秒）。因此本次合計七項行為回歸及主場景 smoke 通過。

原生 Forward+／Vulkan 預覽實例化正式滿／空道具及玩家，尺寸／位移／碰撞射線 PASS，並看過地面成對與玩家持物截圖。沒有進行手動完整玩家探索；保存驗證包含加油回空罐的生產背包磁碟序列化與滿／空世界物品的完整檢查點重建。原生預覽、匯入及所選回歸日誌無 SCRIPT ERROR／ERROR。`git diff --check` 通過。

執行命令：

```powershell
& ./scripts/test.ps1 -Godot 'C:/Program Files/godot/godot.exe' -TestFilter 'test_item_player.gd,test_player_item_release.gd,test_rv_interactions.gd,test_rv_resource_cycle.gd,test_rv_experience.gd,test_item_persistence.gd' -Smoke
& ./scripts/test.ps1 -Godot 'C:/Program Files/godot/godot.exe' -TestFilter 'test_rv_checkpoint.gd'
```

## Skill 問題回報

本次使用專案 `.agents/skills/apocalypse-rv-3d-scenes/SKILL.md`、`.agents/skills/comfyui-image-to-3d/SKILL.md`；沒有擅自修改這兩份 skill。

1. **生成產物與 client 驗證缺口：4 個零長度切線。** `collect` 會通過容器、索引、有限 POSITION 與圖片檢查，但未檢查 NORMAL／TANGENT 的有限值、單位長度及正交性。實際 raw 有 4 個零切線；在副本以 UV 鄰面重建切線，最後為 0，法線／切線長度最大誤差約 5.96e-8，正交點積最大約 8.94e-8。建議擴充技術驗證，不把 `ART_REVIEW_REQUIRED` 視為美術或全網格驗收。

2. **生成／減面拓樸仍有限制。** 尺寸校正的 48k 原模已有 924 條非流形邊；所選減面版在 1 µm 位置合併診斷下有 1,234 條非流形邊、221 個重複幾何三角形餘項，0 邊界邊、0 零面積三角形。`collect` 不診斷此項。六視角與原生預覽未見破洞／明顯閃爍，但未修成流形網格；已記錄為成品限制。物理採用原有獨立 BoxShape3D，沒有從生成網格建立碰撞。

3. **Windows runtime／沙箱環境。** PATH `python` 指向無法啟動的 WindowsApps 別名，改用 `load_workspace_dependencies` 的 bundled Python。離線測試初次在預設 sandbox TEMP 被拒寫；將 TEMP／TMP 限定至本次工作目錄後 **7/7 PASS**。這是環境限制，不是 7 個 client 測試本身故障。建議 skill 操作說明補上可寫暫存路徑的例子。

4. **服務預設未啟動。** 8000／8188 在沙箱外仍 WinError 10061。找到並執行既有 `Apps/Pixal3D-API-v2/start.ps1` 後，preflight／submit／collect 全部成功，無需下載、安裝或更改 preset。這是服務狀態，不是生成 graph 故障。

3D scene skill 的離線替代、尺度／軸向／wrapper 檢查和成本評估流程可完成本次任務。ComfyUI review renderer 的 `front` 固定為顯示 +Z；本資產正面 +X，所以最終代表圖使用純剛體檢視旋轉並保存 `review_pose.json`，沒有將相機標籤當作遊戲語義證明。

其他限制：單圖背面／底部是推測；沿用既有持物位置，近景靠近鏡頭。沒有多罐效能實測或重新拓樸。完整工作證据留在專案已忽略的 `.godot/art-work/gas_can/20261009-01/`；正式交付只保留必要來源、參數、精簡結果與代表圖。


## 後續：使用者要求的最小 skill 修正

上文保留首次建模時的問題回報；其後依使用者要求，僅修改專案的 ComfyUI skill 三個檔案。
`generate.py` 檢查存在的 NORMAL／TEXCOORD_0／TANGENT 數量及有限值，拒收非有限值或數量不符；零長度／非單位方向、非正交切線與 handedness 異常則寫入 `technical_checks.attribute_issues`。
收檔仍保留原 raw、等待美術檢查，不自動修模型或重新送出生成工作；`topology_checked:false` 明確表示另查拓樸。
`test_client.py` 新增 raw 保留／不重送及屬性異常回歸，11/11 PASS。實際原 raw 回報 4 個零切線，正式模型回報全部零異常。
SKILL.md 補充上述流程、已驗證服務啟動及可寫 TEMP／TMP；用詞已改為後續由 agent 修復工作副本。
兩份專案 skill 的 quick_validate 通過。3D scene skill 和使用者全域 skill 未修改。
