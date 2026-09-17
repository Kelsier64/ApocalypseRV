shader_type spatial;
render_mode cull_back;
varying vec3 world_position;
uniform sampler2D ground_texture : source_color, repeat_enable, filter_nearest_mipmap;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float grain = fract(sin(dot(floor(world_position.xz * 3.0), vec2(12.9898, 78.233))) * 43758.5453);
	vec3 mud = texture(ground_texture, world_position.xz * 0.42).rgb;
	vec3 broad = texture(ground_texture, world_position.xz * 0.057 + vec2(0.37, 0.61)).rgb;
	ALBEDO = COLOR.rgb * mix(vec3(0.88), mud * 2.6, 0.55) * mix(0.93, 1.05, grain) * mix(vec3(0.9), broad * 2.5, 0.22);
	ROUGHNESS = 0.98;
}
