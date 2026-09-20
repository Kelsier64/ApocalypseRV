extends RefCounted
class_name WorldActorSnapshot
## Shared loose-actor representation for checkpoints and unloaded outdoor sites.
static func capture(child: Node) -> Dictionary:
	if child.is_queued_for_deletion(): return {}
	if child is Prop:
		if is_instance_valid(child.processing_owner): return {}
		return {"kind": "prop", "scene": child.scene_file_path, "transform": child.global_transform,
			"state": child.capture_item_state(), "frozen": child.freeze, "linear": child.linear_velocity, "angular": child.angular_velocity}
	if child is Equipment:
		if child.is_being_placed: return {}
		var data := VehicleSnapshot.device_state(child)
		data["kind"] = "equipment"
		data["transform"] = child.global_transform
		data["frozen"] = child.freeze
		return data
	if child is Monster and not child.is_dead:
		return {"kind": "monster", "scene": child.scene_file_path, "transform": child.global_transform, "health": child.current_health}
	return {}

static func validation_error(actor: Variant, field: String) -> String:
	if not actor is Dictionary or not actor.get("kind") is String: return field + ".kind"
	if SaveSceneCatalog.resolve(actor.get("scene"), actor.kind) == null or actor.kind not in ["prop", "equipment", "monster"]: return field + ".scene"
	if not CheckpointSchema.valid_transform(actor.get("transform")): return field + ".transform"
	match actor.kind:
		"prop":
			if not actor.get("state") is Dictionary or not VehicleSnapshot.valid_prop_state(actor.scene, actor.state): return field + ".state"
			if not actor.get("frozen") is bool: return field + ".frozen"
			if not CheckpointSchema.vector(actor.get("linear")): return field + ".linear"
			if not CheckpointSchema.vector(actor.get("angular")): return field + ".angular"
		"equipment":
			if not VehicleSnapshot.valid_device(actor): return field + ".device"
			if not actor.get("frozen") is bool: return field + ".frozen"
		"monster":
			if not VehicleSnapshot._number(actor.get("health")) or actor.health < 0: return field + ".health"
	return ""

static func restore(saved: Dictionary, container: Node) -> Node3D:
	var actor: Node3D = SaveSceneCatalog.resolve(saved.scene, saved.kind).instantiate()
	container.add_child(actor)
	actor.global_transform = saved.transform
	if actor is Prop:
		actor.restore_item_state(saved.state)
		actor.freeze = saved.frozen
		actor.linear_velocity = saved.linear
		actor.angular_velocity = saved.angular
	elif actor is Equipment:
		actor.freeze = saved.frozen
		VehicleSnapshot.restore_device(actor, saved, null)
		if saved.has("physics"):
			actor.freeze_mode = saved.physics.mode
			actor.collision_layer = saved.physics.layer
			actor.collision_mask = saved.physics.mask
			actor.linear_velocity = saved.physics.linear
			actor.angular_velocity = saved.physics.angular
	elif actor is Monster:
		actor.current_health = saved.health
	return actor
