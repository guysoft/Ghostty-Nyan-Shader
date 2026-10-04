#language slang 2026

// Procedural Nyan Cat cursor effect for kitty 0.49+.

import kitty_custom_shader_types;

static const float FLY_DURATION = 0.24;
static const float CAT_LIFE = 0.18;
static const float TRAIL_LIFE = 0.70;

static float
sdSegment(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h);
}

static float2
segInfo(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float t = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return float2(length(pa - ba * t), t);
}

static float
sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + float2(r);
    return length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

static float
sdCircle(float2 p, float r) {
    return length(p) - r;
}

static float
hash21(float2 p) {
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

static float
srgbChannelToLinear(float value) {
    return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4);
}

static float3
srgbToLinear(float3 color) {
    return float3(
        srgbChannelToLinear(color.r),
        srgbChannelToLinear(color.g),
        srgbChannelToLinear(color.b));
}

static float3
rainbowStripe(float idx) {
    if (idx < 1.0) return srgbToLinear(float3(1.00, 0.00, 0.00));
    if (idx < 2.0) return srgbToLinear(float3(1.00, 0.60, 0.00));
    if (idx < 3.0) return srgbToLinear(float3(1.00, 1.00, 0.00));
    if (idx < 4.0) return srgbToLinear(float3(0.20, 1.00, 0.00));
    if (idx < 5.0) return srgbToLinear(float3(0.00, 0.60, 1.00));
    return srgbToLinear(float3(0.50, 0.20, 1.00));
}

static float3
over(float3 dst, float4 src) {
    return lerp(dst, src.rgb, src.a);
}

static float4
drawNyan(float2 p, float2 cellSize, float time) {
    float4 col = float4(0.0);
    float s = min(cellSize.x, cellSize.y * 0.55);

    float2 bodyHalf = float2(s * 1.20, s * 0.80);
    float bodyRadius = s * 0.18;
    float crustDistance = sdRoundBox(p, bodyHalf, bodyRadius);
    if (crustDistance < 0.0) col = float4(srgbToLinear(float3(0.62, 0.36, 0.18)), 1.0);

    float frostDistance = sdRoundBox(p, bodyHalf - float2(s * 0.18), bodyRadius * 0.7);
    if (frostDistance < 0.0) col = float4(srgbToLinear(float3(1.00, 0.72, 0.82)), 1.0);

    if (frostDistance < -s * 0.05) {
        float2 sprinklePos = p / (s * 0.35);
        float2 sprinkleCell = floor(sprinklePos);
        float2 f = frac(sprinklePos) - 0.5;
        float h = hash21(sprinkleCell);
        if (h > 0.45 && length(f) < 0.18) {
            float3 sprinkleColor = float3(1.0);
            if (h < 0.6) sprinkleColor = float3(0.20, 0.85, 1.00);
            else if (h < 0.75) sprinkleColor = float3(1.00, 0.85, 0.20);
            else if (h < 0.9) sprinkleColor = float3(1.00, 0.30, 0.80);
            else sprinkleColor = float3(0.30, 1.00, 0.40);
            col = float4(srgbToLinear(sprinkleColor), 1.0);
        }
    }

    float legY = -bodyHalf.y - s * 0.10;
    float legWiggle = sin(time * 14.0) * s * 0.05;
    for (int i = 0; i < 2; i++) {
        float xo = (i == 0 ? -1.0 : 1.0) * s * 0.55;
        float yo = legY + (i == 0 ? legWiggle : -legWiggle);
        float2 legPos = p - float2(xo, yo);
        float legDistance = sdRoundBox(legPos, float2(s * 0.12, s * 0.18), s * 0.06);
        if (legDistance < 0.0) col = float4(srgbToLinear(float3(0.55, 0.55, 0.60)), 1.0);
    }

    float2 headCenter = float2(bodyHalf.x + s * 0.35, s * 0.10);
    float2 headPos = p - headCenter;
    float2 squashedHeadPos = headPos * float2(1.0, 1.15);
    if (sdCircle(squashedHeadPos, s * 0.55) < 0.0)
        col = float4(srgbToLinear(float3(0.78, 0.78, 0.80)), 1.0);

    for (int i = 0; i < 2; i++) {
        float xo = (i == 0 ? -1.0 : 1.0) * s * 0.32;
        float2 earPos = headPos - float2(xo, s * 0.45);
        float angle = i == 0 ? -0.5 : 0.5;
        float cosine = cos(angle);
        float sine = sin(angle);
        float2 rotatedEarPos = float2(
            cosine * earPos.x - sine * earPos.y,
            sine * earPos.x + cosine * earPos.y);
        if (sdRoundBox(rotatedEarPos, float2(s * 0.14, s * 0.18), s * 0.04) < 0.0)
            col = float4(srgbToLinear(float3(0.78, 0.78, 0.80)), 1.0);
    }

    for (int i = 0; i < 2; i++) {
        float xo = (i == 0 ? -1.0 : 1.0) * s * 0.20;
        float2 eyePos = headPos - float2(xo, s * 0.05);
        if (sdCircle(eyePos, s * 0.10) < 0.0)
            col = float4(srgbToLinear(float3(0.05)), 1.0);
    }

    for (int i = 0; i < 2; i++) {
        float xo = (i == 0 ? -1.0 : 1.0) * s * 0.34;
        float2 cheekPos = headPos - float2(xo, -s * 0.12);
        if (sdCircle(cheekPos, s * 0.09) < 0.0)
            col = float4(srgbToLinear(float3(1.00, 0.55, 0.70)), 1.0);
    }

    if (sdCircle(headPos - float2(0.0, -s * 0.10), s * 0.05) < 0.0)
        col = float4(srgbToLinear(float3(0.05)), 1.0);

    return col;
}

