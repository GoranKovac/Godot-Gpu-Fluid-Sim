extends TextureRect

@export var simulation_resolution: int = 512
@export var emitter_viewport: SubViewport = null
#@export var transparent_bg: bool = true

@export_enum("Normal","Velocity","Temperature","Smoke","Flowmap+Vel") var simulation_view: int = 0

@export_group("Solver")
@export_range(4,     400,   1)     var iterations:    int    = 24
@export_range(1,     6,     1)     var substeps:      int    = 1

@export_group("Source")
## Scales overall injection amount — multiplier on temperature and smoke injection
@export_range(0.0,   2.0,   0.01)  var injection_multiplier: float = 1.0
@export_range(20.0,  1000.0, 1.0)   var source_temp:   float  = 445.0
@export_range(0.0,   1000.0, 1.0)   var source_smoke:  float  = 62.0
@export_subgroup("Flicker")
@export var flicker_enabled: bool = false
@export var flicker_noise: Texture2D = null
@export_range(0.0,     1.0, 0.01)  var flicker_strength: float = 0.25
@export_range(0.1,     5.0, 0.1)   var flicker_speed:    float = 0.1
@export_range(0.0,     2.0, 0.01)  var flicker_morph:    float = 0.25

@export_group("Physics")
@export_range(0.05,  1.5,   0.01)  var master_speed:  float  = 0.24
@export_range(0.005, 0.12,  0.001) var time_step:     float  = 0.065
@export_range(-6.0,   6.0,   0.01)  var direction_force: float  = 0.0
@export_range(-10.0,  10.0,  0.01)  var buoyancy:      float  = 6.2
@export_range(0.90,  1.0,   0.0001)var cooling:       float  = 0.965
@export_range(0.0,   200.0, 0.1)   var smoke_from_cooling: float = 74.0

@export_range(0.0,   50.0,  0.01)  var vorticity_fire:       float  = 35.0
@export_range(0.0,   20.0,  0.01)  var vorticity_smoke: float  = 5.0
@export_range(0.0,   50.0,   0.10) var viscosity:      float = 0.0
@export_range(0.0,   100.0,  0.10) var smoke_diffusion: float = 0.0
@export_range(0.0,   100.0,  0.10) var temp_diffusion:  float = 0.0

@export_subgroup("Dissipation")
@export_range(0.90,  1.0,   0.0001)var velocity_dissipation: float = 0.9925
@export_range(0.90,  1.0,   0.0001)var smoke_dissipation:    float = 0.9925
@export_range(0.90,  1.0,   0.0001)var temp_dissipation:     float = 0.976

@export_subgroup("Wind")
@export var wind_enabled: bool = false
@export var wind_noise: Texture2D = null
## Wind direction and strength (X=horizontal, Y=vertical, negative Y=up)
@export var wind: Vector2 = Vector2.ZERO
## How fast the noise pattern scrolls across the sim
@export_range(0.0,   5.0,  0.01) var wind_speed:    float = 0.1
## How fast wind pattern evolves (0=frozen)
@export_range(0.0,   3.0,  0.01) var wind_morph:    float = 1.5

@export_subgroup("Turbulence")
@export var turbulence_enabled: bool = false
@export var turbulence_noise: Texture2D = null
@export_range(0.0,   2.0,   0.001)  var turbulence_strength: float = 0.04
@export_range(0.0,   2.0,   0.01)  var turbulence_speed:    float = 0.04
@export_range(0.0,   2.0,   0.01)  var turbulence_morph:    float = 0.25
@export_enum("Force", "Buoyancy") var turbulence_mode: int = 1

