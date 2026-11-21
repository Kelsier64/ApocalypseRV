shader_type spatial;

uniform vec4 paint : source_color;
uniform float wear = 0.55;
varying vec3 surface_pos;

float hash(vec3 v) {
	v = fract(v * vec3(0.1031, 0.11369, 0.13787));
	v += dot(v, v.yzx + 19.19);
	return fract((v.x + v.y) * v.z);
}

float grain(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	vec4 lower = vec4(hash(cell), hash(cell + vec3(1,0,0)), hash(cell + vec3(0,1,0)), hash(cell + vec3(1,1,0)));
	cell.z += 1.0;
	vec4 upper = vec4(hash(cell), hash(cell + vec3(1,0,0)), hash(cell + vec3(0,1,0)), hash(cell + vec3(1,1,0)));
	vec4 corners = mix(lower, upper, f.z);
	return mix(mix(corners.x, corners.y, f.x), mix(corners.z, corners.w, f.x), f.y);
}

void vertex() {
	surface_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float stain = grain(surface_pos * vec3(2.7, 0.65, 2.7));
	float fleck = grain(surface_pos * 19.0);
	float exposed = smoothstep(0.65, 0.79, stain * 0.65 + fleck * 0.35) * wear;
	ALBEDO = mix(paint.rgb * (0.71 + stain * 0.4 + fleck * 0.12), vec3(0.16, 0.085, 0.047), exposed);
	ROUGHNESS = 0.86;
}
