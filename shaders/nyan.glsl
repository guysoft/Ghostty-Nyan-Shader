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

// Platform coordinate knob:
// macOS Ghostty/Metal has fragCoord Y-down in practice, so the cat needs -1.
// If the cat is upside down on Linux/OpenGL/Vulkan, set this to 1.0.
const float NYAN_Y_SIGN = -1.0;

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

    // The cat now actually flies from the previous cursor position to the
    // current one (instead of appearing instantly at curCenter). catLife is
    // the post-flight morph/fade duration; flyDuration controls travel speed.
    // trailLife keeps exponential decay so the comet smoothly trails.
    float flyDuration = 0.24;
    float catLife = 0.18;
    float trailLife = 0.7;
    float flyT = clamp(dt / flyDuration, 0.0, 1.0);
    float flyProgress = flyT * flyT * (3.0 - 2.0 * flyT); // smoothstep
    vec2 flyCenter = mix(prvCenter, curCenter, flyProgress);

    float morphT = clamp((dt - flyDuration) / catLife, 0.0, 1.0);
    float catFade = morphT;
    float catAlpha = (1.0 - smoothstep(0.6, 1.0, catFade)) * jumpStrength;
    float trailDt = max(dt - flyDuration, 0.0);
    float trailAlpha = exp(-trailDt / trailLife * 2.5) * jumpStrength;
    float nyanVisible = smoothstep(0.0, 0.08, trailAlpha);

    // Crossfade-mask the default block cursor with catAlpha, but only once
    // the flying cat gets close to the destination. This leaves the block
    // cursor visible as a target while nyan is in flight, which makes the
    // direction of travel easier to follow.
    vec2 dCur = abs(P - curCenter) - curSize * 0.5;
    float destinationMask = smoothstep(0.75, 1.0, flyProgress) * catAlpha;
    if (max(dCur.x, dCur.y) < 0.0 && destinationMask > 0.01) {
        base.rgb = mix(base.rgb, iBackgroundColor.rgb, destinationMask);
    }

    vec3 outCol = base.rgb;

    float segLen = jumpDist;
    float maxTrailLen = cell.x * 10.0;
    float tailProgress = max(0.0, flyProgress - maxTrailLen / max(segLen, 1.0));
    vec2 tailCenter = mix(prvCenter, curCenter, tailProgress);
    float liveTrailLen = distance(tailCenter, flyCenter);
    if (segLen > cell.x * 1.2 && liveTrailLen > cell.x * 0.5 && trailAlpha > 0.01) {
        vec2 si = segInfo(P, tailCenter, flyCenter);
        float distPerp = si.x;
        float along = si.y;                 // 0 at tail, 1 at cat

        // band half-height = cursor height * 0.45 → ~ cursor-tall stripes
        float bandH = cell.y * 0.45;

        if (distPerp < bandH) {
            // We only want the trail BEHIND the cat, not under it.
            // Cat occupies roughly the last ~1.6 cell widths of the segment.
            float catLen = cell.x * 1.6;
            float catCutoff = 1.0 - clamp(catLen / liveTrailLen, 0.0, 0.9);

            if (along < catCutoff) {
                // signed perpendicular position across the band, in [-1,1].
                // Force the normal to point DOWN on screen (Y-down frag,
                // so nrm.y >= 0). Without this, leftward motion flips the
                // rainbow vertically — red ends up at the bottom of the
                // band instead of the top.
                vec2 dir = normalize(flyCenter - tailCenter);
                vec2 nrm = vec2(-dir.y, dir.x);
                if (nrm.y < 0.0) nrm = -nrm;
                float perp = dot(P - mix(tailCenter, flyCenter, along), nrm);
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

                // Per-position lifetime: pretend the cat took `travelTime`
                // seconds to traverse the segment. The prv end of the trail
                // is the "oldest" (cat passed it travelTime ago) and the
                // cur end is the "newest" (cat just arrived). Each point
                // gets its own exp() decay so the trail dies tail-first,
                // like a comet, instead of fading uniformly as one block.
                float travelTime = 0.18;
                float age = trailDt + travelTime * (1.0 - along);
                float localAlpha = exp(-age / trailLife * 2.5) * jumpStrength;
                float a = localAlpha * headFade * tailFade;

                outCol = mix(outCol, sc, a);

                // bright edge on the very outer stripes for pop
                float edge = smoothstep(0.95, 1.0, abs(v));
                outCol = mix(outCol, vec3(1.0), edge * a * 0.6);
            }
        }
    }

    // ---- shimmer stars trailing behind ----
    // Same per-position decay as the rainbow band: stars near the prv end
    // of the trail (t→1, far from the cat) are "older" than stars near
    // the cat (t→0), so they fade out first.
    if (segLen > cell.x * 1.2 && liveTrailLen > cell.x * 0.5 && trailAlpha > 0.01) {
        const float travelTime = 0.18;
        for (int i = 0; i < 3; i++) {
            float fi = float(i);
            float t = fract(0.15 + fi * 0.27 - iTime * 0.6);
            vec2 sp = mix(flyCenter, tailCenter, t);
            // jitter
            sp += vec2(sin(iTime * 4.0 + fi), cos(iTime * 3.5 + fi * 2.0))
                  * cell.y * 0.35;
            float ds = sdCircle(P - sp, cell.y * 0.06);
            float starAge = trailDt + travelTime * t;
            float starAlpha = exp(-starAge / trailLife * 2.5) * jumpStrength;
            float sa = smoothstep(0.0, -cell.y * 0.06, ds) * starAlpha * 0.8;
            outCol = mix(outCol, vec3(1.0), sa);
        }
    }

    // ---- draw the nyan body at the current cursor ----
    // Convert the platform's fragment Y convention into our internal
    // "cat-world" space where +Y = up. macOS/Metal needs NYAN_Y_SIGN=-1;
    // if Linux shows the cat upside down, set NYAN_Y_SIGN=1 at the top.
    // Cat sits in cat-space oriented so +X is its nose.
    //
    // Naive approach: rotate cat-space by atan(dir) so the nose follows
    // the motion. Problem: rightward → angle 0 (ok), leftward → angle π
    // which rotates the cat 180° → cat ends up upside-down AND facing
    // backwards. Standard 2D sprite trick: keep the rotation in the
    // "front half" (cos(angle) > 0, i.e. nose-on-the-right) and apply a
    // horizontal mirror to make the cat physically face leftward. This
    // way the cat's belly always points down on screen.
    float angle = 0.0;
    float flipX = 1.0;
    if (jumpDist > 0.5) {
        angle = atan(NYAN_Y_SIGN * toCur.y, toCur.x);
        if (toCur.x < 0.0) {
            // moving leftward: rotate the angle back into the front half
            // (so the cat is upright) and mirror cat-space X so the head
            // visually faces left.
            angle += 3.14159265358979;
            flipX = -1.0;
        }
    }
    float ca = cos(angle);
    float sa = sin(angle);

    vec2 r = P - flyCenter;
    r.y *= NYAN_Y_SIGN;                      // platform frag Y → cat Y-up
    // R(-angle) * r  =  [ca, sa; -sa, ca] * r
    vec2 local = vec2( ca * r.x + sa * r.y,
                      -sa * r.x + ca * r.y);
    local.x *= flipX;                        // horizontal mirror for left motion

    // Implosion morph: as catAlpha falls, scale `local` UP so the cat SDF
    // is sampled further from origin → cat shrinks toward curCenter. Tied
    // to a separate `shrinkProgress` rather than catAlpha directly so the
    // shrink only kicks in during the LAST stretch of the fade (when
    // catAlpha drops below 0.3). Otherwise the cat visibly shrinks well
    // before its alpha fades, making the whole thing look much shorter
    // than catLife.
    float shrinkProgress = smoothstep(0.3, 0.0, catAlpha);
    float shrink = mix(1.0, 2.2, shrinkProgress);
    local *= shrink;

    vec4 cat = drawNyan(local, cell, iTime);
    cat.a *= catAlpha;
    outCol = over(outCol, cat);

    fragColor = vec4(outCol, 1.0);
}
