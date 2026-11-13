shader_type canvas_item;
render_mode unshaded;

#include "res://world/terrain/sdr_shadow_trim.gdshaderinc"

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform bool retro_enabled = true;
uniform float shadow_trim = 0.0;
uniform float saturation = 1.0;

vec3 video_grade(vec3 source) {
	// Resolution loss comes from the 3D viewport, not a second mosaic filter.
	// Keep a shadow toe: the contrast offset otherwise clips faint night
	// silhouettes to black before the world's distance fade reaches its end.
	// Exact black stays black; the original midtone/highlight grade is retained.
	vec3 retro_grade = max((source - 0.38) * 1.04 + 0.38, source * 0.5);
	vec3 graded = retro_enabled ? retro_grade : source;
	graded = clamp(graded, vec3(0.0), vec3(1.0));
	float luminance = dot(graded, vec3(0.2126, 0.7152, 0.0722));
	graded = mix(vec3(luminance), graded, saturation);
	return clamp(graded, 0.0, 1.0);
}

#include "res://player/san_vision.gdshaderinc"

void fragment() {
	vec3 source = texture(screen_texture, SCREEN_UV).rgb;
	vec3 graded = video_grade(source);
	if (san_amount > 0.0) {
		graded = san_vision(source, graded, SCREEN_UV, SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x);
	}
	COLOR = vec4(apply_sdr_shadow_trim(clamp(graded, 0.0, 1.0), shadow_trim), 1.0);
}
