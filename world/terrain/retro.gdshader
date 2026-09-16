shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 pixel_grid = vec2(960.0, 540.0);
void fragment() {
	vec2 cell = floor(SCREEN_UV * pixel_grid);
	vec3 source = texture(screen_texture, (cell + 0.5) / pixel_grid).rgb;
	float dither = (mod(cell.x, 2.0) + mod(cell.y, 2.0) * 2.0) / 4.0 - 0.375;
	COLOR = vec4(clamp(source + dither / 90.0, vec3(0.0), vec3(1.0)), 1.0);
}
