shader_type spatial;
render_mode unshaded, fog_disabled, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;

#include "res://world/night_vision.gdshaderinc"
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D scene_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D night_reference : source_color, filter_linear, repeat_disable;
uniform float adaptation_dark_ratio = 0.1;
uniform float adaptation_lit_ratio = 1.0;
uniform float adaptation_strength = 1.0;

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
	// Material-relative luminance avoids treating dark paint as missing light.
	// Both images contain the same sky/emission. Their ratio suppresses fill on
	// lit surfaces, with a continuous transition instead of a time-of-day switch.
	vec3 luminance = vec3(0.2126, 0.7152, 0.0722);
	float actual_light = max(dot(scene, luminance), 0.0);
	float reference_light = max(dot(reference, luminance), 0.0);
	float darkness = reference_light > 0.00001 ? 1.0 - smoothstep(adaptation_dark_ratio, adaptation_lit_ratio, actual_light / reference_light) : 0.0;
	float missing = max(reference_light - actual_light, 0.0);
	ALBEDO = scene + vec3(missing * darkness * night_curve_visibility(distance_to_camera) * adaptation_strength);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// GLES converts ALBEDO from sRGB before its lighting/output stage.
	ALBEDO = linear_to_srgb(ALBEDO);
#endif
	ALPHA = 1.0;
}
