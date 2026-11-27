shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, specular_disabled;

uniform vec3 camera_center;
uniform float simulation_time = 0.0;
uniform float radius = 24.0;
uniform float field_height = 32.0;
uniform bool distant = false;
uniform float density = 1.0;
// Horizontal wind in m/s; drops drift downwind as they fall.
uniform vec3 wind = vec3(0.0);
uniform sampler2D near_cover : filter_nearest, repeat_disable;
uniform sampler2D far_cover : filter_nearest, repeat_disable;
varying float visibility;
varying float opacity;

#include "res://world/weather_shelter.gdshaderinc"

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;
	float speed = mix(10.0, 17.0, INSTANCE_CUSTOM.b);
	vec3 point;
	point.y = camera_center.y + field_height * 0.5 - mod(camera_center.y + field_height * 0.5 - seed.y + simulation_time * speed, field_height);
	// Horizontal travel per metre fallen. Offsetting by height relative to the
	// camera keeps the lean bounded and moves each drop downwind as it falls.
	vec2 lean = wind.xz / speed;
	point.xz = mod(seed.xz - lean * (point.y - camera_center.y) - camera_center.xz + vec2(radius), vec2(radius * 2.0)) - vec2(radius) + camera_center.xz;
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
	if (under_roof(point - vec3(0.0, streak_length * 0.5, 0.0))) visibility = 0.0;
	opacity = mix(0.24, 0.54, INSTANCE_CUSTOM.a) * density;
	vec3 right = vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z);
	right = length(right) > 0.001 ? normalize(right) : vec3(1.0, 0.0, 0.0);
	// Streaks lie along the drop's path, upwind at the top.
	vec3 path = vec3(-lean.x, 1.0, -lean.y);
	vec3 offset = right * VERTEX.x * width + path * VERTEX.y * streak_length;
	VERTEX = (VIEW_MATRIX * vec4(point + offset, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	if (visibility < 0.001) VERTEX = vec3(0.0, 0.0, -0.01);
}

void fragment() {
	float taper = pow(max(sin(UV.y * 3.14159265), 0.0), 0.7);
	float aa = max(fwidth(UV.x), 0.02);
	float line = 1.0 - smoothstep(0.12 * taper - aa, 0.32 * taper + aa, abs(UV.x - 0.5));
	ALBEDO = vec3(0.63, 0.67, 0.69);
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.5);
	ALPHA = line * taper * opacity * visibility;
}
