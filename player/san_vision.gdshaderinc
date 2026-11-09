uniform float san_amount : hint_range(0.0, 1.0) = 0.0;
// Matches PlayerSanEffects.VisionProfile.
uniform int san_profile = 0;
uniform float san_elapsed = 0.0;

const vec3 SAN_LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 san_bleached(vec3 source, float edge) {
	float value = clamp(dot(source, SAN_LUMA), 0.0, 1.0);
	// Wash the midtones toward paper white while keeping silhouettes visible.
	float exposure = pow(value, 0.53);
	vec3 paper = mix(vec3(0.025, 0.032, 0.045), vec3(1.0, 0.97, 0.87), exposure);
	vec3 silver = mix(paper, source, 0.12);
	return silver + 0.12 * edge * smoothstep(0.04, 0.55, value);
}

vec3 san_cold_split(vec3 source, vec2 uv, float edge) {
	vec2 offset = (uv - vec2(0.5)) * (0.011 + 0.003 * sin(san_elapsed * 2.4)) * san_amount;
	vec3 split = vec3(texture(screen_texture, uv + offset).r, source.g, texture(screen_texture, uv - offset).b);
	float value = clamp(dot(split, SAN_LUMA), 0.0, 1.0);
	vec3 cold = mix(vec3(0.034, 0.025, 0.077), vec3(0.64, 1.0, 0.93), pow(value, 1.18));
	return (mix(cold, split, 0.26) + (split - source) * 0.55) * (1.0 - edge * 0.50);
}

vec3 san_broken_signal(vec2 uv) {
	// Disturb individual scan bands. Their motion is continuous across frames.
	float band = floor(uv.y * 26.0);
	float slip = sin(band * 2.399 + san_elapsed * 2.7);
	uv.x += 0.014 * slip * abs(slip) * san_amount;
	vec2 cells = vec2(460.0, 260.0);
	vec3 sample_color = texture(screen_texture, (floor(uv * cells) + 0.5) / cells).rgb;
	float value = clamp(dot(sample_color, SAN_LUMA), 0.0, 1.0);
	float steps = floor(sqrt(value) * 7.0 + 0.5) / 7.0;
	vec3 signal = mix(vec3(0.023, 0.036, 0.048), vec3(1.0, 0.76, 0.40), steps * steps);
	float scan = 0.89 + 0.11 * cos(uv.y * cells.y * 6.2831853);
	return mix(signal, sample_color, 0.19) * scan;
}

vec3 san_vision(vec3 source, vec2 uv) {
	vec2 centered = uv * 2.0 - 1.0;
	float edge = smoothstep(0.24, 1.65, dot(centered, centered));
	if (san_profile == 1) {
		return san_cold_split(source, uv, edge);
	}
	if (san_profile == 2) {
		return san_broken_signal(uv);
	}
	return san_bleached(source, edge);
}
