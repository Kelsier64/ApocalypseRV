shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(0.57, 0.58, 0.54, 1.0);
uniform float surface_kind = 0.0;
uniform float wear_seed = 0.0;
uniform sampler2D concrete_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D coating_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D aggregate_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 local_position;
varying vec3 local_normal;

float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 q = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(q), hash21(q + vec2(1,0)), f.x), mix(hash21(q + vec2(0,1)), hash21(q + vec2(1,1)), f.x), f.y);
}
void vertex() { local_position = VERTEX; local_normal = NORMAL; }
void fragment() {
	vec3 n = abs(normalize(local_normal));
	float vertical = 1.0 - smoothstep(0.6, 0.85, n.y);
	vec2 p = n.y > 0.7 ? local_position.xz : vec2(n.x > n.z ? local_position.z : local_position.x, local_position.y);
	vec2 offset = vec2(wear_seed * 0.071, wear_seed * 0.039);
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float detail = 1.0 - smoothstep(0.018, 0.10, footprint);
	// Object-space metres keep the grain consistent across every size of module.
	float cement = texture(concrete_texture, p * 0.5 + offset).r;
	float coating = texture(coating_texture, p * 0.5 + offset).r;
	float mineral = noise(p * 0.19 + offset);
	float runoff = smoothstep(0.56, 0.79, noise(p * vec2(2.2, 0.065) + offset));
	float under_ledge = 1.0 - smoothstep(0.0, 3.2, mod(local_position.y + 0.2, 13.5));
	float damp = (1.0 - smoothstep(0.0, 1.0 + mineral * 1.6, local_position.y)) * vertical;
	float shade = mix(0.88, 1.04, COLOR.r);
	vec3 color = base_color.rgb * shade * (0.93 + mineral * 0.13);
	float relief = cement * 0.0015;
	float roughness = 0.94;
	float metal = 0.0;
	if (surface_kind < 0.5) {
		color *= 0.67 + cement * 1.20;
		float damage = COLOR.a;
		vec3 stones = texture(aggregate_texture, p * 0.8 + offset).rgb;
		color = mix(color, stones * vec3(0.70, 0.69, 0.64), damage * 0.85);
		relief += texture(aggregate_texture, p * 0.8 + offset).r * damage * 0.003;
		// Small, antialiased form-tie recesses belong to cast structure only.
		vec2 tie = (fract(p / vec2(1.8, 2.25) + 0.5) - 0.5) * vec2(1.8, 2.25);
		float hole = 1.0 - smoothstep(0.018, 0.029 + fwidth(length(tie)), length(tie));
		color *= 1.0 - hole * vertical * 0.32;
	} else if (surface_kind < 1.5) {
		// Sealed precast cassettes: smooth mineral coating, narrow recessed joints.
		color *= 0.80 + coating * 0.72;
		float joint_distance = abs(mod(local_position.y + 2.25, 4.5) - 2.25);
		float joint = (1.0 - smoothstep(0.012, 0.028 + fwidth(p.y), joint_distance)) * vertical;
		color *= 1.0 - joint * 0.40;
		relief = coating * 0.0008 - joint * 0.002;
		roughness = 0.76 + cement * 0.12;
	} else {
		// Paint and exposed steel respond differently to light; oxide stays matte.
		float worn = 1.0 - smoothstep(0.10, 0.20, coating);
		float rust = worn * smoothstep(0.32, 0.65, mineral);
		color *= 0.76 + coating * 1.05;
		color = mix(color, vec3(0.14, 0.065, 0.028) * (0.7 + cement), rust * 0.85);
		relief = coating * 0.0009 + rust * 0.001;
		roughness = mix(0.63, 0.97, rust);
		metal = mix(0.30, 0.0, rust);
	}
	// Concentrate age below ledges and at the foot, rather than dirtying every face.
	color *= 1.0 - runoff * (0.05 + under_ledge * 0.17) * vertical;
	color = mix(color, color * vec3(0.52, 0.56, 0.48), damp * 0.48);
	ALBEDO = color;
	ROUGHNESS = clamp(roughness + damp * 0.025, 0.0, 1.0);
	METALLIC = metal;
	SPECULAR = surface_kind > 1.5 ? 0.45 : 0.25;
	// View-space surface gradients work on merged boxes, bevels and fittings.
	relief *= detail;
	vec3 dx = dFdx(VERTEX), dy = dFdy(VERTEX);
	vec3 across_x = cross(dy, NORMAL), across_y = cross(NORMAL, dx);
	float determinant = dot(dx, across_x);
	NORMAL = normalize(NORMAL - sign(determinant) * (dFdx(relief) * across_x + dFdy(relief) * across_y) / max(abs(determinant), 0.000001));
}
