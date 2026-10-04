shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 concrete_color : source_color = vec4(0.44, 0.438, 0.417, 1.0);
uniform float formwork_strength : hint_range(0.0, 1.0) = 0.0;
uniform float exposed_aggregate : hint_range(0.0, 1.0) = 0.0;
uniform bool authored_surface = false;
uniform sampler2D cement_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D aggregate_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;
varying vec3 world_normal;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1,0)), f.x), mix(hash21(i + vec2(0,1)), hash21(i + vec2(1,1)), f.x), f.y);
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}
void fragment() {
	vec3 n = abs(normalize(world_normal));
	vec2 p = n.y > 0.7 ? world_position.xz : vec2(n.x > n.z ? world_position.z : world_position.x, world_position.y);
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float grain_visibility = 1.0 - smoothstep(0.016, 0.055, footprint);
	vec2 warp = vec2(noise(p * 0.7 + 3.4), noise(p * 0.7 + 21.1)) - 0.5;
	float mineral = noise(p * 0.7 + warp * 0.4) * 0.6 + noise(p * 2.6) * 0.4;
	float fine = mix(0.5, noise(p * 30.0), grain_visibility);
	float cement = texture(cement_texture, p * 0.42).r;
	float stones = texture(aggregate_texture, p * 1.15).r;
	float damage = authored_surface ? COLOR.g : exposed_aggregate;
	float shade = authored_surface ? COLOR.r : 1.0;
	float joint = authored_surface ? COLOR.b : 0.0;
	// Cast cement remains one material. Wear is authored at structural locations,
	// not a full-wall camouflage mask or uniform repeating curtain of rain streaks.
	vec3 base = concrete_color.rgb * shade * (0.86 + mineral * 0.24 + (fine - 0.5) * 0.07);
	base *= 0.60 + cement * 0.95;
	float coarse = noise(p * 8.0 + warp) * 0.7 + noise(p * 16.0) * 0.3;
	vec3 fractured = concrete_color.rgb * vec3(0.78, 0.76, 0.71) * (0.64 + stones * 2.1 + coarse * 0.15);
	vec3 color = mix(base, fractured, smoothstep(0.12, 0.65, damage));
	float vertical = 1.0 - smoothstep(0.6, 0.85, n.y);
	float damp_height = 0.32 + noise(vec2(p.x * 0.44, 7.1)) * 0.92;
	float damp = (1.0 - smoothstep(-0.12, damp_height, world_position.y)) * vertical;
	color *= mix(vec3(1.0), vec3(0.60, 0.57, 0.52), damp * 0.68);
	color *= 1.0 - joint * 0.28;
	vec2 tie = abs(fract(p / vec2(1.8,2.2) + vec2(0.25,0.5)) - 0.5) * vec2(1.8,2.2);
	float hole = 1.0 - smoothstep(0.012, 0.02 + fwidth(length(tie)), length(tie));
	ALBEDO = color * (1.0 - hole * 0.22 * formwork_strength);
	// Geometry carries the broken concrete relief; bump is only submillimetre grain.
	float relief = (cement * 0.0006 + fine * 0.00025 + stones * damage * 0.001) * grain_visibility;
	vec3 dx = dFdx(VERTEX), dy = dFdy(VERTEX);
	vec3 across_x = cross(dy, NORMAL), across_y = cross(NORMAL, dx);
	float determinant = dot(dx, across_x);
	NORMAL = normalize(NORMAL - sign(determinant) * (dFdx(relief) * across_x + dFdy(relief) * across_y) / max(abs(determinant), 0.000001));
	ROUGHNESS = mix(0.93, 0.99, damage);
	SPECULAR = 0.08;
}
