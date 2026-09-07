shader_type canvas_item;
//render_mode blend_premul_alpha;

uniform sampler2D sam_temp   : filter_linear, repeat_disable;
uniform sampler2D sam_smoke  : filter_linear, repeat_disable;
uniform sampler2D sam_vel    : filter_linear, repeat_disable;
uniform sampler2D sam_flowmap: filter_linear, repeat_disable;
uniform sampler2D sam_embers : filter_linear, repeat_disable;

uniform int   N;
uniform int   is_hellfire;
uniform float flame_height;
uniform float glow;
uniform float fire_glow : hint_range(0.0, 8.0) = 1.0; // overall fire glow strength
uniform int   display_mode;
uniform float temp_scale;
uniform float smoke_scale;
uniform float vel_scale;
uniform float flowmap_scale;
uniform float pixelize_size;
uniform float hue_shift;
uniform float saturation  : hint_range(0.0, 3.0) = 1.0;
uniform float sharpness        : hint_range(0.0, 3.0) = 0.0;
uniform float ember_flicker    : hint_range(0.0, 1.0) = 0.35;
uniform float ember_strength   : hint_range(0.0, 5.0) = 1.0;
uniform float ember_heat_value : hint_range(0.0, 1.0) = 0.70;
uniform bool  hdr_mode = false;
uniform float heat_distortion : hint_range(0.0, 0.05) = 0.0;
uniform sampler2D heat_dist_noise : filter_linear, repeat_enable;
uniform float heat_dist_time = 0.0;

