shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(0.57, 0.58, 0.54, 1.0);
uniform float surface_kind = 0.0;
uniform float wear_seed = 0.0;
uniform sampler2D concrete_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D coating_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D aggregate_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D decay_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D corrosion_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 local_position;
varying vec3 local_normal;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 q = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(q), hash21(q + vec2(1,0)), f.x), mix(hash21(q + vec2(0,1)), hash21(q + vec2(1,1)), f.x), f.y);
}
void vertex() { local_position = VERTEX; local_normal = NORMAL; }
void fragment() {
	vec3 n = abs(normalize(local_normal));
	float vertical = 1.0 - smoothstep(0.6, 0.85, n.y);
	vec2 p = n.y > 0.7 ? local_position.xz : vec2(n.x > n.z ? local_position.z : local_position.x, local_position.y);
	vec2 offset = vec2(wear_seed * 0.071, wear_seed * 0.039);
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float detail = 1.0 - smoothstep(0.018, 0.10, footprint);
	float cement = texture(concrete_texture, p * 0.5 + offset).r;
	float mineral = noise(p * 0.19 + offset);
	vec2 warp = vec2(noise(p * 0.62 + offset), noise(p * 0.71 + offset + 13.0)) - 0.5;
	float shade = mix(0.84, 1.04, COLOR.r);
	vec3 color = base_color.rgb * shade * (0.84 + mineral * 0.23);
	float relief = cement * 0.0015;
	float roughness = 0.96;
	float metal = 0.0;
	if (surface_kind < 0.5) {
		color *= 0.67 + cement * 1.20;
		// Metre-scale erosion exposes aggregate, separate from the tiny cement pores.
		float chipped_skin = texture(decay_texture, p / 3.0 + offset).r;
		float erosion = noise(p * 0.45 + offset) * 0.70 + chipped_skin * 0.30;
		float damage = max(COLOR.a, smoothstep(0.59, 0.65, erosion) * 0.76 * vertical);
		vec3 stones = texture(aggregate_texture, p * 0.8 + offset).rgb;
		color = mix(color, stones * vec3(0.70, 0.67, 0.61) + vec3(0.045), damage);
		relief += stones.r * damage * 0.004;
		vec2 tie = (fract(p / vec2(1.8, 2.25) + 0.5) - 0.5) * vec2(1.8, 2.25);
		float hole = 1.0 - smoothstep(0.018, 0.029 + fwidth(length(tie)), length(tie));
		color *= 1.0 - hole * vertical * 0.40;
	} else if (surface_kind < 1.5) {
		// Decayed mineral paint and exposed cement are actual coloured material,
		// not tiny dark specks added to an otherwise pristine panel.
		vec3 decay = texture(decay_texture, p / 6.0 + offset).rgb;
		color = mix(color, decay, 0.82) * shade * (0.86 + mineral * 0.25);
		float joint_distance = abs(mod(local_position.y + 2.25, 4.5) - 2.25);
		float joint = (1.0 - smoothstep(0.012, 0.028 + fwidth(p.y), joint_distance)) * vertical;
		color *= 1.0 - joint * 0.48;
		relief = dot(decay, vec3(0.3, 0.5, 0.2)) * 0.003 - joint * 0.003;
		roughness = 0.91 + cement * 0.08;
	} else {
		vec3 corrosion = texture(corrosion_texture, p * 0.25 + offset).rgb;
		float rust = smoothstep(0.012, 0.09, corrosion.r - corrosion.g * 0.92);
		color = mix(color * 0.8, corrosion * 1.12, 0.91) * shade;
		float scratch = texture(coating_texture, p * 0.5 + offset).r;
		relief = scratch * 0.0009 + rust * 0.0025;
		roughness = mix(0.65, 0.98, rust);
		metal = mix(0.38, 0.0, rust);
	}
	// Long, broken runoff starts under the actual 13.5m structural bands.
	float band_height = mod(local_position.y + 0.2, 13.5);
	float under_ledge = 1.0 - smoothstep(0.0, 3.0 + mineral * 3.8, band_height);
	float rain_mask = noise(p * vec2(2.4, 0.075) + offset) * 0.68 + noise(p * vec2(8.0, 0.18) + offset) * 0.32;
	float runoff = smoothstep(0.40, 0.66, rain_mask) * (0.17 + under_ledge * 0.83) * vertical;
	color *= 1.0 - runoff * 0.78;
	// Isolated fastener/drain trails supply rust water, without an orange wash.
	float cell = floor(p.x / 3.0);
	float outlet = hash21(vec2(cell, wear_seed));
	float trail_x = abs(mod(p.x, 3.0) - (0.35 + outlet * 2.3) + warp.x * 0.14);
	float trail = (1.0 - smoothstep(0.035, 0.10 + band_height * 0.04, trail_x)) * under_ledge * step(0.57, outlet) * vertical;
	color = mix(color, vec3(0.16, 0.060, 0.022) * (0.75 + cement), trail * 0.67);
	float damp = (1.0 - smoothstep(0.15, 1.4 + mineral * 2.2, local_position.y)) * vertical;
	color = mix(color, vec3(0.035, 0.043, 0.025) * (0.7 + cement), damp * 0.74);
	// Exposed slabs collect irregular dirt; the forecourt must not look newly laid.
	float deposits = noise(p * 0.38 + offset) * 0.65 + noise(p * 1.1 + offset) * 0.35;
	color *= 1.0 - (1.0 - vertical) * (0.20 + deposits * 0.46);
	color = mix(color, vec3(0.065, 0.055, 0.040), smoothstep(0.43, 0.70, deposits) * (1.0 - vertical) * 0.38);
	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = metal;
	SPECULAR = surface_kind > 1.5 ? 0.38 : 0.18;
	relief *= detail;
	vec3 dx = dFdx(VERTEX), dy = dFdy(VERTEX);
	vec3 across_x = cross(dy, NORMAL), across_y = cross(NORMAL, dx);
	float determinant = dot(dx, across_x);
	NORMAL = normalize(NORMAL - sign(determinant) * (dFdx(relief) * across_x + dFdy(relief) * across_y) / max(abs(determinant), 0.000001));
}
