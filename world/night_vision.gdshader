shader_type spatial;
render_mode unshaded, fog_disabled, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled;

#include "res://world/night_vision.gdshaderinc"
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest, repeat_disable;

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
	ALBEDO = vec3(0.0);
	ALPHA = 1.0 - night_visibility(distance_to_camera);
}
