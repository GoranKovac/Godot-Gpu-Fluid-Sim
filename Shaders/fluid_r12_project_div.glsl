#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

layout(set=0, binding=0) uniform sampler2D u_vel;
layout(set=0, binding=1, r16f) uniform writeonly image2D o_div;
layout(set=0, binding=2, r16f) uniform writeonly image2D o_pressure;

layout(push_constant, std430) uniform P {
    int N; float _p0; float _p1; float _p2;
} p;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= p.N || id.y >= p.N) return;

    vec2 uv  = (vec2(id) + 0.5) / float(p.N);
    vec2 inv = vec2(1.0) / float(p.N);

    float uL = texture(u_vel, uv + vec2(-inv.x, 0)).r;
    float uR = texture(u_vel, uv + vec2( inv.x, 0)).r;
    float vB = texture(u_vel, uv + vec2(0, -inv.y)).g;
    float vT = texture(u_vel, uv + vec2(0,  inv.y)).g;

    float div = -0.5 * (uR - uL + vT - vB) / float(p.N);
    imageStore(o_div,      id, vec4(div, 0,0,1));
    imageStore(o_pressure, id, vec4(0.0, 0,0,1));
}
