#ifndef FURBRUSH_PIPELINE_INCLUDED
#define FURBRUSH_PIPELINE_INCLUDED

#include "FurExportPipelineDefines.hlsl"   // generated: FURBRUSH_URP_AVAILABLE / FURBRUSH_HDRP_AVAILABLE

// Every fur shader ships in a URP, an HDRP and a Built-in flavour, and Unity compiles all of them
// no matter which pipeline the project installed — the HDRP shaders are imported in a URP-only
// project too. Instead of letting those fail on an include from a package that isn't there,
// retarget the shader onto whichever pipeline IS installed. It still never renders through the
// wrong pipeline: the SubShader's "RenderPipeline" tag only matches its own (and the Built-in
// shaders' pass LightModes only mean something to Built-in). The Built-in layer is the last
// resort, because the engine's CGIncludes are the only shader library that always exists —
// including right after import, before FurPipelineSupport has written the header above.
//
// Exactly one of FURBRUSH_URP_NATIVE / FURBRUSH_HDRP_COMPAT / FURBRUSH_BIRP_COMPAT ends up
// defined. A shader asks for HDRP or Built-in by defining its flag before including this file;
// asking for nothing means URP.
#if defined(FURBRUSH_BIRP_COMPAT)
    // The Built-in shaders need no package, so this request is always granted as asked.
#elif defined(FURBRUSH_HDRP_COMPAT)
    #if !defined(FURBRUSH_HDRP_AVAILABLE)
        #undef FURBRUSH_HDRP_COMPAT
        #if defined(FURBRUSH_URP_AVAILABLE)
            #define FURBRUSH_URP_NATIVE
        #else
            #define FURBRUSH_BIRP_COMPAT
        #endif
    #endif
#elif defined(FURBRUSH_URP_AVAILABLE)
    #define FURBRUSH_URP_NATIVE
#elif defined(FURBRUSH_HDRP_AVAILABLE)
    #define FURBRUSH_HDRP_COMPAT
#else
    #define FURBRUSH_BIRP_COMPAT
#endif

#if defined(FURBRUSH_BIRP_COMPAT)

#include "FurBuiltIn.hlsl"

#elif defined(FURBRUSH_HDRP_COMPAT)

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonLighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/MostRepresentativePoint.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Packing.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Random.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/PunctualLightCommon.hlsl"

// Forward passes select these through multi_compile. Depth, shadow and editor-selection passes
// share this header too, so give HDShadow a valid filter while those unused functions are stripped.
// HDRP 17 split punctual and directional quality keywords; HDRP 14 uses one SHADOW_* keyword.
#if UNITY_VERSION >= 600000
    #if !defined(PUNCTUAL_SHADOW_ULTRA_LOW) && !defined(PUNCTUAL_SHADOW_LOW) && !defined(PUNCTUAL_SHADOW_MEDIUM) && !defined(PUNCTUAL_SHADOW_HIGH)
        #define PUNCTUAL_SHADOW_MEDIUM
    #endif
    #if !defined(DIRECTIONAL_SHADOW_ULTRA_LOW) && !defined(DIRECTIONAL_SHADOW_LOW) && !defined(DIRECTIONAL_SHADOW_MEDIUM) && !defined(DIRECTIONAL_SHADOW_HIGH)
        #define DIRECTIONAL_SHADOW_MEDIUM
    #endif
#elif !defined(SHADOW_ULTRA_LOW) && !defined(SHADOW_LOW) && !defined(SHADOW_MEDIUM) && !defined(SHADOW_HIGH)
    #define SHADOW_MEDIUM
#endif
#if !defined(AREA_SHADOW_LOW) && !defined(AREA_SHADOW_MEDIUM) && !defined(AREA_SHADOW_HIGH)
    #define AREA_SHADOW_MEDIUM
#endif
#include "Packages/com.unity.render-pipelines.high-definition/Runtime/Lighting/LightLoop/HDShadow.hlsl"
#ifndef UNITY_MATRIX_M
    float4x4 unity_ObjectToWorld;
    #define UNITY_MATRIX_M unity_ObjectToWorld
#endif
#ifndef UNITY_MATRIX_I_M
    float4x4 unity_WorldToObject;
    #define UNITY_MATRIX_I_M unity_WorldToObject
