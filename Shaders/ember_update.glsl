#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D sam_vel;
layout(set = 0, binding = 1) uniform sampler2D sam_temp;
layout(set = 0, binding = 2, std430) buffer EmberPos      { vec2  positions[8192]; };
layout(set = 0, binding = 3, std430) buffer EmberVel      { vec2  velocities[8192]; };
layout(set = 0, binding = 4, std430) buffer EmberAge      { float ages[8192]; };
layout(set = 0, binding = 5, std430) buffer EmberLifetime { float lifetimes[8192]; };
layout(set = 0, binding = 6, std430) buffer EmberSpread   { vec2  spread[8192]; };

layout(push_constant, std430) uniform PC {
    int   N;           // sim resolution
    float dt;          // delta time
    float vel_scale;   // velocity scale to screen space
    float gravity;     // upward force (negative = up)
    float drag;        // velocity drag per second
    float vel_follow;
    float spread_x;
    float _p0;
} p;

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= 8192u) return;

    float age = ages[id];
    if (age < 0.0) return; // dead

    age += p.dt;
    if (age >= lifetimes[id]) {
        ages[id] = -1.0; // kill
        return;
    }
    ages[id] = age;

    // Sample fluid velocity at ember position (UV 0..1)
    vec2 pos = positions[id];
    vec2 uv  = vec2(pos.x, 1.0 - pos.y); // flip Y for sim coords
    uv       = clamp(uv, 0.001, 0.999);

    vec2 fluid_vel = texture(sam_vel, uv).rg;
    fluid_vel.y = -fluid_vel.y; // flip Y: TextureRect has flip_v=true

    // Apply fluid velocity
    vec2 vel = velocities[id];
    vel += fluid_vel * p.vel_follow * p.dt;

    // Gravity in UV space: negative = up (toward y=0)
    vel.y -= p.gravity * p.dt; // flip: positive inspector value = up on screen

    // Drag
    vel *= 1.0 - p.drag * p.dt;

    // Persistent X spread in spawn direction
    vel.x += sign(spread[id].x) * p.spread_x * p.dt;
    vel.x = clamp(vel.x, -0.5, 0.5);

    velocities[id] = vel;
    pos += vel * p.dt;

    // Kill if out of bounds
    if (pos.x < 0.0 || pos.x > 1.0 || pos.y < 0.0 || pos.y > 1.0) {
        ages[id] = -1.0;
        return;
    }

    positions[id] = pos;
}
