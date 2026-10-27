shader_type spatial;
render_mode specular_disabled;
uniform vec4 base_color : source_color = vec4(0.40, 0.42, 0.40, 1.0);
uniform float surface_kind = 0.0;
uniform float wear_seed = 0.0;
varying vec3 local_position;
varying vec3 local_normal;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float coarse(vec2 p) {
	vec2 q = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(q), hash21(q + vec2(1,0)), f.x), mix(hash21(q + vec2(0,1)), hash21(q + vec2(1,1)), f.x), f.y);
}
void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
}
void fragment() {
	vec3 n = abs(normalize(local_normal));
	vec2 p = n.y > 0.7 ? local_position.xz : vec2(n.x > n.z ? local_position.z : local_position.x, local_position.y);
	p = floor(p * 8.0) / 8.0;
	vec2 offset = vec2(wear_seed * 0.071, wear_seed * 0.039);
	float patch = coarse(p * 0.55 + offset);
	float grain = hash21(floor(p * 3.0) + offset);
	float run = smoothstep(0.52, 0.78, coarse(p * vec2(1.8, 0.055) + offset));
	float vertical = 1.0 - step(0.7, n.y);
	float seam_run = 1.0 - smoothstep(0.0, 8.0, mod(local_position.y + 0.3, 13.5));
	float damp = (1.0 - smoothstep(0.0, 3.5, local_position.y)) * vertical;
	vec3 color = base_color.rgb * COLOR.rgb * (0.86 + patch * 0.20 + grain * 0.045);
	color *= 1.0 - (run * (0.13 + seam_run * 0.22) * vertical + damp * 0.22);
	if (surface_kind > 0.5 && surface_kind < 1.5) {
		color *= 1.0 - smoothstep(0.56, 0.72, patch) * 0.12;
	}
	if (surface_kind > 1.5) {
		color = mix(color, vec3(0.035, 0.019, 0.012), smoothstep(0.48, 0.69, patch) * 0.55);
	}
	ALBEDO = color;
	ROUGHNESS = 0.98;
}
