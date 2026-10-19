shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform bool retro_enabled = true;
uniform float brightness = 1.0;
uniform float contrast = 1.0;
uniform float saturation = 1.0;
void fragment() {
	// Resolution loss comes from the 3D viewport, not a second mosaic filter.
	vec3 source = texture(screen_texture, SCREEN_UV).rgb;
	// Keep a shadow toe: the contrast offset otherwise clips faint night
	// silhouettes to black before the world's distance fade reaches its end.
	// Exact black stays black; the original midtone/highlight grade is retained.
	vec3 retro_grade = max((source - 0.38) * 1.04 + 0.38, source * 0.5);
	vec3 graded = retro_enabled ? retro_grade : source;
	graded = clamp(graded, vec3(0.0), vec3(1.0));
	float luminance = dot(graded, vec3(0.2126, 0.7152, 0.0722));
	graded = mix(vec3(luminance), graded, saturation);
	graded = clamp(((graded - 0.5) * contrast + 0.5) * brightness, vec3(0.0), vec3(1.0));
	COLOR = vec4(graded, 1.0);
}
