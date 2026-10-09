shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D base_color : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_map : filter_linear_mipmap, repeat_enable;

void fragment() {
    vec3 color = texture(base_color, UV).rgb;
    vec3 orm = texture(orm_map, UV).rgb;
    // The generated atlas has only a few small amber lenses with this color.
    vec3 atlas_color = pow(max(color, vec3(0.0)), vec3(1.0 / 2.2));
    float lens = smoothstep(0.43, 0.49, atlas_color.r)
        * smoothstep(1.30, 1.42, atlas_color.r / max(atlas_color.g, 0.001))
        * smoothstep(1.48, 1.64, atlas_color.g / max(atlas_color.b, 0.001));
    float pulse = smoothstep(0.72, 0.86, sin(TIME * 1.7 + UV.x * 21.0 + UV.y * 17.0));
    ALBEDO = color * mix(1.0, mix(0.28, 1.0, pulse), lens);
    NORMAL_MAP = texture(normal_map, UV).rgb;
    ROUGHNESS = max(0.82, orm.g);
    METALLIC = orm.b * 0.3;
    AO = orm.r;
    EMISSION = vec3(1.0, 0.28, 0.025) * lens * pulse * 0.75;
}
