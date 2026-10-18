shader_type spatial;
render_mode diffuse_burley;

varying vec3 local_position;
varying vec3 local_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p);
	vec2 f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
float rectangle(vec2 p,vec2 half_size,float feather) {
	vec2 d=half_size-abs(p);
	return smoothstep(0.0,feather,min(d.x,d.y));
}
void vertex() {
	local_position=VERTEX;
	local_normal=NORMAL;
}
void fragment() {
	vec3 n=abs(normalize(local_normal));
	vec2 p=n.y>0.8 ? local_position.xz : (n.z>n.x ? local_position.xy : local_position.zy);
	float mottling=noise(p*14.0);
	float fibre=noise(p*220.0);
	vec3 paper=vec3(0.34,0.235,0.125)*(0.83+mottling*0.22+fibre*0.06);
	float tape=(1.0-smoothstep(0.053,0.061,abs(local_position.x)))*(1.0-step(0.5,n.x));
	vec3 color=mix(paper,vec3(0.19,0.105,0.044)*(0.86+mottling*0.16),tape);
	float seam=(1.0-smoothstep(0.0008,0.002,abs(local_position.x)))*tape;
	color*=1.0-seam*0.15;
	// A small paper shipping label and barcode distinguish sealed stock from equipment.
	vec2 label_p=local_position.xy-vec2(-0.265,0.035);
	float label=rectangle(label_p,vec2(0.135,0.09),0.003)*step(0.95,n.z);
	vec3 label_color=vec3(0.56,0.53,0.43);
	float barcode=step(0.45,fract((label_p.x+0.11)*138.0))*rectangle(label_p-vec2(0.0,0.022),vec2(0.108,0.037),0.001);
	float rule=rectangle(label_p-vec2(-0.035,-0.043),vec2(0.073,0.003),0.001);
	label_color=mix(label_color,vec3(0.035,0.027,0.018),max(barcode,rule)*0.82);
	ALBEDO=mix(color,label_color,label);
	ROUGHNESS=mix(0.96,0.82,tape);
	SPECULAR=0.18;
}
