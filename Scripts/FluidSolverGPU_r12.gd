# FluidSolverGPU_r12.gd
#
# Ping-pong pattern:
#   - Every field = [current_RID, scratch_RID]
#   - Every pass: read [0], write [1]
#   - After every pass: _sw(field) swaps — [0] always holds current result
#
# Field formats:
#   _vel  = [RID, RID]  RG32F — u packed in .r, v packed in .g
#   _temp = [RID, RID]  R32F
#   _smk  = [RID, RID]  R32F
#   _pres = [RID, RID]  R32F
#   _div  = RID         R32F  (single — written fresh each project call)
#   _vort = RID         R32F  (single — written fresh each vorticity call)
#

class_name FluidSolverGPU_r12

var size: int
var _rd:  RenderingDevice

# Public field textures — always [0] = current, exposed for render
var _vel:  Array  # [RID_rg32f_a, RID_rg32f_b]
var _temp: Array  # [RID_r32f_a,  RID_r32f_b]
var _smk:  Array  # [RID_r32f_a,  RID_r32f_b]
var _pres: Array  # [RID_r32f_a,  RID_r32f_b]
var _div:  RID    # single scratch
var _vort: RID    # single scratch
var _flowmap_blended: RID  # RGBA16F — result of blending multiple flowmaps

# Convenience — expose current textures by name
var tex_u: RID:
	get: return _vel[0]
var tex_temperature: RID:
	get: return _temp[0]
var flowmap_blended: RID:
	get: return _flowmap_blended
var tex_smoke: RID:
	get: return _smk[0]

# Sources SSBO
var _buf_sources: RID

# Sampler (one for all field reads — LINEAR + CLAMP_TO_EDGE)
var _sam: RID
var _sam_emit: RID  # same settings, separate RID for emitter viewport
var _sam_repeat: RID  # LINEAR + REPEAT for tileable noise textures

# Shaders + pipelines
var _sh:  Dictionary = {}
var _pip: Dictionary = {}


func _init(p_size: int) -> void:
	size = p_size
	_rd  = RenderingServer.get_rendering_device()
	_setup_sampler()
	_setup_textures()
	_setup_shaders()


func _setup_sampler() -> void:
	var s: RDSamplerState = RDSamplerState.new()
	s.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	s.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	s.repeat_u   = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	s.repeat_v   = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sam      = _rd.sampler_create(s)
	_sam_emit = _rd.sampler_create(s)

	var sr: RDSamplerState = RDSamplerState.new()
	sr.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sr.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sr.repeat_u   = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	sr.repeat_v   = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	_sam_repeat = _rd.sampler_create(sr)


func _mk_rgba16f() -> RID:
	var fmt := RDTextureFormat.new()
	fmt.width = size; fmt.height = size
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = (RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT)
	return _rd.texture_create(fmt, RDTextureView.new(), [])


func _mk_r32f() -> RID:
	var f: RDTextureFormat = RDTextureFormat.new()
	f.width = size; f.height = size
	f.format = RenderingDevice.DATA_FORMAT_R16_SFLOAT  # half-float: 2× less bandwidth than R32F
	f.usage_bits = (RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
				  | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
				  | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
				  | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
				  | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT)
	return _rd.texture_create(f, RDTextureView.new(), [])


func _mk_rg32f() -> RID:
	var f: RDTextureFormat = RDTextureFormat.new()
	f.width = size; f.height = size
	f.format = RenderingDevice.DATA_FORMAT_R32G32_SFLOAT
	f.usage_bits = (RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
				  | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
				  | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
				  | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
				  | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT)
	return _rd.texture_create(f, RDTextureView.new(), [])


