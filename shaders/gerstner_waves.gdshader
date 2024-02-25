shader_type spatial;

uniform vec2 p_wind_dir = vec2(1.0f,0.0f);
uniform float p_wave_length = 1.0f;
uniform float p_wave_height = 1.0f;
uniform float p_wave_phase = 0.0f;
uniform float time_scale = 0.5f;
uniform float noise_intensity = 0.1f;
uniform float wave_numbers = 20.0f;
uniform float frequency = 1.0f;
uniform float depth = 1.0f;

varying vec3 local_vertex;

const float PI_2 = 2.0 * PI;
const float G = 9.81;

float rand(vec2 co)
{
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

float get_dispersion(vec2 k)
{
	float k_len = length(k);
	float val = k_len * G * tanh(k_len * depth);
	
	return val*val;
}

vec3 gerstner_wave(vec3 vertex_pos, vec2 k, float wave_height, float wave_len, float phase)
{
	float k_len = PI_2 / wave_len;
	float w_0 = PI_2 / frequency;
	
	float w_2 = get_dispersion(k);
	float w_k = float(int(w_2 / w_0)) * w_0;
	float w_t = w_k * TIME * time_scale;
	
	vec3 final_vector = vertex_pos;
	
	final_vector.x = (k.x/k_len) * wave_height * sin( (k.x*vertex_pos.x - w_t + phase) );
	final_vector.z = (k.y/k_len) * wave_height * sin( (k.y*vertex_pos.z - w_t + phase) );
	
	
	float kix0 = dot(vec2(vertex_pos.x,vertex_pos.z), k);
	
	final_vector.y = wave_height * cos(kix0 - w_t + phase);
	
	return final_vector;
}


void vertex()
{
	
	vec3 offset = vec3(0.0f);
	
	for(float i = 0.0f; i < wave_numbers; i+=1.0f)
	{
		float percentage = (i / wave_numbers);
		vec2 noise = vec2( rand(UV), rand(UV) ) * noise_intensity;
		
		vec2 wind_percentage = (p_wind_dir + noise) * percentage * 2.0f - 1.0f;//p_wind_dir * (i / WAVE_AMOUNT) * 2.0f - 1.0f;
		float height_percentage = p_wave_height * percentage + noise.y;
		float phase_percentage = p_wave_phase * percentage + noise.y;
		float wave_percentage = p_wave_length * percentage + noise.y;
		
		wind_percentage = normalize(wind_percentage);
		
		offset += gerstner_wave(VERTEX, wind_percentage, height_percentage, wave_percentage, phase_percentage);
	}
	
	VERTEX.xz = VERTEX.xz - offset.xz;
	VERTEX.y = offset.y;
	
	local_vertex = VERTEX;
}


void fragment() 
{
	ALBEDO = normalize(abs(local_vertex.xyz));
}
