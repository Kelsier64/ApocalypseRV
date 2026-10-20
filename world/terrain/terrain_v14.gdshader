shader_type spatial;
render_mode cull_back;
uniform sampler2D ground_texture : repeat_enable, filter_linear_mipmap;
varying vec3 world_position;
varying vec3 world_normal;
varying vec3 view_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	view_position = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 p = world_position;
	vec3 weights = pow(abs(normalize(world_normal)), vec3(4.0));
	weights /= max(dot(weights, vec3(1.0)), 0.001);
	// The same world projections continue over cliff faces and distant sides.
	float xgrain = dot(textureLod(ground_texture, p.yz * 0.10, 3.0).rgb, vec3(0.333));
	float ygrain = dot(textureLod(ground_texture, p.xz * 0.10, 3.0).rgb, vec3(0.333));
	float zgrain = dot(textureLod(ground_texture, p.xy * 0.10, 3.0).rgb, vec3(0.333));
	float grain = dot(vec3(xgrain, ygrain, zgrain), weights);
	float stain = dot(textureLod(ground_texture, p.xz * 0.025, 4.0).rgb, vec3(0.333));
	float slope = 1.0 - abs(normalize(world_normal).y);
	float rock = max(smoothstep(0.18, 0.62, slope), UV2.x * smoothstep(0.16, 0.42, grain) * 0.72);
	float beds = 0.91 + 0.09 * sin(p.y * 0.83 + grain * 5.0);
	vec3 soil = COLOR.rgb * mix(0.74, 1.10, smoothstep(0.12, 0.40, grain)) * mix(0.87, 1.08, smoothstep(0.12, 0.40, stain));
	vec3 stone = mix(vec3(0.31, 0.32, 0.30), COLOR.rgb * 0.92, 0.58) * beds * mix(0.78, 1.08, smoothstep(0.12, 0.38, grain));
	vec3 ground = mix(soil, stone, rock);
	float damp = UV2.y * (1.0 - smoothstep(0.10, 0.45, slope)) * smoothstep(0.15, 0.37, stain);
	ground *= 1.0 - damp * 0.25;
	ground = mix(ground, vec3(0.38, 0.35, 0.27) * mix(0.75, 1.0, grain), max(UV.x * 0.85, UV.y * 0.65));
	ALBEDO = ground;
	vec3 face = normalize(cross(dFdx(view_position), dFdy(view_position)));
	face *= dot(face, NORMAL) < 0.0 ? -1.0 : 1.0;
	// Keep readable facets without exaggerating every regular grid diagonal.
	NORMAL = normalize(mix(NORMAL, face, 0.38));
	ROUGHNESS = mix(0.98, 0.85, damp);
	SPECULAR = 0.04;
}
