#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

// Emit point sources + buoyancy + cooling.
// Reads current fields via sampler (binding 0,1,2).
// Writes to DIFFERENT output textures via image (binding 3,4,5).
// Caller does _sw(vel), _sw(temp), _sw(smoke) after dispatch.

layout(push_constant, std430) uniform P {
    int   N;
    float dt;
    float buoyancy;
    float cooling;
    float smoke_from_cooling;
    float max_velocity;
    float _pad0; float _pad1;
} p;

layout(set=0, binding=0) uniform sampler2D u_vel;
layout(set=0, binding=1) uniform sampler2D u_temp;
layout(set=0, binding=2) uniform sampler2D u_smoke;
layout(set=0, binding=3, rg32f) uniform writeonly image2D o_vel;
layout(set=0, binding=4, r16f)  uniform writeonly image2D o_temp;
layout(set=0, binding=5, r16f)  uniform writeonly image2D o_smoke;
layout(set=0, binding=6, std430) buffer BufSources { float sources[]; };

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= p.N || id.y >= p.N) return;

    // i,j are 0-based here (no ghost border in r12)
    // Sources are stored with 1-based coords from r6 — subtract 1 to match
    vec2 uv = (vec2(id) + 0.5) / float(p.N);

    vec2  vel_v  = texture(u_vel,   uv).rg;
    float temp_v = texture(u_temp,  uv).r;
    float smk_v  = texture(u_smoke, uv).r;

    // Point sources — stored as 1-based (i,j) from r6, convert to 0-based
    for (int s = 0; s < 7; s++) {
        int si = int(sources[s*6+0]) - 1;  // convert 1-based → 0-based
        int sj = int(sources[s*6+1]) - 1;
        if (si == id.x && sj == id.y) {
            temp_v  += sources[s*6+2];
            smk_v   += sources[s*6+3];
            vel_v.y += sources[s*6+4];  // upward velocity → .y (vertical)
        }
    }

    // Buoyancy — upward force goes into .y (texture Y = vertical axis)
    // Buoyancy — negative values push fluid downward
    if (p.buoyancy != 0.0)
        vel_v.y += -p.dt * p.buoyancy * (temp_v * 0.018 + smk_v * 0.0022);

    // Velocity clamp — clamp vertical component
    if (p.max_velocity > 0.0)
        vel_v.y = clamp(vel_v.y, -p.max_velocity, p.max_velocity);

    // Cooling + smoke from cooling
    if (p.cooling < 1.0) {
        float prev_t = temp_v;
        temp_v *= p.cooling;
        float lost = max(prev_t - temp_v, 0.0);
        if (p.smoke_from_cooling > 0.0)
            smk_v += lost * p.smoke_from_cooling * p.dt * 0.35;
    }

    temp_v = max(temp_v, 0.0);
    smk_v  = max(smk_v,  0.0);

    imageStore(o_vel,   id, vec4(vel_v,  0,1));
    imageStore(o_temp,  id, vec4(temp_v, 0,0,1));
    imageStore(o_smoke, id, vec4(smk_v,  0,0,1));
}