#endif
#ifndef UNITY_MATRIX_V
    float4x4 unity_MatrixV;
    #define UNITY_MATRIX_V unity_MatrixV
#endif
#ifndef UNITY_MATRIX_I_V
    float4x4 unity_MatrixInvV;
    #define UNITY_MATRIX_I_V unity_MatrixInvV
#endif
#ifndef UNITY_MATRIX_P
    float4x4 glstate_matrix_projection;
    #define UNITY_MATRIX_P glstate_matrix_projection
#endif
#ifndef UNITY_MATRIX_I_P
    float4x4 unity_MatrixInvP;
    #define UNITY_MATRIX_I_P unity_MatrixInvP
#endif
#ifndef UNITY_MATRIX_VP
    float4x4 unity_MatrixVP;
    #define UNITY_MATRIX_VP unity_MatrixVP
#endif
#ifndef UNITY_MATRIX_I_VP
    float4x4 unity_MatrixInvVP;
    #define UNITY_MATRIX_I_VP unity_MatrixInvVP
#endif
#ifndef UNITY_PREV_MATRIX_M
    float4x4 unity_MatrixPreviousM;
    #define UNITY_PREV_MATRIX_M unity_MatrixPreviousM
#endif
#ifndef UNITY_PREV_MATRIX_I_M
    float4x4 unity_MatrixPreviousMI;
    #define UNITY_PREV_MATRIX_I_M unity_MatrixPreviousMI
#endif

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/SpaceTransforms.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"

struct VertexPositionInputs
{
    float3 positionWS;
    float3 positionVS;
    float4 positionCS;
    float4 positionNDC;
};

struct VertexNormalInputs
{
    real3 tangentWS;
    real3 bitangentWS;
    float3 normalWS;
};

VertexPositionInputs GetVertexPositionInputs(float3 positionOS)
{
    VertexPositionInputs input;
    input.positionWS = TransformObjectToWorld(positionOS);
    input.positionVS = TransformWorldToView(input.positionWS);
    input.positionCS = TransformWorldToHClip(input.positionWS);
    input.positionNDC = input.positionCS * 0.5f;
    input.positionNDC.xy = float2(input.positionNDC.x, input.positionNDC.y * _ProjectionParams.x) + input.positionNDC.w;
    input.positionNDC.zw = input.positionCS.zw;
    return input;
}

VertexNormalInputs GetVertexNormalInputs(float3 normalOS, float4 tangentOS)
{
    VertexNormalInputs tbn;
    real sign = tangentOS.w * GetOddNegativeScale();
    tbn.normalWS = TransformObjectToWorldNormal(normalOS);
    tbn.tangentWS = TransformObjectToWorldDir(tangentOS.xyz);
    tbn.bitangentWS = cross(tbn.normalWS, tbn.tangentWS) * sign;
    return tbn;
}

// GetWorldSpaceViewDir is already defined by HDRP/URP libraries
/*
float3 GetWorldSpaceViewDir(float3 positionWS)
{
    return _WorldSpaceCameraPos.xyz - positionWS;
}
*/

real ComputeFogFactor(float zPositionCS)
{
    return 0.0;
}

half3 MixFog(half3 fragColor, half fogFactor)
{
    return fragColor;
}

half3 MixFog(half3 fragColor, float fogFactor)
{
    return fragColor;
}

float3 MixFog(float3 fragColor, float fogFactor)
{
    return fragColor;
}

