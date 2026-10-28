shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(0.40, 0.42, 0.40, 1.0);
uniform float surface_kind = 0.0;
uniform float wear_seed = 0.0;
uniform vec4 exposed_concrete : source_color = vec4(0.37,0.38,0.35,1.0);
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
	p = floor(p * 12.0) / 12.0;
	vec2 offset = vec2(wear_seed * 0.071, wear_seed * 0.039);
	float patch = coarse(p * 0.48 + offset);
	float grain = hash21(floor(p * 5.0) + offset);
	float fracture = coarse(p*1.8+offset)*0.65 + grain*0.35;
	float run = smoothstep(0.52, 0.78, coarse(p * vec2(2.8, 0.085) + offset));
	float vertical = 1.0 - step(0.7, n.y);
	float seam_run = 1.0 - smoothstep(0.0, 7.0, mod(local_position.y + 0.3, 18.0));
	float damp = (1.0 - smoothstep(0.0, 3.5, local_position.y)) * vertical;
	vec3 color = base_color.rgb * COLOR.rgb * (0.87 + patch * 0.20 + grain * 0.07);
	color *= 1.0 - (run * (0.13 + seam_run * 0.22) * vertical + damp * 0.22);
	if (surface_kind > 0.5 && surface_kind < 1.5) {
		float peel = smoothstep(0.60,0.74,coarse(p*0.22+offset)*0.7+fracture*0.3);
		color = mix(color,exposed_concrete.rgb*(0.76+grain*0.22),peel*0.65);
		// Sparse, shallow construction joints stay secondary to the megablocks.
		float joint = 1.0-smoothstep(0.018,0.035,abs(mod(p.y+0.02,4.5)-0.02));
		color *= 1.0-joint*0.13*vertical;
	} else if (surface_kind < 0.5) {
		float chipped = smoothstep(0.63,0.75,fracture);
		color *= 1.0-chipped*0.16;
	}
	if (surface_kind > 1.5) {
		float corrosion = smoothstep(0.44,0.68,fracture*0.7+patch*0.3);
		color = mix(color,vec3(0.06,0.031,0.016)*(0.8+grain*0.35),corrosion*0.75);
	}
	ALBEDO = color;
	ROUGHNESS = surface_kind > 1.5 ? 0.88 : 0.98;
	SPECULAR = surface_kind > 1.5 ? 0.22 : 0.08;
}
