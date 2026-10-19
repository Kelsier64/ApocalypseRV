// Shared by gray adaptation and transparent weather drawn after it.
uniform sampler2D night_curve : filter_linear, repeat_disable;
uniform float night_fade_begin = 0.0;
uniform float night_fade_end = 60.0;
uniform float night_strength = 0.0;

float night_curve_visibility(float distance_to_camera) {
	float t = clamp((distance_to_camera - night_fade_begin) / max(night_fade_end - night_fade_begin, 0.001), 0.0, 1.0);
	// The LUT includes both endpoints, stored at texel centers.
	float width = float(textureSize(night_curve, 0).x);
	float u = (t * (width - 1.0) + 0.5) / width;
	float visibility = clamp(texture(night_curve, vec2(u, 0.5)).r, 0.0, 1.0);
	return visibility;
}

float night_visibility(float distance_to_camera) {
	if (night_strength <= 0.0) return 1.0;
	float visibility = mix(1.0, night_curve_visibility(distance_to_camera), night_strength);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Compatibility blends transparency after its linear-to-sRGB conversion.
	// Encode the multiplier too, preserving faint silhouettes in the fade tail.
	visibility = visibility <= 0.0031308 ? visibility * 12.92 : 1.055 * pow(visibility, 1.0 / 2.4) - 0.055;
#endif
	return visibility;
}
