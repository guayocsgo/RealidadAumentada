#ifndef FURBRUSH_CARD_INCLUDED
#define FURBRUSH_CARD_INCLUDED

// Method C: alpha fur cards. Quads inherit the base surface color (sampled at the stored
// base-mesh UV in TEXCOORD2), fade root->tip, and sway in the wind by their root->tip weight
// (UV.y). Strand alpha is procedural by default, or from a supplied texture (_ALPHATEX).

#include "FurPipeline.hlsl"
#include "FurCommon.hlsl"

TEXTURE2D(_BaseMap);   SAMPLER(sampler_BaseMap);
TEXTURE2D(_SmoothnessMap);  SAMPLER(sampler_SmoothnessMap);
TEXTURE2D(_FurAlpha);  SAMPLER(sampler_FurAlpha);
TEXTURE2D(_FurControlMap); SAMPLER(sampler_FurControlMap);
TEXTURE2D(_FurWidthMap); SAMPLER(sampler_FurWidthMap);

CBUFFER_START(UnityPerMaterial)
    float4 _BaseMap_ST;
    float4 _BaseColor;
    float4 _RootColor;
    float4 _TipColor;
    float  _AlbedoInfluence;
    float  _RootAO;
    float  _Smoothness;
    float  _RoughnessInput;
    float  _SmoothnessChannel;
    float  _UseSmoothnessMap;
    float  _AnisoSpecular;
    float  _Rim;
    float  _ShadowOpacity;
    float  _CardStrands;
    float  _Thinness;
    float  _Cutoff;
    float  _AlphaFlipY;
    float  _AlphaMipBias;
    float  _UseAlphaTex;
    float  _AlphaFromLuminance;
    float  _AlphaDither;
    float  _AlphaShading;
    float  _CardSegments;    // bend segments the card mesh was built with; set by FurCardSet
    float  _CardDensity;     // exported meshes only: the share of the baked cards that is drawn,
                             // see Developer/Shaders/FurExportLayout.hlsl. FurBrush never sets it.
    float  _ColorVar;
    float  _CombStrength;
    float  _CombSurfaceAdherence;
    float  _CombTipBend;
    float4 _Gravity;
    float4 _DynamicMotion;
    float4 _Wind;
    float  _GravityStrength;
    float  _MaxLength;
    float  _LengthScale;
    float  _AlbedoProjection;
    float  _CombJitter;
    float  _CurlEnabled;
    float  _Curl;
    float  _CurlAmountRandomness;
    float  _CurlDirection;
    float  _CurlFrequency;
    float  _CurlFrequencyRandomness;
    float  _CurlShape;
    float  _CurlShapeRandomness;
    float  _HasControlMap;
    float  _HasWidthMap;
    float  _DiffuseWrap;     // 1 = established wrap-lit look, 0 = Lambert (matches Lit's shading)
CBUFFER_END

struct CardAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float4 tangentOS  : TANGENT;
    float2 uv         : TEXCOORD0;
    float4 uv1        : TEXCOORD1; // halfW, height, yaw, unused legacy slot
    float4 baseUV     : TEXCOORD2;
    // xy = control-map UV. zw = baked alpha-atlas cell (cellIndex, gridColumns) — written only by
    // the Bake Cards step; dynamic meshes store Vector2 here so zw reads as 0 (= no atlas).
    float4 controlUV  : TEXCOORD3;
};

struct CardDepthVaryings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
    float3 normalWS   : TEXCOORD1;
    float4 controlUV  : TEXCOORD2;
};

// Width axis perpendicular to the strand's curve direction, continuously varying as the strand
// bends (comb + gravity can curl it all the way back over itself, curveDir -> -up). A rotation
// built from cross(from,to) (Rodrigues' formula) is numerically unstable as 'from' and 'to'
// approach anti-parallel (the 1/(1+dot) term blows up) and snaps to an arbitrary fallback exactly
// at the cutoff -> a visible kink in the card right where combing lays the tip flat. Gram-Schmidt
// projection has no such singularity (only degenerates when 'primary' is parallel to curveDir,
// handled below), so the ribbon orientation stays smooth through a full 180 degree curl.
float3 StableWidthAxis(float3 primary, float3 curveDir)
{
    float3 proj = primary - curveDir * dot(primary, curveDir);
    float lenSq = dot(proj, proj);
    if (lenSq > 1e-6) return proj * rsqrt(lenSq);
    float3 fallback = (abs(curveDir.y) < 0.99) ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
    return normalize(cross(curveDir, fallback));
}

