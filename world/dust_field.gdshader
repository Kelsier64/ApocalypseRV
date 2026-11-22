shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform, specular_disabled;

// Blowing dust around the camera. Grit: thin streaks skimming the ground along
// the wind. Puffs: soft camera-facing cards, used both for the large clouds
// rolling past in the distance and for the dense sheets streaming past close
// up. Positions come from fixed seeds, the integrated wind travel and time;
// nothing per particle is uploaded after the field is built.
uniform vec3 camera_center;
uniform vec3 drift;
uniform vec3 flow;
uniform float simulation_time = 0.0;
uniform float radius = 18.0;
uniform float band_height = 5.0;
uniform bool puff = false;
uniform float density = 1.0;
uniform float opacity_scale = 1.0;
// Puffs: size range in metres, opacity range, centre height above the ground.
uniform float size_min = 2.5;
uniform float size_max = 6.5;
uniform float opacity_min = 0.05;
uniform float opacity_max = 0.14;
uniform float lift_min = 0.8;
// Above 1 the card stretches along the wind as seen on screen.
uniform float stretch = 1.0;
// 0 to 1: how much a large noise travelling with the air thins the puffs
// between gusts of thick dust, so the view opens and closes.
uniform float clump = 0.0;
// Puffs fade in from near_fade metres from the camera over fade_span.
uniform float near_fade = 2.5;
uniform float fade_span = 4.5;
uniform vec3 dust_color : source_color = vec3(0.64, 0.55, 0.42);
// Self-lit share in the haze colour, so dust in a shadow still reads as haze.
uniform vec3 glow_color : source_color = vec3(0.0);
uniform float glow = 0.0;
uniform sampler2D cover : filter_nearest, repeat_disable;
uniform float cover_cell = 0.75;
uniform sampler2D noise : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
varying float visibility;
varying float opacity;
varying vec2 cloud_seed;

#include "res://world/weather_shelter.gdshaderinc"

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;
	vec4 custom = INSTANCE_CUSTOM;
	float phase = custom.r * 6.2831853;
	vec2 wander = vec2(sin(simulation_time * 0.9 + phase), cos(simulation_time * 0.7 + phase * 1.3)) * (puff ? 0.8 : 0.3);
	vec3 point;
	point.xz = mod(seed.xz + drift.xz + wander - camera_center.xz + vec2(radius), vec2(radius * 2.0)) - vec2(radius) + camera_center.xz;
	float ground = surface_height(cover, point.xz, cover_cell);
	float speed = length(flow.xz);
	float lift;
	if (puff) {
		lift = mix(lift_min, band_height, custom.g);
	} else {
		// Most grit skims the ground; a little bounces higher.
		lift = mix(0.04, band_height, custom.g * custom.g * custom.g) + abs(sin(simulation_time * mix(2.5, 6.0, custom.b) + phase)) * 0.25;
	}
	point.y = ground + lift;
	float distance_to_camera = length(point - camera_center);
	visibility = (1.0 - smoothstep(radius * 0.7, radius, length(point.xz - camera_center.xz)));
	visibility *= puff ? smoothstep(near_fade, near_fade + fade_span, distance_to_camera) : smoothstep(0.4, 1.2, distance_to_camera);
	// Unknown cover cells (still filling, or far out) and sheltered points show nothing.
	if (ground > 50000.0 || under_roof(point)) visibility = 0.0;
	vec3 offset;
	if (puff) {
		float size = mix(size_min, size_max, custom.b);
		vec2 wind_view = (VIEW_MATRIX * vec4(flow, 0.0)).xy;
		float angle;
		if (stretch > 1.0 && length(wind_view) > 0.01) {
			angle = atan(wind_view.y, wind_view.x) + (custom.a - 0.5) * 0.35;
		} else {
			angle = custom.a * 6.2831853 + simulation_time * (custom.a - 0.5) * 0.3;
		}
		vec2 corner = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * (VERTEX.xy * vec2(size * stretch, size));
		offset = INV_VIEW_MATRIX[0].xyz * corner.x + INV_VIEW_MATRIX[1].xyz * corner.y;
		// Thick and thin patches are fixed to the moving air, so they sweep past.
		float air = textureLod(noise, (point.xz - drift.xz) / 70.0 + vec2(simulation_time * 0.004), 0.0).r;
		float gather = mix(1.0 - clump, 1.0, smoothstep(0.38, 0.62, air));
		opacity = min(mix(opacity_min, opacity_max, custom.a) * density * opacity_scale * gather, 1.0);
	} else {
		vec3 along = speed > 0.01 ? vec3(flow.x, 0.0, flow.z) / speed : vec3(1.0, 0.0, 0.0);
		vec3 view = point - INV_VIEW_MATRIX[3].xyz;
		vec3 side = cross(along, view);
		side = length(side) > 0.001 ? normalize(side) : vec3(0.0, 1.0, 0.0);
		float streak_length = mix(0.04, 0.5, clamp(speed / 20.0, 0.0, 1.0)) * mix(0.5, 1.0, custom.b);
		offset = side * VERTEX.x * mix(0.008, 0.02, custom.a) + along * VERTEX.y * streak_length;
		opacity = mix(0.25, 0.6, custom.a) * density;
	}
	cloud_seed = custom.rg;
	VERTEX = (VIEW_MATRIX * vec4(point + offset, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
	if (visibility < 0.001) VERTEX = vec3(0.0, 0.0, -0.01);
}

void fragment() {
	float shape;
	if (puff) {
		vec2 p = UV * 2.0 - 1.0;
		float broad = texture(noise, vec2(UV.x * stretch, UV.y) * 0.6 + cloud_seed + vec2(simulation_time * 0.02, 0.0)).r;
		float detail = texture(noise, vec2(UV.x * stretch, UV.y) * 1.7 - cloud_seed * 2.0).r;
		float reach = length(p);
		// The noise can push the soft edge past the quad; the last term keeps the rim at zero.
		shape = (1.0 - smoothstep(0.3, 1.0, reach + (broad - 0.5) * 0.6)) * mix(0.5, 1.0, detail) * (1.0 - smoothstep(0.75, 1.0, reach));
		// Fade where the cloud meets the ground or a wall instead of a hard edge.
		float scene_depth = texture(depth_texture, SCREEN_UV).r;
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		ndc.z = scene_depth * 2.0 - 1.0;
#endif
		vec4 scene_position = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		shape *= clamp((-scene_position.z / scene_position.w + VERTEX.z) / 1.5, 0.0, 1.0);
	} else {
		float taper = pow(max(sin(UV.y * 3.14159265), 0.0), 0.7);
		float aa = max(fwidth(UV.x), 0.02);
		shape = (1.0 - smoothstep(0.12 * taper - aa, 0.36 * taper + aa, abs(UV.x - 0.5))) * taper;
	}
	ALBEDO = dust_color;
	ROUGHNESS = 1.0;
	BACKLIGHT = dust_color * 0.5;
	EMISSION = glow_color * glow;
	ALPHA = shape * opacity * visibility;
}
