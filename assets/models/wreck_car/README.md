# Shared wreck car

單車、雙車、翻覆與起始 28 輛封路共用之靜態外觀；5,366 三角面，地面中心原點、Y up、車頭 +Z。
車體 GLB 內嵌貼圖；Godot 抽取的 PNG／.import 是正式 wrapper 材質使用的資源。
場景應引用 wreck_car.tscn：它給獨立 BodyPaint 網格設定 roadside_paint.tres 的 RoadsidePaint material_override，供 minor_appearance.gd 調色。
保持既有場址 Model 擺位及獨立 Collision。可編輯來源在 `../../../art_source/wreck_car/`。