float3 CardScaleAndApplyCombAndGravity(float3 rootOS, float3 normalOS, float4 tangentOS, float4 uv1, float2 uv, float2 controlUV, float4 baseUV, out float3 strandDirWS)
{
    float halfW = uv1.x;
    float height = uv1.y;
    float yaw = uv1.z;

    // Sample control map at control UV
    float4 ctrlSample = SAMPLE_TEXTURE2D_LOD(_FurControlMap, sampler_FurControlMap, controlUV, 0);
    FurControl ctrl = DecodeFurControl(ctrlSample, _HasControlMap);

    float widthLoc = 1.0;
    if (_HasWidthMap > 0.5)
    {
        widthLoc = SAMPLE_TEXTURE2D_LOD(_FurWidthMap, sampler_FurWidthMap, controlUV, 0).r;
    }

    // Card height is driven SOLELY by the per-card mesh height (uv1.y — set at scatter time and
    // edited by the per-card Card Height brush) times coverage and the global scale. It no longer
    // reads the control map's R (length) channel: editing card height therefore can't disturb the
    // shared comb map, and there's no global-scale↔map compensation left to fall out of sync.
    // (R stays in use for shell/strands, which have no per-element height of their own.)
    float scaledLength = ctrl.mask * _LengthScale;
    float fullHeight = height * scaledLength;

    // Default (uncombed) width axis: the ACTUAL tangent baked from the brush drag direction at
    // scatter time (FurCardSet stores it as the mesh TANGENT). Re-orthonormalize against the
    // surface normal for safety (skinning can tilt it slightly)
    float3 up = normalize(normalOS);
    float3 draggedTangent = tangentOS.xyz - up * dot(tangentOS.xyz, up);
    float draggedLenSq = dot(draggedTangent, draggedTangent);
    float3 t0_drag = draggedLenSq > 1e-8 ? draggedTangent * rsqrt(draggedLenSq) : normalize(cross(up, float3(1.0, 0.0, 0.0)));

    // Reconstruct base TBN frame. If baseUV.w is 0.0, we fall back to GetStableBasis (legacy/untangented).
    // Otherwise, we rotate the visual tangent t0_drag by theta around the normal up.
    // This is 100% invariant under bone skinning since normalOS and tangentOS rotate together.
    float3 t0_base, b0_base;
    if (baseUV.w == 0.0)
    {
        GetStableBasis(up, t0_base, b0_base);
    }
    else
    {
        float theta = baseUV.z;
        float tangentSign = baseUV.w;
        float3 bitangent = cross(up, t0_drag);
        t0_base = normalize(t0_drag * cos(theta) + bitangent * sin(theta));
        b0_base = normalize(cross(up, t0_base) * tangentSign);
    }

    // 'yaw' is now purely the Yaw Jitter / cross-quad-plane-offset rotation applied ON TOP of the
    // drag-following base — at Yaw Jitter = 0 a card sits exactly along the stroke.
    float rad = yaw * (3.14159265 / 180.0);
    float cosY = cos(rad);
    float sinY = sin(rad);
    float3 t0_scatter = t0_drag * cosY + cross(up, t0_drag) * sinY + up * dot(up, t0_drag) * (1.0 - cosY);
    t0_scatter = normalize(t0_scatter);

    // Flow direction in object space
    float3 flowOS = t0_base * ctrl.comb.x + b0_base * ctrl.comb.y;
    float flowLen = saturate(length(ctrl.comb));

    // Flow magnitude IS the painted Hair Flatness value: 0 = full-height upright card,
    // 1 = fully laid along the surface. A previous 0.85 baseline forced even flatness=0.03
    // almost flat while providing almost no lateral bend, collapsing a 4.6 cm card into a
    // short, wide patch. Keep the mapping direct so the displayed card height stays meaningful.
    float surfaceAdherence = saturate(flowLen * _CombSurfaceAdherence);

    float normalLift = lerp(1.0, 0.0, surfaceAdherence);

    float3 t0 = t0_scatter;
    if (flowLen > 0.001)
    {
        float3 flowDirOS = flowOS / flowLen;
        // Width axis perpendicular to both 'up' and the LIVE painted comb direction. No extra yaw
        // rotation here: once the artist has combed an area, the comb direction alone must decide
        // the orientation, or every card would carry its own baked-in twist on top of the comb —
        // exactly the crooked/sideways look this fixes.
        float3 t0_flow = normalize(cross(up, flowDirOS));

        // Smoothly blend from the scattered tangent to the flow-based tangent in the brush falloff region
        t0 = normalize(lerp(t0_scatter, t0_flow, saturate(flowLen * 10.0)));
    }

    float3 b0 = normalize(cross(up, t0));

    // Combing randomness noise
    float2 id = floor(controlUV * 256.0);
    float2 combRnd = FurHash22(id + 37.1) * 2.0 - 1.0;
    float combJitter = min(_CombJitter, 0.25);
    float3 combNoiseOS = (t0 * combRnd.x + b0 * combRnd.y) * combJitter;
    float3 combLocal = (t0_base * ctrl.comb.x + b0_base * ctrl.comb.y) * (_CombStrength * 0.38) + combNoiseOS * flowLen;

    // Secondary cross-quad plane: useful for volume while the fur stands, but when the card is
    // combed FLAT it is exactly the plane that faces the viewer with its EDGE ("bokiem") — fade it
    // out with surface adherence so the flat-lying primary plane dominates.
    float planeScale = 1.0;
    if (tangentOS.w > 0.5)
    {
        planeScale = lerp(1.0, 0.015, surfaceAdherence);
    }

    float v = saturate(uv.y);
    float taper = 1.0;
    float H = fullHeight * planeScale;

    // Static gravity still fades completely under an authored comb, preserving existing looks.
    // Dynamic world-down is marked in _Gravity.w and keeps half its response at full adherence.
    // Motion is a separate runtime vector: it remains visible even when Gravity Strength is zero.
    float gravityResponse = 1.0 - surfaceAdherence * (1.0 - 0.5 * _Gravity.w);
    float gravFade = _GravityStrength * gravityResponse;
    float motionResponse = 1.0 - surfaceAdherence * 0.5;

    // Tangent projection drives the familiar sideways sway. Preserve the dynamic component parallel
    // to the growth axis separately: projecting it away made a character moving straight up/down
    // leave upright cards completely rigid. A bounded axial spring moves only the free end, while
    // the root remains attached and the existing filtered Motion Sway still controls the response.
    // _Gravity.w marks Dynamic mode; Dynamic gravity/motion and wind are supplied in world space.
    float3 gravityOS = _Gravity.w > 0.5 ? FurWorldToObjectVector(_Gravity.xyz) : _Gravity.xyz;
    float3 motionOS = _Gravity.w > 0.5
        ? FurWorldToObjectVector(_DynamicMotion.xyz)
        : float3(0.0, 0.0, 0.0);
    float3 windOS = FurWorldToObjectVector(_Wind.xyz);
    // Wind is an additive force on top of movement. Combine first so both tangent bending and
    // axial compression use the same vector sum; neither input can replace the other.
    float3 motionAndWindOS = motionOS + windOS;
    float3 externalBendSource = gravityOS * gravFade + motionAndWindOS * motionResponse;
    float motionAxial = dot(motionAndWindOS, up) * motionResponse;
    float3 externalBendT = externalBendSource - up * dot(externalBendSource, up);
    float axialMotion = clamp(motionAxial * 0.35, -0.35, 0.35);

    float3 activeFlow = combLocal;
    if (dot(activeFlow, activeFlow) < 1e-4 && surfaceAdherence > 0.01)
    {
        activeFlow = b0 * (_CombStrength * 0.38) * surfaceAdherence;
    }
    
    float3 bendInput = activeFlow + externalBendT;
    float bendLimit = lerp(1.05, 0.62, surfaceAdherence);
    float bendLen = length(bendInput);
    if (bendLen > bendLimit) bendInput *= bendLimit / bendLen;
    float3 bendLocal = bendInput * ctrl.mask * H;   // H already carries the per-card height (see scaledLength)

    // Smooth cubic Bézier bend. P1 fixes the root tangent to the surface normal; P2 fixes the tip
    // tangent to the groom direction. Bend Segments sample this one continuous curve, so adding
    // subdivisions genuinely makes a smoother arc instead of resolving a kink concentrated at
    // the root or tip. Card Bend blends between the straight chord and the Bézier curve.
    float3 tipOffset = up * (H * normalLift) + bendLocal;
    float tipOffsetLen = length(tipOffset);
    if (tipOffsetLen > H && H > 1e-5) tipOffset *= H / tipOffsetLen;
    tipOffset += up * (H * axialMotion);

    float3 tipAxisRaw = up * (normalLift + axialMotion * 2.0) + bendInput;
    float3 strandAxis = length(tipAxisRaw) > 1e-5 ? normalize(tipAxisRaw) : up;
    float handleLength = H / 3.0;
    float3 p1 = up * handleLength;
    float3 p2 = tipOffset - strandAxis * handleLength;
    float oneMinusV = 1.0 - v;
    float3 bezierOffset =
        3.0 * oneMinusV * oneMinusV * v * p1 +
        3.0 * oneMinusV * v * v * p2 +
        v * v * v * tipOffset;
    float3 straightOffset = tipOffset * v;
    float3 centerOffset = lerp(straightOffset, bezierOffset, saturate(_CombTipBend));

    // Curl follows the already-combed strand axis. The old surface TBN basis failed on flat fur:
    // b0 becomes nearly parallel to strandAxis there, so one "radial" component shortened the
    // card instead of coiling around it. Build a true plane perpendicular to the strand and orient
    // its first bend with the authored comb/gravity direction (or away from the skin once the
    // strand is already flat). A fixed root phase and handedness keep the whole lock bending and
    // winding consistently with that groomed direction instead of neighbouring cards fighting it.
    if (_CurlEnabled > 0.5 && _Curl > 1e-4)
    {
        float curlAmount = saturate(_Curl);
        float randomizedFrequency = max(_CurlFrequency, 0.0);
        float springShape = saturate(_CurlShape);
        if (max(_CurlAmountRandomness, max(_CurlFrequencyRandomness, _CurlShapeRandomness)) > 1e-4)
        {
            // Static mesh attributes provide one stable seed per card. Do not derive this from
            // world position or time: skinning and object motion must never make the pattern shimmer.
            float2 curlSeed = controlUV * 4096.0 +
                float2(yaw * 0.071 + halfW * 463.0, height * 997.0 + yaw * 0.113);
            float amountVariation = FurHash21(curlSeed + 11.7) * 2.0 - 1.0;
            float frequencyVariation = FurHash21(curlSeed + 37.3) * 2.0 - 1.0;
            float shapeVariation = FurHash21(curlSeed + 83.1) * 2.0 - 1.0;

            curlAmount = saturate(_Curl *
                (1.0 + amountVariation * 0.5 * saturate(_CurlAmountRandomness)));
            randomizedFrequency = max(
                0.0,
                _CurlFrequency + frequencyVariation * saturate(_CurlFrequencyRandomness));
            springShape = saturate(
                _CurlShape + shapeVariation * 0.5 * saturate(_CurlShapeRandomness));
        }
        // Frequency 0 is useful authoring input, not a second off switch: low Curl produces one
        // directional quarter-bend, while high Curl grows that into at least one spring turn.
        float curlTurns = max(randomizedFrequency, lerp(0.25, 1.0, curlAmount));
        // Shape is an independent Wavy -> Curly control. Multiplying it by Curl used to
        // attenuate the second (out-of-plane) component twice: once through curlAmp and again
        // here. At normal Curl values that made the entire Shape slider look inert on cards.
        // Curl already controls amplitude, so Shape can directly blend the planar wave into a
        // full helix without changing the overall bend amount.
        float3 curlSide = StableWidthAxis(t0, strandAxis);
        float3 curlOut = normalize(cross(strandAxis, curlSide));
        float3 directionReference = bendInput - strandAxis * dot(bendInput, strandAxis);
        float referenceLenSq = dot(directionReference, directionReference);
        bool flipCurlFrame = referenceLenSq > 1e-6
            ? dot(curlOut, directionReference) < 0.0
            : dot(curlOut, up) < 0.0;
        if (flipCurlFrame)
        {
            curlSide = -curlSide;
            curlOut = -curlOut;
        }

        float2 curlSlope;
        // A card is a polyline of _CardSegments spans, so that is how finely it samples the helix.
        // Full amplitude needs Bend Segments >= 4 x the resolved number of turns.
        float  curlAmp = FurCurlRibbonAmplitude(curlAmount * 0.4, curlTurns, _CardSegments);
        float2 c = FurCurlOffset(v, 0.0, curlAmp, curlTurns, springShape, curlSlope);
        c = FurOrientCurl(c, _CurlDirection);
        curlSlope = FurOrientCurl(curlSlope, _CurlDirection);
        centerOffset += (curlSide * c.x + curlOut * c.y) * H;

        // Small values preserve the clean groom direction; high Curl lets the ribbon tangent and
        // anisotropic highlight follow the coil, which is what makes it read as a spring.
        float3 curledAxis = normalize(strandAxis + curlSide * curlSlope.x + curlOut * curlSlope.y);
        float springFollow = smoothstep(0.15, 0.85, curlAmount);
        float3 followedAxis = lerp(strandAxis, curledAxis, springFollow);
        strandAxis = dot(followedAxis, followedAxis) > 1e-6 ? normalize(followedAxis) : curledAxis;
    }

    // Width axis: one direction shared by the ribbon, perpendicular to the smooth tip tangent.

    // Fixed, view-independent orientation: perpendicular to the strand, no kink at full curl.
    float3 widthDir = StableWidthAxis(t0, strandAxis);
    if (tangentOS.w > 0.5) widthDir = normalize(cross(strandAxis, widthDir)); // 2nd cross-quad plane
    float3 surfaceWidthDir = lerp(widthDir, t0, surfaceAdherence);
    widthDir = dot(surfaceWidthDir, surfaceWidthDir) > 1e-6 ? normalize(surfaceWidthDir) : t0;

    // The ribbon width must ALWAYS stay in the root surface plane. Blending this correction by
    // flowLen made low-flatness cards keep a normal component in their width axis. One root edge
    // then plunged into the body and the clearance correction lifted it visibly above the skin.
    float3 widthDirTangent = widthDir - up * dot(widthDir, up);
    float lenW = length(widthDirTangent);
    if (lenW > 1e-5)
    {
        widthDir = widthDirTangent / lenW;
    }
    else
    {
        widthDir = t0;
    }

    float3 wProj = widthDir * (uv.x - 0.5) * 2.0 * halfW * taper * planeScale * widthLoc;
    float3 offset = centerOffset + wProj;
    
    // Dynamic skin clearance based on width offset to prevent edges from penetrating curved
    // meshes. Proportional but CAPPED: the old 2.5%-of-height + 12%-of-width-offset grew
    // linearly, so tall/wide cards hovered visibly above the skin (a >1 cm root gap on long
    // fur). Height-relative units keep it correct on scaled rigs.
    float distFromCenter = length(wProj);
    float skinClearance = min(max(fullHeight * 0.01, 0.00015) + distFromCenter * 0.05,
                              fullHeight * 0.025);
    // Root vertices are the attachment line and must remain exactly on the geometry. Fade the
    // anti-intersection clearance in over the lower fifth of the card instead of translating the
    // root itself away from the surface.
    skinClearance *= smoothstep(0.0, 0.2, v);
    
    float normalOffset = dot(offset, up);
    if (normalOffset < skinClearance)
    {
        offset += up * (skinClearance - normalOffset);
    }
    strandDirWS = TransformObjectToWorldDir(strandAxis);
    return rootOS + offset;
}

