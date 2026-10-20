shader_type spatial;
render_mode cull_disabled;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float current = sin(world_position.x * 0.55 - TIME * 1.8 + sin(world_position.z * 0.8));
	float ripple = sin(world_position.x * 1.9 - world_position.z * 1.2 - TIME * 2.8);
	ALBEDO = mix(vec3(0.055, 0.14, 0.14), vec3(0.16, 0.27, 0.24), current * 0.15 + ripple * 0.06 + 0.36);
	ROUGHNESS = 0.26;
	SPECULAR = 0.65;
	NORMAL_MAP = vec3(0.5 + ripple * 0.06, 0.5 + current * 0.08, 1.0);
}
