#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uTime;
    float uWidth;
    float uHeight;
    float uRadius;
    float uIntensity;
    float uAnimate;
    vec4 uTint;
};

float roundedBoxSdf(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

float waterCaustic(vec2 uv, float t) {
    vec2 p = uv * vec2(4.5, 3.2);
    float w1 = sin(p.x * 1.9 + t * 1.15 + sin(p.y * 2.1 - t * 0.85));
    float w2 = cos(p.y * 2.4 - t * 0.95 + cos(p.x * 1.7 + t * 1.05));
    float w3 = sin((p.x + p.y) * 2.2 - t * 0.7);
    float crest = abs(w1 + w2 + 0.55 * w3) / 2.55;
    // Narrow bright caustic filaments like sunlight refracting through water
    return pow(1.0 - clamp(crest, 0.0, 1.0), 3.6);
}

void main() {
    vec2 size = max(vec2(uWidth, uHeight), vec2(2.0));
    float r = clamp(uRadius, 1.0, min(size.x, size.y) * 0.5);
    vec2 px = (qt_TexCoord0 - 0.5) * size;
    float d = roundedBoxSdf(px, size * 0.5, r);

    // Mask cleanly outside rounded card bounds
    float inside = 1.0 - smoothstep(-1.2, 0.8, d);
    if (inside <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // Distance inward from outer glass rim (0 at edge, >0 inside)
    float edgeDist = max(0.0, -d);

    // Fresnel curved rim glow + directional specular catchlight (top-left warm/white, bottom-right cool tint)
    float rim = exp(-edgeDist * 0.42) * inside;
    float crispBorder = smoothstep(2.2, 0.0, edgeDist) * inside;

    vec2 normCoord = qt_TexCoord0 - 0.5;
    float topLeftLight = clamp(dot(normalize(-normCoord + vec2(-0.35, -0.55)), vec2(0.6, 0.8)), 0.0, 1.0);
    float bottomRightLight = clamp(dot(normalize(normCoord + vec2(0.35, 0.55)), vec2(0.6, 0.8)), 0.0, 1.0);

    // Chromatic dispersion shimmer at curved edges
    float dispPhase = sin(qt_TexCoord0.x * 6.2831 + qt_TexCoord0.y * 4.5 - uTime * 0.8 * uAnimate);
    vec3 prism = vec3(
        0.72 + 0.28 * sin(dispPhase + 0.0),
        0.82 + 0.18 * sin(dispPhase + 2.094),
        0.95 + 0.05 * sin(dispPhase + 4.188)
    );

    // Subtle animated water optics caustic ribbon
    float t = uTime * uAnimate;
    float caustic = waterCaustic(qt_TexCoord0, t);
    // Concentrate caustics gracefully near curves & gentle diagonal refraction sweep
    float edgeFocus = mix(0.28, 1.0, exp(-edgeDist * 0.06));
    float waterGlow = caustic * edgeFocus * 0.28;

    // Soft glass dome reflection at top
    float topDome = smoothstep(0.62, 0.0, qt_TexCoord0.y) * 0.085;

    vec3 highlightCol = mix(vec3(1.0), uTint.rgb * 1.25 + vec3(0.25), 0.35);
    vec3 rimCol = mix(highlightCol, prism, 0.38);

    vec3 col = rimCol * (rim * (0.28 + 0.35 * topLeftLight) + crispBorder * 0.42)
             + highlightCol * (topDome + waterGlow + bottomRightLight * rim * 0.18);

    float alpha = (rim * 0.24 + crispBorder * 0.36 + topDome + waterGlow * 0.65) * uIntensity * inside;
    alpha = clamp(alpha, 0.0, 0.65) * qt_Opacity;

    fragColor = vec4(col * alpha, alpha);
}
