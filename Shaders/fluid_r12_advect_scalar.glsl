#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

layout(set=0, binding=0) uniform sampler2D u_vel;
layout(set=0, binding=1) uniform sampler2D u_src;
layout(set=0, binding=2, r16f) uniform writeonly image2D o_out;

layout(push_constant, std430) uniform P {
    int N; int _pad; float dt0; float _pf;
} p;

vec2 uv(vec2 pos) { return (pos + 0.5) / float(p.N); }
vec2 vel(vec2 pos) { return texture(u_vel, uv(pos)).rg; }
float d(vec2 pos) { return texture(u_src, uv(pos)).r; }

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= p.N || id.y >= p.N) return;

    vec2 pos = vec2(id);

    vec2  k1  = vel(pos);
    vec2  k2  = vel(pos - 0.5*p.dt0*k1);
    vec2  pb  = clamp(pos - p.dt0*k2, vec2(0), vec2(p.N-1));

    float hat   = d(pb);
    vec2  k2f   = vel(pb + 0.5*p.dt0*vel(pb));
    vec2  pf    = clamp(pb + p.dt0*k2f, vec2(0), vec2(p.N-1));
    float check = d(pf);
    float corr  = hat + 0.5*(d(pos) - check);

    float n0=d(pb+vec2(-1,0)), n1=d(pb+vec2(1,0));
    float n2=d(pb+vec2(0,-1)), n3=d(pb+vec2(0,1));
    float lo=min(min(n0,n1),min(n2,n3)), hi=max(max(n0,n1),max(n2,n3));
    float res = (corr<lo||corr>hi) ? hat : corr;

    imageStore(o_out, id, vec4(max(res,0.0), 0,0,1));
}
