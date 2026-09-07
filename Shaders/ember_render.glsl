#[compute]
#version 450

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform image2D out_image;
layout(set = 0, binding = 1, std430) buffer EmberPos      { vec2  positions[8192]; };
layout(set = 0, binding = 2, std430) buffer EmberAge      { float ages[8192]; };
layout(set = 0, binding = 3, std430) buffer EmberLifetime { float lifetimes[8192]; };
layout(set = 0, binding = 5, std430) buffer EmberSpread   { vec2  spread[8192]; };
layout(set = 0, binding = 4) uniform sampler2D ember_tex;

// We need velocity to rotate the stretch axis
layout(set = 0, binding = 6, std430) buffer EmberVel { vec2 velocities[8192]; };

layout(push_constant, std430) uniform PC {
    int   N;
    float ember_size;
    float hot_duration;
    float use_texture;
    int   max_particles;
    float trail_stretch; // 1=circle, >1=elongated along velocity
    float _p1; float _p2;
    float _pad0; float _pad1; float _pad2;
    float _pad3; float _pad4; float _pad5;
    float _pad6; float _pad7; float _pad8;
    float _pad9; float _pad10; float _pad11;
} p;

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= 8192u) return;
    if (int(id) >= p.max_particles) return;

    float age = ages[id];
    if (age < 0.0) return;

    float t           = age / lifetimes[id];
    float size_factor = spread[id].y;
    float sz          = p.ember_size * size_factor * (1.0 - t * 0.5);

    float cool_t = clamp((t - p.hot_duration) / (1.0 - p.hot_duration + 0.001), 0.0, 1.0);
    float hot_i  = (t < p.hot_duration) ? 1.0 : (1.0 - cool_t);

    vec2 center = vec2(positions[id].x, 1.0 - positions[id].y) * float(p.N);

    // Velocity direction for stretch axis — normalize, fallback to up if zero
    vec2 vel = velocities[id];
    float vlen = length(vel);
    // Flip Y because texture Y is inverted vs sim Y
    vec2 vdir = (vlen > 0.0001) ? vec2(vel.x, -vel.y) / vlen : vec2(0.0, -1.0);
    // Perpendicular axis (width direction)
    vec2 perp = vec2(-vdir.y, vdir.x);

    float stretch = max(p.trail_stretch, 1.0);
    int radius_w = int(ceil(sz * 2.0));
    int radius_h = int(ceil(sz * 2.0 * stretch));

    for (int dy = -radius_h; dy <= radius_h; dy++) {
        for (int dx = -radius_w; dx <= radius_w; dx++) {
            ivec2 px = ivec2(int(center.x) + dx, int(center.y) + dy);
            if (px.x < 0 || px.x >= p.N || px.y < 0 || px.y >= p.N) continue;

            float falloff;
            if (p.use_texture > 0.5) {
                vec2 offset = vec2(float(dx), float(dy));
                float along  = dot(offset, vdir) / stretch;
                float across = dot(offset, perp);
                vec2 local_uv = vec2(across, along) / (sz * 2.0) * 0.5 + 0.5;
                if (local_uv.x < 0.0 || local_uv.x > 1.0 || local_uv.y < 0.0 || local_uv.y > 1.0) continue;
                vec4 tex_col = texture(ember_tex, local_uv);
                falloff = (tex_col.r + tex_col.g + tex_col.b) / 3.0 * tex_col.a;
                if (tex_col.a < 0.01) continue;
            } else {
                // Project offset onto velocity axis and perp axis
                vec2 offset = vec2(float(dx), float(dy));
                float along = dot(offset, vdir);   // distance along velocity
                float across = dot(offset, perp);  // distance across velocity
                // Compress along-axis by stretch so shape extends in velocity direction
                float dist = sqrt((along / stretch) * (along / stretch) + across * across);
                float nd = dist / (sz * 2.0);
                if (nd > 1.0) continue;
                float core = exp(-nd * nd * 16.0);
                float halo = exp(-nd * nd *  2.5) * 0.45;
                falloff = clamp(core + halo, 0.0, 1.0);
            }

            if (falloff < 0.001) continue;

            float flicker = fract(sin(float(id) * 127.1 + ages[id] * 311.7) * 43758.5);
            vec4 incoming = vec4(hot_i * falloff, t * falloff, flicker, falloff);
            vec4 existing = imageLoad(out_image, px);
            if (incoming.a > existing.a) {
                imageStore(out_image, px, incoming);
            }
        }
    }
}
