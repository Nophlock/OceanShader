@tool
extends Node


@export var resolution : int = 64

@export var gen_tex : bool = false:
	set(new_val):
		self.regen_texture()

@export var wind_dir : Vector2 = Vector2(0.0, 1.0)
@export var wind_speed : float = 10.0
@export var wave_height : float = 10.0
@export var damping : float = 0.1
@export var grid_size : float = 1000.0
@export var wave_sharpness : float = 6.0

@export var spectrum_image : Texture2D = null
@export var spectrum_image_conjugate : Texture2D = null



var L : float = 1.0
var LP : float = 1.0 #horizontal patch

const GRAVITY : float = 9.81
const PI_2 : float = PI * 2.0
const COEFF : float = 1.0 / sqrt(2.0)

func philips_spectrum(kv : Vector2) -> float:
	
	var k : float = kv.length()
	
	if k <= 0.00001:
		return 0.0
	
	var kL : float = k * self.L
	var kl_2 : float = kL * kL
	
	var kw_2 : float = (kv/k).dot(self.wind_dir)
	kw_2 = pow(kw_2, self.wave_sharpness)
	
	var k4 : float = k*k*k*k
	var l : float = exp(-(k*k*self.damping*self.damping))
	
	return self.wave_height * (exp(-1.0 / kl_2) / k4) * kw_2 * l 


func calculate_spectrum(k : Vector2, eps_r : float, eps_i : float) -> Vector2:

	var philipps : float = sqrt( philips_spectrum(k) )
			
	var real : float = COEFF * eps_r * philipps
	var imag : float = COEFF * eps_i * philipps

	return Vector2(real, imag)

func regen_texture() -> void:
	
	var h0_image : Image = Image.create(resolution, resolution, false, Image.FORMAT_RGF)
	var h0_conjugate_image : Image = Image.create(resolution, resolution, false, Image.FORMAT_RGF)
	
	#update our constants (for speedup before the loop)
	self.wind_dir = self.wind_dir.normalized()
	self.L = self.wind_speed * self.wind_speed / GRAVITY
	
	var N : float = self.resolution
	
	for y in range(self.resolution):
		for x in range(self.resolution):
			
			var n : float = x - self.resolution * 0.5
			var m : float = y - self.resolution * 0.5
			
			var eps_r : float = randfn(0.0, 1.0)
			var eps_i : float = randfn(0.0, 1.0)
			
			var k = Vector2(PI_2 * n / self.grid_size, PI_2 * m / self.grid_size)
			
			var h0_k : Vector2 = self.calculate_spectrum(k, eps_r, eps_i)
			var h0_k_conjugate : Vector2 = self.calculate_spectrum(-k, eps_r, eps_i)
			
			h0_k_conjugate.y *= -1.0 #the conjugation is just flipping the imaginary part
			
			h0_image.set_pixel(x,y, Color(h0_k.x,h0_k.y,0.0, 1.0))
			h0_conjugate_image.set_pixel(x,y, Color(h0_k_conjugate.x,h0_k_conjugate.y,0.0, 1.0))
	
	
	self.spectrum_image = ImageTexture.create_from_image(h0_image)
	self.spectrum_image_conjugate = ImageTexture.create_from_image(h0_conjugate_image)


func get_spectrum_texture() -> Texture2D:
	return self.spectrum_image


func get_spectrum_conjugate_texture() -> Texture2D:
	return self.spectrum_image_conjugate