float3 CardScaleAndApplyCombAndGravity(float3 rootOS, float3 normalOS, float4 tangentOS, float4 uv1, float2 uv, float2 controlUV, float4 baseUV)
{
    float3 dummy;
    return CardScaleAndApplyCombAndGravity(rootOS, normalOS, tangentOS, uv1, uv, controlUV, baseUV, dummy);
}

float CardAlpha(float2 uv, float4 controlUV)
{
    uv.y = lerp(uv.y, 1.0 - uv.y, saturate(_AlphaFlipY));
#ifdef _ALPHATEX
    float2 auv = uv;
    // Baked alpha atlas: controlUV.zw = (cellIndex, gridColumns) of a square grid packed at bake
    // time so the whole card set renders with ONE material. Data-driven (w = 0 on dynamic meshes)
    // so no extra shader variant is needed. The slight inset guards against cross-cell bleeding
    // from mipmapping at the shared cell borders.
    if (controlUV.w > 0.5)
    {
        float colsA = controlUV.w;
        float idxA  = controlUV.z;
        float2 cell = float2(fmod(idxA, colsA), floor(idxA / colsA));
        float2 inner = clamp(saturate(uv), 0.002, 0.998);
        auv = (cell + inner) / colsA;
    }
    float4 alphaSample = SAMPLE_TEXTURE2D_BIAS(_FurAlpha, sampler_FurAlpha, auv, _AlphaMipBias);
    #ifdef _ALPHALUM
        return dot(alphaSample.rgb, float3(0.299, 0.587, 0.114));
    #else
        return alphaSample.a;
    #endif
#else
    float cols   = max(1.0, _CardStrands);
    float x      = uv.x * cols;
    float id     = floor(x);
    float fx     = frac(x);
    float center = 0.5 + (FurHash11(id) - 0.5) * 0.4;
    
    float widthLoc = 1.0;
    if (_HasWidthMap > 0.5)
    {
        widthLoc = SAMPLE_TEXTURE2D_LOD(_FurWidthMap, sampler_FurWidthMap, controlUV.xy, 0).r;
    }

    float hw     = lerp(0.45, 0.06, _Thinness) * (1.0 - uv.y * 0.7) * widthLoc;
    float d      = abs(fx - center);
    float a      = 1.0 - smoothstep(hw * 0.6, hw, d);
    float h      = lerp(0.55, 1.0, FurHash11(id + 3.1));
    a *= step(uv.y, h);
    return a;
#endif
}

