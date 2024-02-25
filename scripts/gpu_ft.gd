@tool
extends Node


@export_category("Godot Setup")
@export_file("*.glsl") var shader_file = "res://shaders/fft_water.glsl"
@export var spectrum_node : Node = null
@export var water_node : MeshInstance3D = null

@export_category("Running")

@export var time_factor : float = 1.0

@export var init_gpu_and_run : bool = false:
	set(_new_val):
		self.run_compute_step(true)

@export var run_step : bool = false:
	set(_new_val):
		self.run_compute_step(false)
		
@export var run_continues : bool = false:
	set(_new_val):
		run_continues = _new_val
		self.set_process(_new_val)

@export_category("Output")
@export var output_image : Texture2D = null
@export var slope_image : Texture2D = null
@export var displacement_image : Texture2D = null

var rd : RenderingDevice = null
var shader_rid : RID = RID()
var uniform_set : RID = RID()
var pipeline : RID = RID()

var texture_spectrum_rid : RID = RID()
var texture_spectrum_conjugate_rid : RID = RID()
var texture_fft_wave_rid : RID = RID()
var texture_fft_slope_rid : RID = RID()
var texture_fft_displacement_rid : RID = RID()


var parameter_buffer : RID = RID()
var parameter_array : PackedFloat32Array = PackedFloat32Array([])

var last_output_raw_image : Image = Image.new()
var last_output_image : ImageTexture = null

var last_output_slope_raw_image : Image = Image.new()
var last_output_slope_image : ImageTexture = null

var last_output_displacement_raw_image : Image = Image.new()
var last_output_displacement_image : ImageTexture = null

var time : float = 0.0
var L : float = 0.0


func _ready():
	self.set_process(false)


func _process(delta):
	
	if self.run_continues:
		self.time += delta * time_factor
		self.run_compute()

#load the compute shader
func load_shader(device: RenderingDevice, path: String) -> RID:
	var shader_file_data: RDShaderFile = load(path)
	var shader_spirv: RDShaderSPIRV = shader_file_data.get_spirv()
	return device.shader_create_from_spirv(shader_spirv)
	
	
