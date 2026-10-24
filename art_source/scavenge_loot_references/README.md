# 搜刮物資參考圖：第一批

日期：2026-10-24。階段：六件貼圖 3D 模型已生成、校正尺寸與降面，尚未接入遊戲玩法。

每件物資各一張透明 RGBA PNG、單件完整三分之四視角；可將個別 `reference.png` 作為 ComfyUI 單圖輸入。圖片由內建 `image_gen` 生成，完整提示詞由 [prompts.json](prompts.json) 的 `shared_prompt` 加上對應 `subject` 組成。造型強調可辨識的輪廓、厚把手與主要材質分區；細部磨耗在模型製作時應以貼圖表現。

下表尺寸、單／雙手分類與收益皆為提案，不代表現有遊戲規則或已實作功能。尺寸是預計模型外接範圍，單張圖片不保證精確比例。

| 物資 | 參考圖 | 建議尺寸 | 搬運提案 | 用途提案 |
| --- | --- | --- | --- | --- |
| 銅線捲盤 | [PNG](copper_wire_spool/reference.png) | 28 × 24 × 28 cm | 單手 | 可分解為銅與少量鋼材的回收物。 |
| 報廢馬達 | [PNG](salvaged_motor/reference.png) | 42 × 27 × 30 cm | 雙手 | 沉重的高價值回收物，可提供鋼、銅與機械零件。 |
| 故障短波收音機 | [PNG](broken_shortwave_radio/reference.png) | 32 × 12 × 22 cm | 單手 | 可分解為電子元件；是否能修復留待玩法設計。 |
| 密封醫療鐵盒 | [PNG](medical_tin/reference.png) | 30 × 20 × 12 cm | 單手 | 補給容器提案；治療與內容物尚未實作。 |
| 生鏽工業閥門 | [PNG](industrial_valve/reference.png) | 32 × 20 × 36 cm | 單手 | 機械回收物，可提供鋼材與少量黃銅。 |
| 搪瓷熱水壺 | [PNG](enamel_kettle/reference.png) | 27 × 21 × 25 cm | 單手 | 常見生活廢品，可分解回收少量金屬。 |

美術方向沿用 [GDD 工業恐怖規範](../../GDD.md)：低飽和、舊漆、鏽蝕與簡化結構。搜刮工業廢品的題材參考 [Lethal Company 官方介紹](https://store.steampowered.com/app/1966720/Lethal_Company/)，本批為原創道具造型。

參考圖階段已檢查 PNG 的 RGBA／透明通道及完整輪廓。以下為後續實際生成與檢查結果。

## 3D 模型

![六件實際模型渲染](models_preview.png)

每件使用既有 ComfyUI TRELLIS.2 單圖流程，1024、seed 42、生成目標 50k 面，僅提交一次。原始檔保留於各來源目錄的 `raw.glb`，`generation.json` 記錄工作 ID、來源 hash 與原模檢查；`model_parameters.json` 記錄尺寸、旋轉、降面、貼圖 hash 及限制。模型以公尺計、+Y 向上、底部置中，表中尺寸順序為 X／Y／Z。

| 模型 | 原模三角面 | 成品三角面 | 尺寸 cm（X／Y／Z） |
| --- | ---: | ---: | --- |
| [銅線捲盤](../../assets/models/scavenge_loot/copper_wire_spool.glb) | 49,935 | 9,965 | 28／28／24 |
| [報廢馬達](../../assets/models/scavenge_loot/salvaged_motor.glb) | 49,520 | 12,276 | 27／30／42 |
| [故障短波收音機](../../assets/models/scavenge_loot/broken_shortwave_radio.glb) | 49,888 | 5,983 | 32／22／12 |
| [密封醫療鐵盒](../../assets/models/scavenge_loot/medical_tin.glb) | 49,808 | 5,976 | 30／22／18 |
| [生鏽工業閥門](../../assets/models/scavenge_loot/industrial_valve.glb) | 49,490 | 7,360 | 32／36／27 |
| [搪瓷熱水壺](../../assets/models/scavenge_loot/enamel_kettle.glb) | 48,364 | 5,802 | 27／25／21 |

使用 [共用靜態道具工具](../../.agents/skills/comfyui-image-to-3d/references/static-props.md) 與 gltfpack 1.3（ratio 0.12、error 0.025）；誤差限制使部分道具未達 12% 面數，保留實際結果。沒有放寬誤差或強制達標。原本約 297k 面降至合計 47,362 面，嵌入貼圖 bytes 全數保留。

馬達繞 Y 旋轉 180°，醫療箱旋轉 90°，使輸出軸／醫療符號朝 +Z。醫療標記沿用原模，沒有額外新增標記。醫療箱厚度與閥門深度由原先概念提案調整，保留箱體及圓形手輪的比例。

## 本次檢查與限制

- 已在獨立 Godot 4.7.2 檢視器逐件檢視材質／素色的正、側、背、斜、頂、底六視角，並比較校正原模與降面版的斜視角。主要輪廓、把手孔與閥輪開口仍可辨識；單圖未見細節由生成器推測，局部金屬與捲線保留起伏。
- 六件 GLB 的容器、索引與浮點屬性有效；法線／切線檢查無異常。尺寸及底部原點以頂點外接範圍驗證至 1 µm 容差，這不是平面度或支撐穩定度的保證。
- 生成／降面網格仍有非流形邊與重複幾何面；位置以 1 µm 合併後，各件數量記錄於參數檔。銅線捲盤及收音機另有 9／3 條邊界邊，六件均無零面積三角形。這批為靜態道具外觀資產，未宣稱完成乾淨重拓樸或封閉實體。
- 尚未新增碰撞、Item wrapper、拾取、收益或醫療功能，也未做遊戲內持物、場景光照或效能驗證；本次沒有修改場景／遊戲程式或執行行為測試。生成、失敗候選、檢查圖與暫存工具留在已忽略的 `.godot/art-work/scavenge_loot/20261024-01/`。
