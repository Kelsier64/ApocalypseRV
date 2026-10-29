shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.57, 0.58, 0.54, 1.0);
uniform float surface_kind = 0.0;
uniform float wear_seed = 0.0;
uniform int drain_count = 0;
uniform vec4 drain_sources[4];
varying vec3 local_position;
varying vec3 local_normal;
varying flat vec2 module_appearance;

// Continuous volume noise: no images, UV tiles, module offsets or face projection.
// All surfaces evaluate the same field at the same building-local position.
float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(
		mix(mix(hash31(cell), hash31(cell + vec3(1,0,0)), f.x),
			mix(hash31(cell + vec3(0,1,0)), hash31(cell + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash31(cell + vec3(0,0,1)), hash31(cell + vec3(1,0,1)), f.x),
			mix(hash31(cell + vec3(0,1,1)), hash31(cell + vec3(1,1,1)), f.x), f.y), f.z);
}
float filtered_noise(vec3 p, float footprint) {
	return mix(noise3(p), 0.5, smoothstep(0.25, 0.8, footprint));
}
float layers(vec3 p, float footprint) {
	return filtered_noise(p, footprint) * 0.57
		+ filtered_noise(p * 2.07 + vec3(19.1,7.7,31.3), footprint * 2.07) * 0.28
		+ filtered_noise(p * 4.13 + vec3(5.7,43.1,11.9), footprint * 4.13) * 0.15;
}
void vertex() {
	local_position = VERTEX;
	local_normal = NORMAL;
	module_appearance = UV2;
}
void fragment() {
	vec3 p = local_position;
	vec3 seed = vec3(wear_seed * 0.071, wear_seed * 0.039, wear_seed * 0.053);
	// A building has its own ageing history, not just a different noise phase.
	// These remain uniform over every batch, face and module of that building.
	float age = mix(0.35,1.0,hash31(seed + 117.3));
	float patch_scale = mix(0.60, 2.10, hash31(seed + 231.7));
	float patch_stretch = mix(0.72, 1.55, hash31(seed + 319.1));
	float weather_scale = mix(0.60, 1.60, hash31(seed + 431.9));
	float warmth = hash31(seed + 563.1);
	float oxide_hue = hash31(seed + 677.7);
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float vertical = 1.0 - smoothstep(0.6, 0.85, abs(normalize(local_normal).y));
	float detail = 1.0 - smoothstep(0.015, 0.09, footprint);
	float mineral = noise3(p * 0.17 + seed);
	float weather = layers(p * vec3(0.075,0.045,0.075) * weather_scale + seed + 51.7, footprint * 0.075 * weather_scale);
	float exposure = noise3(p * vec3(0.21,0.09,0.21) + seed + 91.6);
	// A continuous coarse field distorts the peeling boundary, never the structure.
	vec3 warped = p + vec3(mineral - 0.5, weather - 0.5, mineral + weather - 1.0) * mix(0.35,1.10,age);
	float grain = filtered_noise(p * 70.0 + seed + 8.3, footprint * 70.0);
	float grit = filtered_noise(p * 20.0 + seed + 37.1, footprint * 20.0);
	float abrasion = filtered_noise(p * 6.5 + seed + 47.9, footprint * 6.5);
	vec3 peel_frequency = vec3(1.35,1.8 * patch_stretch,1.35) * patch_scale;
	float skin = layers(warped * peel_frequency + seed + 17.3, footprint * 2.8 * patch_scale) * 0.62 + abrasion * 0.25 + grit * 0.13;
	float shade = mix(0.90, 1.03, COLOR.r);
	vec3 mineral_tint = mix(vec3(0.92,0.98,1.06), vec3(1.06,1.01,0.89), warmth);
	vec3 cement = mix(vec3(0.18,0.185,0.17), vec3(0.34,0.335,0.295), mineral) * mineral_tint;
	cement *= 0.82 + abrasion * 0.12 + grit * 0.20 + (grain - 0.5) * 0.12;
	float chalking = smoothstep(0.35,0.72,weather) * mix(0.12,0.36,age);
	vec3 paint = mix(base_color.rgb * mineral_tint, vec3(0.36,0.355,0.32), chalking) * (0.86 + mineral * 0.25);
	float pores = smoothstep(0.64,0.80,grain) * detail;
	vec3 color;
	float roughness = 0.96;
	float metal = 0.0;
	float relief = (grain - 0.5) * 0.0012;
	float peel_level = mix(0.55,0.43,age) + (exposure - 0.5) * 0.32;
	float skin_width = max(fwidth(skin) * 0.65, 0.012);
	float missing_paint = smoothstep(peel_level - skin_width, peel_level + skin_width, skin);
	if (surface_kind < 0.5) {
		color = mix(cement * 1.28, base_color.rgb * 0.68, 0.42);
		color *= 0.88 + mineral * 0.23;
		// Authored spall geometry exposes a granular interior, not a pasted patch.
		// Bare concrete pits in small clusters. Broad exposed aggregate belongs
		// to actual spalls, rather than giving structural beams paint-like islands.
		float eroded = max(COLOR.a, smoothstep(0.58,0.76,abrasion) * smoothstep(0.40,0.72,exposure) * mix(0.15,0.40,age));
		float stones = smoothstep(0.38,0.67,grit * 0.65 + abrasion * 0.35);
		vec3 aggregate = mix(vec3(0.10,0.105,0.09), mix(vec3(0.26,0.255,0.22),vec3(0.38,0.36,0.30),mineral), stones) * mineral_tint;
		color = mix(color, aggregate, eroded);
		color *= 1.0 - pores * (0.12 + eroded * 0.10);
		relief += (stones - 0.5) * eroded * 0.006 - pores * 0.001;
	} else if (surface_kind < 1.5) {
		// A worn undercoat appears only at the fragmented edge of remaining paint.
		float undercoat = smoothstep(peel_level - 0.075,peel_level - 0.015,skin) * (1.0 - missing_paint);
		color = mix(paint, vec3(0.31,0.285,0.23) * mineral_tint, undercoat * 0.48);
		color = mix(color, cement, missing_paint);
		float flake_edge = 1.0 - smoothstep(skin_width, skin_width + 0.008, abs(skin - peel_level));
		color *= 1.0 - flake_edge * 0.07 - pores * missing_paint * 0.18;
		relief += (1.0 - missing_paint) * 0.0025 + (grit - 0.5) * missing_paint * 0.003 - pores * 0.0008;
	} else {
		// Corrosion grows beneath paint in connected patches, from dark oxide to rust.
		float rust_scale = mix(0.70,1.80,hash31(seed + 719.3));
		float steel_wear = filtered_noise(warped * vec3(2.7,1.9,2.7) * rust_scale + seed + 101.3, footprint * 2.7 * rust_scale) * 0.7 + grit * 0.3;
		float rust = smoothstep(peel_level - 0.07, peel_level + 0.04, steel_wear);
		// Local repair stock can retain its dark coating; old structural steel
		// keeps alpha=0 and its established corrosion response.
		rust *= 1.0 - clamp(COLOR.a,0.0,1.0) * 0.75;
		float oxidation = filtered_noise(p * vec3(2.5,3.5,2.5) + seed + 227.2, footprint * 3.5);
		float oxide = smoothstep(0.23,0.78,oxidation * 0.60 + grit * 0.25 + exposure * 0.15);
		vec3 oxide_color = mix(vec3(0.14,0.064,0.032),vec3(0.29,0.087,0.021),oxide_hue);
		vec3 corrosion = mix(vec3(0.040,0.030,0.022), oxide_color, oxide);
		corrosion *= 0.76 + grit * 0.42;
		float crust = smoothstep(0.48,0.72,grit * 0.65 + steel_wear * 0.35) * rust;
		corrosion = mix(corrosion,vec3(0.055,0.027,0.013),crust * 0.42 + pores * 0.15);
		color = mix(base_color.rgb * (0.58 + mineral * 0.19), corrosion, rust);
		roughness = mix(0.75, 0.99, rust);
		metal = (1.0 - rust) * 0.20;
		relief += rust * ((grit - 0.5) * 0.0035 + crust * 0.002 - pores * 0.0015);
	}
	if (surface_kind < 1.5) {
		// Sparse fractures in exposed mineral surfaces. Integrated line coverage
		// fades below a pixel instead of widening into black outlines at distance.
		float fracture = noise3(warped * vec3(0.85,1.05,0.85) + seed + 183.7);
		float line_width = max(fwidth(fracture),0.000001);
		// Scale the isosurface band by its local gradient: a near-flat field must
		// not turn a millimetre fracture into a broad topographic contour.
		float crack_radius = line_width / max(footprint,0.0001) * 0.003;
		float crack = (1.0 - smoothstep(crack_radius,crack_radius + line_width * 0.5,abs(fracture - 0.5))) * min(1.0,crack_radius * 2.0 / line_width);
		crack *= smoothstep(0.48,0.64,skin) * smoothstep(0.35,0.65,exposure) * vertical;
		color *= 1.0 - crack * 0.55;
		relief -= crack * 0.0012;
	}
	color *= shade * mix(0.83, 1.09, weather);
	float stains = smoothstep(0.35,0.70,exposure) * smoothstep(0.35,0.60,weather);
	color *= 1.0 - stains * (0.10 + age * 0.15);
	// Rain is stretched along gravity in 3D, so it also crosses corners and modules.
	float rain_length = mix(0.025,0.11,hash31(seed + 829.7));
	float rain = layers(p * vec3(2.2,rain_length,2.2) + seed + 73.2, footprint * 2.2);
	float source_y = module_appearance.y;
	float below_ledge = max(0.0, source_y - p.y);
	float under_ledge = (1.0 - smoothstep(0.0, 2.2 + mineral * 2.4, below_ledge)) * step(p.y, source_y);
	float runoff = smoothstep(0.39,0.62,rain) * (0.16 + age * 0.16 + under_ledge * 0.48) * vertical;
	color *= 1.0 - runoff * 0.70;
	// Rust water follows actual pipes. It never inherits a per-panel random phase.
	float trail = 0.0;
	for (int index = 0; index < drain_count; index++) {
		vec4 drain = drain_sources[index];
		float depth = drain.y - p.y;
		float radius = 0.3 + clamp(depth * 0.025, 0.0, 0.5);
		float distance_to_pipe = length(p.xz - drain.xz) + (mineral - 0.5) * 0.10;
		float flow = (1.0 - smoothstep(0.10,radius,distance_to_pipe)) * step(0.0,depth) * step(drain.w - 1.4,p.y);
		trail = max(trail,flow);
	}
	color = mix(color, vec3(0.12,0.052,0.021) * (0.8 + grit * 0.3), trail * vertical * 0.66);
	float damp = (1.0 - smoothstep(0.15,0.7 + weather * mix(1.2,3.7,age),p.y)) * vertical;
	color = mix(color, vec3(0.045,0.056,0.032), damp * (0.48 + rain * 0.26));
	if (surface_kind < 1.5) {
		float mildew = smoothstep(0.50,0.70,weather + (0.5 - mineral) * 0.28) * (under_ledge * 0.30 + damp * 0.38) * vertical;
		color = mix(color,vec3(0.047,0.055,0.033),mildew);
		float salts = smoothstep(0.51,0.70,mineral * 0.55 + grit * 0.45) * runoff * mix(0.16,0.38,warmth);
		color = mix(color,vec3(0.38,0.37,0.32),salts);
	}
	// Horizontal surfaces collect dirt; broad features survive reduced resolution.
	float deposits = smoothstep(0.34,0.65,weather + (skin - 0.5) * 0.3) * (1.0 - vertical);
	color = mix(color * (1.0 - (1.0 - vertical) * 0.16), vec3(0.09,0.082,0.059), deposits * 0.55);
	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = metal;
	SPECULAR = surface_kind > 1.5 ? 0.32 : 0.18;
	relief *= detail * 0.28;
	vec3 dx = dFdx(VERTEX), dy = dFdy(VERTEX);
	vec3 across_x = cross(dy,NORMAL), across_y = cross(NORMAL,dx);
	float determinant = dot(dx,across_x);
	NORMAL = normalize(NORMAL - sign(determinant) * (dFdx(relief) * across_x + dFdy(relief) * across_y) / max(abs(determinant),0.000001));
}