func _setup_textures() -> void:
	_vel  = [_mk_rg32f(), _mk_rg32f()]
	_temp   = [_mk_r32f(), _mk_r32f()]
	_smk  = [_mk_r32f(),  _mk_r32f()]
	_pres = [_mk_r32f(),  _mk_r32f()]
	_div             = _mk_r32f()
	_vort            = _mk_r32f()
	_flowmap_blended = _mk_rgba16f()
	var z4: PackedByteArray = PackedByteArray(); z4.resize(size*size*2); z4.fill(0)  # R16F = 2 bytes/pixel
	var z8: PackedByteArray = PackedByteArray(); z8.resize(size*size*8); z8.fill(0)
	for t in [_temp[0],_temp[1],
			  _smk[0],_smk[1],_pres[0],_pres[1],_div,_vort]:
		_rd.texture_update(t, 0, z4)
	for t in [_vel[0], _vel[1]]:
		_rd.texture_update(t, 0, z8)
	var z: PackedByteArray = PackedByteArray(); z.resize(192); z.fill(0)
	_buf_sources = _rd.storage_buffer_create(192, z)


func _setup_shaders() -> void:
	var paths := {
		"lin_solve":      "res://Shaders/fluid_r12_lin_solve.glsl",
		"proj_div":       "res://Shaders/fluid_r12_project_div.glsl",
		"proj_grad":      "res://Shaders/fluid_r12_project_grad.glsl",
		"diffuse_vel":    "res://Shaders/fluid_r12_diffuse_vel.glsl",
		"advect_vel":     "res://Shaders/fluid_r12_advect_vel.glsl",
		"advect_scalar":  "res://Shaders/fluid_r12_advect_scalar.glsl",
		"emit":           "res://Shaders/fluid_r12_emit.glsl",
		"inject_bitmap":  "res://Shaders/fluid_r12_inject_bitmap.glsl",
		"vorticity":      "res://Shaders/fluid_r12_vorticity.glsl",
		"vort_force":     "res://Shaders/fluid_r12_vort_force.glsl",
		"blend_flowmaps": "res://Shaders/fluid_r12_blend_flowmaps.glsl",
		"dissipation":    "res://Shaders/fluid_r12_dissipation.glsl",
		"inject_turbulence": "res://Shaders/fluid_r15_inject_turbulence.glsl",
		"inject_wind":       "res://Shaders/fluid_r12_inject_wind.glsl",
		"inject_flowmap":           "res://Shaders/fluid_r12_inject_flowmap.glsl",
		"inject_flowmap_buoyancy2": "res://Shaders/fluid_r12_inject_flowmap_buoyancy.glsl",
	}
	for k in paths:
		var sh: RID = _rd.shader_create_from_spirv(load(paths[k]).get_spirv())
		_sh[k]  = sh
		_pip[k] = _rd.compute_pipeline_create(sh)


# Swap [0] and [1] — zero GPU cost
func _sw(a: Array) -> void:
	var t: RID = a[0]; a[0] = a[1]; a[1] = t


# Dispatch one compute pass
func _run(shader: String, unis: Array, pc: PackedByteArray) -> void:
	var us: RID = _rd.uniform_set_create(unis, _sh[shader], 0)
	if not us.is_valid(): push_error("r12: uniform_set failed for " + shader); return
	var cl: int = _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pip[shader])
	_rd.compute_list_bind_uniform_set(cl, us, 0)
	_rd.compute_list_set_push_constant(cl, pc, pc.size())
	_rd.compute_list_dispatch(cl, ceili(float(size)/8.0), ceili(float(size)/8.0), 1)
	_rd.compute_list_end()
	_rd.free_rid(us)


