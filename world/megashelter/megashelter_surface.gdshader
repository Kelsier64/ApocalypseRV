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
uniform int drain_count = 0;
uniform vec4 drain_sources[4];
varying vec3 local_position;
varying vec3 local_normal;
// Interpolation drift fed into a hash would scramble UV gradients and blur mips.
varying flat vec2 module_appearance;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 q = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(q), hash21(q + vec2(1,0)), f.x), mix(hash21(q + vec2(0,1)), hash21(q + vec2(1,1)), f.x), f.y);
}
vec2 orient(vec2 p, float turn) {
	if (turn < 1.0) { return p; }
	if (turn < 2.0) { return vec2(-p.y, p.x); }
	if (turn < 3.0) { return -p; }
	return vec2(p.y, -p.x);
}
void vertex() { local_position = VERTEX; local_normal = NORMAL; module_appearance = UV2; }
void fragment() {
	vec3 n = abs(normalize(local_normal));
	float vertical = 1.0 - smoothstep(0.6, 0.85, n.y);
	vec2 p = n.y > 0.7 ? local_position.xz : vec2(n.x > n.z ? local_position.z : local_position.x, local_position.y);
	vec2 offset = vec2(wear_seed * 0.071, wear_seed * 0.039);
	// UV2 is flat within each module. Only nondirectional surface textures rotate;
	// rain and drain masks below stay in untransformed building coordinates.
	float story = floor((local_position.y + 0.02) / 4.5);
	vec2 key = vec2(module_appearance.x * 127.0 + wear_seed * 0.013, story);
	vec2 tile_offset = vec2(hash21(key), hash21(key + 19.7)) * 17.0;
	vec2 second_offset = vec2(hash21(key + 113.7), hash21(key + 149.2)) * 23.0;
	float tile_scale = mix(0.68, 1.42, hash21(key + 42.3));
	float second_scale = mix(0.55, 1.35, hash21(key + 193.4));
	float turn = floor(hash21(key + 67.2) * 4.0);
	float second_turn = floor(hash21(key + 173.6) * 4.0);
	float mirror = hash21(key + 73.1) < 0.5 ? -1.0 : 1.0;
	float age = hash21(key + 211.9);
	float mineral = noise(p * 0.19 + offset);
	vec2 warp = vec2(noise(p * 0.62 + offset), noise(p * 0.71 + offset + 13.0)) - 0.5;
	float distortion = mix(0.35, 1.15, hash21(key + 237.4));
	vec2 material_p = orient(p * vec2(mirror, 1.0), turn) * tile_scale + warp * distortion;
	vec2 material_q = orient(p, second_turn) * second_scale - warp.yx * 1.3;
	// Explicit gradients exclude discrete panel offsets/turns from mip selection.
	// Warping is continuous, so its own gradients still contribute to filtering.
	vec2 px = dFdx(p), py = dFdy(p), wx = dFdx(warp), wy = dFdy(warp);
	vec2 primary_x = orient(px * vec2(mirror, 1.0), turn) * tile_scale + wx * distortion;
	vec2 primary_y = orient(py * vec2(mirror, 1.0), turn) * tile_scale + wy * distortion;
	vec2 second_x = orient(px, second_turn) * second_scale - wx.yx * 1.3;
	vec2 second_y = orient(py, second_turn) * second_scale - wy.yx * 1.3;
	float blend_field = noise(p * 0.31 + warp * 0.65 + offset + tile_offset) * 0.70
		+ noise(p * 0.73 + warp * 0.35 + offset + second_offset) * 0.30;
	float material_blend = smoothstep(0.47, 0.55, blend_field);
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float detail = 1.0 - smoothstep(0.018, 0.10, footprint);
	float cement = textureGrad(concrete_texture, material_p * 0.5 + offset + tile_offset, primary_x * 0.5, primary_y * 0.5).r;
	float shade = mix(0.84, 1.04, COLOR.r);
	vec3 color = base_color.rgb * shade * (0.84 + mineral * 0.23);
	float relief = cement * 0.0015;
	float roughness = 0.96;
	float metal = 0.0;
	if (surface_kind < 0.5) {
		color *= 0.67 + cement * 1.20;
		// Metre-scale erosion exposes aggregate, separate from the tiny cement pores.
		float chipped_skin = textureGrad(decay_texture, material_p / 3.0 + offset + tile_offset, primary_x / 3.0, primary_y / 3.0).r;
		float erosion = noise(p * mix(0.30, 0.70, age) + offset + tile_offset * 0.53) * 0.70 + chipped_skin * 0.30;
		float erosion_start = mix(0.64, 0.54, age);
		float damage = max(COLOR.a, smoothstep(erosion_start, erosion_start + 0.07, erosion) * 0.76 * vertical);
		vec3 stones = textureGrad(aggregate_texture, material_p * 0.8 + offset + tile_offset, primary_x * 0.8, primary_y * 0.8).rgb;
		color = mix(color, stones * vec3(0.70, 0.67, 0.61) + vec3(0.045), damage);
		relief += stones.r * damage * 0.004;
		vec2 tie = (fract(p / vec2(1.8, 2.25) + 0.5) - 0.5) * vec2(1.8, 2.25);
		float hole = 1.0 - smoothstep(0.018, 0.029 + fwidth(length(tie)), length(tie));
		color *= 1.0 - hole * vertical * 0.40;
	} else if (surface_kind < 1.5) {
		// Decayed mineral paint and exposed cement are actual coloured material,
		// not tiny dark specks added to an otherwise pristine panel.
		vec3 decay_a = textureGrad(decay_texture, material_p / 6.0 + offset + tile_offset, primary_x / 6.0, primary_y / 6.0).rgb;
		vec3 decay_b = textureGrad(decay_texture, material_q / 4.3 + offset + second_offset, second_x / 4.3, second_y / 4.3).rgb;
		vec3 decay = mix(decay_a, decay_b, material_blend);
		color = mix(color, decay, 0.82) * shade * (0.86 + mineral * 0.25);
		float exposed = smoothstep(0.57, 0.76, blend_field + age * 0.16) * mix(0.08, 0.28, age);
		color = mix(color, vec3(0.22, 0.225, 0.20) * (0.7 + cement), exposed);
		float joint_distance = abs(mod(local_position.y + 2.25, 4.5) - 2.25);
		float joint = (1.0 - smoothstep(0.012, 0.028 + fwidth(p.y), joint_distance)) * vertical;
		color *= 1.0 - joint * 0.48;
		relief = dot(decay, vec3(0.3, 0.5, 0.2)) * 0.003 - joint * 0.003;
		roughness = 0.91 + cement * 0.08;
	} else {
		vec3 corrosion_a = textureGrad(corrosion_texture, material_p * 0.25 + offset + tile_offset, primary_x * 0.25, primary_y * 0.25).rgb;
		vec3 corrosion_b = textureGrad(corrosion_texture, material_q / 3.0 + offset + second_offset, second_x / 3.0, second_y / 3.0).rgb;
		vec3 corrosion = mix(corrosion_a, corrosion_b, material_blend);
		float rust = smoothstep(0.012, 0.09, corrosion.r - corrosion.g * 0.92);
		color = mix(color * 0.8, corrosion * 1.12, 0.91) * shade;
		float scratch = textureGrad(coating_texture, material_p * 0.5 + offset + tile_offset, primary_x * 0.5, primary_y * 0.5).r;
		float paint_remaining = smoothstep(0.52, 0.74, blend_field + (1.0 - age) * 0.12) * mix(0.12, 0.34, hash21(key + 259.3));
		color = mix(color, base_color.rgb * (0.65 + scratch * 0.9), paint_remaining);
		float oxide = smoothstep(0.46, 0.70, 1.0 - blend_field) * age * 0.23;
		color *= mix(vec3(1.0), vec3(0.62, 0.55, 0.48), oxide);
		relief = scratch * 0.0009 + rust * 0.0025;
		roughness = mix(mix(0.65, 0.98, rust), 0.80, paint_remaining);
		metal = mix(0.38, 0.0, rust) * (1.0 - paint_remaining * 0.6);
	}
	vec3 finish_tint = mix(vec3(0.92, 0.97, 1.0), vec3(1.10, 1.03, 0.88), hash21(key + 271.4));
	color *= finish_tint * mix(0.91, 1.09, age);
	// Low-frequency object-space fields cross module/floor boundaries continuously.
	// Their scale is tens of metres, independent of the local peeling texture.
	vec2 macro_p = local_position.xz * 0.043 + vec2(local_position.y * 0.019, -local_position.y * 0.012);
	float weathering = noise(macro_p + offset);
	float bleaching = noise(macro_p * 1.73 + offset + 31.8);
	color *= mix(0.78, 1.12, weathering);
	color = mix(color, color * vec3(1.15, 1.11, 1.02), smoothstep(0.52, 0.83, bleaching) * 0.45);
	// Runoff uses each wall top or beam/lintel underside, not a repeating height grid.
	float source_y = module_appearance.y;
	float below_ledge = max(0.0, source_y - local_position.y);
	float under_ledge = (1.0 - smoothstep(0.0, 3.0 + mineral * 3.8, below_ledge)) * step(local_position.y, source_y);
	float rain_phase = module_appearance.x * 43.0;
	float rain_mask = noise(p * vec2(2.4, 0.075) + offset + rain_phase) * 0.68 + noise(p * vec2(8.0, 0.18) + offset + rain_phase) * 0.32;
	float runoff = smoothstep(0.40, 0.66, rain_mask) * (0.17 + under_ledge * 0.45) * vertical;
	color *= 1.0 - runoff * 0.78;
	// Rust-water trails belong to actual drain lines and stay in building space;
	// they do not inherit the texture's random offset, mirror or scale.
	float trail = 0.0;
	for (int index = 0; index < drain_count; index++) {
		vec4 drain = drain_sources[index];
		float depth = drain.y - local_position.y;
		float radius = 0.35 + clamp(depth * 0.025, 0.0, 0.55);
		float distance_to_pipe = length(local_position.xz - drain.xz) + warp.x * 0.09;
		float flow = (1.0 - smoothstep(0.15, radius, distance_to_pipe)) * step(0.0, depth) * step(drain.w - 1.4, local_position.y);
		trail = max(trail, flow);
	}
	trail *= vertical;
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
