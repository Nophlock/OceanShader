shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D heightmap_texture : repeat_enable;
uniform sampler2D slope_texture : repeat_enable;
uniform sampler2D displacement_texture : repeat_enable;

uniform float water_height = 0.1f;
uniform float tiling = 1.0f;
uniform float displacement_factor = 0.0f;
uniform float shininess = 0.2f;
uniform float water_depth_factor = 0.005f;
uniform float wave_foam_factor = 1.0f;

uniform vec4 water_color : source_color = vec4(0.1, 0.3, 0.5, 1.0);

varying vec3 local_vertex;
varying vec3 local_normal;

varying float water_depth;
varying float vertex_jacobian;

float calculate_jacobian(vec2 uv, float factor) 
{
    float offset = 1.0;
	
	vec3 right = (vec3(offset, texture(displacement_texture, uv + vec2(offset, 0.0)).y, 0.0)) * displacement_factor;
	vec3 left = (vec3(-offset, texture(displacement_texture,uv + vec2(-offset, 0.0)).y, 0.0)) * displacement_factor;
	vec3 bottom = (vec3(0.0, texture(displacement_texture,uv + vec2(0.0, offset)).y, offset)) * displacement_factor;
	vec3 top = (vec3(0.0, texture(displacement_texture,uv + vec2(0.0, -offset)).y, -offset))  * displacement_factor;

	float jxx = 1.0 + factor * right.x / offset;
	float jxy = 1.0 + factor * right.y / offset;
	float jyx = factor * bottom.x / offset;
	float jyy = factor * bottom.y / offset;
	
	return jxx * jyy - jxy * jyx;
}

float fresnel(float amount, vec3 normal, vec3 view)
{
	return pow( clamp(dot(normal, view), 0.0, 1.0) , amount);
}

void vertex()
{
	vec2 uv = UV;
	
	vec2 current_slope = texture(slope_texture, uv * tiling).rg;
	vec4 desired_height = texture(heightmap_texture, uv * tiling);
	vec2 displacement = texture(displacement_texture, uv * tiling).rg;
	
	displacement.x = clamp(displacement.x, 0.00001, 1.0);
	displacement.y = clamp(displacement.y, 0.00001, 1.0);
	
	VERTEX.xz += displacement * displacement_factor;
	VERTEX.y = desired_height.r * water_height;
	
	local_vertex = VERTEX;
	vertex_jacobian = calculate_jacobian(UV, wave_foam_factor);
	vertex_jacobian = clamp(vertex_jacobian, 0.0f, 1.0f);
	vertex_jacobian = pow(vertex_jacobian, 4.0);

	NORMAL.xy = vec2(-current_slope.x, current_slope.y) ;
	NORMAL.z = 1.0f;
	
	NORMAL = normalize(NORMAL);
	local_normal = NORMAL;
	water_depth = desired_height.r;
}

void fragment() 
{	
	float fresnel = fresnel(4.0, NORMAL, VIEW);
	float theta = clamp(dot(local_normal, vec3(0.0,1.0,0.0)), 0.0, 1.0);
	
	theta = pow(theta, 3.0);
	
	ALBEDO = water_color.rgb + shininess*fresnel + theta;
	ALBEDO -= (1.0 - water_depth)*(1.0 - fresnel)*water_depth_factor;
	
	ALBEDO += vec3(vertex_jacobian);
}