# Batch N Jacobi iterations in ONE compute list.
# unis_even: uniform set for even iterations (read [0] write [1])
# unis_odd:  uniform set for odd  iterations (read [1] write [0])
# After all iterations, field[0] holds the result (ensured by _sw if needed).
func _run_batch(shader: String, unis_even: Array, unis_odd: Array,
				pc: PackedByteArray, iters: int, field: Array) -> void:
	var us_e: RID = _rd.uniform_set_create(unis_even, _sh[shader], 0)
	var us_o: RID = _rd.uniform_set_create(unis_odd,  _sh[shader], 0)
	if not us_e.is_valid() or not us_o.is_valid():
		push_error("r12: _run_batch uniform_set failed for " + shader)
		_rd.free_rid(us_e); _rd.free_rid(us_o); return

	var cl: int = _rd.compute_list_begin()
	for ii in range(iters):
		var us: RID = us_e if (ii % 2 == 0) else us_o
		_rd.compute_list_bind_compute_pipeline(cl, _pip[shader])
		_rd.compute_list_bind_uniform_set(cl, us, 0)
		_rd.compute_list_set_push_constant(cl, pc, pc.size())
		_rd.compute_list_dispatch(cl, ceili(float(size)/8.0), ceili(float(size)/8.0), 1)
	_rd.compute_list_end()
	_rd.free_rid(us_e); _rd.free_rid(us_o)

	# After iters iterations: result is in field[1] if iters is odd, field[0] if even.
	# Even iters: last iter was odd → wrote field[0] ✓ no swap needed
	# Odd  iters: last iter was even → wrote field[1] → swap so field[0]=result
	if iters % 2 == 1:
		_sw(field)


# Sampler+texture uniform
func _s(tex: RID, binding: int) -> RDUniform:
	var u: RDUniform = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(_sam); u.add_id(tex)
	return u


# Sampler+texture uniform with explicit sampler (for emitter)
func _se(sam: RID, tex: RID, binding: int) -> RDUniform:
	var u: RDUniform = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(sam); u.add_id(tex)
	return u


# Image uniform
func _i(tex: RID, binding: int) -> RDUniform:
	var u: RDUniform = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(tex)
	return u


# Storage buffer uniform
func _b(buf: RID, binding: int) -> RDUniform:
	var u: RDUniform = RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u.binding = binding
	u.add_id(buf)
	return u


# Push constant: 4 floats
func _pcf(a: float, b: float, c: float, d: float) -> PackedByteArray:
	var pc: PackedByteArray = PackedByteArray(); pc.resize(16)
	pc.encode_float(0,a); pc.encode_float(4,b); pc.encode_float(8,c); pc.encode_float(12,d)
	return pc

# Push constant: int N, int pad, float a, float b
func _pci(n: int, pad: int, a: float, b: float) -> PackedByteArray:
	var pc: PackedByteArray = PackedByteArray(); pc.resize(16)
	pc.encode_s32(0,n); pc.encode_s32(4,pad); pc.encode_float(8,a); pc.encode_float(12,b)
	return pc

# Push constant: int N, float, float, float
func _pcnf(n: int, a: float, b: float, c: float) -> PackedByteArray:
	var pc: PackedByteArray = PackedByteArray(); pc.resize(16)
	pc.encode_s32(0,n); pc.encode_float(4,a); pc.encode_float(8,b); pc.encode_float(12,c)
	return pc

# Push constant: 8 floats (32 bytes)
func _pc8(a:float,b:float,c:float,d:float,e:float,f:float,g:float,h:float) -> PackedByteArray:
	var pc: PackedByteArray = PackedByteArray(); pc.resize(32)
	pc.encode_float(0,a);  pc.encode_float(4,b);  pc.encode_float(8,c);  pc.encode_float(12,d)
	pc.encode_float(16,e); pc.encode_float(20,f); pc.encode_float(24,g); pc.encode_float(28,h)
	return pc

# Push constant: int N, int pad, float dt, float epsilon, 4 pads
func _pc_vort(n: int, dt: float, epsilon_fire: float, epsilon_smoke: float, temp_scale: float) -> PackedByteArray:
	var pc: PackedByteArray = PackedByteArray(); pc.resize(32)
	pc.encode_s32(0,n); pc.encode_s32(4,0)
	pc.encode_float(8,dt); pc.encode_float(12,epsilon_fire)
	pc.encode_float(16,epsilon_smoke); pc.encode_float(20,temp_scale)
	pc.encode_float(24,0.0); pc.encode_float(28,0.0)
	return pc


func clear() -> void:
	var z4: PackedByteArray = PackedByteArray(); z4.resize(size*size*2); z4.fill(0)  # R16F = 2 bytes/pixel
	var z8: PackedByteArray = PackedByteArray(); z8.resize(size*size*8); z8.fill(0)
	for t in [_temp[0],_temp[1],_smk[0],_smk[1],_pres[0],_pres[1],_div,_vort]:
		_rd.texture_update(t, 0, z4)
	for t in [_vel[0], _vel[1]]:
		_rd.texture_update(t, 0, z8)