void fragment() {
    vec2 uv = UV;

    // ── Debug: Velocity ───────────────────────────────────────────────────────
    if (display_mode == 1) {
        vec2 vel = texture(sam_vel, uv).rg;
        vec2 v = clamp(vel / 0.3, -1.0, 1.0) * 0.5 + 0.5;
        COLOR = vec4(v.x, v.y, 0.5, 1.0);

    // ── Debug: Temperature ────────────────────────────────────────────────────
    } else if (display_mode == 2) {
        float tv = clamp(texture(sam_temp, uv).r / temp_scale, 0.0, 1.0);
        COLOR = vec4(tv, tv, tv, 1.0);

    // ── Debug: Smoke ──────────────────────────────────────────────────────────
    } else if (display_mode == 3) {
        float sv = clamp(texture(sam_smoke, uv).r / smoke_scale, 0.0, 1.0);
        COLOR = vec4(sv, sv, sv, 1.0);

    // ── Debug: Flowmap ────────────────────────────────────────────────────────
    } else if (display_mode == 4) {
        vec2 flow_uv = (uv - 0.5) / flowmap_scale + 0.5;
        vec4 flow = texture(sam_flowmap, flow_uv);
        float fvx = (flow.r - 0.5) * 2.0;
        float fvy = (flow.g - 0.5) * 2.0;
        vec3 bg = vec3(clamp(fvx*0.5+0.5,0.0,1.0), clamp(fvy*0.5+0.5,0.0,1.0), 0.5);
        COLOR = vec4(bg, 1.0);

    // ── Normal fire render ────────────────────────────────────────────────────
    } else {
        if (pixelize_size > 0.0) {
            float ps = pixelize_size;
            uv = floor(uv * float(N) / ps) * ps / float(N);
        }

        vec2  vel  = texture(sam_vel, uv).rg;
        float vmag = length(vel);

        // Heat distortion — noise scrolls upward, offset masked by local heat
        if (heat_distortion > 0.0) {
            // Sample heat at wide radius to extend distortion zone beyond visible flame
            float wide = 6.0 / float(N);
            float heat_raw = clamp((
                texture(sam_temp, uv).r +
                texture(sam_temp, uv + vec2( wide, 0.0)).r +
                texture(sam_temp, uv + vec2(-wide, 0.0)).r +
                texture(sam_temp, uv + vec2(0.0,  wide)).r +
                texture(sam_temp, uv + vec2(0.0, -wide)).r +
                texture(sam_temp, uv + vec2( wide,  wide)).r +
                texture(sam_temp, uv + vec2(-wide,  wide)).r +
                texture(sam_temp, uv + vec2( wide, -wide)).r +
                texture(sam_temp, uv + vec2(-wide, -wide)).r
            ) / (9.0 * temp_scale), 0.0, 1.0);
            // Scroll noise upward over time (two layers at different speeds for organic feel)
            vec2 noise_uv1 = uv + vec2(0.0, -heat_dist_time * 0.18);
            vec2 noise_uv2 = uv * 1.7 + vec2(0.0, -heat_dist_time * 0.27);
            vec2 n1 = texture(heat_dist_noise, noise_uv1).rg * 2.0 - 1.0;
            vec2 n2 = texture(heat_dist_noise, noise_uv2).rg * 2.0 - 1.0;
            vec2 noise_offset = (n1 + n2) * 0.5;
            float heat_mask = clamp(heat_raw * flame_height, 0.0, 1.0);
            uv = clamp(uv + noise_offset * heat_mask * heat_distortion, 0.0, 1.0);
        }

        // Unsharp mask — sample neighbors, sharpen center
        float texel = 1.0 / float(N);
        float tv_r    = clamp(texture(sam_temp,  uv).r, 0.0, 255.0);
        float sv      = clamp(texture(sam_smoke, uv).r, 0.0, 255.0);
        if (sharpness > 0.0) {
            float tv_blur = (
                texture(sam_temp, uv + vec2( texel, 0.0)).r +
                texture(sam_temp, uv + vec2(-texel, 0.0)).r +
                texture(sam_temp, uv + vec2(0.0,  texel)).r +
                texture(sam_temp, uv + vec2(0.0, -texel)).r) * 0.25;
            float sv_blur = (
                texture(sam_smoke, uv + vec2( texel, 0.0)).r +
                texture(sam_smoke, uv + vec2(-texel, 0.0)).r +
                texture(sam_smoke, uv + vec2(0.0,  texel)).r +
                texture(sam_smoke, uv + vec2(0.0, -texel)).r) * 0.25;
            tv_r = clamp(tv_r + sharpness * (tv_r - tv_blur), 0.0, 255.0);
            sv   = clamp(sv   + sharpness * (sv   - sv_blur),  0.0, 255.0);
        }
        float heat    = clamp((tv_r / temp_scale) * flame_height, 0.0, 1.0);
        float smoke_n = clamp(sv / smoke_scale, 0.0, 1.0);

        float sg = (is_hellfire==1)
            ? clamp((vmag/vel_scale)*0.40*glow, 0.0,1.0)
            : clamp((vmag/vel_scale)*0.22*glow, 0.0,1.0);

        float t = fract(hue_shift) * 3.0;
        int   ti = int(t);
        float tf = t - float(ti);

        vec3 mult_set    = vec3(2.8,  2.2,  3.6);
        vec3 offset_set  = vec3(0.0,  0.16, 0.72);
        vec3 hc_hell_set = vec3(0.35, 0.45, 0.70);
        vec3 hc_norm_set = vec3(0.24, 0.34, 0.54);

        ivec3 idx0, idx1;
        if (ti == 0) { idx0 = ivec3(0,1,2); idx1 = ivec3(2,0,1); }
        else if (ti == 1) { idx0 = ivec3(2,0,1); idx1 = ivec3(1,2,0); }
        else              { idx0 = ivec3(1,2,0); idx1 = ivec3(0,1,2); }

        float mult_r   = mix(mult_set[idx0.r],   mult_set[idx1.r],   tf);
        float mult_g   = mix(mult_set[idx0.g],   mult_set[idx1.g],   tf);
        float mult_b   = mix(mult_set[idx0.b],   mult_set[idx1.b],   tf);
        float offset_r = mix(offset_set[idx0.r], offset_set[idx1.r], tf);
        float offset_g = mix(offset_set[idx0.g], offset_set[idx1.g], tf);
        float offset_b = mix(offset_set[idx0.b], offset_set[idx1.b], tf);

        float r = clamp((heat - offset_r) * mult_r, 0.0, 1.0);
        float g = clamp((heat - offset_g) * mult_g, 0.0, 1.0);
        float b = clamp((heat - offset_b) * mult_b, 0.0, 1.0);

        float hc;
        float hcr, hcg, hcb;
        if (is_hellfire==1) {
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

        vec3 supp_hell = vec3(0.48, 0.62, 0.82);
        vec3 supp_norm = vec3(0.44, 0.58, 0.80);
        vec3 supp_mult_hell = vec3(1.0, 1.0, 0.8);
        vec3 supp_mult_norm = vec3(1.0, 1.0, 0.72);
        float sr = mix(supp_hell[idx0.r], supp_hell[idx1.r], tf);
        float sg2= mix(supp_hell[idx0.g], supp_hell[idx1.g], tf);
        float sb = mix(supp_hell[idx0.b], supp_hell[idx1.b], tf);
        float smr= mix(supp_mult_hell[idx0.r], supp_mult_hell[idx1.r], tf);
        float smg= mix(supp_mult_hell[idx0.g], supp_mult_hell[idx1.g], tf);
        float smb= mix(supp_mult_hell[idx0.b], supp_mult_hell[idx1.b], tf);
        if (is_hellfire != 1) {
            sr = mix(supp_norm[idx0.r], supp_norm[idx1.r], tf);
            sg2= mix(supp_norm[idx0.g], supp_norm[idx1.g], tf);
            sb = mix(supp_norm[idx0.b], supp_norm[idx1.b], tf);
            smr= mix(supp_mult_norm[idx0.r], supp_mult_norm[idx1.r], tf);
            smg= mix(supp_mult_norm[idx0.g], supp_mult_norm[idx1.g], tf);
            smb= mix(supp_mult_norm[idx0.b], supp_mult_norm[idx1.b], tf);
        }

        float warmth_total = smoke_n * 0.24;
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
        float gray = (is_hellfire==1) ? smoke_n*0.20 : smoke_n*0.16;
        r=clamp(r*(1.0-cm*sr )+gray*smr, 0.0,1.0);
        g=clamp(g*(1.0-cm*sg2)+gray*smg, 0.0,1.0);
        b=clamp(b*(1.0-cm*sb )+gray*smb, 0.0,1.0);

        float br=(is_hellfire==1)
            ?clamp(0.18+heat*1.35+sg,0.0,1.55)
            :clamp(0.10+heat*1.08+sg,0.0,1.30);
        vec3 col = vec3(clamp(r*br,0.0,1.0), clamp(g*br,0.0,1.0), clamp(b*br,0.0,1.0));

        // Shift low-heat zone from red toward orange by boosting green channel
        // Only for normal fire — hellfire has its own calibrated color balance
        if (is_hellfire != 1) {
            float low_boost = clamp(1.0 - (heat - 0.10) / 0.22, 0.0, 1.0);
            col.g += col.r * low_boost * 0.2;
            col = clamp(col, 0.0, 1.0);
        }

        float luma = dot(col, vec3(0.299, 0.587, 0.114));
        float sat_c = saturation * saturation;
        col = clamp(mix(vec3(luma), col, sat_c), 0.0, 1.0);

        // Top tendril glow — only for normal fire, hellfire has its own color balance
        if (is_hellfire != 1) {
            float top_glow_t  = clamp(heat / 0.35, 0.0, 1.0) * clamp(1.0 - heat / 0.35, 0.0, 1.0);
            float smoke_mask  = clamp(1.0 - smoke_n * 2.5, 0.0, 1.0);
            float top_glow    = (fire_glow - 1.0) * top_glow_t * smoke_mask * 2.5;
            col += vec3(top_glow * 0.9, top_glow * 0.4, 0.0);
        }

        // ── Ember composite ───────────────────────────────────────────────────
        vec4 ember_raw      = texture(sam_embers, uv);
        float ember_hot_i   = ember_raw.r;
        float ember_age_t   = ember_raw.g;
        float ember_falloff = ember_raw.a;

        // Per-heat zone brightness — applied after HDR correction so it can exceed glow threshold
        // Below heat=0.3 (smoke zone) multiplier stays 1.0 — smoke should never glow
        // Single fire_glow slider — per-heat sensitivity baked in
        // dim zones respond strongly, hot core barely responds, nothing ever dims
        float heat_sensitivity;
        if (heat < 0.15) {
            heat_sensitivity = 0.0;
        } else if (heat < 0.35) {
            heat_sensitivity = mix(5.0, 2.2, (heat - 0.10) / 0.25);
        } else if (heat < 0.65) {
            heat_sensitivity = mix(1.2, 0.2, (heat - 0.35) / 0.30);
        } else {
            heat_sensitivity = mix(1.6, 0.2, (heat - 0.65) / 0.35);
        }
        float zone_mult = 1.0 + (fire_glow - 1.0) * heat_sensitivity;

        float alpha_heat  = clamp(heat * 2.0, 0.0, 1.0);
        float alpha_smoke = clamp(smoke_n * 1.0, 0.0, 1.0);
        float alpha = clamp(alpha_heat + alpha_smoke, 0.0, 1.0);

        // Taper zone_mult at transparent edges so glow doesn't create a bright
        // semi-transparent halo ring. Full glow only where fire is opaque.
        float edge_taper = alpha_heat * alpha_heat; // quadratic: 0 at edge, 1 at core
        float zone_mult_tapered = 1.0 + (zone_mult - 1.0) * edge_taper;

        if (ember_falloff > 0.001) {
            // Derive ember colors from the fire ramp the same way the fire looks:
            // fire_col * fire_alpha — that composite over dark is what makes mid look reddish.
            // We replicate it by sampling at 3 heat levels and premultiplying by their alpha.

            // hot = ember_heat_value (controls ember color — use Heat Ramp view to pick)
            vec3 e_hot;
            {
                float h = ember_heat_value;
                float er = clamp((h - offset_r) * mult_r, 0.0, 1.0);
                float eg = clamp((h - offset_g) * mult_g, 0.0, 1.0);
                float eb = clamp((h - offset_b) * mult_b, 0.0, 1.0);
                float hc = (is_hellfire==1) ? clamp((h-0.78)*4.5,0.0,1.0) : clamp((h-0.84)*5.4,0.0,1.0);
                float br = (is_hellfire==1) ? clamp(0.18+h*1.35,0.0,1.55) : clamp(0.10+h*1.08,0.0,1.30);
                er = clamp(er + hc*hcr, 0.0,1.0);
                eg = clamp(eg + hc*hcg, 0.0,1.0);
                eb = clamp(eb + hc*hcb, 0.0,1.0);
                float a = clamp(h * 2.0, 0.0, 1.0);
                e_hot = vec3(clamp(er*br,0.0,1.0), clamp(eg*br,0.0,1.0), clamp(eb*br,0.0,1.0)) * a;
            }

            // mid — scales proportionally with ember_heat_value
            vec3 e_mid;
            {
                float h = ember_heat_value * 0.571;
                float er = clamp((h - offset_r) * mult_r, 0.0, 1.0);
                float eg = clamp((h - offset_g) * mult_g, 0.0, 1.0);
                float eb = clamp((h - offset_b) * mult_b, 0.0, 1.0);
                float hc = (is_hellfire==1) ? clamp((h-0.78)*4.5,0.0,1.0) : clamp((h-0.84)*5.4,0.0,1.0);
                float br = (is_hellfire==1) ? clamp(0.18+h*1.35,0.0,1.55) : clamp(0.10+h*1.08,0.0,1.30);
                er = clamp(er + hc*hcr, 0.0,1.0);
                eg = clamp(eg + hc*hcg, 0.0,1.0);
                eb = clamp(eb + hc*hcb, 0.0,1.0);
                float a = clamp(h * 2.0, 0.0, 1.0);
                e_mid = vec3(clamp(er*br,0.0,1.0), clamp(eg*br,0.0,1.0), clamp(eb*br,0.0,1.0)) * a;
            }

            // dark — scales proportionally with ember_heat_value
            vec3 e_smk;
            {
                float h = ember_heat_value * 0.071;
                float er = clamp((h - offset_r) * mult_r, 0.0, 1.0);
                float eg = clamp((h - offset_g) * mult_g, 0.0, 1.0);
                float eb = clamp((h - offset_b) * mult_b, 0.0, 1.0);
                float br = (is_hellfire==1) ? clamp(0.18+h*1.35,0.0,1.55) : clamp(0.10+h*1.08,0.0,1.30);
                float a = clamp(h * 2.0, 0.0, 1.0);
                e_smk = vec3(clamp(er*br,0.0,1.0), clamp(eg*br,0.0,1.0), clamp(eb*br,0.0,1.0)) * a;
            }

            // Apply same saturation as fire
            e_hot = clamp(mix(vec3(dot(e_hot, vec3(0.299,0.587,0.114))), e_hot, sat_c), 0.0, 1.0);
            e_mid = clamp(mix(vec3(dot(e_mid, vec3(0.299,0.587,0.114))), e_mid, sat_c), 0.0, 1.0);
            e_smk = clamp(mix(vec3(dot(e_smk, vec3(0.299,0.587,0.114))), e_smk, sat_c), 0.0, 1.0);

            // Normalize e_hot, e_mid, e_smk by brightest channel
            // so all heat values produce same brightness — only hue differs
            float h_max = max(e_hot.r, max(e_hot.g, e_hot.b));
            if (h_max > 0.001) e_hot /= h_max;
            float m_max = max(e_mid.r, max(e_mid.g, e_mid.b));
            if (m_max > 0.001) e_mid /= m_max;
            float s_max = max(e_smk.r, max(e_smk.g, e_smk.b));
            if (s_max > 0.001) e_smk /= s_max;

            // Blend hot→mid→dark by age
            vec3 ember_col;
            float age_blend = ember_age_t / max(ember_falloff, 0.001);
            float hot_blend = ember_hot_i / max(ember_falloff, 0.001);
            if (age_blend < hot_blend) {
                ember_col = mix(e_hot, e_mid, clamp(age_blend / max(hot_blend, 0.001), 0.0, 1.0));
            } else {
                ember_col = mix(e_mid, e_smk, clamp((age_blend - hot_blend) / max(1.0 - hot_blend, 0.001), 0.0, 1.0));
            }
            ember_col *= ember_falloff * 1.55 * ember_strength;

            // Flicker — per-ember seed stored in B channel, animated with TIME
            if (ember_flicker > 0.0) {
                float seed = ember_raw.b;
                float flicker = sin(TIME * 20.0 + seed * 6.2831) * 0.5 + 0.5; // 0..1
                float flicker_mult = 1.0 + (flicker * 2.0 - 1.0) * ember_flicker;
                ember_col *= max(flicker_mult, 0.0);
            }

            // Sharpness on embers
            if (sharpness > 0.0) {
                float et = 1.0 / float(N * 2);
                float ef_blur = (
                    texture(sam_embers, uv + vec2( et, 0.0)).a +
                    texture(sam_embers, uv + vec2(-et, 0.0)).a +
                    texture(sam_embers, uv + vec2(0.0,  et)).a +
                    texture(sam_embers, uv + vec2(0.0, -et)).a) * 0.25;
                float sharp_f = clamp(ember_falloff + sharpness * (ember_falloff - ef_blur), 0.0, 1.0);
                ember_col *= sharp_f / max(ember_falloff, 0.001);
            }

            vec3 fire_out = hdr_mode ? pow(col * zone_mult_tapered * alpha, vec3(2.2)) : col * zone_mult_tapered * alpha;
            vec3 final_col = fire_out + ember_col;
            COLOR = vec4(final_col, max(alpha, dot(ember_col, vec3(0.333))));
        } else {
            vec3 out_col = hdr_mode ? pow(col * zone_mult_tapered * alpha, vec3(2.2)) : col * zone_mult_tapered * alpha;
            COLOR = vec4(out_col, alpha);
        }
    }
}
