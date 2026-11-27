// Roof shelter shared by weather particles. WeatherRain fills these uniforms
// for its own fields and for every material in its shelter_materials.
uniform int roof_count = 0;
uniform vec3 roof_origin[32];
uniform vec3 roof_row_x[32];
uniform vec3 roof_row_y[32];
uniform vec3 roof_row_z[32];
uniform vec3 roof_extents[32];

// Cache texels carry world cell coordinates so stale/unknown cells never leak weather.
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

// True when any dynamic roof (the RV) sits above the point.
bool under_roof(vec3 point) {
	for (int i = 0; i < 32; i++) {
		if (i >= roof_count) break;
		if (roof_blocks(point, i)) return true;
	}
	return false;
}