func gpu_emit(sources_flat: PackedFloat32Array, dt: float,
			  buoyancy: float, cooling: float, smoke_from_cooling: float) -> void:
	_rd.buffer_update(_buf_sources, 0, 192, sources_flat.to_byte_array())
	var pc: PackedByteArray = PackedByteArray(); pc.resize(32)
	pc.encode_s32(0,size); pc.encode_float(4,dt); pc.encode_float(8,buoyancy)
	pc.encode_float(12,cooling); pc.encode_float(16,smoke_from_cooling)
	pc.encode_float(20,150.0); pc.encode_float(24,0.0); pc.encode_float(28,0.0)
	_run("emit", [
		_s(_vel[0],0), _s(_temp[0],1), _s(_smk[0],2),
		_i(_vel[1],3), _i(_temp[1],4), _i(_smk[1],5),
		_b(_buf_sources, 6),
	], pc)
	_sw(_vel); _sw(_temp); _sw(_smk)
	# Keep G and B channels in sync with master after injection


func gpu_emit_bitmap(emitter_rid: RID, _dt: float, base_temp: float,
					 base_smoke: float, upward: float, jitter: float,
					 sim_time: float, source_scale: float, threshold: float,
					 flowmap_rid: RID = RID(), use_flowmap: bool = false, flowmap_scale: float = 1.0,
					 blur_radius: int = 0) -> void:
	var pc: PackedByteArray = PackedByteArray(); pc.resize(48)
	pc.encode_s32(0,size); pc.encode_float(4,base_temp); pc.encode_float(8,base_smoke)
	pc.encode_float(12,upward); pc.encode_float(16,jitter); pc.encode_float(20,sim_time)
	pc.encode_float(24,threshold); pc.encode_float(28,source_scale)
	pc.encode_s32(32, 1 if use_flowmap else 0)
	pc.encode_float(36, flowmap_scale)
	pc.encode_s32(40, blur_radius)
	pc.encode_float(44, 0.0)
	# Flowmap binding 7 — dummy (reuse emitter sampler+temp) if not used
	var fm_binding: RDUniform
	if use_flowmap and flowmap_rid.is_valid():
		fm_binding = _se(_sam_repeat, flowmap_rid, 7)
	else:
		fm_binding = _s(_temp[0], 7)
	_run("inject_bitmap", [
		_s(_vel[0],0), _s(_temp[0],1), _s(_smk[0],2),
		_i(_vel[1],3), _i(_temp[1],4), _i(_smk[1],5),
		_se(_sam_emit, emitter_rid, 6),
		fm_binding,
	], pc)
	_sw(_vel); _sw(_temp); _sw(_smk)


func gpu_apply_buoyancy_cooling(dt: float, buoyancy: float,
								cooling: float, smoke_from_cooling: float) -> void:
	var zero: PackedByteArray = PackedByteArray(); zero.resize(192); zero.fill(0)
	_rd.buffer_update(_buf_sources, 0, 192, zero)
	var pc: PackedByteArray = PackedByteArray(); pc.resize(32)
	pc.encode_s32(0,size); pc.encode_float(4,dt); pc.encode_float(8,buoyancy)
	pc.encode_float(12,cooling); pc.encode_float(16,smoke_from_cooling)
	pc.encode_float(20,150.0); pc.encode_float(24,0.0); pc.encode_float(28,0.0)
	_run("emit", [
		_s(_vel[0],0), _s(_temp[0],1), _s(_smk[0],2),
		_i(_vel[1],3), _i(_temp[1],4), _i(_smk[1],5),
		_b(_buf_sources, 6),
	], pc)
	_sw(_vel); _sw(_temp); _sw(_smk)


