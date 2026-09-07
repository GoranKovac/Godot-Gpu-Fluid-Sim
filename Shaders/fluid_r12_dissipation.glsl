#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

layout(push_constant, std430) uniform P {
    int   N;
    float vel_diss;
    float smoke_diss;
    float temp_diss;
} p;

layout(set=0, binding=0) uniform sampler2D u_vel;
layout(set=0, binding=1) uniform sampler2D u_temp;
layout(set=0, binding=2) uniform sampler2D u_smoke;
layout(set=0, binding=3, rg32f) uniform writeonly image2D o_vel;
layout(set=0, binding=4, r16f)  uniform writeonly image2D o_temp;
layout(set=0, binding=5, r16f)  uniform writeonly image2D o_smoke;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= p.N || id.y >= p.N) return;

    vec2 uv = (vec2(id) + 0.5) / float(p.N);

    vec2  v = texture(u_vel,   uv).rg * p.vel_diss;
    float t = max(texture(u_temp,  uv).r * p.temp_diss,  0.0);
    float s = max(texture(u_smoke, uv).r * p.smoke_diss, 0.0);

    imageStore(o_vel,   id, vec4(v,  0,1));
    imageStore(o_temp,  id, vec4(t,  0,0,1));
    imageStore(o_smoke, id, vec4(s,  0,0,1));
}
