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
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float vertical = 1.0 - smoothstep(0.6, 0.85, abs(normalize(local_normal).y));
	float detail = 1.0 - smoothstep(0.015, 0.09, footprint);
	float mineral = noise3(p * 0.17 + seed);
	float weather = layers(p * vec3(0.075,0.045,0.075) + seed + 51.7, footprint * 0.075);
	// A continuous coarse field distorts the peeling boundary, never the structure.
	vec3 warped = p + vec3(mineral - 0.5, weather - 0.5, mineral + weather - 1.0) * 0.7;
	float grain = filtered_noise(p * 38.0 + seed + 8.3, footprint * 38.0);
	float grit = filtered_noise(p * 11.0 + seed + 37.1, footprint * 11.0);
	float skin = layers(warped * vec3(1.35,1.8,1.35) + seed + 17.3, footprint * 2.0) * 0.72 + grit * 0.28;
	float shade = mix(0.90, 1.03, COLOR.r);
	vec3 cement = mix(vec3(0.20,0.205,0.185), vec3(0.34,0.335,0.295), mineral);
	cement *= 0.88 + grit * 0.20 + (grain - 0.5) * 0.12;
	vec3 paint = base_color.rgb * (0.86 + mineral * 0.25);
	vec3 color;
	float roughness = 0.96;
	float metal = 0.0;
	float relief = (grain - 0.5) * 0.0012;
	float peel_level = 0.49 + (weather - 0.5) * 0.20;
	float skin_width = max(fwidth(skin) * 0.65, 0.012);
	float missing_paint = smoothstep(peel_level - skin_width, peel_level + skin_width, skin);
	if (surface_kind < 0.5) {
		color = mix(cement * 1.28, base_color.rgb * 0.68, 0.42);
		color *= 0.88 + mineral * 0.23;
		// Authored spall geometry exposes a granular interior, not a pasted patch.
		float eroded = max(COLOR.a, smoothstep(0.60,0.73,skin + weather * 0.13) * 0.65);
		vec3 aggregate = mix(vec3(0.12,0.125,0.11), vec3(0.30,0.29,0.25), grit);
		color = mix(color, aggregate, eroded);
		relief += (grit - 0.5) * eroded * 0.006;
	} else if (surface_kind < 1.5) {
		// Remaining mineral paint, exposed cement and the thin dark flake edge.
		color = mix(paint, cement, missing_paint);
		float flake_edge = 1.0 - smoothstep(skin_width, skin_width + 0.008, abs(skin - peel_level));
		color *= 1.0 - flake_edge * 0.05;
		relief += (1.0 - missing_paint) * 0.0025 + (grit - 0.5) * missing_paint * 0.003;
	} else {
		// Corrosion grows beneath paint in connected patches, from dark oxide to rust.
		float steel_wear = filtered_noise(warped * vec3(2.7,1.9,2.7) + seed + 101.3, footprint * 2.7) * 0.7 + grit * 0.3;
		float rust = smoothstep(peel_level - 0.07, peel_level + 0.04, steel_wear);
		float oxide = clamp((steel_wear - 0.38) * 2.4 + (weather - 0.5) * 0.5, 0.0, 1.0);
		vec3 corrosion = mix(vec3(0.055,0.038,0.024), vec3(0.22,0.082,0.025), oxide);
		corrosion *= 0.76 + grit * 0.42;
		color = mix(base_color.rgb * (0.58 + mineral * 0.19), corrosion, rust);
		roughness = mix(0.75, 0.99, rust);
		metal = (1.0 - rust) * 0.20;
		relief += rust * (grit * 0.0035 - 0.001);
	}
	color *= shade * mix(0.83, 1.09, weather);
	// Rain is stretched along gravity in 3D, so it also crosses corners and modules.
	float rain = layers(p * vec3(2.2,0.055,2.2) + seed + 73.2, footprint * 2.2);
	float source_y = module_appearance.y;
	float below_ledge = max(0.0, source_y - p.y);
	float under_ledge = (1.0 - smoothstep(0.0, 2.2 + mineral * 2.4, below_ledge)) * step(p.y, source_y);
	float runoff = smoothstep(0.39,0.62,rain) * (0.24 + under_ledge * 0.48) * vertical;
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
	float damp = (1.0 - smoothstep(0.15,1.0 + weather * 2.1,p.y)) * vertical;
	color = mix(color, vec3(0.045,0.056,0.032), damp * (0.48 + rain * 0.26));
	// Horizontal surfaces collect dirt; broad features survive reduced resolution.
	float deposits = smoothstep(0.34,0.65,weather + (skin - 0.5) * 0.3) * (1.0 - vertical);
	color = mix(color * (1.0 - (1.0 - vertical) * 0.16), vec3(0.09,0.082,0.059), deposits * 0.55);
	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = metal;
	SPECULAR = surface_kind > 1.5 ? 0.32 : 0.18;
	relief *= detail;
	vec3 dx = dFdx(VERTEX), dy = dFdy(VERTEX);
	vec3 across_x = cross(dy,NORMAL), across_y = cross(NORMAL,dx);
	float determinant = dot(dx,across_x);
	NORMAL = normalize(NORMAL - sign(determinant) * (dFdx(relief) * across_x + dFdy(relief) * across_y) / max(abs(determinant),0.000001));
}
