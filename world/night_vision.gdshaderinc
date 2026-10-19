// Authored distance profile for gray fill; native illumination is independent.
uniform sampler2D night_curve : filter_linear, repeat_disable;
uniform float night_fade_begin = 0.0;
uniform float night_fade_end = 60.0;

float night_curve_visibility(float distance_to_camera) {
	float t = clamp((distance_to_camera - night_fade_begin) / max(night_fade_end - night_fade_begin, 0.001), 0.0, 1.0);
	// The LUT includes both endpoints, stored at texel centers.
	float width = float(textureSize(night_curve, 0).x);
	float u = (t * (width - 1.0) + 0.5) / width;
	float visibility = clamp(texture(night_curve, vec2(u, 0.5)).r, 0.0, 1.0);
	return visibility;
}
