#[compute]
#version 450
layout(local_size_x=16, local_size_y=16) in;

// Fire palette render — identical math to r6's fluid_render.glsl.
// Reads R32F temperature+smoke+velocity textures (N×N, no ghost border).
// XY swap: sim u=vertical(i), sim v=lateral(j).
// Screen px=col(horizontal), py=row(vertical).
// gi=py (sim i = screen row), gj=px (sim j = screen col).

layout(set=0, binding=0, rgba8) uniform writeonly image2D out_image;
layout(set=0, binding=1) uniform sampler2D sam_temp;
layout(set=0, binding=2) uniform sampler2D sam_smoke;
layout(set=0, binding=3) uniform sampler2D sam_vel;

layout(push_constant, std430) uniform P {
    int   N; int is_hellfire;
    float flame_height; float glow; float sparkle; float sim_time;
    float temp_scale; float smoke_scale; float vel_scale;
    float _p0; float _p1; float _p2;
} p;

void main() {
    int px = int(gl_GlobalInvocationID.x);
    int py = int(gl_GlobalInvocationID.y);
    if (px >= p.N || py >= p.N) return;

    // Texture X = col (horizontal) = px, Texture Y = row (upward) = py
    // py=0 (screen top) = sim row 0 (source near bottom), high py = high sim row (hot, rises)
    vec2 uv = (vec2(float(px), float(py)) + 0.5) / float(p.N);

    float tv   = clamp(texture(sam_temp,  uv).r, 0.0, 255.0);
    float sv   = clamp(texture(sam_smoke, uv).r, 0.0, 255.0);
    vec2  vel  = texture(sam_vel, uv).rg;
    float vmag = length(vel);

    float heat    = clamp((tv / p.temp_scale) * p.flame_height, 0.0, 1.0);
    float smoke_n = clamp(sv / p.smoke_scale, 0.0, 1.0);
    float sg      = (p.is_hellfire==1)
        ? clamp((vmag/p.vel_scale)*0.40*p.glow, 0.0,1.0)
        : clamp((vmag/p.vel_scale)*0.22*p.glow, 0.0,1.0);

    float r = clamp(heat*2.8 + smoke_n*0.24, 0.0,1.0);
    float g = clamp((heat-0.16)*2.2,          0.0,1.0);
    float b = clamp((heat-0.72)*3.6,          0.0,1.0);

    float hc;
    if (p.is_hellfire==1) {
        hc=clamp((heat-0.78)*4.5,0.0,1.0);
        r=clamp(r+hc*0.35,0.0,1.0); g=clamp(g+hc*0.45,0.0,1.0); b=clamp(b+hc*0.70,0.0,1.0);
    } else {
        hc=clamp((heat-0.84)*5.4,0.0,1.0);
        r=clamp(r+hc*0.24,0.0,1.0); g=clamp(g+hc*0.34,0.0,1.0); b=clamp(b+hc*0.54,0.0,1.0);
    }

    float cm=clamp(smoke_n*(1.0-heat*0.75),0.0,1.0); float gray;
    if (p.is_hellfire==1) {
        gray=smoke_n*0.20;
        r=clamp(r*(1.0-cm*0.48)+gray,    0.0,1.0);
        g=clamp(g*(1.0-cm*0.62)+gray,    0.0,1.0);
        b=clamp(b*(1.0-cm*0.82)+gray*0.8,0.0,1.0);
    } else {
        gray=smoke_n*0.16;
        r=clamp(r*(1.0-cm*0.44)+gray,     0.0,1.0);
        g=clamp(g*(1.0-cm*0.58)+gray,     0.0,1.0);
        b=clamp(b*(1.0-cm*0.80)+gray*0.72,0.0,1.0);
    }

    if (p.sparkle>0.0) {
        float sf=clamp((sin(float(py)*0.37+p.sim_time*17.0)*cos(float(px)*0.29+p.sim_time*11.0)*0.5+0.5)*p.sparkle,0.0,1.0);
        float ht=(p.is_hellfire==1)?0.62:0.72; float hs=(p.is_hellfire==1)?2.2:2.0;
        float hm=clamp((heat-ht)*hs,0.0,1.0);
        r=clamp(r+sf*hm*((p.is_hellfire==1)?0.12:0.08),0.0,1.0);
        g=clamp(g+sf*hm*((p.is_hellfire==1)?0.10:0.06),0.0,1.0);
    }

    float br=(p.is_hellfire==1)
        ?clamp(0.18+heat*1.35+sg,0.0,1.55)
        :clamp(0.10+heat*1.08+sg,0.0,1.30);

    imageStore(out_image, ivec2(px,py), vec4(clamp(r*br,0.0,1.0),clamp(g*br,0.0,1.0),clamp(b*br,0.0,1.0),1.0));
}
