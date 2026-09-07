#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

// Wind — pure additive force masked by noise.
// Black pixels = zero force. White pixels = full wind force.
// Identical pattern to buoyancy: vel += dt * force * heat_weight

layout(set=0, binding=0) uniform sampler2D u_velocity;
layout(set=0, binding=1) uniform sampler2D u_noise;
layout(set=0, binding=2) uniform sampler2D u_temp;
layout(set=0, binding=3, rg32f) uniform writeonly image2D o_velocity;

layout(push_constant, std430) uniform P {
    float wind_x;
    float wind_y;
    float scroll_x;
    float scroll_y;
    float seed;
    float dt;
    float _p0; float _p1;
} p;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    ivec2 sz = imageSize(o_velocity);
    if (id.x >= sz.x || id.y >= sz.y) return;

    vec2 uv  = (vec2(id) + 0.5) / vec2(sz);
    vec2 vel = texture(u_velocity, uv).rg;

    float mask        = texture(u_noise, uv + vec2(p.scroll_x + p.seed*0.31, p.seed*0.17)).r;
    float temp        = texture(u_temp, uv).r;
    float heat_weight = clamp(temp * 0.018, 0.0, 1.0);

    vel += vec2(p.wind_x, p.wind_y) * mask * heat_weight * p.dt;

    imageStore(o_velocity, id, vec4(vel, 0, 1));
}
