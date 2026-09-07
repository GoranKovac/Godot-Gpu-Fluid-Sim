#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

// Flowmap velocity injection — BUOYANCY MODE v2.
// Temperature weighting uses identical scaling to buoyancy: temp * 0.018
// This means flowmap_strength is on the same scale as buoyancy slider.
// If buoyancy=6.2, flowmap_strength=6.2 gives equal force in flowmap direction.
// No separate temp_scale slider needed.

layout(set=0, binding=0) uniform sampler2D u_velocity;
layout(set=0, binding=1) uniform sampler2D u_flowmap1;
layout(set=0, binding=2) uniform sampler2D u_flowmap2;
layout(set=0, binding=3) uniform sampler2D u_temperature;
layout(set=0, binding=4, rg32f) uniform writeonly image2D o_velocity;

layout(push_constant, std430) uniform P {
    float strength;
    float scale;
    float dt;
    float bump;
    float mix;
    float _p0; float _p1; float _p2;
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

    // Identical weighting to buoyancy: vel.y += -dt * buoyancy * temp * 0.018
    float temp        = texture(u_temperature, uv).r;
    float heat_weight = temp * 0.018;

    vec2 vel = texture(u_velocity, uv).rg;
    vel += dir * p.strength * p.dt * heat_weight;

    imageStore(o_velocity, id, vec4(vel, 0, 1));
}