func gpu_inject_turbulence(noise_rid: RID, strength: float,
						   scroll_x: float, scroll_y: float, morph: float,
						   mode: int = 0, buoyancy: float = 0.0, dt: float = 0.016) -> void:
	# Read _vel[0] + noise (REPEAT sampler) → write _vel[1] → swap
	var u_noise: RDUniform = RDUniform.new()
	u_noise.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_noise.binding = 1
	u_noise.add_id(_sam_repeat); u_noise.add_id(noise_rid)
	var pc: PackedByteArray = PackedByteArray(); pc.resize(32)
	pc.encode_float(0, strength); pc.encode_float(4, strength)
	pc.encode_float(8, scroll_x); pc.encode_float(12, scroll_y)
	pc.encode_float(16, morph)
	pc.encode_s32(20, mode); pc.encode_float(24, buoyancy); pc.encode_float(28, dt)
	_run("inject_turbulence", [_s(_vel[0],0), u_noise, _i(_vel[1],2), _s(_temp[0],3)], pc)
	_sw(_vel)


func gpu_inject_wind(noise_rid: RID, wind_x: float, wind_y: float,
					 scroll_x: float, scroll_y: float, seed_n: float,
					 dt: float) -> void:
	var u_noise: RDUniform = RDUniform.new()
	u_noise.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_noise.binding = 1
	u_noise.add_id(_sam_repeat); u_noise.add_id(noise_rid)
	var pc: PackedByteArray = PackedByteArray(); pc.resize(32)
	pc.encode_float(0,  wind_x);   pc.encode_float(4,  wind_y)
	pc.encode_float(8,  scroll_x); pc.encode_float(12, scroll_y)
	pc.encode_float(16, seed_n);     pc.encode_float(20, dt)
	pc.encode_float(24, 0.0);      pc.encode_float(28, 0.0)
	_run("inject_wind", [_s(_vel[0],0), u_noise, _s(_temp[0],2), _i(_vel[1],3)], pc)
	_sw(_vel)


func gpu_inject_flowmap(flowmap_rid: RID, flowmap2_rid: RID, strength: float, scale: float, dt: float, bump: float, flow_mix: float) -> void:
	var u_flow1: RDUniform = RDUniform.new()
	u_flow1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_flow1.binding = 1
	u_flow1.add_id(_sam_repeat); u_flow1.add_id(flowmap_rid)
	var u_flow2: RDUniform = RDUniform.new()
	u_flow2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_flow2.binding = 2
	u_flow2.add_id(_sam_repeat)
	u_flow2.add_id(flowmap2_rid if flowmap2_rid.is_valid() else flowmap_rid)
	var pc: PackedByteArray = PackedByteArray(); pc.resize(32)
	pc.encode_float(0, strength); pc.encode_float(4, scale)
	pc.encode_float(8, dt);       pc.encode_float(12, bump)
	pc.encode_float(16, flow_mix); pc.encode_float(20, 0.0)
	pc.encode_float(24, 0.0);     pc.encode_float(28, 0.0)
	_run("inject_flowmap", [_s(_vel[0],0), u_flow1, u_flow2, _i(_vel[1],3)], pc)
	_sw(_vel)


func gpu_inject_flowmap_buoyancy2(flowmap_rid: RID, flowmap2_rid: RID,
								  strength: float, scale: float, dt: float,
								  bump: float, flow_mix: float) -> void:
	var u_flow1: RDUniform = RDUniform.new()
	u_flow1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_flow1.binding = 1
	u_flow1.add_id(_sam_repeat); u_flow1.add_id(flowmap_rid)
	var u_flow2: RDUniform = RDUniform.new()
	u_flow2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u_flow2.binding = 2
	u_flow2.add_id(_sam_repeat)
	u_flow2.add_id(flowmap2_rid if flowmap2_rid.is_valid() else flowmap_rid)
	var pc: PackedByteArray = PackedByteArray(); pc.resize(32)
	pc.encode_float(0, strength); pc.encode_float(4, scale)
	pc.encode_float(8, dt);       pc.encode_float(12, bump)
	pc.encode_float(16, flow_mix); pc.encode_float(20, 0.0)
	pc.encode_float(24, 0.0);     pc.encode_float(28, 0.0)
	_run("inject_flowmap_buoyancy2",
		[_s(_vel[0],0), u_flow1, u_flow2, _s(_temp[0],3), _i(_vel[1],4)], pc)
	_sw(_vel)


