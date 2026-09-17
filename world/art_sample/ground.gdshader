shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D ground_texture : source_color, repeat_enable, filter_nearest_mipmap;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 fine = texture(ground_texture, world_position.xz * 0.40).rgb;
	vec3 broad = texture(ground_texture, world_position.xz * 0.034 + vec2(0.31,0.62)).rgb;
	float patch = smoothstep(0.33, 0.58, dot(broad, vec3(0.333)));
	vec3 mud = mix(vec3(0.16,0.20,0.18), vec3(0.36,0.34,0.27), patch);
	ALBEDO = mix(mud, COLOR.rgb * 0.7, 0.20) * (0.67 + fine * 0.75);
	ROUGHNESS = 0.96;
	SPECULAR = 0.12;
}
