extends Chassis
## Observes the real solver callback without replacing production collision handling.
var observed_tree: ForestTrunks
var observed_wall: StaticBody3D
var observed_forward := Vector3.FORWARD
var simultaneous_breaks: Array[Dictionary] = []
var peak_contacts := 0
var saturated_callbacks := 0
var observed_tree_steps: Array[Dictionary] = []
var debris_slowdown_frames := 0
var debris_solver_speed_loss := 0.0

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	peak_contacts = maxi(peak_contacts, state.get_contact_count())
	if state.get_contact_count() >= max_contacts_reported: saturated_callbacks += 1
	var tree_contact := false
	var opposing_wall := false
	for contact in range(state.get_contact_count()):
		var collider := state.get_contact_collider_object(contact)
		if collider == observed_tree:
			tree_contact = true
		if collider == observed_wall and state.get_contact_local_normal(contact).dot(observed_forward) < -0.5:
			opposing_wall = true
	var broken_before := observed_tree.broken.size() if is_instance_valid(observed_tree) else 0
	var before := state.linear_velocity.dot(observed_forward)
	var incoming := _impact_velocity.dot(observed_forward)
	super._integrate_forces(state)
	if incoming - before > 0.01:
		for contact in range(state.get_contact_count()):
			var collider := state.get_contact_collider_object(contact)
			if collider is RigidBody3D and collider.get_parent() is TreeFall:
				debris_slowdown_frames += 1
				debris_solver_speed_loss += incoming - before
				break
	if is_instance_valid(observed_tree) and observed_tree_steps.size() < 32 and (observed_tree.broken.size() > broken_before or incoming - before > 0.05):
		var details: Array[Dictionary] = []
		var seen := {}
		for contact in range(state.get_contact_count()):
			var collider := state.get_contact_collider_object(contact)
			var shape := state.get_contact_collider_shape(contact)
			var normal := state.get_contact_local_normal(contact)
			var key := "%d:%d:%s" % [collider.get_instance_id(), shape, normal.snapped(Vector3.ONE * 0.01)]
			if seen.has(key): continue
			seen[key] = true
			var target := TreeImpact.target_for(collider)
			details.append({"collider": str(collider.get_path()), "class": collider.get_class(), "parent_class": collider.get_parent().get_class(), "normal": normal, "shape": shape, "target": target != null, "broken": target.vehicle_tree_is_broken(shape) if target != null else false})
		observed_tree_steps.append({"frame": Engine.get_physics_frames(), "broken": observed_tree.broken.size(), "new_hits": observed_tree.broken.size() - broken_before, "incoming": incoming, "before": before, "after": state.linear_velocity.dot(observed_forward), "details": details})
	if tree_contact and opposing_wall and observed_tree.broken.size() > broken_before:
		simultaneous_breaks.append({"frame": Engine.get_physics_frames(), "contacts": state.get_contact_count(), "incoming": incoming, "before": before, "after": state.linear_velocity.dot(observed_forward)})
