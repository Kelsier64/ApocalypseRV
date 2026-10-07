shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_front;

// Baked fire/soot density in a bounded volume. Back faces cover the viewport
// when the eye enters it; opaque scene depth stops integration before walls.
uniform sampler2D atlas : source_color, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float age = 0.0;
uniform float animation_duration = 5.5;
uniform bool is_fire = false;
uniform float volume_size = 10.0;
varying mat4 volume_from_view;

void vertex() {
	volume_from_view = inverse(MODELVIEW_MATRIX);
}

vec4 frame_sample(float frame, vec2 uv) {
	vec2 cell = vec2(mod(frame, 8.0), floor(frame / 8.0));
	vec2 tile_uv = clamp(uv, vec2(0.5 / 256.0), vec2(1.0 - 0.5 / 256.0));
	return texture(atlas, (cell + tile_uv) / 8.0);
}

void fragment() {
	vec3 origin = (volume_from_view * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 ray = normalize((volume_from_view * vec4(normalize(VERTEX), 0.0)).xyz);
	vec3 half_size = vec3(volume_size * 0.5);
	vec3 inv_ray = 1.0 / (ray + vec3(0.000001));
	vec3 t0 = (-half_size - origin) * inv_ray;
	vec3 t1 = (half_size - origin) * inv_ray;
	vec3 lower = min(t0, t1);
	vec3 upper = max(t0, t1);
	float entry = max(0.0, max(lower.x, max(lower.y, lower.z)));
	float exit_t = min(upper.x, min(upper.y, upper.z));

	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	if (scene_depth > 0.000001) {
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc.z = scene_depth * 2.0 - 1.0;
#endif
		vec4 scene_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		vec3 scene_local = (volume_from_view * vec4(scene_view.xyz / scene_view.w, 1.0)).xyz;
		exit_t = min(exit_t, dot(scene_local - origin, ray));
	}
	if (exit_t <= entry) { discard; }

	// Preserve world-up while rotating the baked profile about its vertical axis.
	vec3 right = (volume_from_view * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
	right.y = 0.0;
	right = length(right) > 0.0001 ? normalize(right) : vec3(1.0, 0.0, 0.0);
	vec3 forward = cross(right, vec3(0.0, 1.0, 0.0));
	float progress = clamp(age / animation_duration, 0.0, 1.0);
	float clock = (1.0 - pow(1.0 - progress, 2.0)) * 63.0;
	float frame = floor(clock);
	float next_frame = min(frame + 1.0, 63.0);
	float frame_blend = fract(clock);
	float radius = is_fire ? 1.25 : mix(0.9, 2.5, smoothstep(0.0, 2.0, age));
	float tail = is_fire ? (1.0 - smoothstep(4.8, 5.5, age)) : (1.0 - smoothstep(3.8, 8.0, age));
	float step_size = (exit_t - entry) / 12.0;
	vec4 accumulated = vec4(0.0);
	for (int i = 0; i < 12; i++) {
		vec3 point = origin + ray * (entry + (float(i) + 0.5) * step_size);
		vec2 uv = vec2(dot(point, right) / volume_size + 0.5, 0.5 - point.y / volume_size);
		float depth_profile = exp(-4.0 * pow(dot(point, forward) / radius, 2.0));
		if (uv.x > 0.0 && uv.x < 1.0 && uv.y > 0.0 && uv.y < 1.0 && depth_profile > 0.002) {
			vec4 a = frame_sample(frame, uv);
			vec4 b = frame_sample(next_frame, uv);
			float opacity = mix(a.a, b.a, frame_blend);
			vec3 color = mix(a.rgb * a.a, b.rgb * b.a, frame_blend) / max(opacity, 0.0001);
			float density = -log(max(1.0 - opacity, 0.001)) * (is_fire ? 2.4 : 3.0);
			float sample_alpha = 1.0 - exp(-density * depth_profile * step_size / (radius * 0.886));
			sample_alpha *= tail;
			float weight = sample_alpha * (1.0 - accumulated.a);
			accumulated.rgb += color * weight;
			accumulated.a += weight;
		}
	}
	if (accumulated.a < 0.001) { discard; }
	ALBEDO = accumulated.rgb / max(accumulated.a, 0.0001) * (is_fire ? 3.2 : 0.9);
	ALPHA = accumulated.a;
}