half3 SampleSH(half3 normalWS)
{
    float3 N = normalWS;
    float3 res = float3(0.0, 0.0, 0.0);
    
    float4 vA = float4(N, 1.0);
    res.r = dot(unity_SHAr, vA);
    res.g = dot(unity_SHAg, vA);
    res.b = dot(unity_SHAb, vA);
    
    float4 vB = N.xyzz * N.yzzx;
    res.r += dot(unity_SHBr, vB);
    res.g += dot(unity_SHBg, vB);
    res.b += dot(unity_SHBb, vB);
    
    float vC = N.x * N.x - N.y * N.y;
    res += unity_SHC.rgb * vC;
    
    // Robust NaN check that fast-math compilers won't optimize out
    if (!(res.x >= -999999.0 && res.x <= 999999.0) ||
        !(res.y >= -999999.0 && res.y <= 999999.0) ||
        !(res.z >= -999999.0 && res.z <= 999999.0))
    {
        res = float3(0.18, 0.18, 0.18);
    }
    
    res = max(float3(0.0, 0.0, 0.0), res);

    // HDRP stores probe lighting in scene-referred physical units, while the
    // camera color buffer is pre-exposed. Without this conversion the probe
    // alone can turn the whole coat white even when the direct light is sane.
    float exposure = GetCurrentExposureMultiplier();
    if (exposure > 0.99f)
    {
        // When scene lighting is toggled off in the editor, exposure is 1.0,
        // but SH coefficients still contain the unexposed physical values (e.g. thousands of Lux).
        // Clamp the ambient to standard LDR levels (max 0.25) to prevent a blinding white glow.
        float maxChan = max(res.r, max(res.g, res.b));
        if (maxChan > 0.25f)
        {
            res *= (0.25f / maxChan);
        }
    }
    else
    {
        res *= exposure;
    }

    return res;
}

half3 GlossyEnvironmentReflection(half3 reflectVector, half perceptualRoughness, half occlusion)
{
    return half3(0.0, 0.0, 0.0);
}

float4 TransformWorldToShadowCoord(float3 positionWS)
{
    return float4(0.0, 0.0, 0.0, 1.0);
}

float3 ApplyShadowBias(float3 positionWS, float3 normalWS, float3 lightDirectionWS)
{
    return positionWS + normalWS * 0.001;
}

struct Light
{
    half3 direction;
    half3 color;
    half distanceAttenuation;
    half shadowAttenuation;
};

float3 FurHdrpConvertLightColor(float3 lightColor)
{
    float exposure = GetCurrentExposureMultiplier();
    if (exposure > 0.99f)
    {
        // Scene-lighting-off in the editor leaves physical light values unexposed.
        // Keep that preview useful instead of letting thousands of Lux clip the coat white.
        float maxChan = max(lightColor.r, max(lightColor.g, lightColor.b));
        if (maxChan > 1.0f)
        {
            lightColor /= maxChan;
        }
    }
    else
    {
        lightColor *= exposure;
    }

    return lightColor * INV_PI;
}

bool FurHdrpMatchesLightLayers(uint lightLayers)
{
#if UNITY_VERSION >= 600000
    uint renderingLayers = (_EnableLightLayers != 0u) ? GetMeshRenderingLayerMask() : RENDERING_LAYERS_MASK;
#else
    uint renderingLayers = GetMeshRenderingLightLayer();
#endif
    return IsMatchingLightLayer(lightLayers, renderingLayers);
}

Light FurHdrpGetDirectionalLight(
    uint lightIndex,
    float3 positionWS,
    float2 positionSS,
    float3 normalWS,
    bool evaluateShadows)
{
    Light light = (Light)0;
    if (lightIndex >= _DirectionalLightCount)
        return light;

    DirectionalLightData hdLight = _DirectionalLightDatas[lightIndex];
    if (hdLight.lightDimmer <= 0.0 || hdLight.diffuseDimmer <= 0.0 ||
        !FurHdrpMatchesLightLayers(hdLight.lightLayers))
        return light;

    light.direction = -normalize(hdLight.forward);
    light.color = FurHdrpConvertLightColor(hdLight.color * hdLight.diffuseDimmer);
    light.distanceAttenuation = 1.0;
    light.shadowAttenuation = 1.0;

    if (evaluateShadows && hdLight.shadowIndex >= 0 && hdLight.shadowDimmer > 0.0)
    {
        HDShadowContext shadowContext = InitShadowContext();
        float shadow = GetDirectionalShadowAttenuation(
            shadowContext,
            positionSS,
            positionWS,
            normalWS,
            hdLight.shadowIndex,
            light.direction);
        light.shadowAttenuation = lerp(1.0, shadow, saturate(hdLight.shadowDimmer));
    }

    return light;
}

