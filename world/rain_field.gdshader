shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;

uniform vec3 camera_center;
uniform float simulation_time = 0.0;
uniform float daylight = 1.0;
uniform float radius = 24.0;
uniform float field_height = 32.0;
uniform bool distant = false;
uniform float density = 1.0;
uniform sampler2D near_cover : filter_nearest, repeat_disable;
uniform sampler2D far_cover : filter_nearest, repeat_disable;
uniform int roof_count = 0;
uniform vec3 roof_origin[8];
uniform vec3 roof_row_x[8];
uniform vec3 roof_row_y[8];
uniform vec3 roof_row_z[8];
uniform vec3 roof_extents[8];
varying float visibility;
varying float opacity;

// Cache texels carry world cell coordinates so stale/unknown cells never leak rain.
float surface_height(sampler2D field, vec2 world_xz, float cell_size) {
	vec2 cell = floor(world_xz / cell_size);
	vec2 index = mod(cell, 64.0);
	vec4 sample_data = textureLod(field, (index + vec2(0.5)) / 64.0, 0.0);
	if (sample_data.a < 0.5 || any(greaterThan(abs(sample_data.gb - cell), vec2(0.1)))) return 100000.0;
	return sample_data.r;
}

bool roof_blocks(vec3 point, int index) {
	vec3 origin = vec3(dot(roof_row_x[index], point), dot(roof_row_y[index], point), dot(roof_row_z[index], point)) + roof_origin[index];
	vec3 direction = vec3(roof_row_x[index].y, roof_row_y[index].y, roof_row_z[index].y);
	vec3 inverse_direction = 1.0 / (mix(vec3(-1.0), vec3(1.0), greaterThanEqual(direction, vec3(0.0))) * max(abs(direction), vec3(0.00001)));
	vec3 a = (-roof_extents[index] - origin) * inverse_direction;
	vec3 b = (roof_extents[index] - origin) * inverse_direction;
	vec3 low = min(a, b);
	vec3 high = max(a, b);
	float entry = max(max(low.x, low.y), low.z);
	float exit_distance = min(min(high.x, high.y), high.z);
	return exit_distance >= max(entry, 0.0);
}

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;
	float speed = mix(10.0, 17.0, INSTANCE_CUSTOM.b);
	vec3 point;
	point.xz = mod(seed.xz - camera_center.xz + vec2(radius), vec2(radius * 2.0)) - vec2(radius) + camera_center.xz;
	point.y = camera_center.y + field_height * 0.5 - mod(camera_center.y + field_height * 0.5 - seed.y + simulation_time * speed, field_height);
	float distance_to_camera = length(point.xz - camera_center.xz);
	float width = mix(0.022, 0.048, INSTANCE_CUSTOM.r);
	float streak_length = mix(0.18, 0.46, INSTANCE_CUSTOM.g);
	if (distant) width *= 1.8;
	float height_limit;
	if (all(lessThan(abs(point.xz - camera_center.xz), vec2(22.0)))) {
		height_limit = surface_height(near_cover, point.xz, 0.75);
		// Conservative edge samples avoid streaks leaking along static roof edges.
		height_limit = max(height_limit, surface_height(near_cover, point.xz + vec2(0.375, 0.375), 0.75));
		height_limit = max(height_limit, surface_height(near_cover, point.xz + vec2(-0.375, 0.375), 0.75));
		height_limit = max(height_limit, surface_height(near_cover, point.xz + vec2(0.375, -0.375), 0.75));
		height_limit = max(height_limit, surface_height(near_cover, point.xz + vec2(-0.375, -0.375), 0.75));
	} else {
		height_limit = surface_height(far_cover, point.xz, 3.0);
	}
	visibility = smoothstep(0.6, 1.8, distance_to_camera) * (1.0 - smoothstep(radius * 0.78, radius, distance_to_camera));
	if (distant) visibility *= smoothstep(14.0, 23.0, distance_to_camera);
	visibility *= 1.0 - smoothstep(field_height * 0.38, field_height * 0.5, abs(point.y - camera_center.y));
	visibility *= smoothstep(height_limit + streak_length * 0.5, height_limit + streak_length, point.y);
	for (int i = 0; i < 8; i++) {
		if (i >= roof_count) break;
		if (roof_blocks(point - vec3(0.0, streak_length * 0.5, 0.0), i)) visibility = 0.0;
	}
	opacity = mix(0.24, 0.54, INSTANCE_CUSTOM.a) * density;
	vec3 right = vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z);
	right = length(right) > 0.001 ? normalize(right) : vec3(1.0, 0.0, 0.0);
	vec3 offset = right * VERTEX.x * width + vec3(0.0, VERTEX.y * streak_length, 0.0);
	VERTEX = (VIEW_MATRIX * vec4(point + offset, 1.0)).xyz;
	if (visibility < 0.001) VERTEX = vec3(0.0, 0.0, -0.01);
}

void fragment() {
	float taper = pow(max(sin(UV.y * 3.14159265), 0.0), 0.7);
	float aa = max(fwidth(UV.x), 0.02);
	float line = 1.0 - smoothstep(0.12 * taper - aa, 0.32 * taper + aa, abs(UV.x - 0.5));
	ALBEDO = mix(vec3(0.24, 0.29, 0.34), vec3(0.63, 0.67, 0.69), daylight);
	ALPHA = line * taper * opacity * visibility * mix(0.55, 1.0, daylight);
}