@export_group("Flowmap")
@export var flowmap_enabled: bool = false
## Flowmap slots — each texture is additively blended by its mix amount
@export var flowmap_1: Texture2D = null
@export_range(0.0, 2.0, 0.01) var flowmap_1_mix: float = 1.0
@export var flowmap_2: Texture2D = null
@export_range(0.0, 2.0, 0.01) var flowmap_2_mix: float = 0.0
@export var flowmap_3: Texture2D = null
@export_range(0.0, 2.0, 0.01) var flowmap_3_mix: float = 0.0
@export var flowmap_4: Texture2D = null
@export_range(0.0, 2.0, 0.01) var flowmap_4_mix: float = 0.0
@export_range(0.0,   20.0,  0.1)   var flowmap_force:    float = 0.0
@export_range(0.1,   10.0,  0.1)   var flowmap_scale:    float = 1.0
@export_range(0.1,   10.0,  0.1)   var flowmap_bump:     float = 1.0
@export_enum("Force", "Buoyancy") var flowmap_mode: int = 1

@export_group("Render")
## Enable when HDR2D is on in Project Settings → Rendering → Viewport
@export var hdr_mode: bool = false
@export_range(0.2,   3.0,   0.01)  var flame_height:  float  = 1.45
@export_range(0.0,   5.0,   0.01)  var smoke_glow:          float  = 1.0
## Per-heat zone brightness — dark base, mid flame, hot core
## Overall fire glow strength
@export_range(1.0, 8.0, 0.01) var fire_glow: float = 1.6
@export var intense_mode: bool = true
## Hue shift — rotates all fire colours (0=original, 0.33=green, 0.66=blue)
@export_range(-1.0, 1.0, 0.001) var hue_shift: float = 0.0
## Colour saturation — richness of fire and smoke colours (1=normal, 0=grey, 2=vivid)
@export_range(0.0,  3.0,  0.01)  var saturation: float = 1.0

@export_group("Effects")
## Snap to pixel grid — retro pixelated look (0=off, 2-32=pixel size)
@export_range(0.0,  32.0,  1.0)   var pixelize_size:  float = 0.0
## Sharpness — unsharp mask on flame and smoke (0=off)
@export_range(0.0,  3.0,   0.01)  var sharpness: float = 0.0
## Heat distortion — UV wobble driven by velocity field, strongest at high heat (0=off)
@export_range(0.0,  0.05,  0.001) var heat_distortion: float = 0.0
## Dedicated noise texture for heat distortion (use a blurry, low-frequency noise)
@export var heat_dist_noise_tex: Texture2D = null

#@onready var sim_render: TextureRect = TextureRect.new()

@export_group("Embers")
@export var embers_enabled: bool = true
## Spawn threshold — temperature required to spawn embers
@export_range(0.0,   1.0,  0.01) var ember_spawn_threshold: float = 0.5
## Maximum number of live embers at once
@export_range(1, 8192, 1) var ember_max_particles: int = 1000
## Spawn amount — percentage of max_particles to keep alive (0=none, 1=all)
@export_range(0.0,   1.0,  0.01)  var ember_spawn_amount: float = 0.7
## Min lifetime in seconds
@export_range(0.5,   5.0,  0.1)  var ember_min_lifetime: float = 0.6
## Max lifetime in seconds
@export_range(0.5,   8.0,  0.1)  var ember_max_lifetime: float = 1.2
## How strongly embers follow fluid velocity
@export_range(0.0,  50.0,  0.01) var ember_vel_follow: float = 10.0
## Sideways spread strength
@export_range(0.0,  0.8,  0.01) var ember_spread_x: float = 0.35
## Gravity — negative = up
@export_range(-1200.0, 1200.0, 1.0) var ember_gravity: float = -900.0
## Drag
@export_range(0.0,   10.0,  0.01) var ember_drag: float = 4.0
## Ember size in pixels
@export_range(0.5,  10.0,  0.1)  var ember_size: float = 1.1
## Optional texture for ember shape
@export var ember_texture: Texture2D = null
## How long ember stays at hot color (0=instant cool, 1=never cools)
@export_range(0.0, 0.8, 0.01) var ember_hot_duration: float = 0.25
# Ember colors derived automatically from fire ramp math
## Ember flicker intensity (0=no flicker, 1=full strobe)
@export_range(0.0, 1.0, 0.01) var ember_flicker: float = 0.0
## Ember brightness strength multiplier
@export_range(0.5, 50.0, 0.05) var ember_strength: float = 24.0
## Ember color heat value — use Heat Ramp view to pick (0.70=yellow default, lower=more orange/red)
@export_range(0.0, 1.0, 0.01) var ember_heat_value: float = 0.37
## Ember stretch — elongates ember along its velocity direction (1=circle)
@export_range(1.0, 8.0, 0.1) var ember_trail_stretch: float = 4.0

