shader_type spatial;
render_mode cull_disabled;

uniform mat4 mesh_to_print;
uniform float cutoff = 0.0;
uniform float progress = 0.0;
uniform vec4 base_color : source_color = vec4(0.4, 0.5, 0.5, 1.0);
uniform sampler2D base_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_texture = false;
uniform float surface_metallic = 0.0;
uniform float surface_roughness = 0.75;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
varying float print_height;

void vertex() {
	print_height = (mesh_to_print * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	if (progress <= 0.0 || print_height > cutoff) { discard; }
	vec3 color = base_color.rgb;
	if (has_texture) { color *= texture(base_texture, UV * uv_scale.xy + uv_offset.xy).rgb; }
	float active = 1.0 - step(0.9999, progress);
	float edge = (1.0 - smoothstep(0.0, 0.022, cutoff - print_height)) * active;
	float layers = smoothstep(0.72, 0.95, fract(print_height / 0.012)) * active;
	ALBEDO = color * (1.0 - layers * 0.15);
	METALLIC = surface_metallic;
	ROUGHNESS = surface_roughness;
	EMISSION = vec3(0.1, 0.85, 1.0) * edge * 2.5;
}
