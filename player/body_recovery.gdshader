shader_type canvas_item;
render_mode unshaded;

uniform sampler2D view_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float closure : hint_range(0.0, 1.0);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float edge = length(p * vec2(0.75, 1.65));
	float opening = mix(2.15, -0.35, closure);
	float light = 1.0 - smoothstep(opening - 0.28, opening + 0.28, edge);
	vec3 view = textureLod(view_texture, SCREEN_UV, closure * (1.8 + edge)).rgb;
	float luma = dot(view, vec3(0.2126, 0.7152, 0.0722));
	COLOR = vec4(mix(view, vec3(luma), closure * 0.65) * light * (1.0 - 0.35 * closure), 1.0);
}
