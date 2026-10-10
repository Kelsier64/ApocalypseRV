# 共用事故車來源

使用者確認的 V3 參考圖在 `../../docs/modeling/requests/wreck-car/wreck-car-image-to-3d-reference.png`，依遊戲 D 版簡化低模／粗略材質方向製作。
editable/ 為最終可編輯 glTF、BIN 與三張 PNG，和正式 GLB 的幾何及貼圖相同；參數、來源雜湊與接入轉換在 model_parameters.json。

5,366 三角面；X [-1.22,1.22]、Y [0,2]、Z [-2.34,2.39] m，地面車體中心原點，Y up、車頭 +Z。
BodyPaint、Metal、Glass、Rubber 為四個獨立網格。正式 wrapper `../../assets/models/wreck_car/wreck_car.tscn` 為 BodyPaint 掛上 resource_name=RoadsidePaint 的 material_override；不依賴 GLB 材質名稱觸發色差。材質與網格共用，場址腳本在 _ready 複製烤漆 override 後調色。
金屬底盤保留完整；玻璃與輪胎降低反光以符合遊戲風格。沒有動畫、骨架、碰撞或附加遊戲腳本。

單圖背面與底部為生成推測。以 1 µm 位置合併診斷，仍有 199 條非流形邊、88 個重複三角形；無開放邊或零面積面。此為靜態外觀，物理沿用場景獨立盒碰撞。
raw、graph、候選、檢查工具、場景備份和完整截圖保留於忽略目錄 `.godot/art-work/wreck_car/20261009-01/`，未列入 Git 交付。
