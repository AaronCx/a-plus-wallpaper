// SpikeDrift.metal
//
// Original work for a+wallpaper, written for the Phase 0 Live Photo spike.
// No code was taken from Shadertoy, tutorials or other repositories. The
// integer hash implements the published PCG algorithm (M. O'Neill,
// pcg-random.org); the brief asks for a PCG-style hash. Everything else is
// written from scratch.
// License: same as the rest of this repository (pending the owner's choice,
// see docs/DECISIONS.md, item D-2).
//
// A slow, domain-warped colour field. Everything is a pure function of
// (seed, t, pixel): no wall-clock time, no textures, no unbounded loops.

#include <metal_stdlib>
using namespace metal;

struct SpikeUniforms {
    uint  seed;    // 32-bit seed
    float t;       // seconds into the clip, supplied explicitly by the caller
    uint  width;   // output size in pixels
    uint  height;
};

// Fixed at compile time so no input can make the shader loop longer.
constant constexpr int kOctaves = 4;

// Integer hash in the style of the PCG family: one LCG step followed by a
// random xorshift / multiply output permutation. The multiplier and increment
// are the standard 32-bit PCG LCG constants; the output stage follows the
// published RXS-M-XS description (pcg-random.org).
static inline uint pcgHash(uint v) {
    uint state = v * 747796405u + 2891336453u;
    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
    return (word >> 22u) ^ word;
}

static inline float hashToUnit(uint h) {
    return float(h) * (1.0f / 4294967296.0f);
}

// Hash of a lattice point, mixed with the seed.
static inline float latticeValue(int2 cell, uint seed) {
    uint h = pcgHash(uint(cell.x) ^ pcgHash(uint(cell.y) ^ pcgHash(seed)));
    return hashToUnit(h);
}

// Value noise with a quintic fade, in [0, 1].
static float valueNoise(float2 p, uint seed) {
    float2 cellF = floor(p);
    int2 cell = int2(cellF);
    float2 f = p - cellF;
    float2 u = f * f * f * (f * (f * 6.0f - 15.0f) + 10.0f);

    float a = latticeValue(cell, seed);
    float b = latticeValue(cell + int2(1, 0), seed);
    float c = latticeValue(cell + int2(0, 1), seed);
    float d = latticeValue(cell + int2(1, 1), seed);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float layeredNoise(float2 p, uint seed) {
    float sum = 0.0f;
    float amplitude = 0.5f;
    float total = 0.0f;
    for (int octave = 0; octave < kOctaves; ++octave) {
        sum += amplitude * valueNoise(p, seed + uint(octave) * 101u);
        total += amplitude;
        // Rotate-and-scale between octaves so lattice axes don't line up.
        p = float2(1.6f * p.x - 1.2f * p.y, 1.2f * p.x + 1.6f * p.y) + 17.0f;
        amplitude *= 0.5f;
    }
    return sum / total;
}

static float3 hueToRGB(float hue, float saturation, float value) {
    float3 k = fract(float3(hue) + float3(0.0f, 2.0f / 3.0f, 1.0f / 3.0f)) * 6.0f;
    float3 rgb = clamp(abs(k - 3.0f) - 1.0f, 0.0f, 1.0f);
    return value * mix(float3(1.0f), rgb, saturation);
}

kernel void spikeDrift(texture2d<half, access::write> output [[texture(0)]],
                       constant SpikeUniforms &uniforms [[buffer(0)]],
                       uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uniforms.width || gid.y >= uniforms.height) {
        return;
    }

    float2 size = float2(uniforms.width, uniforms.height);
    // Normalise on the short edge so features keep their shape on any aspect.
    float2 p = (float2(gid) + 0.5f - 0.5f * size) / min(size.x, size.y);
    float t = uniforms.t;
    uint seed = uniforms.seed;

    // Two warp passes; the second is driven by the first, which gives the
    // slow "drifting smoke" motion.
    float2 drift = float2(0.21f * t, -0.13f * t);
    float2 q = float2(layeredNoise(2.2f * p + drift, seed),
                      layeredNoise(2.2f * p - drift + 5.2f, seed));
    float2 r = float2(layeredNoise(1.8f * p + 3.0f * q + float2(0.31f * t, 0.0f), seed + 7u),
                      layeredNoise(1.8f * p + 3.0f * q + float2(0.0f, -0.27f * t) + 8.3f, seed + 7u));
    float field = layeredNoise(1.5f * p + 2.5f * r, seed + 13u);

    // Seed-chosen palette: a base hue plus two offsets.
    float baseHue = hashToUnit(pcgHash(seed ^ 0x9E3779B9u));
    float3 deep = hueToRGB(baseHue, 0.75f, 0.18f);
    float3 mid = hueToRGB(baseHue + 0.12f, 0.65f, 0.62f);
    float3 glow = hueToRGB(baseHue - 0.08f, 0.35f, 0.98f);

    float3 colour = mix(deep, mid, smoothstep(0.25f, 0.7f, field));
    colour = mix(colour, glow, smoothstep(0.6f, 0.95f, field * (0.6f + 0.6f * q.x)));

    // Gentle vertical falloff and vignette keep the Lock Screen clock legible.
    float2 uv = float2(gid) / size;
    colour *= mix(0.78f, 1.0f, smoothstep(0.0f, 0.55f, uv.y));
    float vignette = smoothstep(1.25f, 0.35f, length(p));
    colour *= mix(0.65f, 1.0f, vignette);

    output.write(half4(half3(saturate(colour)), 1.0h), gid);
}
