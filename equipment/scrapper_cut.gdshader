shader_type spatial;
render_mode cull_disabled;
uniform mat4 world_to_feed;
uniform float cut_height = 0.705;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, hint_default_white;
uniform float surface_roughness = 0.8;
uniform float surface_metallic = 0.0;
uniform bool piece_mode = false;
uniform mat4 world_to_piece;
uniform vec3 piece_low;
uniform vec3 piece_high;
varying vec3 piece_position;
varying vec3 feed_position;
void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	feed_position = (world_to_feed * world).xyz;
	piece_position = (world_to_piece * world).xyz;
}
void fragment() {
	if (piece_mode && (any(lessThan(piece_position, piece_low)) || any(greaterThan(piece_position, piece_high)))) discard;
	if (feed_position.y < cut_height && abs(feed_position.x) < 0.455 && abs(feed_position.z) < 0.455) discard;
	ALBEDO = tint.rgb * texture(base_texture, UV).rgb;
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
}