float GetBayerDither4x4(float2 screenPos)
{
    const float4x4 bayer = float4x4(
        0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0,
        12.0 / 16.0, 4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0,
        3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0,
        15.0 / 16.0, 7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0
    );
    // 4 is a power of two: bit masking avoids the integer-modulo warning on D3D.
    uint2 idx = uint2(floor(screenPos)) & 3u;
    return bayer[idx.x][idx.y];
}

float CardClip(float2 uv, float4 controlUV, float4 positionCS)
{
    float alpha = CardAlpha(uv, controlUV);
    // EDGE-LIMITED dithering. The old form jittered the cutoff by a full ±0.5*_AlphaDither, which
    // at _AlphaDither=1 stipples the WHOLE card face (every texel whose alpha lands anywhere in the
    // dither band), not just the strand silhouette. Scaling the jitter by the per-pixel alpha
    // gradient (fwidth) confines the dither to the ~1px transition around each strand edge, giving
    // soft anti-aliased edges while solid and empty regions stay clean.
    float aa = max(fwidth(alpha), 1e-5);
    float dither = GetBayerDither4x4(positionCS.xy) - 0.5;
    float jitter = dither * _AlphaDither * aa * 2.0;
    clip(alpha - (_Cutoff + jitter));
    // Handed back untouched so the fragment can shade with the very value it clipped on. Nothing
    // here reshapes the mask: the silhouette is decided by _Cutoff alone, exactly as before.
    return alpha;
}

