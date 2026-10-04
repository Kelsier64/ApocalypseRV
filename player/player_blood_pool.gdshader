shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Fresh red with a lighter thin edge; illumination still controls visibility.
uniform vec4 pooled_red : source_color = vec4(0.40, 0.024, 0.035, 1.0);
uniform vec4 thin_red : source_color = vec4(0.54, 0.042, 0.055, 1.0);
uniform float variation = 1.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

float smooth_union(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	vec2 seed = vec2(variation * 2.31, variation * 4.17);
	// Smooth merged lobes, not a repeating radial star outline.
	vec2 q = p + (vec2(noise(p * 5.0 + seed), noise(p * 5.0 - seed)) - 0.5) * 0.035;
	float pool = length(q * vec2(1.0, 1.3)) - 0.39;
	for (int i = 0; i < 5; i++) {
		float f = float(i);
		float angle = hash(seed + vec2(f, 2.0)) * 6.283185;
		vec2 center = vec2(cos(angle), sin(angle)) * (0.22 + hash(seed + f) * 0.1);
		float radius = 0.10 + hash(seed - f) * 0.065;
		pool = smooth_union(pool, length(q - center) - radius, 0.09);
	}
	float drops = 1.0;
	for (int i = 0; i < 14; i++) {
		float f = float(i);
		float angle = hash(seed + vec2(f, 7.0)) * 6.283185;
		float reach = 0.48 + hash(seed + vec2(f, 11.0)) * 0.34;
		vec2 center = vec2(cos(angle), sin(angle)) * reach;
		vec2 d = p - center;
		vec2 radial = vec2(dot(d, normalize(center)), dot(d, vec2(-sin(angle), cos(angle))));
		float radius = 0.009 + pow(hash(seed + vec2(f, 17.0)), 2.0) * 0.033;
		drops = min(drops, length(radial * vec2(0.75, 1.0)) - radius);
	}
	float dist = min(pool, drops);
	float aa = max(fwidth(dist), 0.0015);
	float coverage = 1.0 - smoothstep(-aa, aa, dist);
	float depth = smoothstep(0.0, 0.028, -dist);
	float mottling = noise(p * 10.0 + seed) * 0.6 + noise(p * 23.0 - seed) * 0.4;
	ALBEDO = mix(thin_red.rgb, pooled_red.rgb, depth * 0.85) * (0.88 + mottling * 0.22);
	ROUGHNESS = mix(0.34, 0.16, depth) + mottling * 0.045;
	SPECULAR = 0.65;
	// A very shallow liquid meniscus changes the directional highlight.
	float nx = noise(p * 10.0 + seed + vec2(0.04, 0.0)) - noise(p * 10.0 + seed - vec2(0.04, 0.0));
	float ny = noise(p * 10.0 + seed + vec2(0.0, 0.04)) - noise(p * 10.0 + seed - vec2(0.0, 0.04));
	NORMAL_MAP = normalize(vec3(nx * 0.28, ny * 0.28, 1.0)) * 0.5 + 0.5;
	ALPHA = coverage * opacity * mix(0.82, 0.98, depth);
}
