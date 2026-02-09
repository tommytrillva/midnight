## CRT/PSX post-processing overlay for the MIDNIGHT GRIND retro look.
## Applied as a CanvasLayer with a full-screen ColorRect using the
## retro_post_process shader (scanlines, dither, vignette, chromatic aberration).
extends CanvasLayer

@export var enabled: bool = true:
	set(value):
		enabled = value
		if _color_rect:
			_color_rect.visible = enabled

var _color_rect: ColorRect = null


func _ready() -> void:
	layer = 100
	_color_rect = ColorRect.new()
	_color_rect.name = "CRTRect"
	_color_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_color_rect.visible = enabled

	# Load the post-process shader material
	var shader := load("res://assets/shaders/retro_post_process.gdshader") as Shader
	if shader:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("color_depth", 32.0)
		mat.set_shader_parameter("dither_strength", 0.3)
		mat.set_shader_parameter("scanline_strength", 0.15)
		mat.set_shader_parameter("scanline_frequency", 320.0)
		mat.set_shader_parameter("vignette_strength", 0.3)
		mat.set_shader_parameter("chromatic_aberration", 1.0)
		mat.set_shader_parameter("saturation_boost", 1.3)
		mat.set_shader_parameter("bloom_threshold", 0.7)
		mat.set_shader_parameter("bloom_strength", 0.2)
		_color_rect.material = mat
	else:
		print("[CRT] WARNING: Could not load retro_post_process.gdshader")

	add_child(_color_rect)
	print("[CRT] Post-process overlay ready. Enabled: %s" % str(enabled))


func toggle() -> void:
	enabled = not enabled


func set_intensity(value: float) -> void:
	## Scale all effects by a 0-1 intensity multiplier.
	if _color_rect == null or _color_rect.material == null:
		return
	var mat := _color_rect.material as ShaderMaterial
	mat.set_shader_parameter("scanline_strength", 0.15 * value)
	mat.set_shader_parameter("dither_strength", 0.3 * value)
	mat.set_shader_parameter("vignette_strength", 0.3 * value)
	mat.set_shader_parameter("chromatic_aberration", 1.0 * value)
