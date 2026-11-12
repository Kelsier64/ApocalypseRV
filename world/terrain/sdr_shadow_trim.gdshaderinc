vec3 apply_sdr_shadow_trim(vec3 rgb, float trim) {
	// Work in the SDR canvas's encoded values. A common gain preserves hue
	// and fades to identity before any channel reaches 64/255.
	float peak = max(rgb.r, max(rgb.g, rgb.b));
	float weight = max(1.0 - peak / (64.0 / 255.0), 0.0);
	return rgb * (1.0 + trim * weight * weight);
}
