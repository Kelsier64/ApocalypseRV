shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec3 dust_color : source_color = vec3(0.38, 0.34, 0.28);
uniform float density = 0.22;
varying float seed;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() {
	seed = fract(float(INSTANCE_ID) * 0.618034);
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	facing[0].xyz *= length(MODEL_MATRIX[0].xyz);
	facing[1].xyz *= length(MODEL_MATRIX[1].xyz);
	facing[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float cloud = noise(UV * 5.0 + seed * 13.0) * 0.65 + noise(UV * 12.0 - seed * 7.0) * 0.35;
	float edge = 1.0 - smoothstep(0.30, 0.96, length(p) + (cloud - 0.5) * 0.3);
	ALBEDO = dust_color * (0.65 + cloud * 0.7);
	ALPHA = edge * cloud * density * COLOR.a;
}
