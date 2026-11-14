shader_type spatial;
render_mode cull_back;
// UV.x: metres from the centreline. UV.y: metres along the route. UV2.x: half width.
// COLOR.r: 1 on bridge decks, where no verge soil can creep onto the asphalt.

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return  value_noise(p) * 0.5 +  value_noise(p * 2.03 + 7.1) * 0.3 +  value_noise(p * 4.1 + 3.7) * 0.2;
}

void fragment() {
	float lateral = UV.x;
	float along = UV.y;
	float half_width = UV2.x;
	vec2 p = vec2(lateral, along);
	// Fine detail fades with distance so the low-resolution view does not shimmer.
	float footprint = max(fwidth(along), fwidth(lateral));
	float detail = clamp(1.0 - footprint * 2.5, 0.0, 1.0);
	float broad = fbm(p * 0.07);
	float grain = mix(0.5,  value_noise(p * 3.3), detail);
	vec3 asphalt = mix(vec3(0.085, 0.092, 0.088), vec3(0.165, 0.17, 0.158), broad) * mix(0.88, 1.1, grain);
	// Polished wheel paths, two per lane.
	float lane = abs(abs(lateral) - half_width * 0.5);
	float wheel = 1.0 - smoothstep(0.2, 0.75, abs(lane - 0.95));
	asphalt = mix(asphalt, asphalt * 1.22 + 0.008, wheel * 0.45 * (0.5 + 0.5 * broad));
	// Old repair patches: darker, squarer, never aligned with each other.
	vec2 cell = vec2(floor(along / 17.0), step(0.0, lateral));
	if (hash21(cell) > 0.6) {
		vec2 centre = vec2((cell.y - 0.5) * half_width + (hash21(cell + 3.1) - 0.5) * half_width * 0.45, (cell.x + 0.25 + 0.5 * hash21(cell + 9.7)) * 17.0);
		vec2 size = vec2(0.7 + 1.3 * hash21(cell + 1.3), 1.4 + 3.6 * hash21(cell + 5.9));
		vec2 d = abs(p - centre) - size;
		float inside = 1.0 - smoothstep(-0.05, 0.05 + footprint, max(d.x, d.y));
		float seam = (1.0 - smoothstep(0.0, 0.07 + footprint, abs(max(d.x, d.y)))) * detail;
		asphalt = mix(asphalt, vec3(0.062, 0.066, 0.068) * mix(0.9, 1.12, grain), inside * 0.9);
		asphalt = mix(asphalt, vec3(0.03, 0.032, 0.032), seam * 0.6);
	}
	// Long cracks run with the traffic, in patches of tired surface, plus the
	// occasional straight transverse joint.
	float fatigue = smoothstep(0.42, 0.62, fbm(p * 0.045 + 31.0));
	float crack = 1.0 - smoothstep(0.004, 0.011 + footprint * 0.1, abs(fbm(p * vec2(0.55, 0.13) + 11.0) - 0.5));
	float joint = 1.0 - smoothstep(0.02, 0.05 + footprint, abs(fract(along / 23.0 + 0.15 * value_noise(vec2(lateral * 0.6, floor(along / 23.0)))) - 0.5) * 23.0);
	joint *= step(0.45, hash21(vec2(floor(along / 23.0 + 0.5), 4.0)));
	asphalt = mix(asphalt, vec3(0.04, 0.042, 0.04), max(crack * fatigue, joint * 0.8) * 0.55 * mix(0.3, 1.0, detail));
	// Road paint, worn through wherever the tyres and weather got to it.
	float wear = fbm(p * vec2(1.7, 0.55) + 5.0);
	float centre_line = (1.0 - smoothstep(0.075, 0.105 + footprint, abs(lateral))) * step(fract((along - 1.0) / 10.0), 0.4);
	float edge_line = 1.0 - smoothstep(0.065, 0.095 + footprint, abs(abs(lateral) - (half_width - 0.55)));
	asphalt = mix(asphalt, vec3(0.42, 0.35, 0.13), centre_line * smoothstep(0.3, 0.52, wear) * 0.85);
	asphalt = mix(asphalt, vec3(0.44, 0.44, 0.40), edge_line * smoothstep(0.44, 0.66, wear) * 0.8);
	// Oil and damp.
	float stain = smoothstep(0.7, 0.86, fbm(p * 0.19 + 23.0));
	asphalt *= 1.0 - stain * 0.32;
	// The verge creeps in from both edges in ragged tongues.
	float edge = half_width - abs(lateral);
	float dirt = (1.0 - smoothstep(0.0, 0.35 + 1.5 * fbm(p * 0.45 + 2.0), edge)) * (1.0 - COLOR.r);
	asphalt = mix(asphalt, vec3(0.24, 0.215, 0.165) * mix(0.8, 1.15, grain), dirt * 0.9);
	ALBEDO = asphalt;
	ROUGHNESS = mix(0.94, 0.74, stain);
	SPECULAR = 0.1;
}
