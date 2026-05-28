// Nyan Cat cursor shader for Ghostty
// -----------------------------------
// Draws a procedural pop-tart cat at the cursor position with a 6-stripe
// rainbow trail connecting the previous cursor position to the current one.
// No textures (Ghostty exposes only iChannel0 = terminal contents), so the
// cat is built from SDF primitives sized relative to iCurrentCursor.zw.
//
// Uniforms used (Ghostty extensions on top of Shadertoy):
//   iCurrentCursor   .xy = top-left px, .zw = w/h px
//   iPreviousCursor  .xy = top-left px, .zw = w/h px
//   iTimeCursorChange    = iTime at last cursor move
//   iChannel0            = terminal framebuffer below the shader

// ---------- helpers ----------
float sdSegment(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// distance to segment AND the param t in [0,1] along it
vec2 segInfo(vec2 p, vec2 a, vec2 b) {
    vec2 pa = p - a;
    vec2 ba = b - a;
    float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return vec2(length(pa - ba * t), t);
}

float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 d = abs(p) - b + vec2(r);
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

float sdCircle(vec2 p, float r) { return length(p) - r; }

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// 6 classic nyan rainbow stripes, idx in [0,6)
vec3 rainbowStripe(float idx) {
    if (idx < 1.0) return vec3(1.00, 0.00, 0.00); // red
    if (idx < 2.0) return vec3(1.00, 0.60, 0.00); // orange
    if (idx < 3.0) return vec3(1.00, 1.00, 0.00); // yellow
    if (idx < 4.0) return vec3(0.20, 1.00, 0.00); // green
    if (idx < 5.0) return vec3(0.00, 0.60, 1.00); // blue
    return                  vec3(0.50, 0.20, 1.00); // purple
}

// premultiplied-alpha-ish overlay
vec3 over(vec3 dst, vec4 src) {
    return mix(dst, src.rgb, src.a);
}

// ---------- nyan body, drawn in cursor-local pixels ----------
// p is in pixels, with (0,0) at the center of the cursor cell.
// scale = cursor cell size; we draw the cat occupying ~1.6x cell width.
vec4 drawNyan(vec2 p, vec2 cellSize, float t) {
    vec4 col = vec4(0.0);

    // overall scale: nyan ~ as tall as one cell, ~1.4x wide
    float s = min(cellSize.x, cellSize.y * 0.55);

    // ---- pop-tart body ----
    vec2 bodyHalf = vec2(s * 1.20, s * 0.80);
    float bodyR = s * 0.18;
    // brown crust
    float dCrust = sdRoundBox(p, bodyHalf, bodyR);
    if (dCrust < 0.0) col = vec4(vec3(0.62, 0.36, 0.18), 1.0);
    // pink frosting (inset)
    float dFrost = sdRoundBox(p, bodyHalf - vec2(s * 0.18), bodyR * 0.7);
    if (dFrost < 0.0) col = vec4(vec3(1.00, 0.72, 0.82), 1.0);

    // sprinkles (procedural dots on the frosting)
    if (dFrost < -s * 0.05) {
        // tile space for sprinkles
        vec2 sp = p / (s * 0.35);
        vec2 cell = floor(sp);
        vec2 f = fract(sp) - 0.5;
        float h = hash21(cell);
        if (h > 0.45 && length(f) < 0.18) {
            // pick a sprinkle color from hash
            vec3 sc = vec3(1.0);
            if (h < 0.6)      sc = vec3(0.20, 0.85, 1.00); // cyan
            else if (h < 0.75) sc = vec3(1.00, 0.85, 0.20); // yellow
            else if (h < 0.9)  sc = vec3(1.00, 0.30, 0.80); // magenta
            else               sc = vec3(0.30, 1.00, 0.40); // green
            col = vec4(sc, 1.0);
        }
    }

    // ---- legs (wiggle) ----
    float legY = -bodyHalf.y - s * 0.10;
    float legWiggle = sin(t * 14.0) * s * 0.05;
    for (int i = 0; i < 2; i++) {
        float xo = (i == 0 ? -1.0 : 1.0) * s * 0.55;
        float yo = legY + (i == 0 ? legWiggle : -legWiggle);
        vec2 lp = p - vec2(xo, yo);
        float dLeg = sdRoundBox(lp, vec2(s * 0.12, s * 0.18), s * 0.06);
        if (dLeg < 0.0) col = vec4(vec3(0.55, 0.55, 0.60), 1.0);
    }

    // ---- head (grey cat) sticking out to the right ----
    vec2 headC = vec2(bodyHalf.x + s * 0.35, s * 0.10);
    vec2 hp = p - headC;
    // squash head slightly
    vec2 hpS = hp * vec2(1.0, 1.15);
    float dHead = sdCircle(hpS, s * 0.55);
    if (dHead < 0.0) col = vec4(vec3(0.78, 0.78, 0.80), 1.0);

    // ears (two triangles approximated as small rotated boxes)
    for (int i = 0; i < 2; i++) {
        float xo = (i == 0 ? -1.0 : 1.0) * s * 0.32;
        vec2 ep = hp - vec2(xo, s * 0.45);
        // rotate 30deg out
        float a = (i == 0 ? -0.5 : 0.5);
        float ca = cos(a), sa = sin(a);
        vec2 epr = vec2(ca * ep.x - sa * ep.y, sa * ep.x + ca * ep.y);
        float dEar = sdRoundBox(epr, vec2(s * 0.14, s * 0.18), s * 0.04);
        if (dEar < 0.0) col = vec4(vec3(0.78, 0.78, 0.80), 1.0);
    }

    // eyes
    for (int i = 0; i < 2; i++) {
        float xo = (i == 0 ? -1.0 : 1.0) * s * 0.20;
        vec2 ep = hp - vec2(xo, s * 0.05);
        if (sdCircle(ep, s * 0.10) < 0.0) col = vec4(vec3(0.05), 1.0);
    }

    // cheeks
    for (int i = 0; i < 2; i++) {
        float xo = (i == 0 ? -1.0 : 1.0) * s * 0.34;
        vec2 ep = hp - vec2(xo, -s * 0.12);
        if (sdCircle(ep, s * 0.09) < 0.0) col = vec4(vec3(1.00, 0.55, 0.70), 1.0);
    }

    // tiny mouth (small dark dot)
    if (sdCircle(hp - vec2(0.0, -s * 0.10), s * 0.05) < 0.0)
        col = vec4(vec3(0.05), 1.0);

    return col;
}

// ---------- main ----------
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = fragCoord / res;

    // base = whatever the terminal drew underneath
    vec4 base = texture(iChannel0, uv);

    // --- cursor geometry (in pixels). Ghostty's iCurrentCursor.xy is
    // already in fragCoord space (Y-up), with .y being the TOP edge of
    // the cursor box. So center.y = top.y - halfH (NOT a res.y - y flip).
    // Reference: KroneCorylus/ghostty-shader-playground cursor_smear.glsl.
    vec2 curSize = iCurrentCursor.zw;
    vec2 prvSize = iPreviousCursor.zw;
    vec2 curCenter = iCurrentCursor.xy + vec2(curSize.x * 0.5, -curSize.y * 0.5);
    vec2 prvCenter = iPreviousCursor.xy + vec2(prvSize.x * 0.5, -prvSize.y * 0.5);

    vec2 cell = curSize; // use current cell as our unit
    vec2 P = fragCoord;  // pixel coord

    // ---- visibility envelope ----
    // Nyan (cat + trail + stars) is a motion effect. Two gates compose:
    //   1. trailAlpha — exponential decay since the last cursor move.
    //   2. jumpStrength — how far the cursor jumped. Per-character typing
    //      moves the cursor 1 cell, which would otherwise re-trigger nyan
    //      on every keystroke. Require ≥ ~2 cells to consider it a jump.
    vec2 toCur = curCenter - prvCenter;
    float jumpDist = length(toCur);
    float jumpStrength = smoothstep(cell.x * 1.2, cell.x * 3.0, jumpDist);

    float dt = max(iTime - iTimeCursorChange, 0.0);
    float trailLife = 0.55;                 // seconds the trail is visible
    float trailAlpha = exp(-dt / trailLife * 2.5) * jumpStrength;
    float nyanVisible = smoothstep(0.0, 0.08, trailAlpha);

    // hide the default block cursor under us, but only while nyan is on
    // screen — when idle (or just typing), let the normal cursor through.
    vec2 dCur = abs(P - curCenter) - curSize * 0.5;
    if (max(dCur.x, dCur.y) < 0.0 && nyanVisible > 0.05) {
        base.rgb = mix(base.rgb, iBackgroundColor.rgb, nyanVisible);
    }

    vec3 outCol = base.rgb;

    float segLen = jumpDist;
    if (segLen > cell.x * 1.2 && trailAlpha > 0.01) {
        vec2 si = segInfo(P, prvCenter, curCenter);
        float distPerp = si.x;
        float along = si.y;                 // 0 at prev, 1 at cur

        // band half-height = cursor height * 0.45 → ~ cursor-tall stripes
        float bandH = cell.y * 0.45;

        if (distPerp < bandH) {
            // We only want the trail BEHIND the cat, not under it.
            // Cat occupies roughly the last ~1.6 cell widths of the segment.
            float catLen = cell.x * 1.6;
            float catCutoff = 1.0 - clamp(catLen / segLen, 0.0, 0.9);

            if (along < catCutoff) {
                // signed perpendicular position across the band, in [-1,1]
                // Use the direction-perpendicular to give a stable "top"
                vec2 dir = normalize(curCenter - prvCenter);
                vec2 nrm = vec2(-dir.y, dir.x);
                float perp = dot(P - mix(prvCenter, curCenter, along), nrm);
                float v = perp / bandH;     // [-1, 1]
                float stripeIdx = floor((v * 0.5 + 0.5) * 6.0);
                stripeIdx = clamp(stripeIdx, 0.0, 5.0);
                vec3 sc = rainbowStripe(stripeIdx);

                // wavy shimmer along the trail
                float wob = sin(along * 18.0 - iTime * 12.0) * 0.04;
                sc += wob;

                // fade-in near the head, fade-out at the tail
                float headFade = smoothstep(catCutoff, catCutoff - 0.05, along);
                float tailFade = smoothstep(0.0, 0.05, along);
                float a = trailAlpha * headFade * tailFade;

                outCol = mix(outCol, sc, a);

                // bright edge on the very outer stripes for pop
                float edge = smoothstep(0.95, 1.0, abs(v));
                outCol = mix(outCol, vec3(1.0), edge * a * 0.6);
            }
        }
    }

    // ---- shimmer stars trailing behind ----
    if (segLen > cell.x * 1.2 && trailAlpha > 0.01) {
        for (int i = 0; i < 3; i++) {
            float fi = float(i);
            float t = fract(0.15 + fi * 0.27 - iTime * 0.6);
            vec2 sp = mix(curCenter, prvCenter, t);
            // jitter
            sp += vec2(sin(iTime * 4.0 + fi), cos(iTime * 3.5 + fi * 2.0))
                  * cell.y * 0.35;
            float ds = sdCircle(P - sp, cell.y * 0.06);
            float sa = smoothstep(0.0, -cell.y * 0.06, ds) * trailAlpha * 0.8;
            outCol = mix(outCol, vec3(1.0), sa);
        }
    }

    // ---- draw the nyan body at the current cursor ----
    // Empirically Ghostty's fragCoord uses Y-down (screen-top = Y 0), so we
    // negate Y to get into our internal "cat-world" space where +Y = up.
    // Cat then sits in cat-space, oriented so +X is its nose. We rotate
    // cat-world by `angle` so the nose points along the direction of the
    // last cursor move; equivalently, we counter-rotate fragment-relative
    // coords by -angle before sampling the cat SDF.
    //
    // When prv≈cur (cursor hasn't really moved), angle = 0 → cat faces
    // right (default). After any meaningful jump, iPreviousCursor sticks
    // at the pre-jump position, so the angle is latched until the next
    // jump even as the cat fades out.
    float angle = 0.0;
    if (jumpDist > 0.5) {
        // negate Y because frag-down → cat-up
        angle = atan(-toCur.y, toCur.x);
    }
    float ca = cos(angle);
    float sa = sin(angle);

    vec2 r = P - curCenter;
    r.y = -r.y;                              // flip frag-down to cat Y-up
    // R(-angle) * r  =  [ca, sa; -sa, ca] * r
    vec2 local = vec2( ca * r.x + sa * r.y,
                      -sa * r.x + ca * r.y);

    vec4 cat = drawNyan(local, cell, iTime);
    cat.a *= nyanVisible;
    outCol = over(outCol, cat);

    fragColor = vec4(outCol, 1.0);
}
