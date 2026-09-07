#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

// RK2 + MacCormack velocity advection.
// Reads vel[0] (source AND velocity field — same texture, read-only).
// Writes to vel[1] (output — different texture).
// After dispatch caller does _sw(vel).

layout(set=0, binding=0) uniform sampler2D u_vel;    // current velocity (read)
layout(set=0, binding=1) uniform sampler2D u_src;    // source snapshot (same as u_vel after copy)
layout(set=0, binding=2, rg32f) uniform writeonly image2D o_vel;

layout(push_constant, std430) uniform P {
    int N; int _pad; float dt0; float _pf;
} p;

vec2 uv(vec2 pos) { return (pos + 0.5) / float(p.N); }
vec2 vel(vec2 pos) { return texture(u_vel, uv(pos)).rg; }
vec2 src(vec2 pos) { return texture(u_src, uv(pos)).rg; }

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= p.N || id.y >= p.N) return;

    vec2 pos = vec2(id);  // integer cell coords

    // RK2 backtrace
    vec2 k1  = vel(pos);
    vec2 k2  = vel(pos - 0.5*p.dt0*k1);
    vec2 pb  = clamp(pos - p.dt0*k2, vec2(0), vec2(p.N-1));

    // MacCormack
    vec2 hat   = src(pb);
    vec2 k2f   = vel(pb + 0.5*p.dt0*vel(pb));
    vec2 pf    = clamp(pb + p.dt0*k2f, vec2(0), vec2(p.N-1));
    vec2 check = src(pf);
    vec2 corr  = hat + 0.5*(src(pos) - check);

    // Neighbourhood clamp
    vec2 n0=src(pb+vec2(-1,0)), n1=src(pb+vec2(1,0));
    vec2 n2=src(pb+vec2(0,-1)), n3=src(pb+vec2(0,1));
    vec2 lo=min(min(n0,n1),min(n2,n3)), hi=max(max(n0,n1),max(n2,n3));
    vec2 res = (any(lessThan(corr,lo))||any(greaterThan(corr,hi))) ? hat : corr;

    // No-slip at walls
    if (id.x==0||id.x==p.N-1) res.x=0.0;
    if (id.y==0||id.y==p.N-1) res.y=0.0;

    imageStore(o_vel, id, vec4(res, 0,1));
}
