shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;
varying vec3 wall_position;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1,0)), f.x), mix(hash21(i + vec2(0,1)), hash21(i + vec2(1,1)), f.x), f.y);
}
void vertex() { wall_position = VERTEX; }
void fragment() {
	vec2 seed = wall_position.xz * 0.19;
	float streams = noise(vec2(UV.x * 15.0, UV.y * 1.7) + seed);
	float length_variation = 0.38 + noise(vec2(UV.x * 8.0, 2.7) + seed) * 0.62;
	float meander = (noise(vec2(UV.y * 3.0, 7.3) + seed) - 0.5) * 0.1;
	float spread = mix(0.44, 0.24, UV.y);
	float sides = 1.0 - smoothstep(spread * 0.3, spread, abs(UV.x - 0.5 + meander));
	float ends = smoothstep(0.0, 0.07, UV.y) * (1.0 - smoothstep(length_variation * 0.45, length_variation, UV.y));
	ALBEDO = COLOR.rgb;
	ALPHA = sides * ends * (0.15 + streams * 0.65) * COLOR.a;
	ROUGHNESS = 0.97;
}
