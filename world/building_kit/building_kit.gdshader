shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Building kit finish. The photo texture supplies value detail; the finish tint
// supplies the colour, so every building stays inside the GDD's cold, low
// saturation palette. keep_color lets rust and stains show their own hue.
// UV is building-local metres (written by BuildingKit); UV2.x is local height,
// COLOR.r a per-piece shade and COLOR.a marks chamfered edges.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(0.55, 0.56, 0.54, 1.0);
uniform vec4 mean_color : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float keep_color : hint_range(0.0, 1.0) = 0.0;
uniform float detail : hint_range(0.0, 2.0) = 1.0;
uniform float texel_meters = 2.0;
uniform float roughness_scale = 1.0;
uniform float normal_strength = 1.0;
uniform float grime_height = 1.1;
uniform float grime : hint_range(0.0, 1.0) = 0.35;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.3;

varying float v_height;
varying float v_shade;
varying float v_edge;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

void vertex() {
	v_height = UV2.x;
	v_shade = COLOR.r;
	v_edge = COLOR.a;
}

void fragment() {
	vec2 uv = UV / texel_meters;
	vec3 photo = texture(albedo_tex, uv).rgb;
	float mean_luma = max(dot(mean_color.rgb, LUMA), 0.02);
	float ratio = dot(photo, LUMA) / mean_luma;
	vec3 value = tint.rgb * mix(1.0, ratio, detail);
	vec3 hue = photo * (dot(tint.rgb, LUMA) / mean_luma);
	vec3 colour = mix(value, hue, keep_color);
	// Rising damp and splash grime near the building's base.
	float damp = 1.0 - smoothstep(0.0, grime_height, v_height);
	colour *= 1.0 - grime * damp * clamp(1.15 - ratio * 0.5, 0.3, 1.0);
	// Chamfered edges read as handled, chipped wear.
	colour = mix(colour, colour * 1.3 + vec3(0.015), edge_wear * v_edge);
	ALBEDO = clamp(colour * v_shade, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(texture(rough_tex, uv).r * roughness_scale, 0.04, 1.0);
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}