func step(dt: float, viscosity: float, smoke_diffusion: float,
		  temperature_diffusion: float, iterations: int,
		  vorticity_fire: float, vorticity_smoke: float,
		  velocity_dissipation: float, smoke_dissipation: float,
		  temperature_dissipation: float) -> void:

	# ── 1. Velocity diffuse ───────────────────────────────────────────────────
	if viscosity > 0.0:
		var a: float = dt * viscosity * float(size)
		var inv_c: float = 1.0 / (1.0 + 4.0 * a)
		var pc: PackedByteArray = _pci(size, 0, a, inv_c)
		_run_batch("diffuse_vel",
			[_s(_vel[0],0), _s(_vel[0],1), _i(_vel[1],2)],
			[_s(_vel[1],0), _s(_vel[1],1), _i(_vel[0],2)],
			pc, iterations, _vel)

	# ── 2. Project ────────────────────────────────────────────────────────────
	_project(iterations)

	# ── 3. Velocity advect ────────────────────────────────────────────────────
	var pc_av := _pci(size, 0, dt*float(size), 0.0)
	_run("advect_vel",
		[_s(_vel[0],0), _s(_vel[0],1), _i(_vel[1],2)], pc_av)
	_sw(_vel)

	# ── 4. Project ────────────────────────────────────────────────────────────
	_project(iterations)

	# ── 5. Vorticity + project ────────────────────────────────────────────────
	if vorticity_fire > 0.0 or vorticity_smoke > 0.0:
		# Pass 0: compute curl → _vort
		_run("vorticity",
			[_s(_vel[0],0), _i(_vort,1)],
			_pcnf(size, 0.0, 0.0, 0.0))
		# Pass 1: confinement with separate fire/smoke epsilon
		_run("vort_force",
			[_s(_vort,0), _s(_vel[0],1), _i(_vel[1],2), _s(_temp[0],3)],
			_pc_vort(size, dt, vorticity_fire, vorticity_smoke, 8.0))
		_sw(_vel)
		_project(iterations)

	# ── 6. Temperature diffuse + advect ───────────────────────────────────────
	if temperature_diffusion > 0.0:
		var a2: float = dt * temperature_diffusion * float(size)
		var inv_c2: float = 1.0 / (1.0 + 4.0 * a2)
		var pc2: PackedByteArray = _pci(size, 0, a2, inv_c2)
		# Copy current temp into _vort as fixed rhs (vorticity not run yet, safe to use)
		_rd.texture_copy(_temp[0], _vort, Vector3.ZERO, Vector3.ZERO, Vector3(size,size,1),0,0,0,0)
		_run_batch("lin_solve",
			[_s(_temp[0],0), _s(_vort,1), _i(_temp[1],2)],
			[_s(_temp[1],0), _s(_vort,1), _i(_temp[0],2)],
			pc2, iterations, _temp)
	_run("advect_scalar",
		[_s(_vel[0],0), _s(_temp[0],1), _i(_temp[1],2)],
		_pci(size, 0, dt*float(size), 0.0))
	_sw(_temp)

	# ── 7. Smoke diffuse + advect ─────────────────────────────────────────────
	if smoke_diffusion > 0.0:
		var a3: float = dt * smoke_diffusion * float(size)
		var inv_c3: float = 1.0 / (1.0 + 4.0 * a3)
		var pc3: PackedByteArray = _pci(size, 0, a3, inv_c3)
		# Copy current smoke into _vort as fixed rhs
		_rd.texture_copy(_smk[0], _vort, Vector3.ZERO, Vector3.ZERO, Vector3(size,size,1),0,0,0,0)
		_run_batch("lin_solve",
			[_s(_smk[0],0), _s(_vort,1), _i(_smk[1],2)],
			[_s(_smk[1],0), _s(_vort,1), _i(_smk[0],2)],
			pc3, iterations, _smk)
	_run("advect_scalar",
		[_s(_vel[0],0), _s(_smk[0],1), _i(_smk[1],2)],
		_pci(size, 0, dt*float(size), 0.0))
	_sw(_smk)

	# ── 8. Dissipation + clamp ────────────────────────────────────────────────
	var pc_d: PackedByteArray = PackedByteArray(); pc_d.resize(16)
	pc_d.encode_s32(0, size)
	pc_d.encode_float(4, velocity_dissipation)
	pc_d.encode_float(8, smoke_dissipation)
	pc_d.encode_float(12, temperature_dissipation)
	_run("dissipation",
		[_s(_vel[0],0), _s(_temp[0],1), _s(_smk[0],2),
		 _i(_vel[1],3), _i(_temp[1],4), _i(_smk[1],5)],
		pc_d)
	_sw(_vel); _sw(_temp); _sw(_smk)


