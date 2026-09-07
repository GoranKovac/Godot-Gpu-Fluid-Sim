#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

layout(set=0, binding=0) uniform sampler2D u_vel;
layout(set=0, binding=1) uniform sampler2D u_pressure;
layout(set=0, binding=2, rg32f) uniform writeonly image2D o_vel;

layout(push_constant, std430) uniform P {
    int N; float _p0; float _p1; float _p2;
} p;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= p.N || id.y >= p.N) return;

    vec2 uv  = (vec2(id) + 0.5) / float(p.N);
    vec2 inv = vec2(1.0) / float(p.N);

    float pL = texture(u_pressure, uv + vec2(-inv.x, 0)).r;
    float pR = texture(u_pressure, uv + vec2( inv.x, 0)).r;
    float pB = texture(u_pressure, uv + vec2(0, -inv.y)).r;
    float pT = texture(u_pressure, uv + vec2(0,  inv.y)).r;

    vec2 vel = texture(u_vel, uv).rg;
    vel -= 0.5 * float(p.N) * vec2(pR - pL, pT - pB);

    // No-slip at walls — matches r6 set_bnd(1) and set_bnd(2)
    if (id.x == 0 || id.x == p.N-1) vel.x = 0.0;
    if (id.y == 0 || id.y == p.N-1) vel.y = 0.0;

    imageStore(o_vel, id, vec4(vel, 0,1));
}
