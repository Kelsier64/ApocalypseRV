shader_type spatial;
render_mode unshaded, fog_disabled, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;

#include "res://world/night_vision.gdshaderinc"
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D scene_texture : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D night_reference : source_color, filter_linear, repeat_disable;
uniform float adaptation_reference_energy = 0.06;
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
	// The reference estimates the readable luminance of this material.
	vec3 luminance = vec3(0.2126, 0.7152, 0.0722);
	float actual_light = max(dot(scene, luminance), 0.0);
	// Emission is present in both views and must not raise the fill ceiling
	// above the reference's diffuse white ambient level.
	float reference_light = clamp(dot(reference, luminance), 0.0, adaptation_reference_energy);
	ALBEDO = scene;
	if (reference_light > 0.00001 && actual_light < adaptation_lit_ratio * reference_light) {
		float ratio = actual_light / reference_light;
		float deficit = adaptation_lit_ratio - ratio;
		// A wider knee keeps partly lit surfaces close to the authored night
		// darkness while leaving the distance curve in control of falloff.
		float knee = 0.5 * (adaptation_lit_ratio - adaptation_dark_ratio);
		float rounded = min(deficit, knee);
		// Round off the lift at the lit threshold. Each extra unit of native
		// luminance can remove at most one unit of lift, even at full strength.
		float fill = (deficit - rounded + 0.5 * rounded * rounded / knee) * reference_light;
		fill *= night_curve_visibility(distance_to_camera) * adaptation_strength / max(adaptation_lit_ratio, 1.0);
		// Give part of the fill the native hue without normalizing near-black
		// pixels. The bounded gain trades gray for color at equal luminance.
		float hue_gain = 0.65 * fill / max(fill + 2.0 * actual_light, 0.000001);
		ALBEDO += vec3(fill - actual_light * hue_gain) + scene * hue_gain;
	}
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// GLES converts ALBEDO from sRGB before its lighting/output stage.
	ALBEDO = linear_to_srgb(ALBEDO);
#endif
	ALPHA = 1.0;
}
