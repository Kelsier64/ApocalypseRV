shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform float damage : hint_range(0.0, 1.0) = 0.0;
uniform bool glass = false;
uniform float pattern_offset = 0.0;
varying vec3 local_position;
varying vec3 local_normal;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
		mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
	VERTEX += NORMAL * 0.001;
}
void fragment() {
	vec3 n = abs(local_normal);
	vec2 p = n.y > max(n.x, n.z) ? local_position.xz : (n.x > n.z ? local_position.zy : local_position.xy);
	p += vec2(pattern_offset, pattern_offset * 0.37);
	float visible_damage = smoothstep(0.01, 0.85, damage);
	if (glass) {
		// Irregular Voronoi edges: connected fractures in metres, independent of UVs.
		vec2 q = p * 5.0;
		vec2 cell = floor(q);
		vec2 f = fract(q);
		float nearest = 10.0;
		float second = 10.0;
		for (int x = -1; x <= 1; x++) {
			for (int y = -1; y <= 1; y++) {
				vec2 offset = vec2(float(x), float(y));
				vec2 point = vec2(hash(cell + offset), hash(cell + offset + 73.2));
				float d = length(offset + point - f);
				if (d < nearest) { second = nearest; nearest = d; }
				else { second = min(second, d); }
			}
		}
		float edge = 1.0 - smoothstep(0.008, 0.035, second - nearest);
		float spread = smoothstep(1.0 - visible_damage, 1.12 - visible_damage, noise(p * 2.4));
		ALBEDO = vec3(0.72, 0.85, 0.86);
		ROUGHNESS = 0.65;
		ALPHA = edge * spread * 0.9;
	} else {
		float scars = noise(p * 8.0) * 0.64 + noise(p * 31.0) * 0.24 + noise(p * 94.0) * 0.12;
		float threshold = mix(0.94, 0.44, visible_damage);
		float rim = smoothstep(threshold - 0.06, threshold + 0.01, scars);
		float metal = smoothstep(threshold + 0.025, threshold + 0.075, scars);
		float scratches = smoothstep(0.82, 0.95, noise(p * vec2(3.0, 160.0))) * step(0.53, noise(p * 6.0));
		ALBEDO = mix(vec3(0.16, 0.085, 0.045), vec3(0.48, 0.51, 0.5), metal);
		ALBEDO = mix(ALBEDO, vec3(0.67, 0.69, 0.65), scratches);
		METALLIC = metal * 0.8;
		ROUGHNESS = mix(0.96, 0.52, metal);
		ALPHA = max(rim, scratches * visible_damage) * visible_damage;
	}
}
