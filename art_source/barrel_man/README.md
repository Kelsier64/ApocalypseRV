# 油桶人 Blender 來源

2026-10-07，使用本機 Blender **5.2.2 LTS + Blender MCP** 完成建模、UV、膚色烘焙、綁定、動畫、檢視及 GLB 匯出。沒有覆寫原油桶；工作場景為 `BARREL_MAN_AUTHORING`，原先開啟的 Blender 場景保留。

- [可編輯來源](barrel_man.blend)：人腿網格、11 根骨骼、10 組 60 Hz Action、打包膚色圖、桶身參考及檢視攝影棚。
- [遊戲 GLB](../../assets/models/barrel_man/barrel_man.glb)：只輸出雙腿、趾甲、骨架與動畫，共 **42,846 三角面**；桶身由遊戲共用 [原油桶](../../assets/models/oil_barrel/oil_barrel.glb)，不重複烘進 GLB。
- [膚色圖](skin_basecolor.png)：2048×2048，Blender 程序污垢材質烘焙。材質與網格為本次製作；桶身來源沿用 [油桶來源紀錄](../oil_barrel/README.md)。
- [初版功能驗收](../../docs/validation/2026-10-07-barrel-man.md)及[腳部細修驗收](../../docs/validation/2026-10-07-barrel-man-feet.md)。

腳部第二版重塑內外踝、阿基里斯腱、腳跟、內側足弓及前腳掌；五趾有不同長短、圓潤趾腹與淺關節皺褶。趾甲以實際趾面射線定位，使用貼合皮膚的薄曲面與窄自由緣。踝部蒙皮限制在下脛／跟腱區，避免彎踝時拉扯整個腳背。初版完整 `.blend` 與 GLB 保留在 [versions/feet_v1](versions/feet_v1/)。

桶身高 1 m、直徑約 0.65918 m，站立總高約 1.9 m。Godot 根原點在地面；Blender Z 向上、面向 -Y，遊戲視覺子節點轉 180° 對齊角色 -Z 前方。`barrel` 骨掛載原桶，`pelvis`、左右 thigh/shin/foot/toes 控制雙腿；網格包括髕骨、小腿、踝骨、腳跟、足弓、五趾及趾甲。

## 製作與再匯出

以下腳本的內容交給 **Blender MCP `execute_blender_code`** 執行，不以外部 Blender 批次程序替代。建立模型只在乾淨的新工作場景執行一次；之後動畫與渲染腳本可以重跑。

1. [build_model.py](build_model.py)：建立與合併解剖網格、UV、烘焙、蒙皮。此腳本建立新場景，重跑前應先另存自己的修改。
2. [optimize_model.py](optimize_model.py)：在靜止網格上減面到遊戲預算，校正腳底；有已執行標記，避免重複減面。
3. [refine_feet.py](refine_feet.py)：以保存的初版上腿網格為基準重建腳部、連接成封閉網格、重綁下肢與烘焙 2K 膚色。可重跑；不反覆減面上腿。烘焙後移除舊 packed payload、重新載入並打包 PNG，防止 GLB 帶入過期貼圖。
4. [animate_export.py](animate_export.py)：重建本資產的 Action，60 Hz 烘焙與選取／active-scene-only 匯出。保留其他場景；GLB 不含攝影棚或桶身參考。
5. [render_review.py](render_review.py)：建立攝影棚及全身檢視；[render_feet_review.py](render_feet_review.py)輸出新版腳部正面、後跟、足弓、趾甲及動作近景，並另存 `.blend` 副本。

| 動畫 | 秒 | 播放 |
|---|---:|---|
| disguised | 1 | 循環，腿完整藏入桶內 |
| rise / retract | 0.8 | 單次，先落腳再撐起；收腿反向 |
| idle | 2 | 循環，輕微重心起伏 |
| run / turn_left / turn_right | 34/60 | 循環，6 m/s 基準 |
| sprint | 28/60 | 循環，10 m/s 基準 |
| fall | 1 | 循環 |
| land | 0.4 | 單次 |

Godot 依實際速度調步頻，過渡按遊戲階段 seek；有限雙骨 IK 只修正支撐腳的地面高度（-8 到 +10 cm），保留原動畫的腳跟／腳趾蹬地高度，不移動角色根節點。跑動落地保留步態並疊加短暫重心下壓，停下落地播放 land。遊戲只依實際碰撞觸發爆炸，動畫不提供攻擊事件。

`test_barrel_man_assets.gd` 在 Godot 匯入後逐一檢查全部動畫每個 60 Hz 姿勢、骨骼／權重、循環端點、桶內隱藏、桶壁交界、腳底與爆點掛點。數值與幾何測試不取代遊戲畫面驗收。
