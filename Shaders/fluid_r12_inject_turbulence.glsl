#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

layout(set=0, binding=0) uniform sampler2D u_velocity;
layout(set=0, binding=1) uniform sampler2D u_noise;
layout(set=0, binding=2, rg32f) uniform writeonly image2D o_velocity;
layout(set=0, binding=3) uniform sampler2D u_temp;

layout(push_constant, std430) uniform P {
    float strength_x; float strength_y;
    float scroll_x; float scroll_y; float morph;
    int   mode; float buoyancy; float dt;
} p;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    ivec2 sz = imageSize(o_velocity);
    if (id.x >= sz.x || id.y >= sz.y) return;
    vec2 uv = (vec2(id) + 0.5) / vec2(sz);
    vec2 nuv = uv + vec2(p.scroll_x + p.morph*0.31, p.scroll_y + p.morph*0.17);
    float nx = texture(u_noise, nuv).r * 2.0 - 1.0;
    float ny = texture(u_noise, nuv + vec2(0.37, 0.63)).g * 2.0 - 1.0;
    float temp = texture(u_temp, uv).r;
    float heat_weight = clamp(temp * 0.018, 0.0, 1.0);
    float strength = (p.strength_x + p.strength_y) * 0.5;
    vec2 vel = texture(u_velocity, uv).rg;
    if (p.mode == 0) {
        vel += vec2(nx, ny) * strength * heat_weight;
    } else {
        float buoy_mag = p.buoyancy * temp * 0.018 * p.dt * strength;
        vec2 buoy_dir = normalize(vec2(nx * 0.5, -1.0));
        vel += buoy_dir * buoy_mag;
    }
    imageStore(o_velocity, id, vec4(vel, 0, 1));
}
