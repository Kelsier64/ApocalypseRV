# 屋頂過濾設備組

正式 GLB：`../../assets/models/shelter_roof_filter_bank/shelter_roof_filter_bank.glb`。
editable/ 提供可編輯 glTF、BIN 與三張 PNG；單組三箱、共同底架與後方密閉風道，無動畫／活動機構。
5,998 三角面，包圍盒 9 × 1.5 × 5 m、中心原點、Y up、主要維修面 +Z。
場景節點 RoofPlantB 放在東翼屋頂前緣 (17.7,11.75,9.8)，保持單位縮放；碰撞與混凝土支座同步移位，導航標記保留，原灰盒保留並隱藏。

沿用專案參考圖、TRELLIS.2 1024／seed 42。原圖／來源授權本次未新增核實。
原生成風道分離，在副本將後方風道及附屬件原座標 Z -0.05 接回箱體，未做 boolean union。
Y 180° 朝向校正後逐軸尺寸與中心校正；gltfpack 1.3 以 .12 比例／.02 誤差降面，最後重新校正尺寸並正交化切線。
詳細參數與來源／成品 SHA256 在 model_parameters.json。三張貼圖 bytes 保留。

背面／底部為單圖推測，濾網主要以材質呈現。
1 µm 位置合併診斷下，成品有 18 條非流形邊及 6 個重複三角形；無開放邊／零面積面，未宣稱流形或物理網格。
原 raw、生成 graph、完整候選、整理／檢查工具與截圖都保留在忽略目錄 `.godot/art-work/shelter_roof_filter_bank/20261009-01/`。
