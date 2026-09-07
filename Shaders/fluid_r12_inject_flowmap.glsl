#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

// Flowmap velocity injection — additive acceleration, same as buoyancy.
// Two flowmaps blended by mix (0=flowmap1 only, 1=flowmap2 only).

layout(set=0, binding=0) uniform sampler2D u_velocity;
layout(set=0, binding=1) uniform sampler2D u_flowmap1;
layout(set=0, binding=2) uniform sampler2D u_flowmap2;
layout(set=0, binding=3, rg32f) uniform writeonly image2D o_velocity;

layout(push_constant, std430) uniform P {
    float strength;
    float scale;
    float dt;
    float bump;
    float mix;   // 0.0=flowmap1 only, 1.0=flowmap2 only
    float _p1; float _p2; float _p3;
} p;

vec2 decode(vec4 flow) {
    vec2 dir = (flow.rg - 0.5) * 2.0;
    dir.y = -dir.y;
    return sign(dir) * pow(abs(dir), vec2(1.0 / p.bump));
}

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    ivec2 sz = imageSize(o_velocity);
    if (id.x >= sz.x || id.y >= sz.y) return;

    vec2 uv      = (vec2(id) + 0.5) / vec2(sz);
    vec2 flow_uv = (uv - 0.5) / p.scale + 0.5;

    vec2 dir1 = decode(texture(u_flowmap1, flow_uv));
    vec2 dir2 = decode(texture(u_flowmap2, flow_uv));
    vec2 dir  = mix(dir1, dir2, p.mix);

    vec2 vel = texture(u_velocity, uv).rg;
    vel += dir * p.strength * p.dt;

    imageStore(o_velocity, id, vec4(vel, 0, 1));
}
