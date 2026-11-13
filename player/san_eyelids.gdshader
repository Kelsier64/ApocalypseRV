shader_type canvas_item;
render_mode unshaded;

uniform float closure : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 eye = UV * 2.0 - 1.0;
	float opening = mix(1.08, -0.04, closure) - 0.15 * eye.x * eye.x * closure;
	float lid = smoothstep(-0.035, 0.035, abs(eye.y) - opening);
	COLOR = vec4(0.0, 0.0, 0.0, lid);
}
