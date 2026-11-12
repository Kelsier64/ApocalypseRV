shader_type canvas_item;
render_mode unshaded;

#include "res://world/terrain/sdr_shadow_trim.gdshaderinc"

uniform float patch_level;
uniform float shadow_trim;

void fragment() {
	// An opaque zero-valued surround gives each patch a black reference.
	vec2 edge = abs(UV - vec2(0.5));
	float level = edge.x < 0.38 && edge.y < 0.35 ? patch_level : 0.0;
	COLOR = vec4(apply_sdr_shadow_trim(vec3(level), shadow_trim), 1.0);
}
