#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D sam_temp;
layout(set = 0, binding = 1, std430) buffer EmberPos      { vec2  positions[8192]; };
layout(set = 0, binding = 2, std430) buffer EmberVel      { vec2  velocities[8192]; };
layout(set = 0, binding = 3, std430) buffer EmberAge      { float ages[8192]; };
layout(set = 0, binding = 4, std430) buffer EmberLifetime { float lifetimes[8192]; };
layout(set = 0, binding = 5, std430) buffer SpawnCounter  { int   counter; };
layout(set = 0, binding = 6, std430) buffer EmberSpread   { vec2  spread[8192]; };

layout(push_constant, std430) uniform PC {
    int   N;
    float temp_scale;
    float spawn_threshold;
    float min_lifetime;
    float max_lifetime;
    float sim_time;
    float spawn_amount;
    int   max_particles;
} p;

// Simple hash for pseudo-random
float hash(float n) { return fract(sin(n) * 43758.5453123); }
float hash2(vec2 v) { return hash(dot(v, vec2(127.1, 311.7))); }

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= 8192u) return;
    if (int(id) >= p.max_particles) return;

    // Only try to spawn in dead slots
    if (ages[id] >= 0.0) return;

    // Probabilistic spawn — controls density
    float seed_chance = float(id) * 0.001 + p.sim_time * 7.3;
    if (p.spawn_amount <= 0.0001 || hash(seed_chance) > p.spawn_amount) return;

    // Random UV to sample temperature
    float seed = float(id) + p.sim_time * 13.7;
    float rx = hash(seed);
    float ry = hash(seed + 1.3);
    vec2 uv = vec2(rx, ry);

    // Check temperature at this position
    float temp = texture(sam_temp, uv).r;
    if (temp < p.spawn_threshold * p.temp_scale) return;

    // Spawn ember here
    positions[id] = vec2(rx, 1.0 - ry);
    float vx = (hash(seed + 2.7) - 0.5) * 0.02;
    float vy = (hash(seed + 3.1) * 0.03 + 0.01);
    ages[id]      = 0.0;
    lifetimes[id] = p.min_lifetime + hash(seed + 4.5) * (p.max_lifetime - p.min_lifetime);
    // Write spread FIRST
    float x_dir = hash(seed + 6.1) > 0.5 ? 1.0 : -1.0;
    float x_mag = hash(seed + 7.2) * 0.1 + 0.05;
    spread[id] = vec2(x_dir * x_mag, pow(0.3 + hash(seed + 8.3) * 0.7, 5.0));
    // Then set velocity using local variables (not spread buffer read)
    velocities[id] = vec2(x_dir * x_mag * 2.0, vy);
}
