# 搜刮物資參考圖：第一批

日期：2026-10-24。階段：供使用者挑選的概念參考，尚未送 ComfyUI 生成 3D 模型，未修改玩法。

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

本次已逐件檢視圖片主體、三分之四視角與完整輪廓，並檢查 PNG 的 RGBA／透明通道。未執行 Godot 或遊戲測試，因為沒有場景或程式變更。3D 生成後仍須另查背面、底部、把手／閥輪孔洞、尺寸及遊戲內光照。
