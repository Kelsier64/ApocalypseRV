shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 metal_color : source_color = vec4(0.33, 0.32, 0.30, 1.0);
uniform float corrosion : hint_range(0.0, 1.0) = 0.6;
uniform float pattern_offset = 0.0;
varying vec3 object_position;
varying vec3 object_normal;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1,0)), f.x), mix(hash21(i + vec2(0,1)), hash21(i + vec2(1,1)), f.x), f.y);
}
void vertex() {
	// Local coordinates keep corrosion attached to the sliding leaves.
	object_position = VERTEX;
	object_normal = NORMAL;
}
void fragment() {
	vec3 n = abs(normalize(object_normal));
	vec2 p = n.y > 0.7 ? object_position.xz : vec2(n.x > n.z ? object_position.z : object_position.x, object_position.y);
	p += vec2(pattern_offset, pattern_offset * 0.7);
	float broad = noise(p * 0.9);
	float fine = noise(p * 32.0);
	float rust = smoothstep(0.48, 0.72, broad * 0.65 + noise(p * 5.5) * 0.35 + corrosion * 0.23);
	vec3 oxide = mix(vec3(0.075, 0.046, 0.031), vec3(0.17, 0.092, 0.046), fine);
	vec3 base = metal_color.rgb * (0.78 + fine * 0.28);
	float runs = smoothstep(0.58, 0.82, noise(p * vec2(9.0, 0.5)));
	ALBEDO = mix(base, oxide, rust * 0.82) * (1.0 - runs * 0.14);
	ROUGHNESS = mix(0.77, 0.98, rust);
	METALLIC = (1.0 - rust) * 0.32;
	SPECULAR = 0.3;
}
