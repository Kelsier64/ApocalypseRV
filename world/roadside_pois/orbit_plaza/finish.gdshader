shader_type spatial;
render_mode cull_back;
uniform vec4 pigment : source_color;
uniform float glaze = 0.0;
uniform bool tile = false;
varying vec3 world_point;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1,311.7))) * 4375.5453);
}
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 t = smoothstep(vec2(0.0), vec2(1.0), fract(p));
	return mix(mix(hash21(i),hash21(i+vec2(1,0)),t.x),
		mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),t.x), t.y);
}
void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec3 p = world_point;
	vec2 horizontal = p.xz;
	float stain = noise2(horizontal * 0.6 + vec2(p.y * 0.3, 0.0));
	float streak = noise2(horizontal * 4.4 + vec2(0.0,p.y * 0.6));
	vec3 paint = pigment.rgb * (0.77 + 0.28 * stain + 0.09 * streak);
	paint = mix(paint, vec3(0.125,0.091,0.058), 0.34 * smoothstep(0.55,0.86,stain*0.6+streak*0.4));
	if (tile) {
		vec2 grid = horizontal * 2.0;
		vec2 edge = min(fract(grid), 1.0-fract(grid));
		vec2 aa = max(vec2(0.006), fwidth(grid) * 0.55);
		vec2 interior = smoothstep(vec2(0.014) - aa, vec2(0.014) + aa, edge);
		float grout = min(interior.x, interior.y);
		paint *= 0.83 + 0.21 * hash21(floor(grid));
		paint = mix(paint * 0.65,paint,grout);
	}
	ALBEDO = paint;
	ROUGHNESS = 0.89 - 0.53 * glaze;
	METALLIC = 0.30 * glaze;
}
