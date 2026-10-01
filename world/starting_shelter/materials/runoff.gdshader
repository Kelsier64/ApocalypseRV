shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1,0)), f.x), mix(hash21(i + vec2(0,1)), hash21(i + vec2(1,1)), f.x), f.y);
}
void fragment() {
	float streams = noise(vec2(UV.x * 27.0, UV.y * 2.0));
	float length_variation = 0.35 + noise(vec2(UV.x * 9.0, 2.7)) * 0.65;
	float sides = smoothstep(0.0, 0.22, UV.x) * (1.0 - smoothstep(0.78, 1.0, UV.x));
	float ends = smoothstep(0.0, 0.07, UV.y) * (1.0 - smoothstep(length_variation * 0.45, length_variation, UV.y));
	ALBEDO = COLOR.rgb;
	ALPHA = sides * ends * (0.28 + streams * 0.72) * COLOR.a;
	ROUGHNESS = 0.97;
}