@onready var solver: FluidSolverGPU_r12 = FluidSolverGPU_r12.new(simulation_resolution)

var sim_time: float = 0.0
var _turb_scroll_x: float = 0.0
var _turb_scroll_y: float = 0.0
var _turb_seed:     float = 0.0
var _wind_scroll_x: float = 0.0
var _wind_scroll_y: float = 0.0
var _wind_seed:     float = 0.0
var _flicker_scroll: float = 0.0
var _flicker_seed:   float = 0.0

var _rd: RenderingDevice

# ── Ember system ─────────────────────────────────────────────────────────────
const EMBER_MAX := 8192
var _e_buf_pos:      RID
var _e_buf_vel:      RID
var _e_buf_age:      RID
var _e_buf_lifetime: RID
var _e_buf_spread:   RID
var _e_buf_counter:  RID
var _e_out_tex:      RID
var _e_out_wrap:     Texture2DRD
var _e_sh_update: RID; var _e_pl_update: RID
var _e_sh_spawn:  RID; var _e_pl_spawn:  RID
var _e_sh_render: RID; var _e_pl_render: RID
var _e_time: float = 0.0
var _e_ember_tex_rid: RID
# Texture2DRD wrappers so solver RIDs can be bound to ShaderMaterial
var _tex_temp:  Texture2DRD
var _tex_smoke: Texture2DRD
var _tex_vel:   Texture2DRD
var _tex_flow:  Texture2DRD
var _mat: ShaderMaterial

func _ready() -> void:
	_rd = RenderingServer.get_rendering_device()
	# Create Texture2DRD wrappers for solver textures
	_tex_temp  = Texture2DRD.new()
	_tex_smoke = Texture2DRD.new()
	_tex_vel   = Texture2DRD.new()
	_tex_flow  = Texture2DRD.new()
	# Setup ShaderMaterial on this TextureRect
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://Shaders/fluid_r15_render.gdshader")
	material = _mat
	# TextureRect needs a texture assigned to actually emit draw calls
	var placeholder := PlaceholderTexture2D.new()
	placeholder.size = Vector2(simulation_resolution, simulation_resolution)
	texture = placeholder
	set_anchors_preset(Control.PRESET_FULL_RECT)
	expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE




	_ember_setup()

func _process(delta: float) -> void:
	var effective_dt: float = time_step * master_speed
	for _s in range(substeps):
		var sub_dt: float = effective_dt / float(substeps)
		sim_time       += sub_dt
		_turb_scroll_x += turbulence_speed * sub_dt
		_turb_scroll_y += turbulence_speed * sub_dt * 0.7
		_turb_seed     += turbulence_morph * sub_dt
		_wind_scroll_x  += wind_speed * sub_dt
		_wind_scroll_y  += wind_speed * sub_dt * 0.7
		if flicker_enabled:
			_flicker_scroll += flicker_speed * sub_dt
			_flicker_seed   += flicker_morph * sub_dt
		_wind_seed     += wind_morph * sub_dt
		_update_sim(sub_dt)

	_render_gpu(delta)


