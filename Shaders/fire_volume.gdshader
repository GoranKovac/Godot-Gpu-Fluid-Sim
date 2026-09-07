shader_type spatial;
render_mode blend_add, depth_draw_never, cull_front, unshaded;

// 3D noise volume — base shape of the smoke/fire
uniform sampler3D noise_volume : filter_linear, repeat_enable;

// 2D sim textures from our fluid solver
uniform sampler2D sam_smoke  : filter_linear, repeat_disable;
uniform sampler2D sam_temp   : filter_linear, repeat_disable;
uniform sampler2D sam_vel    : filter_linear, repeat_disable;

// Parameters
uniform float density_scale   : hint_range(0.0, 10.0) = 3.0;
uniform float noise_scale     : hint_range(0.1, 5.0)  = 1.0;
uniform float noise_speed     : hint_range(0.0, 2.0)  = 0.1;
uniform float vel_strength    : hint_range(0.0, 2.0)  = 0.5;
uniform float smoke_mask      : hint_range(0.0, 1.0)  = 1.0;
uniform float temp_scale      : hint_range(1.0, 20.0) = 8.0;
uniform float march_steps     : hint_range(8.0, 64.0) = 32.0;
uniform float time_offset     : hint_range(0.0, 100.0) = 0.0;

// Fire color ramp
uniform vec3 color_hot   = vec3(1.0, 0.9, 0.5);   // white/yellow hot core
uniform vec3 color_mid   = vec3(1.0, 0.3, 0.05);   // orange mid flame
uniform vec3 color_smoke = vec3(0.15, 0.1, 0.08);  // dark smoke

varying vec3 world_pos;
varying vec3 object_pos;

void vertex() {
    world_pos  = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    object_pos = VERTEX; // -0.5 to 0.5 in local space
}

// Convert local box position (-0.5..0.5) to 2D sim UV (0..1)
// The box Y goes from -0.5 (bottom/fire base) to +0.5 (top/smoke)
vec2 to_sim_uv(vec3 local_pos) {
    return vec2(local_pos.x + 0.5, 1.0 - (local_pos.y + 0.5));
}

void fragment() {
    // Ray setup in local object space
    vec3 ray_origin = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
    vec3 ray_dir    = normalize(object_pos - ray_origin);

    // Ray-box intersection in local space (box is -0.5..0.5)
    vec3 box_min = vec3(-0.5);
    vec3 box_max = vec3( 0.5);
    vec3 inv_dir = 1.0 / ray_dir;
    vec3 t0 = (box_min - ray_origin) * inv_dir;
    vec3 t1 = (box_max - ray_origin) * inv_dir;
    vec3 tmin = min(t0, t1);
    vec3 tmax = max(t0, t1);
    float t_enter = max(max(tmin.x, tmin.y), tmin.z);
    float t_exit  = min(min(tmax.x, tmax.y), tmax.z);

    if (t_exit < t_enter || t_exit < 0.0) discard;

    t_enter = max(t_enter, 0.0);

    float step_size = (t_exit - t_enter) / march_steps;

    // Accumulate
    vec3  accumulated_color = vec3(0.0);
    float transmittance     = 1.0;

    for (int i = 0; i < int(march_steps); i++) {
        float t   = t_enter + (float(i) + 0.5) * step_size;
        vec3  pos = ray_origin + ray_dir * t; // local -0.5..0.5

        // Discard if outside box
        if (any(greaterThan(abs(pos), vec3(0.5)))) break;

        // 2D sim UV for this position
        vec2 sim_uv = to_sim_uv(pos);

        // Sample velocity and distort noise UVs
        vec2 vel = texture(sam_vel, sim_uv).rg * 2.0 - 1.0;

        // 3D noise UV — use object pos + time + velocity advection
        vec3 noise_uv = (pos + 0.5) * noise_scale;
        noise_uv.y   -= time_offset * noise_speed;         // upward drift
        noise_uv.xz  += vel * vel_strength * 0.1;         // velocity distortion

        float noise = texture(noise_volume, noise_uv).r;

        // Sample 2D sim density and temperature
        float sim_density = texture(sam_smoke, sim_uv).r / 255.0;
        float sim_temp    = clamp(texture(sam_temp, sim_uv).r / (temp_scale * 32.0), 0.0, 1.0);

        // Combine: noise shaped by sim density
        // Noise shaped by sim density — smoke where sim has smoke, fire where sim has heat
        float smoke_density = clamp(sim_density * 3.0, 0.0, 1.0);
        float fire_density  = clamp(sim_temp * 4.0, 0.0, 1.0);
        float combined = max(smoke_density, fire_density);
        float density = noise * combined * smoke_mask + fire_density * (1.0 - smoke_mask);
        density = clamp(density * density_scale / march_steps, 0.0, 1.0);

        if (density > 0.001) {
            // Color based on temperature
            vec3 col = mix(color_smoke, color_mid, clamp(sim_temp * 2.0, 0.0, 1.0));
            col      = mix(col, color_hot, clamp(sim_temp * 4.0 - 1.0, 0.0, 1.0));

            accumulated_color += transmittance * density * col;
            transmittance     *= exp(-density * 2.0);

            if (transmittance < 0.01) break;
        }
    }

    // Debug: show faint red box outline if nothing accumulated
    if (length(accumulated_color) < 0.001) {
        ALBEDO = vec3(0.3, 0.0, 0.0);
        ALPHA  = 0.3;
    } else {
        ALBEDO = accumulated_color;
        ALPHA  = 1.0 - transmittance;
    }
}
