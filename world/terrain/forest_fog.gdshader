shader_type fog;
uniform float density = 0.14;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float noise(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void fog() {
	vec3 edge = abs(UVW * 2.0 - 1.0);
	float border = 1.0 - smoothstep(0.35, 1.0, max(edge.x, edge.z));
	float height = 1.0 - smoothstep(0.12, 0.95, UVW.y);
	float pockets = smoothstep(0.22, 0.72, noise(WORLD_POSITION * vec3(0.045, 0.12, 0.045)));
	DENSITY = density * border * height * mix(0.15, 1.0, pockets);
	ALBEDO = vec3(0.28, 0.31, 0.30);
}
