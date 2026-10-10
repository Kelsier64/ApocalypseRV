# Shelter roof air handler

靜態屋頂裝飾，正式模型為 `../../assets/models/shelter_roof_air_handler/shelter_roof_air_handler.glb`。
包圍盒 6 × 2 × 4 m，中心原點、Y 向上、進氣面 +Z。模型不烘入場景位置。
指定 `world/starting_shelter/exterior_extension.tscn` 的 `Visuals/RoofPlantA` 現置於 (-17.7,10,9.8) 的左翼屋頂前緣，保持單位縮放。
獨立碰撞同步移位／導航標記完整保留；隱藏的 RoofPlantAGraybox 和 graybox/ 原場景可供比對。

沿用專案提供的透明參考圖，2026-10-09 單次 TRELLIS.2 / 1024 / seed 42 生成。
raw.glb 為未修改的 49,998 面來源；editable/ 是整理後 5,998 面的可編輯 glTF、BIN 與 PNG。
三張內嵌貼圖 bytes 完整保留；貼圖依 glTF 材質使用 base color、ORM 與 tangent normal。
先 Y -90°、逐軸尺寸校正與置中，再 gltfpack 1.3 -si .12 -se .02 -sp -sv -noq -kn -km，
最後重新校正尺寸及正交化切線。參數、雜湊、幾何與實際場景檢查存於 JSON。

重建需 Python + numpy 和 gltfpack 1.3，必須指定新工作目錄：
`python -B rebuild.py --gltfpack <gltfpack.exe> --output <new-directory>`。
腳本核對來源／輸出 SHA256；生成與候選完整本機證據在忽略的 `.godot/art-work/shelter_roof_air_handler/20261009-01/`。

限制：背面百葉由單圖推測；罩口／百葉為靜態外觀近似，無內部機械。
以 1 µm 位置合併統計，成品有 11 條非流形邊和 2 個重複三角形；無開放邊、零面積面。
適用既有獨立 BoxShape3D 的屋頂裝飾，未宣稱可製造流形或物理網格。
沒有多機組 FPS 測量或人工遊戲巡查。參考圖來源沿用專案既存檔案，未新增來源／授權核實。