func _update_sim(dt: float) -> void:
	_emit_bitmap(dt)

	if turbulence_enabled and turbulence_strength > 0.0 and turbulence_noise != null:
		var tex_rid: RID = turbulence_noise.get_rid()
		if tex_rid.is_valid():
			var noise_rd: RID = RenderingServer.texture_get_rd_texture(tex_rid, false)
			if not noise_rd.is_valid():
				noise_rd = RenderingServer.texture_get_rd_texture(tex_rid, true)
			if noise_rd.is_valid():
				solver.gpu_inject_turbulence(noise_rd, turbulence_strength / float(substeps),
					_turb_scroll_x, _turb_scroll_y, _turb_seed,
					turbulence_mode, buoyancy, dt)

	if wind_enabled and wind_noise != null and wind != Vector2.ZERO:
		var tex_rid: RID = wind_noise.get_rid()
		if tex_rid.is_valid():
			var noise_rd: RID = RenderingServer.texture_get_rd_texture(tex_rid, false)
			if not noise_rd.is_valid():
				noise_rd = RenderingServer.texture_get_rd_texture(tex_rid, true)
			if noise_rd.is_valid():
				solver.gpu_inject_wind(noise_rd, wind.x, wind.y,
					_wind_scroll_x, _wind_scroll_y, _wind_seed, dt)

	if flowmap_enabled and (flowmap_mode == 1 or flowmap_force > 0.0):
		var r1 := _flowmap_rid(flowmap_1)
		var r2 := _flowmap_rid(flowmap_2)
		var r3 := _flowmap_rid(flowmap_3)
		var r4 := _flowmap_rid(flowmap_4)
		var any_valid := r1.is_valid() or r2.is_valid() or r3.is_valid() or r4.is_valid()
		if any_valid:
			solver.gpu_blend_flowmaps(r1, r2, r3, r4,
				flowmap_1_mix, flowmap_2_mix, flowmap_3_mix, flowmap_4_mix)
			var blended := solver.flowmap_blended
			if flowmap_mode == 0:
				solver.gpu_inject_flowmap(blended, RID(), flowmap_force, flowmap_scale, dt, flowmap_bump, 0.0)
			else:
				solver.gpu_inject_flowmap_buoyancy2(blended, RID(), buoyancy, flowmap_scale, dt, flowmap_bump, 0.0)

	var inv_sub := 1.0 / float(substeps)
	var vel_diss_sub  := pow(velocity_dissipation, inv_sub)
	var smk_diss_sub  := pow(smoke_dissipation,    inv_sub)
	var tmp_diss_sub  := pow(temp_dissipation,     inv_sub)
	var iter_sub = max(1, int(round(float(iterations) * inv_sub)))
	solver.step(
		dt, viscosity / 1000.0, smoke_diffusion / 1000.0, temp_diffusion / 1000.0,
		iter_sub, vorticity_fire, vorticity_smoke, vel_diss_sub,
		smk_diss_sub, tmp_diss_sub)


func _flicker_multiplier() -> float:
	if not flicker_enabled or flicker_noise == null or flicker_strength <= 0.0: return 1.0
	var img: Image = flicker_noise.get_image()
	var w: int = img.get_width()
	var h: int = img.get_height()
	var x: int = int(_flicker_scroll * w) % w
	var y: int = int(_flicker_seed   * h) % h
	var noise_val: float = img.get_pixel(x, y).r  # 0..1
	var flicker: float = noise_val * 2.0 - 1.0    # remap to -1..1
	return clamp(1.0 + flicker * flicker_strength, 0.2, 2.0)


func _flowmap_rid(tex: Texture2D) -> RID:
	if tex == null: return RID()
	var rid: RID = tex.get_rid()
	if not rid.is_valid(): return RID()
	var rd_rid: RID = RenderingServer.texture_get_rd_texture(rid, false)
	if not rd_rid.is_valid():
		rd_rid = RenderingServer.texture_get_rd_texture(rid, true)
	return rd_rid

func _emit_bitmap(dt: float) -> void:
	var rid: RID = _get_emitter_rid()
	if not rid.is_valid():
		return

	var source_scale: float = injection_multiplier

	var use_fm: bool = flowmap_enabled and flowmap_mode == 1
	var flow_rd: RID = solver.flowmap_blended if use_fm else RID()

	solver.gpu_emit_bitmap(rid, dt,
		source_temp * dt * _flicker_multiplier(),
		source_smoke * dt,
		direction_force * dt * 1.7,
		0.0,
		sim_time, source_scale, 0.05,
		flow_rd, use_fm and flow_rd.is_valid(), flowmap_scale)

	var eff_buoyancy: float = 0.0 if (flowmap_enabled and flowmap_mode == 1) else buoyancy
	solver.gpu_apply_buoyancy_cooling(dt, eff_buoyancy, pow(cooling, 1.0 / float(substeps)), smoke_from_cooling)


