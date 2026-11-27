shader_type fog;

// Large dust billows rolling along the ground with the wind, inside a box that
// follows the camera. The noise is fixed to the moving air (world position
// minus the integrated wind travel), so thick walls of dust sweep past and
// swallow the view, then thin out. Forward+ volumetric fog only; the haze and
// the particle sheets carry the storm everywhere else. RV cabins cancel it with
// their CabinAir volumes; ground under any roof surface gets none.
#include "res://world/weather_shelter.gdshaderinc"

uniform sampler3D noise3d : repeat_enable, filter_linear;
uniform sampler2D cover : filter_nearest, repeat_disable;
uniform float cover_cell = 3.0;
uniform vec3 camera_center;
uniform vec3 drift;
uniform float simulation_time = 0.0;
uniform float radius = 30.0;
// Peak extinction per metre inside a billow.
uniform float density = 0.0;
// Fraction of the air that is billow rather than gap, 0 to 1.
uniform float coverage = 0.45;
// Metres across one noise tile; larger means bigger billows and gaps.
uniform float scale = 16.0;
// Density halves roughly every this many metres above the ground.
uniform float height = 3.0;
uniform vec3 albedo : source_color = vec3(0.56, 0.47, 0.35);

void fog() {
	vec3 p = WORLD_POSITION;
	float ground = surface_height(cover, p.xz, cover_cell);
	float above = p.y - ground;
	// Unknown cells and points below a roof or canopy surface stay clear.
	if (ground > 50000.0 || above < -0.3) {
		DENSITY = 0.0;
	} else {
		vec3 q = vec3(p.x - drift.x, max(above, 0.0) * 1.6 + simulation_time * 0.35, p.z - drift.z) / scale;
		float body = texture(noise3d, q).r * 0.7 + texture(noise3d, q * 2.3 + vec3(0.37, 0.11, 0.73)).r * 0.3;
		float threshold = 1.0 - coverage;
		float billow = smoothstep(threshold - 0.08, threshold + 0.18, body);
		float falloff = exp(-max(above, 0.0) * 0.693 / max(height, 0.1));
		float edge = 1.0 - smoothstep(radius * 0.7, radius, length(p.xz - camera_center.xz));
		DENSITY = density * billow * falloff * edge;
	}
	ALBEDO = albedo;
}
