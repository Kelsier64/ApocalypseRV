shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform float opacity = 1.0;
uniform bool ground_ring = false;
uniform bool velocity_aligned = false;
uniform vec3 tint : source_color = vec3(1.0, 0.56, 0.18);

void vertex() {
	if (!ground_ring) {
		mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		facing[0].xyz *= length(MODEL_MATRIX[0].xyz);
		facing[1].xyz *= length(MODEL_MATRIX[1].xyz);
		facing[2].xyz *= length(MODEL_MATRIX[2].xyz);
		MODELVIEW_MATRIX = VIEW_MATRIX * facing;
		if (velocity_aligned) {
			vec2 direction = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xy;
			float angle = atan(-direction.x, direction.y);
			VERTEX.xy = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xy;
		}
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float mask;
	if (ground_ring) {
		float angle = atan(p.y, p.x);
		float ragged = sin(angle * 13.0 + r * 19.0) * 0.025 + sin(angle * 23.0) * 0.015;
		mask = (1.0 - smoothstep(0.025, 0.19, abs(r - 0.77 + ragged))) * 0.24;
	} else {
		mask = pow(max(0.0, 1.0 - r), 2.5);
	}
	ALBEDO = tint * 2.0;
	ALPHA = mask * opacity * COLOR.a;
}