Light FurHdrpGetPunctualLight(
    uint lightIndex,
    float3 positionWS,
    float2 positionSS,
    float3 normalWS,
    bool evaluateShadows)
{
    Light light = (Light)0;
    if (lightIndex >= _PunctualLightCount)
        return light;

    LightData hdLight = _LightDatas[lightIndex];
    if (hdLight.lightDimmer <= 0.0 || hdLight.diffuseDimmer <= 0.0 ||
        !FurHdrpMatchesLightLayers(hdLight.lightLayers))
        return light;

    float4 distances;
    GetPunctualLightVectors(positionWS, hdLight, light.direction, distances);

    light.color = FurHdrpConvertLightColor(hdLight.color * hdLight.diffuseDimmer);
    light.distanceAttenuation = PunctualLightAttenuation(
        distances,
        hdLight.rangeAttenuationScale,
        hdLight.rangeAttenuationBias,
        hdLight.angleScale,
        hdLight.angleOffset);
    light.shadowAttenuation = 1.0;

    if (evaluateShadows && light.distanceAttenuation > 0.0 &&
        hdLight.shadowIndex >= 0 && hdLight.shadowDimmer > 0.0)
    {
        HDShadowContext shadowContext = InitShadowContext();
        float shadow = GetPunctualShadowAttenuation(
            shadowContext,
            positionSS,
            positionWS,
            normalWS,
            hdLight.shadowIndex,
            light.direction,
            distances.x,
            hdLight.lightType == GPULIGHTTYPE_POINT,
            hdLight.lightType != GPULIGHTTYPE_PROJECTOR_BOX);
        light.shadowAttenuation = lerp(1.0, shadow, saturate(hdLight.shadowDimmer));
    }

    return light;
}

Light FurHdrpGetAreaLight(
    uint areaLightIndex,
    float3 positionWS,
    float2 positionSS,
    float3 normalWS,
    bool evaluateShadows)
{
    Light light = (Light)0;
    if (areaLightIndex >= _AreaLightCount)
        return light;

    LightData hdLight = _LightDatas[_PunctualLightCount + areaLightIndex];
    if (hdLight.lightDimmer <= 0.0 || hdLight.diffuseDimmer <= 0.0 ||
        !FurHdrpMatchesLightLayers(hdLight.lightLayers))
        return light;

    float3 unL = hdLight.positionRWS - positionWS;

    if (hdLight.lightType == GPULIGHTTYPE_TUBE)
    {
        float halfLength = hdLight.size.x * 0.5;
        float axisOffset = clamp(dot(-unL, hdLight.right), -halfLength, halfLength);
        float3 closestPoint = hdLight.positionRWS + hdLight.right * axisOffset;
        float3 closestVector = closestPoint - positionWS;
        float closestDistance = max(length(closestVector), 1e-4);
        float perpendicularDistance = max(length(unL - hdLight.right * dot(unL, hdLight.right)), 1e-4);
        float angularExtent = 2.0 * atan(halfLength / perpendicularDistance);

        light.direction = closestVector / closestDistance;
        light.color = FurHdrpConvertLightColor(hdLight.color * hdLight.diffuseDimmer * angularExtent);
#if UNITY_VERSION >= 600000
        light.distanceAttenuation = CapsuleWindowing(
            unL,
            hdLight.right,
            halfLength,
            hdLight.rangeAttenuationScale,
            hdLight.rangeAttenuationBias);
#else
        float invAspectRatio = saturate(hdLight.range / (hdLight.range + halfLength));
        light.distanceAttenuation = EllipsoidalDistanceAttenuation(
            unL,
            hdLight.right,
            invAspectRatio,
            hdLight.rangeAttenuationScale,
            hdLight.rangeAttenuationBias);
#endif
        light.shadowAttenuation = 1.0;
        return light;
    }

    // HDRP's realtime Area Light is normally a rectangle. A disc is approximated by
    // an equally-sized square here, because HDRP exposes raster area shadows only for rects.
    if (dot(hdLight.forward, unL) >= FLT_EPS)
        return light;

    float halfWidth = hdLight.size.x * 0.5;
    float halfHeight = (hdLight.lightType == GPULIGHTTYPE_DISC ? hdLight.size.x : hdLight.size.y) * 0.5;
    float4x3 lightVertices;
    lightVertices[0] = hdLight.positionRWS - hdLight.right * halfWidth - hdLight.up * halfHeight;
    lightVertices[1] = hdLight.positionRWS - hdLight.right * halfWidth + hdLight.up * halfHeight;
    lightVertices[2] = hdLight.positionRWS + hdLight.right * halfWidth + hdLight.up * halfHeight;
    lightVertices[3] = hdLight.positionRWS + hdLight.right * halfWidth - hdLight.up * halfHeight;

    float solidAngle = max(SolidAngleRectangle(positionWS, lightVertices), 0.0);
    if (solidAngle <= 0.0)
        return light;

    light.direction = normalize(unL);
    light.color = FurHdrpConvertLightColor(hdLight.color * hdLight.diffuseDimmer * solidAngle);
    light.distanceAttenuation = 1.0;
    light.shadowAttenuation = 1.0;

    if (evaluateShadows && hdLight.lightType == GPULIGHTTYPE_RECTANGLE &&
        hdLight.shadowIndex >= 0 && hdLight.shadowDimmer > 0.0)
    {
        HDShadowContext shadowContext = InitShadowContext();
        float lightCameraDistance = length(hdLight.positionRWS);
        float3 shadowDirection = hdLight.positionRWS / max(lightCameraDistance, 1e-4);
        float shadow = GetRectAreaShadowAttenuation(
            shadowContext,
            positionSS,
            positionWS,
            normalWS,
            hdLight.shadowIndex,
            shadowDirection,
            lightCameraDistance);
        light.shadowAttenuation = lerp(1.0, shadow, saturate(hdLight.shadowDimmer));
    }

    return light;
}

