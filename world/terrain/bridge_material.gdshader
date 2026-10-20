shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.48, 0.49, 0.44, 1.0);
uniform bool steel = false;
varying vec3 world_position;
float hash(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 p = world_position;
	float grain = hash(floor(p * 18.0));
	float patch = sin(p.x * 0.73 + sin(p.z * 0.31)) * sin(p.y * 0.42 + p.z * 0.16);
	float streak = smoothstep(0.65, 0.95, sin(p.x * 3.8 + p.z * 2.9)) * 0.08;
	ALBEDO = base_color.rgb * (0.84 + grain * 0.12 + patch * 0.08 - streak);
	if (steel) {
		float rust = smoothstep(0.35, 0.85, patch + grain * 0.35);
		ALBEDO = mix(ALBEDO, vec3(0.24, 0.13, 0.07), rust * 0.28);
	} else {
		float joint = 1.0 - smoothstep(0.015, 0.045, abs(fract(p.y / 2.4) - 0.5));
		ALBEDO *= 1.0 - joint * 0.12;
	}
	ROUGHNESS = steel ? 0.78 : 0.94;
	METALLIC = steel ? 0.55 : 0.0;
}
