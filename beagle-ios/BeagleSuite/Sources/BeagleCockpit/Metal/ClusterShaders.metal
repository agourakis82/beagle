//
//  ClusterShaders.metal
//  BeagleCockpit
//
//  Metal shaders for the 3D cluster topology visualization.
//  Matches the web cockpit's Three.js scene: emissive sphere nodes
//  with breathing glow, edges between nodes, data flow particles.
//
//  Colors (matching web cockpit):
//   - Healthy/Observed:  0x51D6BD  (teal)
//   - Degraded/Warm:     0xF4C15E  (gold)
//   - Error:             0xEF4444  (red)
//   - Control/Declared:  0x9FB2CD  (slate)
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Shared types

struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal   [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float  emissive;
};

struct NodeUniforms {
    float4x4 mvp;
    float4x4 model;
    float3   nodeColor;
    float    time;
    float    health;     // 1.0 = healthy, 0.0 = down
    float    radius;
};

struct EdgeUniforms {
    float4x4 mvp;
    float3   color;
    float    time;
    float    opacity;
};

struct SceneUniforms {
    float4x4 viewProjection;
    float3   cameraPos;
    float    time;
};

// MARK: - Node vertex shader

vertex VertexOut nodeVertex(
    VertexIn in [[stage_in]],
    constant NodeUniforms &uniforms [[buffer(1)]]
) {
    // Breathing scale: healthy nodes pulse gently
    float breathe = 1.0 + uniforms.health * 0.05 * sin(uniforms.time * 0.8);
    float3 scaledPos = in.position * uniforms.radius * breathe;

    VertexOut out;
    out.position = uniforms.mvp * float4(scaledPos, 1.0);
    out.worldPos = (uniforms.model * float4(scaledPos, 1.0)).xyz;
    out.normal = normalize((uniforms.model * float4(in.normal, 0.0)).xyz);

    // Emissive intensity: 0.2 + 0.15 * sin(t * 0.8) for healthy nodes
    out.emissive = 0.2 + uniforms.health * 0.15 * sin(uniforms.time * 0.8);

    return out;
}

// MARK: - Node fragment shader (PBR + emissive glow)

fragment float4 nodeFragment(
    VertexOut in [[stage_in]],
    constant NodeUniforms &uniforms [[buffer(1)]]
) {
    float3 color = uniforms.nodeColor;

    // Simple Blinn-Phong with emissive
    float3 lightDir = normalize(float3(0.5, 1.0, 0.3));
    float NdotL = max(dot(in.normal, lightDir), 0.0);

    // Diffuse
    float3 diffuse = color * (0.3 + 0.4 * NdotL);

    // Emissive glow
    float3 emissive = color * in.emissive;

    // Rim light for depth
    float3 viewDir = normalize(float3(0, 0, 1)); // simplified
    float rim = 1.0 - max(dot(in.normal, viewDir), 0.0);
    float3 rimColor = color * pow(rim, 3.0) * 0.2;

    float3 final = diffuse + emissive + rimColor;

    // Metallic feel
    final = mix(final, color * 0.8, 0.3); // metalness 0.6 from web

    return float4(final, 1.0);
}

// MARK: - Glow billboard vertex shader

struct GlowVertexIn {
    float3 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
};

struct GlowVertexOut {
    float4 position [[position]];
    float2 uv;
    float  glowIntensity;
};

vertex GlowVertexOut glowVertex(
    GlowVertexIn in [[stage_in]],
    constant NodeUniforms &uniforms [[buffer(1)]]
) {
    GlowVertexOut out;
    float scale = uniforms.radius * 3.0; // glow is 3x node size
    float3 pos = in.position * scale;
    out.position = uniforms.mvp * float4(pos, 1.0);
    out.uv = in.uv;

    // Glow oscillates: 0.08 + 0.08 * sin(t * 0.6)
    out.glowIntensity = uniforms.health * (0.08 + 0.08 * sin(uniforms.time * 0.6));

    return out;
}

fragment float4 glowFragment(
    GlowVertexOut in [[stage_in]],
    constant NodeUniforms &uniforms [[buffer(1)]]
) {
    // Radial falloff from center
    float2 center = in.uv - 0.5;
    float dist = length(center) * 2.0;
    float falloff = exp(-dist * dist * 3.0);

    float3 color = uniforms.nodeColor * falloff * in.glowIntensity;
    float alpha = falloff * in.glowIntensity;

    return float4(color, alpha);
}

// MARK: - Edge line shader

struct EdgeVertexIn {
    float3 position [[attribute(0)]];
};

struct EdgeVertexOut {
    float4 position [[position]];
    float  alpha;
};

vertex EdgeVertexOut edgeVertex(
    EdgeVertexIn in [[stage_in]],
    constant EdgeUniforms &uniforms [[buffer(1)]]
) {
    EdgeVertexOut out;
    out.position = uniforms.mvp * float4(in.position, 1.0);
    out.alpha = uniforms.opacity;
    return out;
}

fragment float4 edgeFragment(
    EdgeVertexOut in [[stage_in]],
    constant EdgeUniforms &uniforms [[buffer(1)]]
) {
    return float4(uniforms.color, in.alpha);
}

// MARK: - Data flow particle shader

struct ParticleIn {
    float3 position [[attribute(0)]];
    float  progress [[attribute(1)]]; // 0-1 along edge
};

struct ParticleOut {
    float4 position [[position]];
    float  pointSize [[point_size]];
    float  brightness;
};

vertex ParticleOut particleVertex(
    ParticleIn in [[stage_in]],
    constant SceneUniforms &scene [[buffer(1)]]
) {
    ParticleOut out;
    out.position = scene.viewProjection * float4(in.position, 1.0);
    out.pointSize = 3.0;

    // Particles pulse as they travel
    out.brightness = 0.3 + 0.7 * sin(in.progress * 3.14159);

    return out;
}

fragment float4 particleFragment(
    ParticleOut in [[stage_in]],
    float2 pointCoord [[point_coord]]
) {
    // Circular particle with soft edge
    float dist = length(pointCoord - 0.5) * 2.0;
    if (dist > 1.0) discard_fragment();

    float alpha = (1.0 - dist) * in.brightness;
    float3 color = float3(0.32, 0.84, 0.74); // teal

    return float4(color * alpha, alpha);
}
