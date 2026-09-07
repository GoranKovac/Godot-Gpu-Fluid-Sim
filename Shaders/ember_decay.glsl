#[compute]
#version 450

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform image2D ember_tex;

layout(push_constant, std430) uniform PC {
    float decay;
    float _p0; float _p1; float _p2;
} p;

void main() {
    ivec2 px = ivec2(gl_GlobalInvocationID.xy);
    ivec2 size = imageSize(ember_tex);
    if (px.x >= size.x || px.y >= size.y) return;

    // Sample from 1 pixel below (embers rise, so trail should extend downward)
    ivec2 src = ivec2(px.x, px.y + 1);
    vec4 col = (src.y < size.y) ? imageLoad(ember_tex, src) : vec4(0.0);
    imageStore(ember_tex, px, col * p.decay);
}
