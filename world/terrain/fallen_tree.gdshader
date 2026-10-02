shader_type spatial;
render_mode cull_disabled;

uniform sampler2D surface_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool use_vertex_color = true;
uniform vec3 ground_origin;
uniform vec3 fall_direction;
uniform float ground_slope = 0.0;
uniform float compression : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ground = ground_origin.y + dot(world.xz - ground_origin.xz, fall_direction.xz) * ground_slope;
	// Settled leaf clusters form a thin layer above sampled terrain.
	world.y = mix(world.y, max(world.y, ground + 0.04), compression);
	VERTEX = (inverse(MODEL_MATRIX) * vec4(world, 1.0)).xyz;
}

void fragment() {
	vec4 sample_color = texture(surface_texture, UV) * tint;
	if (use_vertex_color) sample_color *= COLOR;
	ALBEDO = sample_color.rgb;
	ROUGHNESS = 1.0;
	ALPHA = sample_color.a * (1.0 - fade);
	ALPHA_HASH_SCALE = 1.0;
}
