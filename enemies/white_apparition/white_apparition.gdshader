shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, unshaded;
uniform float presence : hint_range(0.0, 1.0) = 1.0;
uniform float veil : hint_range(0.0, 1.0) = 0.0;
varying vec3 local_point;
void vertex() {
 local_point = VERTEX;
 float shiver = sin(VERTEX.y * 27.0 + TIME * 8.0) * sin(TIME * 3.7 + VERTEX.z * 19.0);
 VERTEX += NORMAL * (shiver * (0.002 + veil * 0.006) + veil * 0.014);
}
void fragment() {
 float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
 float soft_edge = smoothstep(0.015, 0.8, facing);
 float grain = sin(local_point.y * 92.0 + sin(local_point.x * 70.0) + TIME * 1.6) * 0.024;
 ALBEDO = vec3(0.84, 0.85, 0.83) + grain;
 ROUGHNESS = 0.94;
 EMISSION = vec3(0.12, 0.13, 0.125) * (1.0 - veil * 0.4);
 ALPHA = presence * soft_edge * mix(0.9, 0.085, veil);
}
