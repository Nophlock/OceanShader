#[compute]
#version 450


layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

//contains the 2d image we're our output will be read and stored
layout(set = 0, binding = 0, rg32f) readonly uniform image2D SPECTRUM_TEXTURE;
layout(set = 0, binding = 1, rg32f) readonly uniform image2D SPECTRUM_CONJUGATE_TEXTURE;
layout(set = 0, binding = 2, r32f) restrict uniform image2D OUTPUT_TEXTURE;
layout(set = 0, binding = 3, rg32f) restrict uniform image2D SLOPE_TEXTURE;
layout(set = 0, binding = 4, rg32f) restrict uniform image2D DISPLACEMENT_TEXTURE;
layout(set = 0, binding = 5, std430) readonly buffer parameters 
{
    float data[];
} Parameters;

const float PI = 3.14159265358979323846;
const float PI_2 = 2.0 * PI;
const float G = 9.81;


float get_L()
{
	return Parameters.data[1];
}

vec2 calculate_k(float x, float y, vec2 dim)
{
	float n = x - dim.x*0.5;
	float m = y - dim.y*0.5;

	return vec2( (PI_2 * n) / get_L(), (PI_2 * m) / get_L());
}

float dispersion(vec2 k)
{
	return sqrt( G * length(k) );
}

//for complex e^ix = cos(x) + isin(x)
vec2 complex_exp(float angle)
{
	return vec2(cos(angle), sin(angle));
}

//http://www2.clarku.edu/faculty/djoyce/complex/mult.html as an example
vec2 complex_mul(vec2 a, vec2 b)
{
	return vec2(a.x * b.x - a.y*b.y, a.x * b.y + a.y*b.x);
}


// we compute the spectrum and its conjugate spectrum which gives us an hermitian spectrum ( makes it possible to calculate the fft faster)
// our texture alone are not in hermitian since they are generated from random number making it almost impossible to match h(-k) = h(k)* which is what we desire
// therefore we do this computation to get an hermitian result 
vec2 h_tilde(vec2 idx, vec2 k)
{
	vec2 h0 		= imageLoad(SPECTRUM_TEXTURE, ivec2(idx)).rg;
	vec2 h0_conj 	= imageLoad(SPECTRUM_CONJUGATE_TEXTURE, ivec2(idx)).rg;

	float angle = dispersion(k) * Parameters.data[0]; 
	
    vec2 c_exp_1 = complex_exp(angle);
	vec2 c_exp_2 = c_exp_1; //makes use of the even and off functionalities of cos and sin (we needed to do e^-ix which basicly only flips the sin)
	c_exp_2.y *= -1.0f;
	
	return (complex_mul(h0,c_exp_1) + complex_mul(h0_conj,c_exp_2)) * 0.5f ;
}


// Brute force inverse FFT (AI suggested way / probably wrong)...


void run_ifft(in ivec2 coord, out vec2 height_result, out vec2 slope, out vec2 displacement)
{
	ivec2 dim = imageSize(SPECTRUM_TEXTURE); //doesnt matter, all have the same size
	
	vec2 xv = vec2(coord);
	
	vec2 slope_x = vec2(0.0f);
	vec2 slope_y = vec2(0.0f);
	
	vec2 displacement_x = vec2(0.0f);
	vec2 displacement_y = vec2(0.0f);
	
	
	float size = (dim.x * dim.y);
	
    for (float y = 0.0f; y < dim.y; y+=1.0f) 
	{
        for (float x = 0.0f; x < dim.x; x+=1.0f) 
		{
			vec2 k = calculate_k(x, y, dim);
			float k_len = length(k);
			
            vec2 h = h_tilde(vec2(x,y), k);
			float angle = dot(k, xv);
			
            vec2 c_exp = complex_exp(angle);
			vec2 h_cmp = complex_mul(h, c_exp);
			
			
			height_result += h_cmp;
			slope_x += complex_mul(vec2(0.0, k.x),h_cmp ) ;
			slope_y += complex_mul(vec2(0.0, k.y),h_cmp ) ;
			
			
			vec2 displacement_cmplx = vec2(0.0f,0.0f);
			
			if (k_len > 0.00001f)
			{
				displacement_cmplx = vec2( -k.x/k_len, -k.y/k_len);
			}
			
			
			displacement_x += complex_mul(vec2(0.0, displacement_cmplx.x), h_cmp ) ;
			displacement_y += complex_mul(vec2(0.0, displacement_cmplx.y), h_cmp ) ;
        }
    }

	height_result /= size;
	slope_x /= size;
	slope_y /= size;
	displacement_x /= size;
	displacement_y /= size;
	
	slope = vec2(slope_x.x, slope_y.x);
	displacement = vec2(displacement_x.x, displacement_y.x);
}


void main() 
{
    ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	
	vec2 height_cplx = vec2(0.0f);
	vec2 slope = vec2(0.0f);
	vec2 displacement = vec2(0.0f);
	
	run_ifft(coord, height_cplx, slope, displacement);
	
	vec4 height_pixel = vec4(height_cplx.x, 0.0f,0.0f, 0.0f);
	vec4 slope_pixel = vec4(slope.x, slope.y,0.0f, 0.0f);
	vec4 displacement_pixel = vec4(displacement.x, displacement.y,0.0f, 0.0f);
	
	
    imageStore(OUTPUT_TEXTURE, coord, height_pixel);
	imageStore(SLOPE_TEXTURE, coord, slope_pixel);
	imageStore(DISPLACEMENT_TEXTURE, coord, displacement_pixel);
}