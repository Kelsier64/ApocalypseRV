# 共用汽油罐

`gas_can.glb` 由 `props/gas_can.tscn` 和 `props/gas_can_empty.tscn` 的 `gas_can` 外觀共用。

X×Y×Z = 0.39759523 × 0.84584963 × 0.82353514 m，中心原點、Y-up、寬面 +X、提把沿 Z。8,280 面／8,777 頂點、1 材質、GLB 內嵌 3 張 1024² PNG。Godot 匯入會抽出 `gas_can_0.png`（顏色）、`gas_can_1.png`（ORM）、`gas_can_2.png`（法線）；伴隨 PNG／`.import` 一併保留。兩個場景的原局部位移、盒碰撞與滿／空物品資料保留，灰盒隱藏保留。

可編輯來源、raw、重建與實測限制見 `art_source/gas_can/README.md`。網格有非流形拓樸，使用既有獨立碰撞，不適合作為流形製造網格。GLB SHA-256：`5763771e41607947addf2eabfc7a949d7904e40b1c13ec59fd5ae285b33f802a`。
