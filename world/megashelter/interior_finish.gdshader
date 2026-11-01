shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(0.5,0.5,0.45,1.0);
uniform float finish_kind = 0.0;
varying vec3 p;
float hash31(vec3 q) {
	q = fract(q * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}
float noise3(vec3 q) {
	vec3 a = floor(q);
	vec3 f = fract(q);
	f = f*f*(3.0-2.0*f);
	return mix(mix(mix(hash31(a),hash31(a+vec3(1,0,0)),f.x),mix(hash31(a+vec3(0,1,0)),hash31(a+vec3(1,1,0)),f.x),f.y),mix(mix(hash31(a+vec3(0,0,1)),hash31(a+vec3(1,0,1)),f.x),mix(hash31(a+vec3(0,1,1)),hash31(a+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { p = VERTEX; }
void fragment() {
	float footprint = max(length(dFdx(p)),length(dFdy(p)));
	float grain = mix(noise3(p*55.0),0.5,smoothstep(0.008,0.04,footprint));
	float dirt = noise3(p*4.2+13.7);
	vec3 color = base_color.rgb * (0.84+dirt*0.2);
	float roughness = 0.87;
	if (finish_kind < 0.5) {
		// Aged ceramic: broad mineral deposits, glazed faces and tiny pits.
		float deposit = smoothstep(0.56,0.75,dirt);
		color = mix(color,vec3(0.2,0.22,0.17),deposit*0.46);
		roughness = mix(0.36,0.82,deposit);
	} else if (finish_kind > 1.5 && finish_kind < 2.5) {
		float grain_line = noise3(p*vec3(19.0,2.0,0.55));
		color *= 0.77+grain_line*0.36;
		roughness = 0.94;
	} else if (finish_kind > 2.5) {
		color *= 0.91+grain*0.09;
		roughness = 1.0;
	}
	ALBEDO = color * COLOR.rgb;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
