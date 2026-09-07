#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

// Vorticity pass 0: compute curl from velocity, write to vort texture.
// vort is a single texture (not ping-pong) — written fresh each frame.

layout(set=0, binding=0) uniform sampler2D u_vel;
layout(set=0, binding=1, r16f) uniform writeonly image2D o_vort;

layout(push_constant, std430) uniform P {
    int N; float _p0; float _p1; float _p2;
} p;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= p.N || id.y >= p.N) return;

    vec2 inv = vec2(1.0) / float(p.N);
    vec2 uv  = (vec2(id) + 0.5) / float(p.N);

    vec2 vL = texture(u_vel, uv + vec2(-inv.x, 0)).rg;
    vec2 vR = texture(u_vel, uv + vec2( inv.x, 0)).rg;
    vec2 vB = texture(u_vel, uv + vec2(0, -inv.y)).rg;
    vec2 vT = texture(u_vel, uv + vec2(0,  inv.y)).rg;

    // curl = dv/dx - du/dy  (2D scalar vorticity)
    float c = 0.5*((vR.y - vL.y) - (vT.x - vB.x));
    imageStore(o_vort, id, vec4(c, 0,0,1));
}
