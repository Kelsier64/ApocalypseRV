shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform float daylight = 1.0;
varying float age;
void vertex() {
	age = INSTANCE_CUSTOM.r;
}
void fragment() {
	float radius = length(UV - vec2(0.5));
	float ring = 1.0 - smoothstep(0.025, 0.10, abs(radius - 0.32));
	float spokes = 0.4 + 0.6 * pow(abs(sin(atan(UV.y - 0.5, UV.x - 0.5) * 5.0)), 4.0);
	ALBEDO = mix(vec3(0.2, 0.24, 0.28), vec3(0.57, 0.61, 0.63), daylight);
	ALPHA = ring * spokes * (1.0 - age) * 0.32 * mix(0.5, 1.0, daylight);
}
