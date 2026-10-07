shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// A soft, rolling cloud rather than a collection of visible sphere meshes.
uniform sampler2D turbulence : repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float age = 0.0;
uniform float heat = 1.0;
uniform vec3 smoke_color : source_color = vec3(0.19, 0.18, 0.16);
uniform float density = 1.0;
varying float cloud_seed;

void vertex() {
	cloud_seed = fract(float(INSTANCE_ID) * 0.618034);
	float angle = INSTANCE_CUSTOM.x;
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	facing[0].xyz *= length(MODEL_MATRIX[0].xyz);
	facing[1].xyz *= length(MODEL_MATRIX[1].xyz);
	facing[2].xyz *= length(MODEL_MATRIX[2].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
	VERTEX.xy = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xy;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 drift = vec2(cloud_seed * 3.1, -age * 0.18);
	float broad = texture(turbulence, UV * 0.78 + drift).r;
	float detail = texture(turbulence, UV * 2.15 - drift * 0.57).r;
	float curls = texture(turbulence, UV * 4.6 + vec2(broad * 0.26, age * -0.1)).r;
	float radius = length(p);
	float edge = 1.0 - smoothstep(0.48, 0.96, radius + (broad - 0.5) * 0.52);
	float volume = smoothstep(0.14, 0.69, broad * 0.55 + detail * 0.45 + (1.0 - radius) * 0.32);
	float body = edge * mix(0.4, 1.0, volume);
	float burning = clamp(heat * (0.60 + broad * 0.55 + detail * 0.45) - radius * 0.20, 0.0, 1.0);
	float veins = smoothstep(0.29, 0.78, detail * 0.65 + curls * 0.35);
	vec3 fire = mix(vec3(0.62, 0.065, 0.006), vec3(1.5, 0.43, 0.025), veins);
	fire = mix(fire, vec3(2.6, 1.5, 0.39), smoothstep(0.66, 0.95, burning + veins * 0.14));
	vec3 lobe_normal = normalize(vec3(p.x, -p.y, sqrt(max(0.05, 1.0 - dot(p, p)))));
	float lobes = smoothstep(0.2, 0.8, broad * 0.65 + detail * 0.35);
	float shade = (0.35 + lobes * 1.25) * (0.55 + max(0.0, dot(lobe_normal, normalize(vec3(-0.4, 0.7, 0.6)))) * 0.65);
	vec3 soot = smoke_color * shade;
	ALBEDO = mix(soot, fire, smoothstep(0.13, 0.78, burning));
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = scene_depth * 2.0 - 1.0;
#endif
	vec4 scene_position = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float soft_intersection = clamp((-scene_position.z / scene_position.w + VERTEX.z) / 0.28, 0.0, 1.0);
	ALPHA = body * COLOR.a * density * soft_intersection;
}
