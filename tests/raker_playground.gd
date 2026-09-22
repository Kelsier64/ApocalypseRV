extends "res://tests/monster_pursuit_playground.gd"
var clip_index := 0
var preview := false
var clips: Array[String] = ["idle","walk","chase","sprint","attack_left","attack_right","crouch_idle","crouch_walk","crouch_attack","climb_loop","hang_idle","attack_door","mantle","roof_settle","attack_down","slip_loop","fall_loop","land","hit_react","death","crouch_hit_react","crouch_land","crouch_death"]

func _ready() -> void:
	monster_scene = preload("res://enemies/raker.tscn")
	super._ready()
	DisplayServer.window_set_title("Raker 2.18m — Behavior & Animation")
	var camera := get_viewport().get_camera_3d()
	camera.position = Vector3(6,3,6)
	camera.look_at(Vector3(2,1,0))
	status.add_theme_font_size_override("font_size",18)
	status.position.y=120

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode==KEY_R:
		get_tree().reload_current_scene()
		return
	if not is_instance_valid(monster): return
	match event.keycode:
		KEY_F6: monster.take_damage(10)
		KEY_F7: monster.take_damage(10000)
		KEY_F8:
			preview = true
			monster.set_physics_process(false)
			monster.get_node("BodyMesh").set_process(false)
			monster.position=Vector3(2,-.25,0)
			monster.rotation.y=0
			monster.get_node("BodyMesh").play(clips[clip_index],1,true)
			clip_index=(clip_index+1)%clips.size()
		KEY_SPACE:
			player.position.x = 4 if player.position.x < 5 else 7
		KEY_F9:
			var anim: AnimationPlayer=monster.get_node("BodyMesh").animation_player
			anim.seek(anim.current_animation_length*.6,true)
			anim.pause()

func _process(_delta: float) -> void:
	if not is_instance_valid(monster):
		status.text="Raker defeated — R: restart"
		return
	var raker := monster as Raker
	status.text="RAKER | standing 2.18 m | HP %.0f | Player HP %.0f\nAnimation: %s | attack time %.2f | crouched %s\nF6 hit reaction / cancel attack | F7 death | Space evade\nF8 next animation preview | R restart live AI" % [monster.current_health,player.current_player_health,monster.get_node("BodyMesh").animation_player.current_animation,raker.strike_elapsed,str(raker.crouched)]
