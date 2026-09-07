shader_type fog;

// 2D sim textures
uniform sampler2D sam_smoke  : filter_linear, repeat_disable;
uniform sampler2D sam_temp   : filter_linear, repeat_disable;

// Volume bounds — must match FogVolume size
uniform vec3 volume_size     = vec3(2.0, 3.0, 2.0);
uniform vec3 volume_position = vec3(0.0, 0.0, 0.0);

// Sim scaling
uniform float temp_scale     : hint_range(1.0, 20.0) = 8.0;
uniform float smoke_scale    : hint_range(1.0, 20.0) = 4.0;
uniform float density_mult   : hint_range(0.0, 5.0)  = 1.0;
uniform float emission_mult  : hint_range(0.0, 10.0) = 3.0;

// Height falloff — smoke fades at top
uniform float height_falloff : hint_range(0.0, 1.0) = 0.8;

// Fire colors
uniform vec3 color_hot   : source_color = vec3(1.0, 0.95, 0.6);
uniform vec3 color_mid   : source_color = vec3(1.0, 0.35, 0.05);
uniform vec3 color_smoke : source_color = vec3(0.12, 0.10, 0.09);

void fog() {
    // Convert world position to local UV relative to volume
    // UVW is 0..1 within the FogVolume bounds
    vec2 sim_uv = vec2(UVW.x, 1.0 - UVW.y); // flip Y so fire is at bottom

    // Sample 2D sim textures
    float raw_smoke = texture(sam_smoke, sim_uv).r;
    float raw_temp  = texture(sam_temp,  sim_uv).r;

    float smoke_n = clamp(raw_smoke / (smoke_scale * 32.0), 0.0, 1.0);
    float heat    = clamp(raw_temp  / (temp_scale  * 32.0), 0.0, 1.0);

    // Height-based falloff — upper smoke thins out
    float h = UVW.y; // 0=bottom, 1=top
    float falloff = 1.0 - smoothstep(height_falloff, 1.0, h);

    // Total density from both smoke and heat
    float total_density = clamp((smoke_n + heat * 0.5) * falloff, 0.0, 1.0);

    // Debug: always output some density so we know shader is running
    DENSITY = max(total_density * density_mult, 0.1);

    // Color — mix from smoke through orange to hot white based on temperature
    vec3 col = color_smoke;
    col = mix(col, color_mid, clamp(heat * 2.0, 0.0, 1.0));
    col = mix(col, color_hot, clamp(heat * 4.0 - 1.0, 0.0, 1.0));

    ALBEDO   = col;
    EMISSION = vec3(1.0, 0.0, 0.0) * 2.0; // DEBUG: red emission
}
