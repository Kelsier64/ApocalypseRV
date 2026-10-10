shader_type spatial;
render_mode cull_disabled;

// Vertices are the original surface, tessellated in the machine's local frame.
// Only material close to the cutters yields; the upper body shares one pose.
uniform mat4 body_pose;
uniform float grip = 0.0;
uniform float tooth_phase = 0.0;
uniform float flexibility = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, hint_default_white;
uniform vec3 uv_scale = vec3(1.0);
uniform vec3 uv_offset = vec3(0.0);
uniform float surface_roughness = 0.8;
uniform float surface_metallic = 0.0;
uniform sampler2D normal_texture : hint_normal;
uniform bool has_normal_texture = false;
uniform float normal_strength = 1.0;
varying vec3 feed_position;

vec3 deform(vec3 rest) {
	vec3 p = (body_pose * vec4(rest, 1.0)).xyz;
	float pinch = grip * (1.0 - smoothstep(0.76, 1.08, p.y));
	float fold = grip * (1.0 - smoothstep(0.84, 1.08, p.y));
	// Opposing shafts pull across X; Z runs along the cutter stack.
	p.x = mix(p.x, clamp(p.x, -0.105, 0.105), pinch);
	p.z = mix(p.z, clamp(p.z, -0.36, 0.36), fold);
	float crease = pinch * (1.0 - pinch) * (1.0 - flexibility * 0.65);
	p.x += sin(p.y * 67.0 + p.z * 19.0) * crease * 0.095;
	p.z += sin(p.y * 53.0 - p.x * 27.0) * crease * 0.06;
	// Entire deformed surface clears the rim before entering the housing.
	float throat = grip * (1.0 - smoothstep(0.84, 1.0, p.y));
	p.x = mix(p.x, clamp(p.x, -0.395, 0.395), throat);
	p.z = mix(p.z, clamp(p.z, -0.395, 0.395), throat);
	// Short strips twist only between the teeth, never above the hopper.
	float tear = grip * (1.0 - smoothstep(0.71, 0.82, p.y));
	p.x += sin(p.z * 71.0 + tooth_phase) * tear * 0.018;
	return p;
}

void vertex() {
	vec3 rest = VERTEX;
	vec3 n = normalize(NORMAL);
	vec3 t = normalize(cross(n, abs(n.y) < 0.9 ? vec3(0,1,0) : vec3(1,0,0)));
	vec3 b = cross(n, t);
	vec3 p = deform(rest);
	vec3 dt = deform(rest + t * 0.002) - deform(rest - t * 0.002);
	vec3 db = deform(rest + b * 0.002) - deform(rest - b * 0.002);
	NORMAL = normalize(cross(dt, db));
	if (has_normal_texture) {
		vec3 old_tangent = TANGENT;
		vec3 old_binormal = BINORMAL;
		TANGENT = normalize(deform(rest + old_tangent * 0.002) - deform(rest - old_tangent * 0.002));
		BINORMAL = normalize(deform(rest + old_binormal * 0.002) - deform(rest - old_binormal * 0.002));
	}
	VERTEX = p;
	feed_position = p;
}

void fragment() {
	// Irregular tooth cuts stay at the roller surface, rather than slicing in air.
	float tooth_edge = 0.705 + 0.012 * sin(feed_position.z * 71.0 + tooth_phase);
	if (feed_position.y < tooth_edge) discard;
	ALBEDO = tint.rgb * texture(base_texture, UV * uv_scale.xy + uv_offset.xy).rgb;
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
	if (has_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV * uv_scale.xy + uv_offset.xy).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}