Light FurHdrpGetMainLight(float3 positionWS, float2 positionSS, float3 normalWS, bool evaluateShadows)
{
    return FurHdrpGetDirectionalLight(0u, positionWS, positionSS, normalWS, evaluateShadows);
}

uint GetAdditionalLightsCount()
{
    uint additionalDirectionals = (_DirectionalLightCount > 0u) ? (_DirectionalLightCount - 1u) : 0u;
    return additionalDirectionals + _PunctualLightCount + _AreaLightCount;
}

Light FurHdrpGetAdditionalLight(
    uint lightIndex,
    float3 positionWS,
    float2 positionSS,
    float3 normalWS,
    bool evaluateShadows)
{
    Light light = (Light)0;
    uint additionalDirectionals = (_DirectionalLightCount > 0u) ? (_DirectionalLightCount - 1u) : 0u;
    if (lightIndex < additionalDirectionals)
    {
        light = FurHdrpGetDirectionalLight(lightIndex + 1u, positionWS, positionSS, normalWS, evaluateShadows);
    }
    else
    {
        lightIndex -= additionalDirectionals;
        if (lightIndex < _PunctualLightCount)
            light = FurHdrpGetPunctualLight(lightIndex, positionWS, positionSS, normalWS, evaluateShadows);
        else
            light = FurHdrpGetAreaLight(lightIndex - _PunctualLightCount, positionWS, positionSS, normalWS, evaluateShadows);
    }

    return light;
}

// Preserve the old public helper signatures for custom shaders which included FurPipeline.hlsl.
// They intentionally remain unshadowed because they do not provide a fragment position and normal.
Light GetMainLight(float4 shadowCoord)
{
    return FurHdrpGetMainLight(float3(0.0, 0.0, 0.0), shadowCoord.xy, float3(0.0, 1.0, 0.0), false);
}

Light GetMainLight()
{
    return GetMainLight(float4(0.0, 0.0, 0.0, 1.0));
}

Light GetAdditionalLight(uint lightIndex, float3 positionWS)
{
    return FurHdrpGetAdditionalLight(lightIndex, positionWS, float2(0.0, 0.0), float3(0.0, 1.0, 0.0), false);
}

#else

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"

#endif

// Dynamic gravity and motion arrive in WORLD space and are converted here, per draw, with the
// very matrix the renderer is bound with. Converting on the CPU cannot be right for every method:
// the shell overlay draws through a CHILD SkinnedMeshRenderer whose object space is not the space
// of the GameObject holding FurController, so a character travelling forward bent the coat along
// whichever object axis happened to receive world forward — it read as sideways sway.
//
// A plain matrix multiply, not the normalizing TransformWorldToObjectDir: _DynamicMotion carries
// the sway strength in its magnitude and normalizing would throw that away.
float3 FurWorldToObjectVector(float3 dirWS)
{
    return mul((float3x3)UNITY_MATRIX_I_M, dirWS);
}

