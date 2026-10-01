extends StaticBody3D
var run: Node

func get_interaction_prompt(_player: Node3D) -> String:
	if not is_instance_valid(run): return ""
	match run.phase:
		"preparing": return "啟程按鈕｜E 開啟車庫並出發\n車輛離開後大門永久封閉，留下的物資將無法取回"
		"opening": return "車庫大門開啟中"
		"started": return "旅程已開始｜請駕駛 RV 駛離車庫\n離開後大門永久封閉"
		"closing": return "車庫大門正在封閉｜請保持距離"
		_: return "車庫已永久封閉"

func interact(player: Node3D) -> String:
	if not is_instance_valid(run): return ""
	return run.begin_run(player)