func _get_emitter_rid() -> RID:
	if emitter_viewport == null: return RID()
	var vt: ViewportTexture = emitter_viewport.get_texture()
	if vt == null: return RID()
	return RenderingServer.texture_get_rd_texture(vt.get_rid())


func _render_gpu(delta: float) -> void:
	var temp_scale: float  = 8.0  if intense_mode else 10.0
	var smoke_scale: float = 4.0  if intense_mode else 6.0
	var vel_scale: float   = 0.35 if intense_mode else 0.45

	# Update Texture2DRD wrappers with current solver texture RIDs
	_tex_temp.texture_rd_rid  = solver._temp[0]
	_tex_smoke.texture_rd_rid = solver._smk[0]
	_tex_vel.texture_rd_rid   = solver._vel[0]
	var blend_rid := solver.flowmap_blended
	_tex_flow.texture_rd_rid  = blend_rid if (flowmap_enabled and blend_rid.is_valid()) else solver._temp[0]

	# Pass all uniforms to shader material
	_mat.set_shader_parameter("sam_temp",      _tex_temp)
	_mat.set_shader_parameter("sam_smoke",     _tex_smoke)
	_mat.set_shader_parameter("sam_vel",       _tex_vel)
	_mat.set_shader_parameter("sam_flowmap",   _tex_flow)
	_mat.set_shader_parameter("N",             simulation_resolution)
	# ── Run ember passes ─────────────────────────────────────────────────────
	if embers_enabled:
		_ember_process(delta)
	_mat.set_shader_parameter("is_hellfire",   1 if intense_mode else 0)
	_mat.set_shader_parameter("flame_height",  flame_height)
	_mat.set_shader_parameter("glow",          smoke_glow)
	_mat.set_shader_parameter("fire_glow", fire_glow)
	_mat.set_shader_parameter("display_mode",  simulation_view)
	_mat.set_shader_parameter("temp_scale",    temp_scale)
	_mat.set_shader_parameter("smoke_scale",   smoke_scale)
	_mat.set_shader_parameter("vel_scale",     vel_scale)
	_mat.set_shader_parameter("flowmap_scale", flowmap_scale)
	_mat.set_shader_parameter("pixelize_size", pixelize_size)
	_mat.set_shader_parameter("hue_shift",     hue_shift)
	_mat.set_shader_parameter("saturation",    saturation)
	_mat.set_shader_parameter("sharpness",     sharpness)
	_mat.set_shader_parameter("heat_distortion", heat_distortion)
	_mat.set_shader_parameter("heat_dist_noise", heat_dist_noise_tex)
	_mat.set_shader_parameter("heat_dist_time",  sim_time)
	_mat.set_shader_parameter("ember_flicker",  ember_flicker)
	_mat.set_shader_parameter("ember_strength",   ember_strength if embers_enabled else 0.0)
	_mat.set_shader_parameter("ember_heat_value", ember_heat_value)
	_mat.set_shader_parameter("hdr_mode",       hdr_mode)


# ══════════════════════════════════════════════════════════════════════════════
# EMBER SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

