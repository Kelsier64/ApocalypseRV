shader_type spatial;
render_mode cull_disabled;
void fragment() {
	vec2 cell = abs(fract(vec2(UV.x + UV.y, UV.x - UV.y) * 24.0) - 0.5);
	ALBEDO = vec3(0.27, 0.29, 0.25);
	ROUGHNESS = 0.95;
	ALPHA = 1.0 - step(0.08, min(cell.x, cell.y));
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
