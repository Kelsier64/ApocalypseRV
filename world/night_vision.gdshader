shader_type spatial;
render_mode unshaded, fog_disabled, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;

#include "res://world/night_vision.gdshaderinc"
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D scene_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D night_reference : source_color, filter_linear, repeat_disable;

vec3 srgb_to_linear(vec3 value) {
	return mix(value / 12.92, pow((value + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), value));
}

vec3 linear_to_srgb(vec3 value) {
	return mix(value * 12.92, 1.055 * pow(max(value, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), value));
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth * 2.0 - 1.0);
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float distance_to_camera = abs(view.w) > 0.000001 ? length(view.xyz / view.w) : night_fade_end;
	vec3 scene = textureLod(scene_texture, SCREEN_UV, 0.0).rgb;
	vec3 reference = textureLod(night_reference, SCREEN_UV, 0.0).rgb;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	scene = srgb_to_linear(scene);
	reference = srgb_to_linear(reference);
#endif
	// Fill only missing gray adaptation; keep native light, color and shadows.
	float missing = max(dot(reference - scene, vec3(0.2126, 0.7152, 0.0722)), 0.0);
	ALBEDO = scene + vec3(missing * night_curve_visibility(distance_to_camera) * night_strength);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// GLES converts ALBEDO from sRGB before its lighting/output stage.
	ALBEDO = linear_to_srgb(ALBEDO);
#endif
	ALPHA = 1.0;
}
