shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D cement : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 local_position;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1, 0)), f.x),
		mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1)), f.x), f.y);
}

void vertex() { local_position = VERTEX; }

void fragment() {
	vec2 p = local_position.xz;
	float grain = texture(cement, p * 0.42).r;
	float mottling = noise(p * 0.38);
	float aggregate = noise(p * 45.0);
	vec3 base = vec3(0.092, 0.089, 0.076) * (0.65 + grain * 0.6 + mottling * 0.13 + aggregate * 0.12);
	// Saw-cut expansion joints and small repaired sections break up the slab.
	vec2 grid = abs(fract((p + vec2(2.4, 0.7)) / 5.0) - 0.5) * 5.0;
	float joint = 1.0 - smoothstep(0.009, 0.028, min(grid.x, grid.y));
	float joint_rim = 1.0 - smoothstep(0.02, 0.065, min(grid.x, grid.y));
	base *= 1.0 - joint * 0.3 - joint_rim * 0.045;
	float fracture = 1.0 - smoothstep(0.004, 0.014, abs(noise(p * 2.3) - 0.51));
	fracture *= smoothstep(0.6, 0.74, noise(p * 0.4 + 14.0));
	base *= 1.0 - fracture * 0.15;
	float oil = smoothstep(0.57, 0.76, noise(p * 0.42 + 9.0) * 0.7 + noise(p * 1.5) * 0.3);
	// Shared, faint paired wear follows the central vehicle lane.
	float track = (1.0 - smoothstep(0.14, 0.34, abs(abs(p.x) - 1.35)));
	track *= smoothstep(0.25, 0.62, noise(p * vec2(6.0, 0.55)));
	ALBEDO = base * (1.0 - oil * 0.34 - track * 0.16);
	ROUGHNESS = mix(0.96, 0.73, oil);
	SPECULAR = 0.25;
}
