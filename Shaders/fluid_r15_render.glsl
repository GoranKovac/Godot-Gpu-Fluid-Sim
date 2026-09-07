#[compute]
#version 450
layout(local_size_x=16, local_size_y=16) in;

layout(set=0, binding=0, rgba8) uniform writeonly image2D out_image;
layout(set=0, binding=1) uniform sampler2D sam_temp;
layout(set=0, binding=2) uniform sampler2D sam_smoke;
layout(set=0, binding=3) uniform sampler2D sam_vel;
layout(set=0, binding=4) uniform sampler2D sam_flowmap;

layout(push_constant, std430) uniform P {
    int   N; int is_hellfire;
    float flame_height; float glow;
    int   display_mode;  // 0=normal 1=velocity 2=temperature 3=smoke 4=flowmap+vel overlay
    float _pad0;
    float temp_scale; float smoke_scale; float vel_scale;
    float flowmap_scale;
    float pixelize_size; // 0=off, >0=snap UV to pixel grid (retro look)
    float _p_cart;       // reserved
    float hue_shift;    // hue rotation 0..1 = full circle
    float saturation;   // colour richness: 1=normal, 0=greyscale, >1=vivid
    float _p2; float _p3;
} p;

void main() {
    int px = int(gl_GlobalInvocationID.x);
    int py = int(gl_GlobalInvocationID.y);
    if (px >= p.N || py >= p.N) return;

    vec2 uv  = (vec2(float(px), float(py)) + 0.5) / float(p.N);
    vec4 out_col;

    // ── Debug: Velocity ───────────────────────────────────────────────────────
    if (p.display_mode == 1) {
        vec2 vel = texture(sam_vel, uv).rg;
        // Remap: 0=gray(no flow), red=rightward, green=upward
        // Divide by small value to make subtle velocities visible
        vec2 v = clamp(vel / 0.3, -1.0, 1.0) * 0.5 + 0.5;
        out_col = vec4(v.x, v.y, 0.5, 1.0);

    // ── Debug: Temperature ────────────────────────────────────────────────────
    } else if (p.display_mode == 2) {
        float tv = clamp(texture(sam_temp, uv).r / p.temp_scale, 0.0, 1.0);
        out_col = vec4(tv, tv, tv, 1.0);

    // ── Debug: Smoke ──────────────────────────────────────────────────────────
    } else if (p.display_mode == 3) {
        float sv = clamp(texture(sam_smoke, uv).r / p.smoke_scale, 0.0, 1.0);
        out_col = vec4(sv, sv, sv, 1.0);

    // ── Debug: Flowmap + Velocity arrow overlay ───────────────────────────────
    } else if (p.display_mode == 4) {
        // Background: flowmap RG as direction colors
        vec2 flow_uv = (uv - 0.5) / p.flowmap_scale + 0.5;
        vec4 flow = texture(sam_flowmap, flow_uv);
        float fvx = (flow.r - 0.5) * 2.0;
        float fvy = (flow.g - 0.5) * 2.0;
        vec3 bg = vec3(clamp(fvx*0.5+0.5,0.0,1.0), clamp(fvy*0.5+0.5,0.0,1.0), 0.5);

        // Arrow grid — identical logic to old project
        float grid = 32.0;
        float Nf = float(p.N);
        vec2 cell     = floor(vec2(float(px), float(py)) / grid);
        vec2 cell_uv  = (cell * grid + grid * 0.5) / Nf;
        vec2 vel      = texture(sam_vel, cell_uv).rg * 0.3;  // scale for arrow length
        vec2 local    = (vec2(float(px), float(py)) - (cell * grid + grid * 0.5)) / grid;

        float arrow_len = length(vel) * 8.0;
        vec2 vel_dir = length(vel) > 0.0001 ? normalize(vel) : vec2(0.0);
        float proj = dot(local, vel_dir);
        float perp = abs(dot(local, vec2(-vel_dir.y, vel_dir.x)));
        float on_arrow = float(proj > 0.0 && proj < arrow_len && perp < 0.02);
        float on_head  = float(proj > arrow_len - 0.08 && proj < arrow_len
                          && perp < (arrow_len - proj) * 1.5);
        float arrow_mask = clamp(on_arrow + on_head, 0.0, 1.0);
        out_col = vec4(mix(bg, vec3(1.0, 1.0, 0.0), arrow_mask * 0.9), 1.0);

    // ── Normal fire render ────────────────────────────────────────────────────
    } else {
        // Pixelize — snap UV to pixel grid for retro look
        if (p.pixelize_size > 0.0) {
            float ps = p.pixelize_size;
            uv = floor(uv * float(p.N) / ps) * ps / float(p.N);
        }

        vec2  vel  = texture(sam_vel, uv).rg;
        float vmag = length(vel);

        float tv_r    = clamp(texture(sam_temp,  uv).r, 0.0, 255.0);
        float sv      = clamp(texture(sam_smoke, uv).r, 0.0, 255.0);
        float heat    = clamp((tv_r / p.temp_scale) * p.flame_height, 0.0, 1.0);
        float smoke_n = clamp(sv / p.smoke_scale, 0.0, 1.0);

        float sg = (p.is_hellfire==1)
            ? clamp((vmag/p.vel_scale)*0.40*p.glow, 0.0,1.0)
            : clamp((vmag/p.vel_scale)*0.22*p.glow, 0.0,1.0);

        // ── Hue-aware fire colour formula ─────────────────────────────────
        // The original coefficients (mult, offset, hc_boost) are designed for
        // orange fire where R=dominant, G=mid, B=late/hot.
        // We continuously rotate which channel plays each role based on hue_shift,
        // so the formula shape is preserved at every hue — no harsh edges.

        // Original per-channel parameters:
        //   mult:     R=2.8,  G=2.2,  B=3.6   (how fast channel rises with heat)
        //   offset:   R=0.0,  G=0.16, B=0.72  (heat threshold where channel starts)
        //   hc_hell:  R=0.35, G=0.45, B=0.70  (hot core boost hellfire)
        //   hc_norm:  R=0.24, G=0.34, B=0.54  (hot core boost normal)
        // hue_shift rotates which channel gets which parameter set.
        // t = hue_shift * 3.0 means one full rotation = 3 channel swaps = full circle.

        float t = fract(p.hue_shift) * 3.0;  // 0..3 continuous
        int   ti = int(t);
        float tf = t - float(ti);  // fractional part for smooth blend

        // Three parameter sets (one per channel role): "red-role", "green-role", "blue-role"
        vec3 mult_set    = vec3(2.8,  2.2,  3.6);
        vec3 offset_set  = vec3(0.0,  0.16, 0.72);
        vec3 hc_hell_set = vec3(0.35, 0.45, 0.70);
        vec3 hc_norm_set = vec3(0.24, 0.34, 0.54);

        // Rotate sets by ti steps, then lerp toward ti+1
        // Index mapping: which set index goes to which channel (R=0,G=1,B=2)
        // At ti=0: R gets set[0], G gets set[1], B gets set[2]  (original)
        // At ti=1: R gets set[2], G gets set[0], B gets set[1]  (one step)
        // At ti=2: R gets set[1], G gets set[2], B gets set[0]  (two steps)
        ivec3 idx0, idx1;
        if (ti == 0) { idx0 = ivec3(0,1,2); idx1 = ivec3(2,0,1); }
        else if (ti == 1) { idx0 = ivec3(2,0,1); idx1 = ivec3(1,2,0); }
        else              { idx0 = ivec3(1,2,0); idx1 = ivec3(0,1,2); }

        // Interpolate multipliers and offsets
        float mult_r   = mix(mult_set[idx0.r],   mult_set[idx1.r],   tf);
        float mult_g   = mix(mult_set[idx0.g],   mult_set[idx1.g],   tf);
        float mult_b   = mix(mult_set[idx0.b],   mult_set[idx1.b],   tf);
        float offset_r = mix(offset_set[idx0.r], offset_set[idx1.r], tf);
        float offset_g = mix(offset_set[idx0.g], offset_set[idx1.g], tf);
        float offset_b = mix(offset_set[idx0.b], offset_set[idx1.b], tf);

        float r = clamp((heat - offset_r) * mult_r, 0.0, 1.0);
        float g = clamp((heat - offset_g) * mult_g, 0.0, 1.0);
        float b = clamp((heat - offset_b) * mult_b, 0.0, 1.0);

        // Hot core boost — also rotated
        float hc;
        float hcr, hcg, hcb;
        if (p.is_hellfire==1) {
            hc = clamp((heat-0.78)*4.5, 0.0, 1.0);
            hcr = mix(hc_hell_set[idx0.r], hc_hell_set[idx1.r], tf);
            hcg = mix(hc_hell_set[idx0.g], hc_hell_set[idx1.g], tf);
            hcb = mix(hc_hell_set[idx0.b], hc_hell_set[idx1.b], tf);
        } else {
            hc = clamp((heat-0.84)*5.4, 0.0, 1.0);
            hcr = mix(hc_norm_set[idx0.r], hc_norm_set[idx1.r], tf);
            hcg = mix(hc_norm_set[idx0.g], hc_norm_set[idx1.g], tf);
            hcb = mix(hc_norm_set[idx0.b], hc_norm_set[idx1.b], tf);
        }
        r=clamp(r+hc*hcr, 0.0,1.0);
        g=clamp(g+hc*hcg, 0.0,1.0);
        b=clamp(b+hc*hcb, 0.0,1.0);

        // Rotate smoke warmth and suppression coefficients with hue
        // Original: warmth on R, suppression (0.48,0.62,0.82) per channel
        vec3 supp_hell = vec3(0.48, 0.62, 0.82);
        vec3 supp_norm = vec3(0.44, 0.58, 0.80);
        vec3 supp_mult_hell = vec3(1.0, 1.0, 0.8);  // gray multiplier per channel
        vec3 supp_mult_norm = vec3(1.0, 1.0, 0.72);
        // Rotate suppression same way as other coefficients
        float sr = mix(supp_hell[idx0.r], supp_hell[idx1.r], tf);
        float sg2= mix(supp_hell[idx0.g], supp_hell[idx1.g], tf);
        float sb = mix(supp_hell[idx0.b], supp_hell[idx1.b], tf);
        float smr= mix(supp_mult_hell[idx0.r], supp_mult_hell[idx1.r], tf);
        float smg= mix(supp_mult_hell[idx0.g], supp_mult_hell[idx1.g], tf);
        float smb= mix(supp_mult_hell[idx0.b], supp_mult_hell[idx1.b], tf);
        if (p.is_hellfire != 1) {
            sr = mix(supp_norm[idx0.r], supp_norm[idx1.r], tf);
            sg2= mix(supp_norm[idx0.g], supp_norm[idx1.g], tf);
            sb = mix(supp_norm[idx0.b], supp_norm[idx1.b], tf);
            smr= mix(supp_mult_norm[idx0.r], supp_mult_norm[idx1.r], tf);
            smg= mix(supp_mult_norm[idx0.g], supp_mult_norm[idx1.g], tf);
            smb= mix(supp_mult_norm[idx0.b], supp_mult_norm[idx1.b], tf);
        }
        // Smoke warmth — distribute proportionally across channels based on
        // continuous t value so there are NO discrete jumps at boundary crossings.
        // t=0..1 → red-dominant, t=1..2 → green-dominant, t=2..3 → blue-dominant
        // Each channel gets a smooth weight that peaks when it holds the "hot role".
        // We use a triangle wave centred at the dominant t position.
        float warmth_total = smoke_n * 0.24;
        // Channel dominance weights — triangle peaks at t=0/3, t=1, t=2
        float wr = 1.0 - min(min(abs(t - 0.0), abs(t - 3.0)), abs(t - 6.0));
        float wg = 1.0 - min(abs(t - 1.0), abs(t - 4.0));
        float wb = 1.0 - min(abs(t - 2.0), abs(t - 5.0));
        wr = clamp(wr, 0.0, 1.0);
        wg = clamp(wg, 0.0, 1.0);
        wb = clamp(wb, 0.0, 1.0);
        float wsum = wr + wg + wb;
        if (wsum > 0.0001) { wr /= wsum; wg /= wsum; wb /= wsum; }
        r = clamp(r + warmth_total * wr, 0.0, 1.0);
        g = clamp(g + warmth_total * wg, 0.0, 1.0);
        b = clamp(b + warmth_total * wb, 0.0, 1.0);

        float cm=clamp(smoke_n*(1.0-heat*0.75),0.0,1.0);
        float gray = (p.is_hellfire==1) ? smoke_n*0.20 : smoke_n*0.16;
        r=clamp(r*(1.0-cm*sr )+gray*smr, 0.0,1.0);
        g=clamp(g*(1.0-cm*sg2)+gray*smg, 0.0,1.0);
        b=clamp(b*(1.0-cm*sb )+gray*smb, 0.0,1.0);

        float br=(p.is_hellfire==1)
            ?clamp(0.18+heat*1.35+sg,0.0,1.55)
            :clamp(0.10+heat*1.08+sg,0.0,1.30);
        vec3 raw = vec3(clamp(r*br,0.0,1.0), clamp(g*br,0.0,1.0), clamp(b*br,0.0,1.0));

        vec3 col = raw;
        // Saturation — lerp between luminance (grey) and full colour
        float luma = dot(col, vec3(0.299, 0.587, 0.114));
        col = clamp(mix(vec3(luma), col, p.saturation), 0.0, 1.0);
        float alpha = clamp(heat * 2.0 + smoke_n * 1.0, 0.0, 1.0);
        out_col = vec4(col * alpha, alpha);
    }

    imageStore(out_image, ivec2(px,py), out_col);
}