// The light a forward fragment shades, resolved the way its pipeline expects. A macro rather than
// a function because URP's GetMainLight lives in Lighting.hlsl, which each forward pass includes
// AFTER this header — so a wrapper defined here could not call it yet.
//   * URP     — main light + cascaded shadow lookup from the world position.
//   * HDRP    — the shim above reads every relevant HDRP light buffer and samples its shadow atlas.
//   * Built-in — one light per pass (ForwardBase/ForwardAdd); needs the world position for
//                cookie/falloff and the pixel position for the screen-space shadow buffer.
#if defined(FURBRUSH_BIRP_COMPAT)
    #define FUR_GET_MAIN_LIGHT(positionWS, positionCS, normalWS) FurBuiltInGetLight(positionWS, positionCS)
    #define FUR_GET_ADDITIONAL_LIGHT(lightIndex, positionWS, positionCS, normalWS) GetAdditionalLight(lightIndex, positionWS)
#elif defined(FURBRUSH_HDRP_COMPAT)
    #define FUR_GET_MAIN_LIGHT(positionWS, positionCS, normalWS) FurHdrpGetMainLight(positionWS, positionCS.xy, normalWS, true)
    #define FUR_GET_ADDITIONAL_LIGHT(lightIndex, positionWS, positionCS, normalWS) FurHdrpGetAdditionalLight(lightIndex, positionWS, positionCS.xy, normalWS, true)
#else
    #define FUR_GET_MAIN_LIGHT(positionWS, positionCS, normalWS) GetMainLight(TransformWorldToShadowCoord(positionWS))
    #define FUR_GET_ADDITIONAL_LIGHT(lightIndex, positionWS, positionCS, normalWS) GetAdditionalLight(lightIndex, positionWS)
#endif

// Keep the established URP look, but use a response closer to HDRP/Lit for
// physically-scaled HDRP lighting. A small amount of wrap remains so the fur
// does not shade like a hard plastic surface.
// wrapScale (= material _DiffuseWrap, 0..1) scales the pipeline's wrap amount:
// 1 = the established look, 0 = pure Lambert — matching how Lit shades the base
// surface, for when the wrap-brightened fur reads paler/yellower than the skin.
float FurDiffuseLightingTerm(float NdotL, float wrapScale)
{
#if defined(FURBRUSH_HDRP_COMPAT)
    float w = 0.18 * saturate(wrapScale);
#else
    float w = saturate(wrapScale);   // legacy URP look: NdotL*0.5+0.5 == wrap 1.0
#endif
    return saturate((NdotL + w) / (1.0 + w));
}

float FurDiffuseLightingTerm(float NdotL)
{
    return FurDiffuseLightingTerm(NdotL, 1.0);
}

half3 FurAnisotropicSpecular(
    half3 albedo,
    float primary,
    float secondary,
    float intensity,
    float glossMultiplier)
{
#if defined(FURBRUSH_HDRP_COMPAT)
    // Hair reflects a mostly neutral primary lobe, but partially tinting it
    // prevents broad clipped-white bands over a coloured HDRP/Lit surface.
    half3 primaryTint = lerp(half3(1.0, 1.0, 1.0), albedo, 0.35);
    return intensity * (primary * 0.55 * primaryTint
                      + secondary * 0.35 * albedo) * glossMultiplier;
#else
    return intensity * (primary * 0.8 + secondary * 0.5 * albedo) * glossMultiplier;
#endif
}

float FurTransmissionLightingScale()
{
#if defined(FURBRUSH_HDRP_COMPAT)
    return 0.65;
#else
    return 1.0;
#endif
}

half3 FurRootTipTint(half3 rootColor, half3 tipColor, float strandT)
{
#if defined(FURBRUSH_HDRP_COMPAT)
    // Keep each control local to its physical end. A linear lerp makes both colors visibly tint
    // nearly the entire fibre, which is especially obvious under bright punctual HDRP lights.
    float rootWeight = pow(saturate(1.0 - strandT), 4.0);
    float tipWeight  = pow(saturate(strandT), 4.0);
    return lerp(half3(1.0, 1.0, 1.0), rootColor, rootWeight)
         * lerp(half3(1.0, 1.0, 1.0), tipColor, tipWeight);
#else
    return lerp(rootColor, tipColor, strandT);
#endif
}

#endif // FURBRUSH_PIPELINE_INCLUDED
