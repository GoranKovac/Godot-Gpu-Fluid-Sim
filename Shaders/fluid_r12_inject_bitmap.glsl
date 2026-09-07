#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

layout(push_constant, std430) uniform P {
    int   N;
    float base_temp;
    float base_smoke;
    float upward;
    float jitter;
    float sim_time;
    float threshold;
    float source_scale;
    int   use_flowmap;   // 1 = redirect upward force along flowmap direction
    float flowmap_scale;
    float _p0; float _p1;
} p;

layout(set=0, binding=0) uniform sampler2D u_vel;
layout(set=0, binding=1) uniform sampler2D u_temp;
layout(set=0, binding=2) uniform sampler2D u_smoke;
layout(set=0, binding=3, rg32f) uniform writeonly image2D o_vel;
layout(set=0, binding=4, r16f)  uniform writeonly image2D o_temp;
layout(set=0, binding=5, r16f)  uniform writeonly image2D o_smoke;
layout(set=0, binding=6) uniform sampler2D emitter_tex;
layout(set=0, binding=7) uniform sampler2D flowmap_tex;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= p.N || id.y >= p.N) return;

    vec2 uv = (vec2(id) + 0.5) / float(p.N);

    vec2  vel_v  = texture(u_vel,   uv).rg;
    float temp_v = texture(u_temp,  uv).r;
    float smk_v  = texture(u_smoke, uv).r;

    // Sample emitter viewport — use lum*alpha as weight for soft gradient edges
    vec4  px     = texture(emitter_tex, uv);
    float lum    = (px.r + px.g + px.b) / 3.0;
    float weight = lum * px.a;

    if (weight >= p.threshold) {
        temp_v += p.base_temp  * p.source_scale * weight;
        smk_v  += p.base_smoke * p.source_scale * weight;

        if (p.use_flowmap == 1) {
            vec2 flow_uv = (uv - 0.5) / p.flowmap_scale + 0.5;
            vec4 flow    = texture(flowmap_tex, flow_uv);
            vec2 dir     = (flow.rg - 0.5) * 2.0;
            dir.y        = -dir.y;
            float mag    = length(dir);
            if (mag > 0.001) dir /= mag;
            vel_v += dir * p.upward * weight;
        } else {
            vel_v.y += -p.upward * weight;
        }
    }

    imageStore(o_vel,   id, vec4(vel_v,  0,1));
    imageStore(o_temp,  id, vec4(temp_v, 0,0,1));
    imageStore(o_smoke, id, vec4(smk_v,  0,0,1));
}
