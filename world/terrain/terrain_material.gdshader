shader_type spatial;
render_mode cull_back;
varying vec3 world_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float grain = fract(sin(dot(floor(world_position.xz * 3.0), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = COLOR.rgb * mix(0.91, 1.07, grain);
	ROUGHNESS = 0.98;
}
