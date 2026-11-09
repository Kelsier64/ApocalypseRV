shader_type canvas_item;
render_mode unshaded;

uniform sampler2D scene_texture : hint_screen_texture, filter_linear, repeat_disable;
uniform vec3 tint = vec3(1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 scene = texture(scene_texture, SCREEN_UV).rgb;
	float luminance = dot(scene, vec3(0.2126, 0.7152, 0.0722));
	vec3 faded = mix(scene, vec3(luminance), 0.68);
	vec3 shifted = faded * tint + luminance * (tint - 1.0) * 0.45;
	vec2 centered = SCREEN_UV * 2.0 - 1.0;
	float edge = smoothstep(0.26, 1.65, dot(centered, centered));
	shifted *= 1.0 - 0.55 * edge;
	COLOR = vec4(clamp(mix(scene, shifted, amount), 0.0, 1.0), 1.0);
}
