#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

// Vorticity confinement with separate epsilon for fire vs smoke.
// Samples temperature to determine fire/smoke weight at each cell,
// then lerps between epsilon_fire and epsilon_smoke accordingly.

layout(set=0, binding=0) uniform sampler2D u_vort;
layout(set=0, binding=1) uniform sampler2D u_vel;
layout(set=0, binding=2, rg32f) uniform writeonly image2D o_vel;
layout(set=0, binding=3) uniform sampler2D u_temp;   // to distinguish fire vs smoke

layout(push_constant, std430) uniform P {
    int   N;
    int   _pad;
    float dt;
    float epsilon_fire;   // vorticity strength for hot fire regions
    float epsilon_smoke;  // vorticity strength for cool smoke regions
    float temp_scale;     // normalisation — same as render shader (e.g. 8.0)
    float _p0; float _p1;
} p;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= p.N || id.y >= p.N) return;

    vec2 inv = vec2(1.0) / float(p.N);
    vec2 uv  = (vec2(id) + 0.5) / float(p.N);

    float omL = abs(texture(u_vort, uv + vec2(-inv.x, 0)).r);
    float omR = abs(texture(u_vort, uv + vec2( inv.x, 0)).r);
    float omB = abs(texture(u_vort, uv + vec2(0, -inv.y)).r);
    float omT = abs(texture(u_vort, uv + vec2(0,  inv.y)).r);

    float gx = 0.5 * (omR - omL);
    float gy = 0.5 * (omT - omB);

    float len = sqrt(gx*gx + gy*gy) + 1e-6;
    gx /= len; gy /= len;

    float omega = texture(u_vort, uv).r;

    // Heat at this cell — 0=pure smoke, 1=hot fire
    float heat = clamp(texture(u_temp, uv).r / p.temp_scale, 0.0, 1.0);

    // Blend epsilon: hot pixels use epsilon_fire, cool pixels use epsilon_smoke
    float epsilon = mix(p.epsilon_smoke, p.epsilon_fire, heat);

    vec2 force = epsilon * vec2(gy * omega, -gx * omega);
    vec2 vel   = texture(u_vel, uv).rg;
    vel += p.dt * force;

    imageStore(o_vel, id, vec4(vel, 0, 1));
}
