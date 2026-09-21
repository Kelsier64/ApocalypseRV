shader_type sky;
// WorldClock already matches the sky to distance fog. A second volumetric
// attenuation here would darken only the background and reveal pale silhouettes.
render_mode disable_fog;
uniform vec4 horizon_color : source_color = vec4(0.643137, 0.674510, 0.662745, 1.0);
uniform vec4 zenith_color : source_color = vec4(0.498, 0.573, 0.596, 1.0);
uniform vec4 sun_color : source_color = vec4(0.87, 0.86, 0.80, 1.0);
uniform vec3 sun_direction = vec3(0.0, 0.85, 0.526783);
uniform float sun_strength : hint_range(0.0, 1.0) = 1.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.7;
uniform float fog_cover : hint_range(0.0, 1.0) = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float cloud_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1,0)), f.x), mix(hash(i + vec2(0,1)), hash(i + vec2(1,1)), f.x), f.y);
}
void sky() {
	vec2 p = EYEDIR.xz / (0.32 + max(EYEDIR.y, 0.0)) * 1.6;
	float cloud = cloud_noise(p) * 0.7 + cloud_noise(p * 2.2) * 0.3;
	// Shared source_color keeps sky and fog in the same color space.
	// Low-contrast cloud cover fades out above the horizon, not over geometry.
	vec3 top = zenith_color.rgb * mix(1.0, mix(0.88, 1.03, smoothstep(0.2, 0.8, cloud)), cloud_cover);
	COLOR = mix(horizon_color.rgb, top, smoothstep(0.06, 0.65, EYEDIR.y));
	float alignment = max(dot(normalize(EYEDIR), sun_direction), 0.0);
	float disk = smoothstep(cos(0.014), cos(0.009), alignment);
	float halo = pow(alignment, 96.0) * 0.10;
	float cloud_transmission = mix(1.0, mix(0.2, 0.65, cloud), cloud_cover);
	// Soft sun behind overcast, clipped below the horizon rather than glowing at night.
	COLOR += sun_color.rgb * (disk * 0.65 + halo) * sun_strength * cloud_transmission * smoothstep(-0.015, 0.015, EYEDIR.y);
	COLOR = mix(COLOR, horizon_color.rgb, fog_cover);
}
