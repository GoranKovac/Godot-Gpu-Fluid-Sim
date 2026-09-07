#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

// Turbulence — curl noise with NORMALIZED magnitude.
// curl direction creates rotational motion (curls/tendrils), not bulk translation.
// normalize(curl) keeps force magnitude constant regardless of field values,
// preventing vorticity feedback regardless of strength setting.

layout(set=0, binding=0) uniform sampler2D u_velocity;
layout(set=0, binding=1) uniform sampler2D u_noise;
layout(set=0, binding=2, rg32f) uniform writeonly image2D o_velocity;
layout(set=0, binding=3) uniform sampler2D u_temp;

layout(push_constant, std430) uniform P {
    float strength_x;
    float strength_y;
    float scroll_x;
    float scroll_y;
    float morph;
    float _p5; float _p6; float _p7;
} p;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    ivec2 sz = imageSize(o_velocity);
    if (id.x >= sz.x || id.y >= sz.y) return;

    vec2 uv  = (vec2(id) + 0.5) / vec2(sz);
    vec2 ts  = 1.0 / vec2(sz);  // texel size for finite differences

    vec2 nuv = uv + vec2(p.scroll_x + p.morph * 0.31,
                         p.scroll_y + p.morph * 0.17);

    // ── Curl from noise channel R ─────────────────────────────────────────
    // curl = (dn/dy, -dn/dx) — perpendicular to gradient = rotational force
    float n_c  = texture(u_noise, nuv).r;
    float n_dx = texture(u_noise, nuv + vec2(ts.x, 0.0)).r;
    float n_dy = texture(u_noise, nuv + vec2(0.0, ts.y)).r;
    vec2 curl_a = vec2(-(n_dy - n_c), (n_dx - n_c));

    // ── Second curl from noise channel G (offset UV) ──────────────────────
    vec2  nuv2  = nuv + vec2(0.37, 0.63);
    float n2_c  = texture(u_noise, nuv2).g;
    float n2_dx = texture(u_noise, nuv2 + vec2(ts.x, 0.0)).g;
    float n2_dy = texture(u_noise, nuv2 + vec2(0.0, ts.y)).g;
    vec2 curl_b = vec2(-(n2_dy - n2_c), (n2_dx - n2_c));

    vec2 curl = (curl_a + curl_b) * 0.5;

    // ── Temperature weighting — only affect hot regions ───────────────────
    float temp        = texture(u_temp, uv).r;
    float heat_weight = clamp(temp * 0.018, 0.0, 1.0);

    float strength = (p.strength_x + p.strength_y) * 0.5;

    // NORMALIZE: consistent small magnitude, no vorticity feedback
    vec2 curl_dir = length(curl) > 0.0001 ? normalize(curl) : vec2(0.0);

    vec2 vel = texture(u_velocity, uv).rg;
    vel += curl_dir * strength * heat_weight;

    imageStore(o_velocity, id, vec4(vel, 0, 1));
}
