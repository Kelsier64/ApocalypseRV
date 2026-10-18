shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D grain_texture : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 local_position;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1)), f.x), f.y);
}
void vertex() { local_position = VERTEX; }

void fragment() {
	vec2 p = local_position.xz;
	float roll = floor(p.x / 1.2);
	float lap = fract(p.x / 1.2);
	float end = fract((p.y + hash(vec2(roll, 3.0)) * 4.0) / 6.0);
	vec2 edge = min(vec2(lap, end), vec2(1.0-lap, 1.0-end)) * vec2(1.2, 6.0);
	float aa = max(fwidth(p.x), fwidth(p.y));
	float seam = 1.0 - smoothstep(0.009, 0.02 + aa, min(edge.x, edge.y));
	float grit = texture(grain_texture, p * 0.4).r;
	float runoff = noise(p * vec2(0.6, 0.08));
	float patch = mix(0.91, 1.06, hash(vec2(roll, floor((p.y+hash(vec2(roll,3.0))*4.0)/6.0))));
	ALBEDO = vec3(0.095, 0.103, 0.094) * (0.72 + grit * 0.35 + runoff * 0.17) * patch * (1.0 - seam * 0.24);
	ROUGHNESS = 0.96;
	SPECULAR = 0.19;
}