public float4
fragment_main(float4 color, KittyTextures textures, KittyCustomShaderData data) {
    if (data.cursor_trail_change_time <= 0.0) return color;

    float previousEdgeMagnitude = dot(abs(data.cursor_trail_prev_edge), float4(1.0));
    if (previousEdgeMagnitude <= 1e-6) return color;

    float2 pixelDimensions = max(
        float2(data.viewport_size_pixels) * textures.viewport.zw,
        float2(1.0));
    float2 pixel = textures.pos * pixelDimensions;

    float4 currentEdge = data.cursor_trail_edge;
    float4 previousEdge = data.cursor_trail_prev_edge;
    float2 currentSize = float2(
        (currentEdge.y - currentEdge.x) * pixelDimensions.x,
        (currentEdge.z - currentEdge.w) * pixelDimensions.y);
    float2 previousSize = float2(
        (previousEdge.y - previousEdge.x) * pixelDimensions.x,
        (previousEdge.z - previousEdge.w) * pixelDimensions.y);
    if (min(currentSize.x, currentSize.y) <= 0.0) return color;

    float2 currentCenter = float2(
        (currentEdge.x + currentEdge.y) * 0.5 * pixelDimensions.x,
        (currentEdge.z + currentEdge.w) * 0.5 * pixelDimensions.y);
    float2 previousCenter = float2(
        (previousEdge.x + previousEdge.y) * 0.5 * pixelDimensions.x,
        (previousEdge.z + previousEdge.w) * 0.5 * pixelDimensions.y);

    float2 toCurrent = currentCenter - previousCenter;
    float jumpDistance = length(toCurrent);
    float jumpStrength = smoothstep(currentSize.x * 1.2, currentSize.x * 3.0, jumpDistance);
    if (jumpStrength <= 0.001) return color;

    float elapsed = max(data.timestamp - data.cursor_trail_change_time, 0.0);
    float flightT = clamp(elapsed / FLY_DURATION, 0.0, 1.0);
    float flightProgress = flightT * flightT * (3.0 - 2.0 * flightT);
    float2 flightCenter = lerp(previousCenter, currentCenter, flightProgress);

    float morphT = clamp((elapsed - FLY_DURATION) / CAT_LIFE, 0.0, 1.0);
    float catAlpha = (1.0 - smoothstep(0.6, 1.0, morphT)) * jumpStrength;
    float trailElapsed = max(elapsed - FLY_DURATION, 0.0);
    float trailAlpha = exp(-trailElapsed / TRAIL_LIFE * 2.5) * jumpStrength;

    float2 cursorDistance = abs(pixel - currentCenter) - currentSize * 0.5;
    float destinationMask = smoothstep(0.75, 1.0, flightProgress) * catAlpha;
    float3 outputColor = color.rgb;
    if (max(cursorDistance.x, cursorDistance.y) < 0.0 && destinationMask > 0.01) {
        outputColor = lerp(outputColor, data.active_window_background.rgb, destinationMask);
    }

    float maxTrailLength = currentSize.x * 10.0;
    float tailProgress = max(0.0, flightProgress - maxTrailLength / max(jumpDistance, 1.0));
    float2 tailCenter = lerp(previousCenter, currentCenter, tailProgress);
    float liveTrailLength = distance(tailCenter, flightCenter);

    if (jumpDistance > currentSize.x * 1.2 && liveTrailLength > currentSize.x * 0.5 && trailAlpha > 0.01) {
        float2 segment = segInfo(pixel, tailCenter, flightCenter);
        float perpendicularDistance = segment.x;
        float along = segment.y;
        float bandHeight = currentSize.y * 0.45;
        float waveAmplitude = currentSize.y * 0.12;

        if (perpendicularDistance < bandHeight + waveAmplitude) {
            float catScale = min(currentSize.x, currentSize.y * 0.55);
            float catBackDistance = catScale * 1.05;
            float catCutoff = 1.0 - clamp(catBackDistance / liveTrailLength, 0.0, 0.9);
            if (along < catCutoff) {
                float2 direction = normalize(flightCenter - tailCenter);
                float2 normal = float2(-direction.y, direction.x);
                if (normal.y > 0.0) normal = -normal;
                float perpendicular = dot(pixel - lerp(tailCenter, flightCenter, along), normal);
                float waveEnvelope = sin(3.14159265358979 * clamp(along / max(catCutoff, 1e-4), 0.0, 1.0));
                float waveOffset = sin(along * 16.0 - data.timestamp * 8.0) * waveAmplitude * waveEnvelope;
                float bandPosition = (perpendicular - waveOffset) / bandHeight;
                if (abs(bandPosition) < 1.0) {
                    float stripeIndex = clamp(floor((bandPosition * 0.5 + 0.5) * 6.0), 0.0, 5.0);
                    float3 stripeColor = rainbowStripe(stripeIndex);
                    stripeColor += sin(along * 18.0 - data.timestamp * 12.0) * 0.04;

                    float tailFade = smoothstep(0.0, 0.05, along);
                    float age = trailElapsed + 0.18 * (1.0 - along);
                    float localAlpha = exp(-age / TRAIL_LIFE * 2.5) * jumpStrength;
                    float alpha = localAlpha * tailFade;
                    outputColor = lerp(outputColor, stripeColor, alpha);

                    float edge = smoothstep(0.95, 1.0, abs(bandPosition));
                    outputColor = lerp(outputColor, float3(1.0), edge * alpha * 0.6);
                }
            }
        }
    }

    if (jumpDistance > currentSize.x * 1.2 && liveTrailLength > currentSize.x * 0.5 && trailAlpha > 0.01) {
        for (int i = 0; i < 3; i++) {
            float index = float(i);
            float position = frac(0.15 + index * 0.27 - data.timestamp * 0.6);
            float2 starPosition = lerp(flightCenter, tailCenter, position);
            starPosition += float2(
                sin(data.timestamp * 4.0 + index),
                cos(data.timestamp * 3.5 + index * 2.0)) * currentSize.y * 0.35;
            float starDistance = sdCircle(pixel - starPosition, currentSize.y * 0.06);
            float starAge = trailElapsed + 0.18 * position;
            float starAlpha = exp(-starAge / TRAIL_LIFE * 2.5) * jumpStrength;
            float alpha = smoothstep(0.0, -currentSize.y * 0.06, starDistance) * starAlpha * 0.8;
            outputColor = lerp(outputColor, float3(1.0), alpha);
        }
    }

    float angle = 0.0;
    float flipX = 1.0;
    if (jumpDistance > 0.5) {
        angle = atan2(toCurrent.y, toCurrent.x);
        if (toCurrent.x < 0.0) {
            angle += 3.14159265358979;
            flipX = -1.0;
        }
    }

    float cosine = cos(angle);
    float sine = sin(angle);
    float2 relative = pixel - flightCenter;
    float2 local = float2(
        cosine * relative.x + sine * relative.y,
        -sine * relative.x + cosine * relative.y);
    local.x *= flipX;

    float shrinkProgress = smoothstep(0.3, 0.0, catAlpha);
    local *= lerp(1.0, 2.2, shrinkProgress);

    float4 cat = drawNyan(local, currentSize, data.timestamp);
    cat.a *= catAlpha;
    outputColor = over(outputColor, cat);

    return float4(outputColor, color.a);
}
