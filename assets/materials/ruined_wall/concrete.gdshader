shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D aggregate_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cement_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 object_position;
varying vec3 object_normal;
float hash21(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
void vertex() { object_position=VERTEX; object_normal=NORMAL; }
void fragment() {
	vec3 n=abs(normalize(object_normal));
	vec2 p=n.y>0.75?object_position.xz:vec2(n.x>n.z?object_position.z:object_position.x,object_position.y);
	vec3 aggregate=texture(aggregate_texture,p*0.65).rgb;
	float fine=texture(aggregate_texture,p*2.7).r;
	float cement=texture(cement_texture,p*0.65).r;
	float damage=COLOR.r;
	float clouds=noise(p*0.8)*0.65+noise(p*3.4)*0.35;
	vec3 skin=vec3(0.075,0.069,0.06)*(0.60+cement*0.6+fine*0.5+(clouds-0.5)*0.65);
	vec3 stones=mix(aggregate*0.8,vec3(0.09,0.087,0.081),0.35);
	vec3 color=mix(skin,stones,smoothstep(0.04,0.52,damage));
	float damp=(1.0-smoothstep(0.0,0.5+noise(p*0.9)*0.45,object_position.y));
	float runoff=0.0;
	for(int i=0;i<4;i++) {
		float x=-1.85+float(i)*0.92;
		float width=0.1+noise(vec2(p.y*2.0,float(i)))*0.11;
		runoff+=exp(-pow((p.x-x)/width,2.0))*smoothstep(0.1,0.45,p.y)*(1.0-smoothstep(1.5,2.7,p.y));
	}
	color*=1.0-damp*0.42-noise(p*vec2(2.3,0.21))*0.12;
	color=mix(color,color*vec3(0.55,0.30,0.14),clamp(runoff*0.42,0.0,0.55));
	ALBEDO=color;
	float height=mix(cement*0.0006+fine*0.0003,texture(aggregate_texture,p*0.65).r*0.0004,damage);
	vec3 dx=dFdx(VERTEX),dy=dFdy(VERTEX);
	vec3 rx=cross(dy,NORMAL),ry=cross(NORMAL,dx);
	float det=dot(dx,rx);
	NORMAL=normalize(NORMAL-sign(det)*(dFdx(height)*rx+dFdy(height)*ry)/max(abs(det),0.000001));
	ROUGHNESS=0.97;
	SPECULAR=0.06;
}