void CardClipShadowOpacity(float4 controlUV)
{
    float opacity = saturate(_ShadowOpacity);
    if (opacity <= 1e-4)
    {
        clip(-1.0);
    }
    else if (opacity < 0.999)
    {
        // controlUV.xy is baked from the card root and remains stable while the object, camera,
        // and directional shadow cascades move. Selecting whole cards also avoids a moving
        // shadow-map-space checkerboard crawling over thin alpha fibres.
        float2 cardSeed = controlUV.xy * 4096.0 + controlUV.zw * float2(17.0, 31.0);
        float dither = FurHash21(cardSeed + 53.19);
        clip(opacity - dither);
    }
}

half SampleCardSmoothness(float2 buv)
{
    half s = _Smoothness;
#ifdef _SMOOTHNESSMAP
    float4 m = SAMPLE_TEXTURE2D(_SmoothnessMap, sampler_SmoothnessMap, buv);
    float4 sel = float4(_SmoothnessChannel < 0.5,
                        _SmoothnessChannel >= 0.5 && _SmoothnessChannel < 1.5,
                        _SmoothnessChannel >= 1.5 && _SmoothnessChannel < 2.5,
                        _SmoothnessChannel >= 2.5);
    s = dot(m, sel);
    #ifdef _ROUGHNESS_INPUT
        s = 1.0 - s;
    #endif
    // The slider acts as a gloss FLOOR under the map, exactly as in the shell shader. Letting the
    // map replace it outright made Smoothness do literally nothing on any model that carries a
    // metallic/smoothness texture — and the harvested map IS bound on card materials, because
    // Apply() guards only the _Smoothness value with !isCards, not the map or its keyword.
    s = max(s, (half)_Smoothness);
#endif
    return saturate(s);
}