func _b(rid: RID, binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(rid)
	return u

func _s_e(rid: RID, binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(solver._sam)
	u.add_id(rid)
	return u

func _img_e(rid: RID, binding: int) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u

func _ember_setup() -> void:
	# Buffers
	var age_data := PackedByteArray(); age_data.resize(EMBER_MAX * 4)
	for i in range(EMBER_MAX): age_data.encode_float(i * 4, -1.0)
	var zero8 := PackedByteArray(); zero8.resize(EMBER_MAX * 8)
	var zero4 := PackedByteArray(); zero4.resize(EMBER_MAX * 4)
	_e_buf_pos      = _rd.storage_buffer_create(EMBER_MAX * 8, zero8)
	_e_buf_vel      = _rd.storage_buffer_create(EMBER_MAX * 8, zero8)
	_e_buf_age      = _rd.storage_buffer_create(EMBER_MAX * 4, age_data)
	_e_buf_lifetime = _rd.storage_buffer_create(EMBER_MAX * 4, zero4)
	_e_buf_spread   = _rd.storage_buffer_create(EMBER_MAX * 8, zero8)
	var ctr_data := PackedByteArray(); ctr_data.resize(4); ctr_data.encode_s32(0, 0)
	_e_buf_counter  = _rd.storage_buffer_create(4, ctr_data)

	# Output texture — same size as sim
	var fmt := RDTextureFormat.new()
	fmt.width  = simulation_resolution * 2
	fmt.height = simulation_resolution * 2
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | \
					 RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | \
					 RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	_e_out_tex  = _rd.texture_create(fmt, RDTextureView.new(), [])
	_e_out_wrap = Texture2DRD.new()
	_e_out_wrap.texture_rd_rid = _e_out_tex

	# Shaders
	_e_sh_update = _rd.shader_create_from_spirv(load("res://Shaders/ember_update.glsl").get_spirv())
	_e_pl_update = _rd.compute_pipeline_create(_e_sh_update)
	_e_sh_spawn  = _rd.shader_create_from_spirv(load("res://Shaders/ember_spawn.glsl").get_spirv())
	_e_pl_spawn  = _rd.compute_pipeline_create(_e_sh_spawn)
	_e_sh_render = _rd.shader_create_from_spirv(load("res://Shaders/ember_render.glsl").get_spirv())
	_e_pl_render = _rd.compute_pipeline_create(_e_sh_render)

	# Pass ember texture to fire shader
	_mat.set_shader_parameter("sam_embers", _e_out_wrap)

func _ember_process(delta: float) -> void:
	_e_time += delta
	var wg := int(ceil(EMBER_MAX / 64.0))

	# Clear output texture
	var clear_data := PackedByteArray(); clear_data.resize(simulation_resolution * simulation_resolution * 4 * 8)
	_rd.texture_update(_e_out_tex, 0, clear_data)

	# ── Update ───────────────────────────────────────────────────────────────────
	var us_upd := _rd.uniform_set_create([
		_s_e(solver._vel[0],  0),
		_s_e(solver._temp[0], 1),
		_b(_e_buf_pos,  2),
		_b(_e_buf_vel,  3),
		_b(_e_buf_age,  4),
		_b(_e_buf_lifetime, 5),
		_b(_e_buf_spread, 6),
	], _e_sh_update, 0)

	var pc_upd := PackedByteArray(); pc_upd.resize(32)
	pc_upd.encode_s32(0,   simulation_resolution)
	pc_upd.encode_float(4, delta)
	pc_upd.encode_float(8, 1.0)
	pc_upd.encode_float(12, ember_gravity / 1000.0)
	pc_upd.encode_float(16, ember_drag)
	pc_upd.encode_float(20, ember_vel_follow)
	pc_upd.encode_float(24, ember_spread_x)
	pc_upd.encode_float(28, 0.0)

	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _e_pl_update)
	_rd.compute_list_bind_uniform_set(cl, us_upd, 0)
	_rd.compute_list_set_push_constant(cl, pc_upd, pc_upd.size())
	_rd.compute_list_dispatch(cl, wg, 1, 1)
	_rd.compute_list_end()
	_rd.free_rid(us_upd)

	# ── Spawn ─────────────────────────────────────────────────────────────────────
	var spawn_invocations: int = max(1, int(float(ember_max_particles) * ember_spawn_amount))
	var spawn_wg := int(ceil(float(spawn_invocations) / 64.0))
	var temp_scale_val := 8.0 if intense_mode else 10.0

	var us_spn := _rd.uniform_set_create([
		_s_e(solver._temp[0], 0),
		_b(_e_buf_pos,  1),
		_b(_e_buf_vel,  2),
		_b(_e_buf_age,  3),
		_b(_e_buf_lifetime, 4),
		_b(_e_buf_counter, 5),
		_b(_e_buf_spread, 6),
	], _e_sh_spawn, 0)

	var pc_spn := PackedByteArray(); pc_spn.resize(32)
	pc_spn.encode_s32(0,   simulation_resolution)
	pc_spn.encode_float(4, temp_scale_val)
	pc_spn.encode_float(8, ember_spawn_threshold)
	pc_spn.encode_float(12, ember_min_lifetime)
	pc_spn.encode_float(16, ember_max_lifetime)
	pc_spn.encode_float(20, _e_time)
	pc_spn.encode_float(24, ember_spawn_amount)
	pc_spn.encode_s32(28, ember_max_particles)

	cl = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _e_pl_spawn)
	_rd.compute_list_bind_uniform_set(cl, us_spn, 0)
	_rd.compute_list_set_push_constant(cl, pc_spn, pc_spn.size())
	_rd.compute_list_dispatch(cl, spawn_wg, 1, 1)
	_rd.compute_list_end()
	_rd.free_rid(us_spn)

	# ── Render ───────────────────────────────────────────────────────────────────
	_e_ember_tex_rid = RID()
	var use_tex := false
	if ember_texture != null:
		var _tr := ember_texture.get_rid()
		if _tr.is_valid():
			var _trr := RenderingServer.texture_get_rd_texture(_tr, false)
			if not _trr.is_valid(): _trr = RenderingServer.texture_get_rd_texture(_tr, true)
			if _trr.is_valid():
				_e_ember_tex_rid = _trr
				use_tex = true

	var u_etex := RDUniform.new()
	u_etex.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_etex.binding = 4
	u_etex.add_id(solver._sam)
	u_etex.add_id(_e_ember_tex_rid if use_tex else solver._temp[0])

	var us_rnd := _rd.uniform_set_create([
		_img_e(_e_out_tex, 0),
		_b(_e_buf_pos,  1),
		_b(_e_buf_age,  2),
		_b(_e_buf_lifetime, 3),
		u_etex,
		_b(_e_buf_spread, 5),
		_b(_e_buf_vel,   6),
	], _e_sh_render, 0)

	var pc_rnd := PackedByteArray(); pc_rnd.resize(80)
	pc_rnd.encode_s32(0,   simulation_resolution * 2)
	pc_rnd.encode_float(4,  ember_size)
	pc_rnd.encode_float(8,  ember_hot_duration)
	pc_rnd.encode_float(12, 1.0 if use_tex else 0.0)
	pc_rnd.encode_s32(16,   ember_max_particles)
	pc_rnd.encode_float(20, ember_trail_stretch)
	pc_rnd.encode_float(24, 0.0)
	pc_rnd.encode_float(28, 0.0)
	pc_rnd.encode_float(32, 0.0) # was ember_color_hot.r  — now derived in fragment shader
	pc_rnd.encode_float(36, 0.0)
	pc_rnd.encode_float(40, 0.0)
	pc_rnd.encode_float(44, 0.0) # was ember_color_mid.r
	pc_rnd.encode_float(48, 0.0)
	pc_rnd.encode_float(52, 0.0)
	pc_rnd.encode_float(56, 0.0) # was ember_color_smoke.r
	pc_rnd.encode_float(60, 0.0)
	pc_rnd.encode_float(64, 0.0)
	pc_rnd.encode_float(68, 0.0)
	pc_rnd.encode_float(72, 0.0)
	pc_rnd.encode_float(76, 0.0)

	cl = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _e_pl_render)
	_rd.compute_list_bind_uniform_set(cl, us_rnd, 0)
	_rd.compute_list_set_push_constant(cl, pc_rnd, pc_rnd.size())
	_rd.compute_list_dispatch(cl, wg, 1, 1)
	_rd.compute_list_end()
	_rd.free_rid(us_rnd)

	# Update sam_embers uniform with latest output
	_mat.set_shader_parameter("sam_embers", _e_out_wrap)
