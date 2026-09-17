shader_type spatial;
render_mode cull_back;
varying vec3 world_position;
// Used as a scalar stain mask, so keep raw values identical across renderers.
uniform sampler2D ground_texture : repeat_enable, filter_linear_mipmap;
varying vec3 view_position;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	view_position = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	// Broad stains describe soil; suppress the source's individual leaf litter.
	float stain = dot(textureLod(ground_texture, world_position.xz * 0.045, 3.0).rgb, vec3(0.333));
	float soil = dot(textureLod(ground_texture, world_position.xz * 0.22, 1.0).rgb, vec3(0.333));
	ALBEDO = COLOR.rgb * mix(0.60, 1.14, smoothstep(0.16, 0.38, stain)) * mix(0.82, 1.12, smoothstep(0.12, 0.43, soil));
	// Flat light on the existing triangles; vertex positions and collision stay aligned.
	vec3 face = normalize(cross(dFdx(view_position), dFdy(view_position)));
	NORMAL = face * (dot(face, NORMAL) < 0.0 ? -1.0 : 1.0);
	ROUGHNESS = 0.98;
	SPECULAR = 0.0;
}
