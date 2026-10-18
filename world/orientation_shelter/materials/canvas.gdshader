shader_type spatial;
render_mode cull_disabled, diffuse_burley;

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec4 h = fract(sin(vec4(dot(i,vec2(127.1,311.7)), dot(i+vec2(1,0),vec2(127.1,311.7)), dot(i+vec2(0,1),vec2(127.1,311.7)), dot(i+vec2(1),vec2(127.1,311.7)))) * 43758.5453);
	return mix(mix(h.x,h.y,f.x),mix(h.z,h.w,f.x),f.y);
}

void fragment() {
	float grime = noise(UV * vec2(7.0, 14.0));
	float weave = sin(UV.x * 1700.0) * sin(UV.y * 3500.0);
	float hem = smoothstep(0.018, 0.03, min(min(UV.x, 1.0-UV.x), min(UV.y, 1.0-UV.y)));
	ALBEDO = vec3(0.105, 0.12, 0.073) * (0.7 + grime * 0.42 + weave * 0.018) * mix(0.6, 1.0, hem);
	ROUGHNESS = 0.97;
	SPECULAR = 0.15;
}
