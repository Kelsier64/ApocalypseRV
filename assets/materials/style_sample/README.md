# 工業美術樣板材質

本目錄為本專案原創 SVG，直接以向量與程序排列製作；本輪沒有使用 image_gen，也未使用 Lethal Company 的遊戲資產。

- `panel.svg`：面板暗縫、邊緣高光、螺栓、底部大塊磨耗；每個面使用自己的 UV。
- `concrete.svg`：澆築接縫、雨痕、下緣積污；三向投影維持世界尺度。
- `bark.svg`：縱向裂溝和樹節。
- `needles.svg`：透明底枝葉剪影，使用 alpha scissor；避免完整封閉圓錐樹冠。

全部啟用 mipmap，採 nearest with mipmaps。針葉採雙面材質；有深度寫入的裁切葉片不同於透明混合，但仍需量測大量重疊葉片的繪製成本。

樣板地面沿用上一輪生成的 `../industrial/forest_floor.png`，其來源與提示詞見該目錄 README。天空使用固定程序雲層，沒有動態天氣。

僅由 `tests/industrial_style_playground.tscn` 及 `world/art_sample/` 使用，未替換正式世界資源。