#init the compute shader on the gpu
func init_gpu(soft_clean : bool = false) -> void:
	
	self.time = 0.0
	
	#only create the render device once (ideally)
	if soft_clean == false or rd == null:

		if rd != null:
			self.cleanup_gpu()
			
		rd = RenderingServer.create_local_rendering_device()
		shader_rid = load_shader(rd, shader_file)
	else:
		self.soft_cleanup_gpu()


	var spectrum_texture : Texture2D = self.spectrum_node.get_spectrum_texture()
	var spectrum_conjugate_texture : Texture2D = self.spectrum_node.get_spectrum_conjugate_texture()
	
	var resolution : Vector2i = Vector2i(spectrum_texture.get_size())


	self.last_output_raw_image = Image.create(resolution.x, resolution.y, false, Image.FORMAT_RF)
	self.last_output_image = ImageTexture.create_from_image(Image.create(resolution.x, resolution.y, false, Image.FORMAT_RF) )

	self.last_output_slope_raw_image = Image.create(resolution.x, resolution.y, false, Image.FORMAT_RGF)
	self.last_output_slope_image = ImageTexture.create_from_image(Image.create(resolution.x, resolution.y, false, Image.FORMAT_RGF) )
	
	self.last_output_displacement_raw_image = Image.create(resolution.x, resolution.y, false, Image.FORMAT_RGF)
	self.last_output_displacement_image = ImageTexture.create_from_image(Image.create(resolution.x, resolution.y, false, Image.FORMAT_RGF) )
	
	self.L = self.spectrum_node.L


	# Create texture
	var texture_format_input := RDTextureFormat.new()

	texture_format_input.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	texture_format_input.width = resolution.x
	texture_format_input.height = resolution.y
	
	texture_format_input.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
			RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	
	
	# Create texture
	var texture_format_output := RDTextureFormat.new()

	texture_format_output.format = RenderingDevice.DATA_FORMAT_R32_SFLOAT
	texture_format_output.width = resolution.x
	texture_format_output.height = resolution.y
	
	texture_format_output.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
			RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	
	# Create texture
	var texture_format_slope := RDTextureFormat.new()

	texture_format_slope.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	texture_format_slope.width = resolution.x
	texture_format_slope.height = resolution.y
	
	texture_format_slope.usage_bits = (
			RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
			RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
			RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	
	#

	texture_spectrum_rid = rd.texture_create(texture_format_input, RDTextureView.new(), [spectrum_texture.get_image().get_data()])
	var texture_uniform_0 : RDUniform = RDUniform.new()
	texture_uniform_0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texture_uniform_0.binding = 0  
	texture_uniform_0.add_id(texture_spectrum_rid)
	
	texture_spectrum_conjugate_rid = rd.texture_create(texture_format_input, RDTextureView.new(), [spectrum_conjugate_texture.get_image().get_data()])
	var texture_uniform_1 : RDUniform = RDUniform.new()
	texture_uniform_1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texture_uniform_1.binding = 1  
	texture_uniform_1.add_id(texture_spectrum_conjugate_rid)
	
	texture_fft_wave_rid = rd.texture_create(texture_format_output, RDTextureView.new())
	var texture_uniform_2 : RDUniform = RDUniform.new()
	texture_uniform_2.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texture_uniform_2.binding = 2 
	texture_uniform_2.add_id(texture_fft_wave_rid)
	
	texture_fft_slope_rid = rd.texture_create(texture_format_slope, RDTextureView.new())
	var texture_uniform_3 : RDUniform = RDUniform.new()
	texture_uniform_3.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texture_uniform_3.binding = 3 
	texture_uniform_3.add_id(texture_fft_slope_rid)
	
	texture_fft_displacement_rid = rd.texture_create(texture_format_slope, RDTextureView.new())
	var texture_uniform_4 : RDUniform = RDUniform.new()
	texture_uniform_4.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	texture_uniform_4.binding = 4 
	texture_uniform_4.add_id(texture_fft_displacement_rid)


	parameter_array = PackedFloat32Array([self.time, self.L])
	var parameter_byte_array : PackedByteArray = parameter_array.to_byte_array()
	
	parameter_buffer = rd.storage_buffer_create(parameter_byte_array.size(), parameter_byte_array)
	var parameter_uniform := RDUniform.new()
	parameter_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	parameter_uniform.binding = 5 
	parameter_uniform.add_id(parameter_buffer)
	

	uniform_set = rd.uniform_set_create([texture_uniform_0, texture_uniform_1, texture_uniform_2,texture_uniform_3,texture_uniform_4, parameter_uniform], shader_rid, 0)
	pipeline = rd.compute_pipeline_create(shader_rid)


#cleanup everything of the compute shader
func cleanup_gpu() -> void:
	
	if rd == null:
		return

	self.soft_cleanup_gpu()
	
	if shader_rid.is_valid():
		rd.free_rid(shader_rid)
		shader_rid = RID()

	rd.free()
	rd = null
	

#cleanup all parameters of the compute shader but not the shader and the device manager
func soft_cleanup_gpu() -> void:
	
	if self.rd == null:
		return 
	
	if pipeline.is_valid():
		rd.free_rid(pipeline)
		pipeline = RID()

	if uniform_set.is_valid():
		rd.free_rid(uniform_set)
		uniform_set = RID()

	if texture_spectrum_rid.is_valid():
		rd.free_rid(texture_spectrum_rid)
		texture_spectrum_rid = RID()
		
	if texture_spectrum_conjugate_rid.is_valid():
		rd.free_rid(texture_spectrum_conjugate_rid)
		texture_spectrum_conjugate_rid = RID()
		
	if texture_fft_slope_rid.is_valid():
		rd.free_rid(texture_fft_slope_rid)
		texture_fft_slope_rid = RID()	
		
	if texture_fft_wave_rid.is_valid():
		rd.free_rid(texture_fft_wave_rid)
		texture_fft_wave_rid = RID()
		
	if texture_fft_displacement_rid.is_valid():
		rd.free_rid(texture_fft_displacement_rid)
		texture_fft_displacement_rid = RID()
		
	if parameter_buffer.is_valid():
		rd.free_rid(parameter_buffer)
		parameter_buffer = RID()
	
	
func run_compute_step(force_init : bool = true):
	
	if rd == null or force_init:
		print("Regen GPU compute shader")
		self.init_gpu()
	
	print("running compute now: ", self.time, " - ", self.L)
		
	self.run_compute()
	
	self.output_image = self.last_output_image
	self.slope_image = self.last_output_slope_image
	self.displacement_image = self.last_output_displacement_image
	
	
#generate the actual texture by running the prepared compute shader
func run_compute() -> void:
	
	if shader_file == null:
		return 
		
	if spectrum_node == null:
		return 
	
	if rd == null:
		print("Regen GPU compute shader")
		self.init_gpu()
	
	
	var spectrum_texture : Texture2D = self.spectrum_node.get_spectrum_texture()
	var spectrum_resolution : Vector2i = Vector2i(spectrum_texture.get_size())
	
	parameter_array[0] = self.time
	
	var parameter_array_byte : PackedByteArray = parameter_array.to_byte_array()
	rd.buffer_update(parameter_buffer, 0, parameter_array_byte.size(), parameter_array_byte)
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)

	@warning_ignore("integer_division")
	rd.compute_list_dispatch(compute_list, spectrum_resolution.x / 8, spectrum_resolution.y / 8 , 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

	var output_bytes_height : PackedByteArray = rd.texture_get_data(texture_fft_wave_rid, 0)
	var output_bytes_slope : PackedByteArray = rd.texture_get_data(texture_fft_slope_rid, 0)
	var output_bytes_displacement : PackedByteArray = rd.texture_get_data(texture_fft_displacement_rid, 0)
	
	self.last_output_raw_image.set_data(spectrum_resolution.x, spectrum_resolution.y, false, Image.FORMAT_RF, output_bytes_height)
	self.last_output_image.update(self.last_output_raw_image)
	
	self.last_output_slope_raw_image.set_data(spectrum_resolution.x, spectrum_resolution.y, false, Image.FORMAT_RGF, output_bytes_slope)
	self.last_output_slope_image.update(self.last_output_slope_raw_image)
	
	self.last_output_displacement_raw_image.set_data(spectrum_resolution.x, spectrum_resolution.y, false, Image.FORMAT_RGF, output_bytes_displacement)
	self.last_output_displacement_image.update(self.last_output_displacement_raw_image)
	
	if self.water_node != null:
		self.water_node.material_override.set_shader_parameter("heightmap_texture", self.last_output_image)
		self.water_node.material_override.set_shader_parameter("slope_texture", self.last_output_slope_image)
		self.water_node.material_override.set_shader_parameter("displacement_texture", self.last_output_displacement_image)


#scene notification that this node gets deleted and therefore we need to cleanup the compute shader to prevent leaking
func _notification(what):
	# Object destructor, triggered before the engine deletes this Node.
	if what == NOTIFICATION_PREDELETE:
		cleanup_gpu()
