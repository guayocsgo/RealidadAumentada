#ifndef FURBRUSH_COMMON_INCLUDED
#define FURBRUSH_COMMON_INCLUDED

// Pipeline-agnostic helpers shared by every FurBrush shader: control-map decode,
// hashes / strand pattern, and the Kajiya-Kay anisotropic highlight. No URP/HDRP
// includes here on purpose so this file can be reused anywhere (incl. the Blit brush).

// ----------------------------------------------------------------------------
// Control map  (R = length 0..1, G = mask 0..1, B,A = comb direction packed 0..1)
// ----------------------------------------------------------------------------
struct FurControl
{
    float  length;   // 0..1  multiply by _MaxLength
    float  mask;     // 0..1  fur presence / density
    float2 comb;     // -1..1 tangent-space flow direction
};

FurControl DecodeFurControl(float4 c, float hasControlMap)
{
    FurControl o;
    if (hasControlMap < 0.5)
    {
        o.length = 1.0;
        o.mask   = 1.0;
        o.comb   = float2(0.0, 0.0);
    }
    else
    {
        o.length = c.r;
        o.mask   = c.g;
        o.comb   = c.ba * 2.0 - 1.0;
    }
    return o;
}

// Generates a stable, continuous orthonormal basis for a normal n.
// Swizzled Frisvad method placing the singularity at n.y = -1.0 (bottom of mesh).
void GetStableBasis(float3 n, out float3 t, out float3 b)
{
    if (n.y < -0.9999)
    {
        t = float3(1.0, 0.0, 0.0);
        b = float3(0.0, 0.0, 1.0);
        return;
    }
    float a = 1.0 / (1.0 + n.y);
    float d = -n.x * n.z * a;
    t = float3(1.0 - n.x * n.x * a, -n.x, d);
    b = float3(d, -n.z, 1.0 - n.z * n.z * a);
}

