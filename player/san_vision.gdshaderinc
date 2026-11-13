uniform float san_amount : hint_range(0.0, 1.0) = 0.0;
// Matches PlayerSanEffects.VisionProfile.
uniform int san_profile = 0;
uniform float san_elapsed = 0.0;

const vec3 SAN_LUMA = vec3(0.2126, 0.7152, 0.0722);

vec3 san_space_warp(vec2 uv, float aspect) {
	vec2 point = (uv - 0.5) * vec2(aspect, 1.0);
	vec2 edge = min(uv, 1.0 - uv);
	// Keep the center of attention and the frame border fixed.
	float mask = smoothstep(0.17, 0.43, length(point)) * smoothstep(0.0, 0.15, min(edge.x, edge.y));

	float phase = san_elapsed * 0.85;
	float swell = sin(dot(point, vec2(0.8, 0.6)) * 9.0 - phase);
	float crossflow = sin(dot(point, vec2(-0.6, 0.8)) * 12.0 + phase * 0.7);
	vec2 flow = vec2(0.73 * swell + 0.27 * crossflow, 0.28 * swell - 0.42 * crossflow);
	float strength = san_amount * mix(0.55, 1.0, san_amount);
	vec2 offset = flow * vec2(0.0065, 0.0060) * strength * mask;
	return video_grade(texture(screen_texture, uv + offset).rgb);
}

vec3 san_color_split(vec3 base, vec2 uv) {
	vec2 offset = (uv - 0.5) * (0.016 + 0.029 * san_amount + 0.004 * sin(san_elapsed * 3.0));
	vec3 red = video_grade(texture(screen_texture, uv + offset).rgb);
	vec3 blue = video_grade(texture(screen_texture, uv - offset).rgb);
	return vec3(red.r, base.g, blue.b);
}

vec3 san_tunnel_vision(vec3 base, vec2 uv) {
	float radius = length((uv - 0.5) * vec2(2.0, 2.45));
	float rim = 1.04 - 0.34 * san_amount;
	float aperture = 1.0 - smoothstep(rim * 0.62, rim, radius);
	return base * mix(0.025, 1.0, aperture);
}

vec3 san_vision(vec3 source, vec3 base, vec2 uv, float aspect) {
	switch (san_profile) {
		case 0:
			return (0.5 - base) * (1.0 + 0.45 * san_amount) + 0.5;
		case 1:
			return vec3((dot(base, SAN_LUMA) - 0.5) * (1.0 + 0.48 * san_amount) + 0.5);
		case 2:
			return mix(vec3(dot(source, SAN_LUMA)), source, 2.0 + 2.2 * san_amount);
		case 3:
			return san_space_warp(uv, aspect);
		case 4:
			return san_color_split(base, uv);
		case 5:
			return san_tunnel_vision(base, uv);
	}
	return base;
}
