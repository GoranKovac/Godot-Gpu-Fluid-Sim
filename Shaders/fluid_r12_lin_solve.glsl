#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

// Jacobi iteration for scalar diffuse AND pressure solve.
// Read from u_x (sampler), write to o_x (image). Always different textures.
// Caller does _sw() after each iteration so [0]=current, [1]=scratch always.
// CLAMP_TO_EDGE on sampler = implicit Neumann BC on every neighbor read.

layout(set=0, binding=0) uniform sampler2D u_x;   // current estimate
layout(set=0, binding=1) uniform sampler2D u_x0;  // rhs (fixed, never written)
layout(set=0, binding=2, r16f) uniform writeonly image2D o_x;

layout(push_constant, std430) uniform P {
    int   N;
    int   _pad;
    float a;
    float inv_c;
} p;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= p.N || id.y >= p.N) return;

    vec2 uv  = (vec2(id) + 0.5) / float(p.N);
    vec2 inv = vec2(1.0) / float(p.N);

    float xL = texture(u_x, uv + vec2(-inv.x,     0)).r;
    float xR = texture(u_x, uv + vec2( inv.x,     0)).r;
    float xB = texture(u_x, uv + vec2(     0, -inv.y)).r;
    float xT = texture(u_x, uv + vec2(     0,  inv.y)).r;
    float x0 = texture(u_x0, uv).r;

    imageStore(o_x, id, vec4((x0 + p.a*(xL+xR+xB+xT))*p.inv_c, 0,0,1));
}