// ----------------------------------------------------------------------------
// Hashes  (Dave Hoskins, https://www.shadertoy.com/view/4djSRW)
// ----------------------------------------------------------------------------
float FurHash11(float p)
{
    p = frac(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return frac(p);
}

float FurHash21(float2 p)
{
    float3 p3 = frac(p.xyx * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float2 FurHash22(float2 p)
{
    float3 p3 = frac(p.xyx * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

// Smooth value noise for low-frequency clumping.
float FurValueNoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = FurHash21(i + float2(0, 0));
    float b = FurHash21(i + float2(1, 0));
    float c = FurHash21(i + float2(0, 1));
    float d = FurHash21(i + float2(1, 1));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

// ----------------------------------------------------------------------------
// Clumping — strands lean into shared tufts.
//
// Tuft centres are one jittered point per FUR_CLUMP_SPACING x FUR_CLUMP_SPACING block of strand
// cells, and a strand leans toward the NEAREST point of the 3x3 block neighbourhood, with the pull
// fading to zero at the parting it shares with the next tuft. Both halves matter:
//
//  * nearest-of-9, faded out toward the parting with the next tuft, keeps the field continuous.
//    The previous version pinned every strand to its OWN block's centre, so the pull direction
//    flipped across every block border and the 10x10-cell block lattice printed itself into the
//    coat as an even grid of tufts with bare gutters between them — the "grid / mesh" pattern.
//  * the pull is capped so the strand centre stays inside its own cell. Coverage only tests the
//    strand that belongs to the shaded cell, so a strand dragged past the cell border used to
//    vanish outright; at higher Clumping that deleted most of the coat and left regularly spaced
//    survivors, which is the other half of the same look.
//
// The tuft lookup depends on position alone, so a caller that tests several neighbouring strands
// resolves it ONCE and shares it: neighbours sit within a cell of each other while tufts are
// several cells apart, and where the assignment would differ the fade has already reached ~0.
// ----------------------------------------------------------------------------
#define FUR_CLUMP_SPACING 2.5    // strand cells between tuft centres
#define FUR_CLUMP_EDGE    2.4    // how fast a strand stops belonging to its tuft near the parting

struct FurTuft
{
    float2 center;     // nearest tuft centre, in strand-cell space
    float  rival;      // distance to the SECOND nearest centre — where this tuft's territory ends
    float  strength;   // 0 = this patch stays unclumped, up to 1 = tight
};

FurTuft FurFindTuft(float2 cellPos)
{
    float2 blockId = floor(cellPos / FUR_CLUMP_SPACING);

    float  d1 = 1e9, d2 = 1e9;
    float2 c1 = cellPos;
    float  s1 = 0.0;

    [unroll]
    for (int y = -1; y <= 1; y++)
    {
        [unroll]
        for (int x = -1; x <= 1; x++)
        {
            float2 nb = blockId + float2(x, y);
            float2 h  = FurHash22(nb + 13.7);
            float  d  = length((nb + h) * FUR_CLUMP_SPACING - cellPos);
            if (d < d1)
            {
                d2 = d1;
                d1 = d;
                c1 = (nb + h) * FUR_CLUMP_SPACING;
                // A second, decorrelated random out of the same hash: ~15% of tufts stay flat and
                // the rest gather with their own tightness, so a coat never clumps uniformly.
                float r = frac(dot(h, float2(7.31, 3.17)));
                s1 = step(0.15, r) * lerp(0.35, 1.0, r);
            }
            else if (d < d2)
            {
                d2 = d;
            }
        }
    }

    FurTuft o;
    o.center   = c1;
    o.rival    = d2;
    o.strength = s1;
    return o;
}

// Response curve for the Clumping slider: 0 at 0, still climbing at the shader's 4 maximum, never
// past 1 so both the pull and the height cone stay bounded whatever the artist types in.
float FurClumpAmount(float clumping)
{
    return saturate(clumping / (1.0 + clumping * 0.4));
}

// Leans one strand into its tuft. `strandPos` is the strand's UNCLUMPED centre in absolute cell
// space and `maxPull` is how far it may travel — pass the distance that still leaves the centre
// inside its own cell. `t` is shell height, so roots stay planted and the tips do the gathering.
// `heightMul` returns the tuft's cone profile: full height in the core, shorter out by the parting.
float2 FurClumpStrand(FurTuft tuft, float2 strandPos, float clumping, float t, float strandRand,
                      float maxPull, out float heightMul)
{
    float2 d    = tuft.center - strandPos;
    float  dist = sqrt(max(dot(d, d), 1e-8));

    // Worley F2-F1: 1 at the tuft's centre, exactly 0 where two tufts meet. Everything below is
    // scaled by it, so the pull direction can only flip at a parting where its magnitude has
    // already reached 0 — which is what keeps the whole field continuous and seam-free.
    float core = saturate((tuft.rival - dist) / max(tuft.rival + dist, 1e-5) * FUR_CLUMP_EDGE);

    float amount = FurClumpAmount(clumping) * tuft.strength;

    // A tuft is a cone: the strands gathered into its core keep their height, the ones left out by
    // the parting are shorter. This replaces the old fixed-frequency value-noise height mask, whose
    // axis-aligned lattice showed through as square patches of long and short fur.
    heightMul = lerp(1.0, lerp(0.3, 1.0, core), amount * 0.9);

    float pull = min(dist * amount * core * lerp(0.6, 1.4, strandRand) * t, maxPull);
    return strandPos + d * (pull / dist);
}

// ----------------------------------------------------------------------------
// Curl / wave — the strand traces a helix as it rises instead of running straight.
//
//   t      : 0..1 along the strand (0 = root, 1 = tip)
//   phase  : per-card or per-GPU-strand starting angle
//   amount : lateral amplitude, as a fraction of strand length
//   freq   : turns (or waves) along the strand
//   shape  : 0 = flat wave / crimp, 1 = full helix / ringlets
//
// Anchored at the root: both components are 0 at t = 0, so the strand still leaves the skin
// where it was seeded. `slope` is the exact derivative with respect to t, for callers that build
// their shading tangent from the curve rather than from the root-to-point direction.
// ----------------------------------------------------------------------------
#define FUR_CURL_TAU 6.2831853

float2 FurCurlOffset(float t, float phase, float amount, float freq, float shape, out float2 slope)
{
    float omega = FUR_CURL_TAU * freq;
    float theta = phase + omega * t;
    float s     = saturate(shape);
    slope = float2(-sin(theta) * s, cos(theta)) * (amount * omega);
    return float2((cos(theta) - cos(phase)) * s, sin(theta) - sin(phase)) * amount;
}

// Horizontal starts across the local strand/card width. Vertical keeps the perpendicular axis,
// effectively rotating the curl plane 90 degrees around the strand. Apply this to both the
// position and its derivative so ribbon orientation and anisotropic lighting follow the same curl.
float2 FurOrientCurl(float2 value, float direction)
{
    return direction < 0.5 ? value.yx : value;
}

// Cards and GPU Strands carry curl as a continuous polyline, one sample per bend segment. What
// breaks at high frequency is sampling: the
// slope between two samples is amount * TAU * freq whatever the segment count, but below roughly
// four samples per turn the polyline stops tracing the helix at all and kinks into a zigzag.
// Hence the criterion is samples per turn, and full amplitude is reached at segments >= 4 * freq.
#define FUR_CURL_SAMPLES_PER_TURN 4.0

float FurCurlRibbonAmplitude(float amount, float freq, float segments)
{
    float samplesPerTurn = max(segments, 1.0) / max(freq, 1e-5);
    return amount * saturate(samplesPerTurn / FUR_CURL_SAMPLES_PER_TURN);
}

// ----------------------------------------------------------------------------
// Helper to safely normalize a 2D vector with fallback
// ----------------------------------------------------------------------------
float2 FurSafeDir(float2 v, float2 fallback)
{
    float l2 = dot(v, v);
    return l2 > 1e-8 ? v * rsqrt(l2) : fallback;
}

// ----------------------------------------------------------------------------
// Strand coverage for a shell at normalized height t (0 = skin, 1 = tip).
//   uv        : UV0 (will be scaled by density internally)
//   density   : strands per UV unit
//   t         : current shell height 0..1
//   thinness  : 0..1 how fast strands taper toward the tip
//   jitter    : 0..1 random per-strand height variation
//   clumping  : how hard strands gather into tufts (see FurFindTuft / FurClumpStrand)
//   flowDir   : direction to stretch the strand along
//   flowStretch : stretch scale factor (>= 1.0)
// Returns soft coverage in 0..1.
// ----------------------------------------------------------------------------
float FurStrandCoverage(float2 uv, float density, float t, float thinness, float jitter, float clumping, float pixelSize, float2 flowDir, float flowStretch)
{
    const float jitterRange = 0.5;
    float2 cell   = uv * density;
    float2 id     = floor(cell);
    float2 f      = frac(cell);
    float2 center = 0.5 + (FurHash22(id) - 0.5) * jitterRange;

    // Pull strands together into tufts (clumping); see FurFindTuft / FurClumpStrand above.
    float clumpHeight = 1.0;
    if (clumping > 0.01)
    {
        FurTuft tuft = FurFindTuft(cell);
        center = FurClumpStrand(tuft, id + center, clumping, t, FurHash21(id + 42.1),
                                0.5 - jitterRange * 0.5, clumpHeight) - id;
    }

    // Radius shrinks toward the tip -> tapered strands.
    float r = lerp(0.5, 0.16, thinness) * saturate(1.0 - t * 0.85);

    // Dynamic distance thickness adjustment: keep strands visible and reduce aliasing
    // by ensuring the strand radius in cell space doesn't shrink below 0.25 of the screen pixel size.
    r = max(r, min(pixelSize * 0.25, 0.4));

    // Thickening at grazing angles based on flowStretch to prevent gap separation (scales down towards tips to preserve tapering)
    r *= 1.0 + min(max(0.0, flowStretch - 1.0), 10.0) * 0.06 * saturate(1.0 - t * 0.85);

    float2 dir = FurSafeDir(flowDir, float2(1.0, 0.0));
    float2 p = f - center;
    float halfLen = r * max(0.0, flowStretch - 1.0);
    p -= dir * clamp(dot(p, dir), -halfLen, halfLen);

    float d = length(p);

    float strand = 1.0 - smoothstep(r * 0.55, r, d);

    // Per-strand max height, shortened toward the rim of the strand's tuft (cone profile).
    float h = lerp(1.0, FurHash21(id + 11.5), jitter) * clumpHeight;
    float alive  = step(t, h);
    return strand * alive;
}

// ----------------------------------------------------------------------------
// Kajiya-Kay anisotropic highlight along strand tangent T (world space).
// ----------------------------------------------------------------------------
float FurKajiyaKay(float3 T, float3 L, float3 V, float exponent)
{
    float3 H     = normalize(L + V);
    float  dotTH = dot(T, H);
    float  sinTH = sqrt(saturate(1.0 - dotTH * dotTH));
    return pow(sinTH, exponent);
}

#endif // FURBRUSH_COMMON_INCLUDED
