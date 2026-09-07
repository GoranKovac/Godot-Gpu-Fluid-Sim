#[compute]
#version 450
layout(local_size_x=8, local_size_y=8) in;

// Additively blends up to 4 flowmap textures.
// Each slot: sample RG (direction), multiply by mix weight, accumulate.
// Result clamped to [0,1] — use flowmap_bump in injection to control strength.

layout(set=0, binding=0) uniform sampler2D fm0;
layout(set=0, binding=1) uniform sampler2D fm1;
layout(set=0, binding=2) uniform sampler2D fm2;
layout(set=0, binding=3) uniform sampler2D fm3;
layout(set=0, binding=4, rgba16f) uniform writeonly image2D o_blend;

layout(push_constant, std430) uniform P {
    int   N;
    float mix0;
    float mix1;
    float mix2;
    float mix3;
    float _p0; float _p1; float _p2;
} p;

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    if (id.x >= p.N || id.y >= p.N) return;
    vec2 uv = (vec2(id) + 0.5) / float(p.N);

    vec4 result = vec4(0.5, 0.5, 0.0, 1.0);  // neutral = no flow

    if (p.mix0 > 0.0) {
        vec4 s = texture(fm0, uv);
        result.rg += (s.rg - 0.5) * p.mix0;
    }
    if (p.mix1 > 0.0) {
        vec4 s = texture(fm1, uv);
        result.rg += (s.rg - 0.5) * p.mix1;
    }
    if (p.mix2 > 0.0) {
        vec4 s = texture(fm2, uv);
        result.rg += (s.rg - 0.5) * p.mix2;
    }
    if (p.mix3 > 0.0) {
        vec4 s = texture(fm3, uv);
        result.rg += (s.rg - 0.5) * p.mix3;
    }

    // Clamp back to [0,1] range
    result.rg = clamp(result.rg, 0.0, 1.0);
    imageStore(o_blend, id, result);
}