func _project(iters: int) -> void:
	# A: divergence + zero pressure
	_run("proj_div",
		[_s(_vel[0],0), _i(_div,1), _i(_pres[1],2)],
		_pcnf(size, 0.0, 0.0, 0.0))
	_sw(_pres)  # [0]=zeroed pressure, [1]=scratch

	# B: Jacobi pressure solve — batched in one compute list
	var pc_ls: PackedByteArray = _pci(size, 0, 1.0, 0.25)
	_run_batch("lin_solve",
		[_s(_pres[0],0), _s(_div,1), _i(_pres[1],2)],
		[_s(_pres[1],0), _s(_div,1), _i(_pres[0],2)],
		pc_ls, iters, _pres)

	# C: gradient subtract
	_run("proj_grad",
		[_s(_vel[0],0), _s(_pres[0],1), _i(_vel[1],2)],
		_pcnf(size, 0.0, 0.0, 0.0))
	_sw(_vel)


func set_bnd(_b_val: int, _x) -> void:
	pass  # boundaries handled in shaders (no-slip in grad, CLAMP_TO_EDGE elsewhere)


func gpu_blend_flowmaps(fm0: RID, fm1: RID, fm2: RID, fm3: RID,
						 mix0: float, mix1: float, mix2: float, mix3: float) -> void:
	## Blends up to 4 flowmap textures additively into _flowmap_blended.
	## Pass RID() for unused slots — they contribute nothing.
	var dummy: RID = _temp[0]  # neutral fallback for empty slots
	var r0 := fm0 if fm0.is_valid() else dummy
	var r1 := fm1 if fm1.is_valid() else dummy
	var r2 := fm2 if fm2.is_valid() else dummy
	var r3 := fm3 if fm3.is_valid() else dummy
	var m0 := mix0 if fm0.is_valid() else 0.0
	var m1 := mix1 if fm1.is_valid() else 0.0
	var m2 := mix2 if fm2.is_valid() else 0.0
	var m3 := mix3 if fm3.is_valid() else 0.0
	var pc := PackedByteArray(); pc.resize(32)
	pc.encode_s32(0, size)
	pc.encode_float(4,  m0); pc.encode_float(8,  m1)
	pc.encode_float(12, m2); pc.encode_float(16, m3)
	pc.encode_float(20, 0.0); pc.encode_float(24, 0.0); pc.encode_float(28, 0.0)
	_run("blend_flowmaps", [
		_se(_sam_repeat, r0, 0), _se(_sam_repeat, r1, 1),
		_se(_sam_repeat, r2, 2), _se(_sam_repeat, r3, 3),
		_i(_flowmap_blended, 4),
	], pc)


func free_gpu() -> void:
	if _flowmap_blended.is_valid(): _rd.free_rid(_flowmap_blended)
	for r in [_vel[0],_vel[1],_temp[0],_temp[1],
			  _smk[0],_smk[1],_pres[0],_pres[1],_div,_vort,_buf_sources,_sam,_sam_emit,_sam_repeat]:
		if r.is_valid(): _rd.free_rid(r)
	for k in _pip:
		if _pip[k].is_valid(): _rd.free_rid(_pip[k])
	for k in _sh:
		if _sh[k].is_valid(): _rd.free_rid(_sh[k])