#ifdef FURBRUSH_FORWARD_LIGHTING
#ifdef FURBRUSH_URP_NATIVE
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#endif

struct CardVaryings
{
    float4 positionCS : SV_POSITION;
    float2 uv         : TEXCOORD0;
    float2 baseUV     : TEXCOORD1;
    float3 positionWS : TEXCOORD2;
    float3 normalWS   : TEXCOORD3;
    float4 tangentWS  : TEXCOORD4;
    float  fogFactor  : TEXCOORD5;
    float3 rootOS     : TEXCOORD6;
    float4 controlUV  : TEXCOORD7;
    float3 strandDirWS : TEXCOORD8;
};

CardVaryings CardVert(CardAttributes IN)
{
    CardVaryings o = (CardVaryings)0;
    float3 strandDirWS;
    float3 posOS = CardScaleAndApplyCombAndGravity(IN.positionOS.xyz, IN.normalOS, IN.tangentOS, IN.uv1, IN.uv, IN.controlUV.xy, IN.baseUV, strandDirWS);
    float3 positionWS = TransformObjectToWorld(posOS);
    o.positionCS = TransformWorldToHClip(positionWS);
    o.positionWS = positionWS;
    o.normalWS   = TransformObjectToWorldNormal(IN.normalOS);
    o.tangentWS  = float4(TransformObjectToWorldDir(IN.tangentOS.xyz), IN.tangentOS.w);
    o.uv         = IN.uv;
    // baseUV also stores tangent-frame metadata in zw; the fragment only samples xy.
    o.baseUV     = IN.baseUV.xy;
    o.rootOS     = IN.positionOS.xyz;
    o.fogFactor  = ComputeFogFactor(o.positionCS.z);
    o.controlUV  = IN.controlUV;
    o.strandDirWS = strandDirWS;
    return o;
}

