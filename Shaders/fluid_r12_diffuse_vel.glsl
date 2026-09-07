#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

// Velocity diffuse (viscosity). RG32F packed u+v.
// u_vel = current estimate (read neighbors), u_vel0 = rhs (snapshot before diffuse)
// o_vel = output (always different texture from inputs)

layout(set=0, binding=0) uniform sampler2D u_vel;   // current [0]
layout(set=0, binding=1) uniform sampler2D u_vel0;  // rhs snapshot [prev_0 before diffuse started]
layout(set=0, binding=2, rg32f) uniform writeonly image2D o_vel;

layout(push_constant, std430) uniform P {
    int   N; int _pad;
    float a;      // dt * viscosity * N^2
    float inv_c;  // 1.0 / (1.0 + 4.0*a)
} p;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= p.N || id.y >= p.N) return;

    vec2 uv  = (vec2(id) + 0.5) / float(p.N);
    vec2 inv = vec2(1.0) / float(p.N);

    vec2 vL = texture(u_vel, uv + vec2(-inv.x, 0)).rg;
    vec2 vR = texture(u_vel, uv + vec2( inv.x, 0)).rg;
    vec2 vB = texture(u_vel, uv + vec2(0, -inv.y)).rg;
    vec2 vT = texture(u_vel, uv + vec2(0,  inv.y)).rg;
    vec2 v0 = texture(u_vel0, uv).rg;

    imageStore(o_vel, id, vec4((v0 + p.a*(vL+vR+vB+vT))*p.inv_c, 0,1));
}
