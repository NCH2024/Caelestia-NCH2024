#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float uWidth;
    float uHeight;
    float uRadius;
    float uIntensity;
    float uIsLight;
    vec4 uTint;
};

float roundedBoxSdf(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - halfSize + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec2 size = max(vec2(uWidth, uHeight), vec2(2.0));
    float r = clamp(uRadius, 1.0, min(size.x, size.y) * 0.5);
    vec2 px = (qt_TexCoord0 - 0.5) * size;
    float d = roundedBoxSdf(px, size * 0.5, r);

    // Strictly clip outside rounded rectangle
    float inside = 1.0 - smoothstep(-1.0, 0.5, d);
    if (inside <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // Distance inward from outer glass rim (in logical pixels)
    float edgeDist = max(0.0, -d);

    // Fast exit for pure interior so text/content remains 100% distortion-free
    if (edgeDist > 10.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Outward normal approximation on rounded rect for directional Fresnel reflection
    vec2 dir = normalize(px + vec2(0.0001));
    // Overhead top-left directional specular catchlight (classic Apple Liquid Glass lighting)
    float keyLight = clamp(dot(-dir, normalize(vec2(0.55, 0.84))), 0.0, 1.0);
    // Subtle opposite rim bounce light at bottom-right bevel
    float rimBounce = clamp(dot(dir, normalize(vec2(0.55, 0.84))), 0.0, 1.0);

    // 1.25px razor-sharp optical glass rim + 5px soft curved bevel thickness
    float hairline = smoothstep(1.6, 0.0, edgeDist) * inside;
    float bevelGlow = exp(-edgeDist * 0.52) * inside * 0.45;

    // Modulate edge brightness smoothly around perimeter (brightest at top-left, subtle at sides/bottom)
    float lightCurve = mix(0.24, 1.0, pow(keyLight, 1.45)) + 0.36 * pow(rimBounce, 2.0);

    vec3 neutralSpecular = mix(vec3(1.0), vec3(0.95, 0.97, 1.0), 0.35);
    vec3 tintedSpecular = mix(neutralSpecular, clamp(uTint.rgb * 1.18 + vec3(0.28), 0.0, 1.0), 0.22);

    float lightModeFactor = mix(1.0, 1.25, uIsLight);
    float alpha = (hairline * 0.42 + bevelGlow * 0.18) * lightCurve * uIntensity * lightModeFactor;
    alpha = clamp(alpha, 0.0, 0.58) * qt_Opacity;

    fragColor = vec4(tintedSpecular * alpha, alpha);
}