half3 ShadeCardLight(Light light, half3 albedo, float3 N, float3 T, float3 V, half gloss, float strandT)
{
    float3 L = light.direction;
    float3 radiance = light.color * (light.shadowAttenuation * light.distanceAttenuation);
    float wrap = FurDiffuseLightingTerm(dot(N, L), _DiffuseWrap);

    // Smoothness tightens the coat body, not just the highlight. Without this the only thing the
    // slider drove on a card was the Kajiya-Kay lobe below, gated by _AnisoSpecular — which the
    // card shader defaults to 0.062 against the shell shader 0.6, so it read as doing nothing at
    // all. Same response the shell shader already applies.
#if defined(FURBRUSH_HDRP_COMPAT)
    float diffuseScale = 1.0;
#else
    float diffuseScale = lerp(1.0, 0.7, gloss * gloss);
#endif

    float3 T1 = normalize(T + 0.08 * N);
    float3 T2 = normalize(T - 0.12 * N);
    float spec1 = FurKajiyaKay(T1, L, V, lerp(45.0, 300.0, gloss));
    float spec2 = FurKajiyaKay(T2, L, V, lerp(15.0, 100.0, gloss));
    float glossMultiplier = lerp(0.5, 2.0, gloss);
    half3 specColor = FurAnisotropicSpecular(albedo, spec1, spec2, _AnisoSpecular, glossMultiplier);

    // True backlight PLUS a fresnel rim, so the slider is visible from any angle. The old
    // dot(-L,V)-only term was ~zero unless the camera looked into the light, which is why Rim
    // appeared dead on cards; the shell shader already carries this fix. abs() on the fresnel
    // because cards draw Cull Off - a card seen from behind should rim at grazing angles, not
    // glow flat across its whole back face.
    float fresnelRim = pow(1.0 - saturate(abs(dot(N, V))), 2.0);
    float back = (saturate(dot(-L, V)) * 0.7 + fresnelRim * 0.6)
               * _Rim * (1.0 + _Rim * 1.5) * strandT * FurTransmissionLightingScale();
    return (albedo * ((wrap + back) * diffuseScale) + specColor) * radiance;
}

