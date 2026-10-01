shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D concrete_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 concrete_color : source_color = vec4(0.62, 0.60, 0.56, 1.0);
uniform float formwork_strength : hint_range(0.0, 1.0) = 1.0;
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
	float grain = texture(concrete_texture, p * 0.38).r;
	float patch = noise(p * 0.37) * 0.65 + noise(p * 1.7) * 0.35;
	vec2 panel = vec2(p.x / 3.6, p.y / 1.5);
	vec2 edge = min(fract(panel), 1.0 - fract(panel)) * vec2(3.6, 1.5);
	float joint = 1.0 - smoothstep(0.008, 0.025, min(edge.x, edge.y));
	// No painted lower band: mineral dust and damp fade gradually into bare concrete.
	float vertical = 1.0 - smoothstep(0.6, 0.85, n.y);
	float damp_height = 0.5 + noise(vec2(p.x * 0.65, 7.1)) * 1.25;
	float damp = (1.0 - smoothstep(-0.15, damp_height, world_position.y)) * vertical;
	float streak = smoothstep(0.56, 0.83, noise(vec2(p.x * 2.8, p.y * 0.18))) * vertical;
	vec3 color = concrete_color.rgb * (0.79 + grain * 0.35 + (patch - 0.5) * 0.22);
	color = mix(color, color * vec3(0.55, 0.51, 0.46), damp * 0.62);
	color *= 1.0 - streak * 0.19;
	color *= 1.0 - joint * 0.15 * formwork_strength;
	// Formwork tie holes, measured in metres, remain small at player distance.
	vec2 tie = abs(fract(p / vec2(1.8,1.5) + vec2(0.25,0.5)) - 0.5) * vec2(1.8,1.5);
	float hole = 1.0 - smoothstep(0.014, 0.027, length(tie));
	ALBEDO = color * (1.0 - hole * 0.3 * formwork_strength);
	ROUGHNESS = mix(0.97, 0.86, damp);
	SPECULAR = 0.2;
}
