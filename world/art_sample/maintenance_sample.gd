extends Node3D
## Taller upper workshop volume over the existing 9x9 solid shell.
## All additions are visual; entry, return landing and ground collision stay intact.

func _ready() -> void:
	var steel := SampleMaterials.surface("panel", Color("50605e"))
	var pale := SampleMaterials.surface("panel", Color("b1b4a2"))
	var dark := SampleMaterials.surface("flat", Color("1c2626"))
	var concrete := SampleMaterials.surface("concrete", Color("a5a99b"))
	var rust := SampleMaterials.surface("panel", Color("925d43"))
	var yellow := SampleMaterials.surface("panel", Color("c0a166"))
	# Substantial upper facade; the existing roof supports this inaccessible volume.
	SampleMaterials.box(self, Vector3(9.1, 3.8, 8.9), Vector3(0, 7.25, 0), steel)
	for x in [-4.6, -1.55, 1.55, 4.6]:
		SampleMaterials.box(self, Vector3(0.23, 9.5, 0.35), Vector3(x, 4.75, 4.72), dark)
	for y in [5.35, 9.22]:
		SampleMaterials.box(self, Vector3(9.6, 0.2, 0.45), Vector3(0, y, 4.7), dark)
	# Three sawtooth bays with dirty clerestory panes and heavy black mullions.
	for x in [-3.05, 0.0, 3.05]:
		var roof := SampleMaterials.box(self, Vector3(3.25, 0.22, 9.65), Vector3(x, 9.65, 0), rust)
		roof.rotation.z = 0.26
		SampleMaterials.box(self, Vector3(2.72, 1.7, 0.05), Vector3(x, 7.88, 4.48), dark)
		for j in range(4):
			var at := Vector3(x - 1.0 + j * 0.67, 8.05, 4.53)
			SampleMaterials.box(self, Vector3(0.55, 1.25, 0.06), at, SampleMaterials.surface("panel", Color("707f78") if j % 3 != 0 else Color("263a39")))
	# Retain the production chimney's position and dimensions.
	SampleMaterials.box(self, Vector3(3, 17, 3), Vector3(2.5, 8.5, -2), rust)
	for y in [5.0, 10.0, 14.0, 16.5]:
		SampleMaterials.box(self, Vector3(3.2, 0.18, 3.2), Vector3(2.5, y, -2), dark)
	SampleMaterials.box(self, Vector3(3.05, 0.2, 3.05), Vector3(2.5, 17.05, -2), dark)
	# Recessed entrance: keep clear 3m door aperture and existing canopy collision.
	for side in [-1.0, 1.0]:
		SampleMaterials.box(self, Vector3(2.68, 4.95, 0.065), Vector3(side * 3.03, 2.5, 4.64), concrete)
		SampleMaterials.box(self, Vector3(2.7, 1.3, 0.07), Vector3(side * 3.03, 0.67, 4.69), steel)
		SampleMaterials.box(self, Vector3(0.18, 3.48, 0.22), Vector3(side * 1.54, 1.74, 4.75), dark)
		SampleMaterials.box(self, Vector3(0.08, 3.3, 0.04), Vector3(side * 1.4, 1.65, 4.79), yellow)
		SampleMaterials.box(self, Vector3(0.25, 4.7, 0.25), Vector3(side * 4.05, 2.4, 4.84), rust)
		for y in [0.7, 2.4, 4.2]:
			SampleMaterials.box(self, Vector3(0.36, 0.11, 0.30), Vector3(side * 4.05, y, 4.85), dark)
	SampleMaterials.box(self, Vector3(3.05, 0.18, 0.25), Vector3(0, 3.48, 4.74), dark)
	for x in [-0.75, 0.75]:
		SampleMaterials.box(self, Vector3(1.44, 3.35, 0.035), Vector3(x, 1.70, 4.64), steel)
		SampleMaterials.box(self, Vector3(0.46, 0.58, 0.02), Vector3(x, 2.48, 4.68), dark)
		SampleMaterials.box(self, Vector3(0.44, 0.045, 0.065), Vector3(x, 1.18, 4.71), pale)
	SampleMaterials.box(self, Vector3(3.8, 0.7, 0.09), Vector3(0, 4.77, 4.77), dark)
	SampleMaterials.caption(self, "NORTHLINE / 07", Vector3(0, 4.8, 4.83), 28)
	SampleMaterials.caption(self, "SERVICE ACCESS", Vector3(0, 3.76, 4.80), 16)
	SampleMaterials.caption(self, "07", Vector3(-3.08, 3.25, 4.73), 100, Color("cdc8aa"))
	SampleMaterials.box(self, Vector3(0.95, 0.57, 0.03), Vector3(2.52, 2.3, 4.73), yellow)
	SampleMaterials.caption(self, "DANGER\nHIGH VOLTAGE", Vector3(2.52, 2.3, 4.76), 10, Color("242e2c"))
	# Overhead service pipes break the front into depth layers without blocking it.
	for y in [5.65, 6.14]:
		SampleMaterials.beam(self, Vector3(-4.65, y, 5), Vector3(4.65, y, 5), 0.22, rust)
		for x in [-3.9, 0.0, 3.9]:
			SampleMaterials.box(self, Vector3(0.11, 0.4, 0.42), Vector3(x, y, 5), dark)
	for x in [-3.6, 3.6]:
		# Physical poles already exist here in the base shell.
		for y in [0.25, 0.5, 0.75, 1.0]:
			SampleMaterials.box(self, Vector3(0.34, 0.12, 0.34), Vector3(x, y, 7), yellow if int(y * 4) % 2 == 0 else dark)
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color("ecd9a0")
	lens.emission_enabled = true
	lens.emission = Color("ffd592")
	lens.emission_energy_multiplier = 2.2
	SampleMaterials.box(self, Vector3(1.1, 0.08, 0.18), Vector3(0, 3.85, 5.1), lens)
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, 3.80, 5.1)
	lamp.rotation_degrees.x = -67
	lamp.light_color = Color("ffd6a0")
	lamp.light_energy = 5.5
	lamp.spot_range = 10
	lamp.spot_angle = 68
	lamp.shadow_enabled = true
	add_child(lamp)
	# Small bounce light reveals handles, without lifting the entire facade.
	var bounce := OmniLight3D.new()
	bounce.position = Vector3(0, 2.3, 5.4)
	bounce.light_color = Color("e9c087")
	bounce.light_energy = 1.1
	bounce.omni_range = 4
	bounce.shadow_enabled = true
	add_child(bounce)