half4 CardFrag(CardVaryings IN) : SV_Target
{
    float cardAlpha = CardClip(IN.uv, IN.controlUV, IN.positionCS);

    float2 buv = IN.baseUV * _BaseMap_ST.xy + _BaseMap_ST.zw;
    half4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, buv) * _BaseColor;

    half3 tint   = FurRootTipTint(_RootColor.rgb, _TipColor.rgb, IN.uv.y);
    half3 albedo = lerp(tint, baseTex.rgb * tint, _AlbedoInfluence);   // inherit the surface albedo
    albedo *= lerp(1.0 - 0.4 * _RootAO, 1.0, IN.uv.y);
    float2 cvCell = floor(IN.rootOS.xy * 128.0 + IN.rootOS.z * 64.0);  // uniform per-card color variation
    albedo *= 1.0 + (half3(FurHash21(cvCell + 1.3), FurHash21(cvCell + 7.7), FurHash21(cvCell + 3.2)) - 0.5) * _ColorVar;

    // The alpha ramp IS the occlusion of this card: a photographed feather or hair clump carries
    // its bright rachis, its striated barbs and the gaps between them. Alpha clipping alone throws
    // all of that away and leaves a flat cutout in the shape of the source image, which is what
    // makes cards read as printed paper rather than as fur.
    // Normalised to the band that actually survives: everything under _Cutoff is discarded, so
    // mapping [_Cutoff .. 1] onto [0 .. 1] is what puts the full tonal range of the mask on screen.
    // Feeding the raw value in instead wasted most of the slider — at a 0.5 cutoff the darkest texel
    // that can even reach the fragment is already 0.5, so full strength could only ever halve it.
    float alphaShade = saturate((cardAlpha - _Cutoff) / max(1.0 - _Cutoff, 1e-4));
    albedo *= lerp(1.0, alphaShade, saturate(_AlphaShading));

    half gloss = SampleCardSmoothness(buv);
    float3 N = normalize(IN.normalWS);
    float3 T = IN.strandDirWS;
    T = dot(T, T) > 1e-5 ? normalize(T) : normalize(cross(N, float3(0.0, 1.0, 0.0) + 1e-3));
    float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));

    Light mainLight = FUR_GET_MAIN_LIGHT(IN.positionWS, IN.positionCS, N);

    half3 color = ShadeCardLight(mainLight, albedo, N, T, V, gloss, IN.uv.y);

#if defined(_ADDITIONAL_LIGHTS) || defined(FURBRUSH_HDRP_COMPAT)
    uint count = GetAdditionalLightsCount();
#if defined(FURBRUSH_URP_NATIVE)
    InputData inputData = (InputData)0;
    inputData.positionWS = IN.positionWS;
    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);
#if USE_CLUSTER_LIGHT_LOOP || USE_FORWARD_PLUS
    UNITY_LOOP for (uint li = 0u; li < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); li++)
    {
        Light al = FUR_GET_ADDITIONAL_LIGHT(li, IN.positionWS, IN.positionCS, N);
        color += ShadeCardLight(al, albedo, N, T, V, gloss, IN.uv.y);
    }
#endif
    LIGHT_LOOP_BEGIN(count)
        Light al = FUR_GET_ADDITIONAL_LIGHT(lightIndex, IN.positionWS, IN.positionCS, N);
        color += ShadeCardLight(al, albedo, N, T, V, gloss, IN.uv.y);
    LIGHT_LOOP_END
#else
    for (uint li = 0u; li < count; li++)
    {
        Light al = FUR_GET_ADDITIONAL_LIGHT(li, IN.positionWS, IN.positionCS, N);
        color += ShadeCardLight(al, albedo, N, T, V, gloss, IN.uv.y);
    }
#endif
#endif

    color += SampleSH(N) * albedo;

    // Subtle, grazing-only env reflection — see the shell shader note: a broad probe/skybox term
    // recolours the fur (blue sky -> blue sheen). Fresnel-gate it to a faint rim sheen.
    half3 envRefl = GlossyEnvironmentReflection(reflect(-V, N), 1.0 - gloss, 1.0);
    half fresnel = pow(1.0 - saturate(abs(dot(N, V))), 4.0);
    color += envRefl * (gloss * gloss * fresnel * 0.2);

    color = MixFog(color, IN.fogFactor);
    return half4(color, 1.0);
}
#endif // FURBRUSH_FORWARD_LIGHTING

#endif // FURBRUSH_CARD_INCLUDED
