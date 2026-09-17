shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
void fragment() {
	// Resolution loss comes from the 3D viewport, not a second mosaic filter.
	vec3 source = texture(screen_texture, SCREEN_UV).rgb;
	vec3 graded = clamp((source - 0.38) * 1.04 + 0.38, vec3(0.0), vec3(1.0));
	COLOR = vec4(graded, 1.0);
}
