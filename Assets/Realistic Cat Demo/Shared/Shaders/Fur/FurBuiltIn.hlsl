#ifndef FURBRUSH_BUILTIN_INCLUDED
#define FURBRUSH_BUILTIN_INCLUDED

// ----------------------------------------------------------------------------
// FurBrush - Built-in Render Pipeline compatibility layer.
//
// The fur shaders are written against the URP shader library. This header re-implements the
// handful of names they actually use (texture macros, space transforms, one Light struct, fog,
// ambient) on top of the engine's own CGIncludes, which ship with every Unity install and need
// no package. FurPipeline.hlsl includes it for the *_BIRP shaders, and also as the fallback for
// the URP/HDRP shader variants in a project that has neither SRP package installed - those never
// render (their SubShader asks for a pipeline that isn't there) but Unity still compiles them.
//
// Additional lights work the Built-in way: one ForwardAdd pass per light, so the light returned
// here is whichever light the current pass is shading and GetAdditionalLightsCount() is 0.
// ----------------------------------------------------------------------------

#include "UnityCG.cginc"
#include "UnityLightingCommon.cginc"    // _LightColor0
#include "AutoLight.cginc"              // UnityComputeForwardShadows, per-light cookie/attenuation

// ---- scalar aliases the SRP libraries provide -------------------------------
#define real  float
#define real2 float2
#define real3 float3
#define real4 float4

#ifndef INV_PI
#define INV_PI 0.31830988618379067154
#endif

#ifndef UNITY_SPECCUBE_LOD_STEPS
#define UNITY_SPECCUBE_LOD_STEPS (6)
#endif

// ---- texture declaration / sampling ----------------------------------------
// Mirrors HLSLSupport's own split so the fur shaders keep working on the (legacy) targets that
// cannot address a texture and a sampler separately.
#ifdef UNITY_SEPARATE_TEXTURE_SAMPLER
    #define TEXTURE2D(name)                             Texture2D name
    #define SAMPLER(name)                               SamplerState name
    #define SAMPLE_TEXTURE2D(tex, samp, uv)             tex.Sample(samp, uv)
    #define SAMPLE_TEXTURE2D_LOD(tex, samp, uv, lod)    tex.SampleLevel(samp, uv, lod)
    #define SAMPLE_TEXTURE2D_BIAS(tex, samp, uv, bias)  tex.SampleBias(samp, uv, bias)
#else
    #define TEXTURE2D(name)                             sampler2D name
    // No separate sampler object exists on this target; keep the declaration syntactically valid.
    #define SAMPLER(name)                               float name##_unused
    #define SAMPLE_TEXTURE2D(tex, samp, uv)             tex2D(tex, uv)
    #define SAMPLE_TEXTURE2D_LOD(tex, samp, uv, lod)    tex2Dlod(tex, float4(uv, 0.0, lod))
    #define SAMPLE_TEXTURE2D_BIAS(tex, samp, uv, bias)  tex2Dbias(tex, float4(uv, 0.0, bias))
#endif

// ---- space transforms -------------------------------------------------------
float3 TransformObjectToWorld(float3 positionOS)     { return mul(unity_ObjectToWorld, float4(positionOS, 1.0)).xyz; }
float3 TransformWorldToObject(float3 positionWS)     { return mul(unity_WorldToObject, float4(positionWS, 1.0)).xyz; }
float3 TransformObjectToWorldDir(float3 dirOS)       { return normalize(mul((float3x3)unity_ObjectToWorld, dirOS)); }
float3 TransformWorldToObjectDir(float3 dirWS)       { return normalize(mul((float3x3)unity_WorldToObject, dirWS)); }
float3 TransformObjectToWorldNormal(float3 normalOS) { return normalize(mul(normalOS, (float3x3)unity_WorldToObject)); }
float4 TransformWorldToHClip(float3 positionWS)      { return mul(UNITY_MATRIX_VP, float4(positionWS, 1.0)); }
float3 TransformWorldToView(float3 positionWS)       { return mul(UNITY_MATRIX_V, float4(positionWS, 1.0)).xyz; }
float4 TransformObjectToHClip(float3 positionOS)     { return UnityObjectToClipPos(positionOS); }

#ifndef UNITY_MATRIX_M
    #define UNITY_MATRIX_M unity_ObjectToWorld
#endif
#ifndef UNITY_MATRIX_I_M
    #define UNITY_MATRIX_I_M unity_WorldToObject
#endif

float GetOddNegativeScale() { return unity_WorldTransformParams.w; }

float3 GetWorldSpaceViewDir(float3 positionWS)
{
    // Orthographic cameras have no eye point: every fragment shares the camera's forward axis.
    if (unity_OrthoParams.w == 0.0) return _WorldSpaceCameraPos.xyz - positionWS;
    return UNITY_MATRIX_V[2].xyz;
}

struct VertexPositionInputs
{
    float3 positionWS;
    float3 positionVS;
    float4 positionCS;
    float4 positionNDC;
};

struct VertexNormalInputs
{
    real3  tangentWS;
    real3  bitangentWS;
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
    tbn.normalWS    = TransformObjectToWorldNormal(normalOS);
    tbn.tangentWS   = TransformObjectToWorldDir(tangentOS.xyz);
    tbn.bitangentWS = cross(tbn.normalWS, tbn.tangentWS) * sign;
    return tbn;
}

// ---- noise ------------------------------------------------------------------
// Same constants as SRP core's Random.hlsl, so the shell dither pattern is identical across
// pipelines (it has to be: the forward and depth passes must clip the same texels).
float InterleavedGradientNoise(float2 pixCoord, int frameCount)
{
    const float3 magic = float3(0.06711056, 0.00583715, 52.9829189);
    float2 frameMagicScale = float2(2.083, 4.867);
    pixCoord += frameCount * frameMagicScale;
    return frac(magic.z * frac(dot(pixCoord, magic.xy)));
}

// ---- fog --------------------------------------------------------------------
// Built-in fog lives entirely in macros, so the factor has to be resolved here rather than by a
// library function. Fog off -> factor 1 (fully unfogged) so MixFog is a no-op either way.
float ComputeFogFactor(float clipSpaceZ)
{
#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
    UNITY_CALC_FOG_FACTOR(clipSpaceZ);
    return saturate(unityFogFactor);
#else
    return 1.0;
#endif
}

float3 MixFog(float3 fragColor, float fogFactor)
{
#if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
    #if defined(UNITY_PASS_FORWARDADD)
        // Additive passes must fade to black, not to the fog colour, or every extra light lays
        // one more coat of fog over the base pass.
        return fragColor * saturate(fogFactor);
    #else
        return lerp(unity_FogColor.rgb, fragColor, saturate(fogFactor));
    #endif
#else
    return fragColor;
#endif
}

// ---- ambient / environment --------------------------------------------------
float3 SampleSH(float3 normalWS)
{
#if defined(UNITY_PASS_FORWARDADD)
    return float3(0.0, 0.0, 0.0);   // ambient belongs to the base pass only
#else
    return max(float3(0.0, 0.0, 0.0), ShadeSH9(float4(normalWS, 1.0)));
#endif
}

float3 GlossyEnvironmentReflection(float3 reflectVector, float perceptualRoughness, float occlusion)
{
#if defined(UNITY_PASS_FORWARDADD)
    return float3(0.0, 0.0, 0.0);
#else
    float mip = perceptualRoughness * (1.7 - 0.7 * perceptualRoughness) * UNITY_SPECCUBE_LOD_STEPS;
    half4 encoded = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0, reflectVector, mip);
    return DecodeHDR(encoded, unity_SpecCube0_HDR) * occlusion;
#endif
}

// ---- lighting ---------------------------------------------------------------
struct Light
{
    half3 direction;
    half3 color;
    half  distanceAttenuation;
    half  shadowAttenuation;
};

// Cookie + falloff of the light this pass is shading. Built-in declares the lookup textures per
// light type (see AutoLight.cginc), which is why each type needs its own branch.
half FurBuiltInLightFalloff(float3 positionWS)
{
#if defined(POINT)
    float3 lightCoord = mul(unity_WorldToLight, float4(positionWS, 1.0)).xyz;
    return tex2D(_LightTexture0, dot(lightCoord, lightCoord).rr).r;
#elif defined(SPOT)
    float4 lightCoord = mul(unity_WorldToLight, float4(positionWS, 1.0));
    return (lightCoord.z > 0.0) * UnitySpotCookie(lightCoord) * UnitySpotAttenuate(lightCoord.xyz);
#elif defined(POINT_COOKIE)
    float3 lightCoord = mul(unity_WorldToLight, float4(positionWS, 1.0)).xyz;
    return tex2D(_LightTextureB0, dot(lightCoord, lightCoord).rr).r * texCUBE(_LightTexture0, lightCoord).w;
#elif defined(DIRECTIONAL_COOKIE)
    float2 lightCoord = mul(unity_WorldToLight, float4(positionWS, 1.0)).xy;
    return tex2D(_LightTexture0, lightCoord).w;
#else
    return 1.0;
#endif
}

// positionCS is SV_POSITION, i.e. pixel coordinates: the directional shadow map is resolved into
// a screen-space buffer before the forward pass, so it is sampled by screen position rather than
// through a light-space coordinate interpolated from the vertex stage.
half FurBuiltInShadowAttenuation(float3 positionWS, float4 positionCS)
{
#if defined(SHADOWS_SCREEN) || defined(SHADOWS_DEPTH) || defined(SHADOWS_CUBE)
    // On targets that keep fragment interpolators at half precision, UnityComputeForwardShadows
    // reads its third argument as a light-space coordinate instead of a screen position (see
    // AutoLight.cginc) - hand it the one it expects.
    #if defined(UNITY_HALF_PRECISION_FRAGMENT_SHADER_REGISTERS) && \
        ((defined(SHADOWS_DEPTH) && defined(SPOT)) || (defined(SHADOWS_SCREEN) && defined(UNITY_NO_SCREENSPACE_SHADOWS)))
        float4 shadowCoord = mul(unity_WorldToShadow[0], float4(positionWS, 1.0));
    #else
        float4 shadowCoord = float4(positionCS.xy / _ScreenParams.xy, 0.0, 1.0);
    #endif
    return UnityComputeForwardShadows(float2(0.0, 0.0), positionWS, shadowCoord);
#else
    return 1.0;
#endif
}

// The light this pass shades: the main directional in ForwardBase, one punctual light per
// ForwardAdd pass.
Light FurBuiltInGetLight(float3 positionWS, float4 positionCS)
{
    Light light;
    float3 lightVec = _WorldSpaceLightPos0.xyz - positionWS * _WorldSpaceLightPos0.w;
    float  lenSq    = dot(lightVec, lightVec);
    light.direction = lenSq > 1e-12 ? (half3)(lightVec * rsqrt(lenSq)) : half3(0.0, 1.0, 0.0);
    light.color     = _LightColor0.rgb;
    light.distanceAttenuation = FurBuiltInLightFalloff(positionWS);
    light.shadowAttenuation   = FurBuiltInShadowAttenuation(positionWS, positionCS);
    return light;
}

// Built-in has no light loop: extra lights arrive as their own ForwardAdd passes.
uint GetAdditionalLightsCount() { return 0u; }

Light GetAdditionalLight(uint lightIndex, float3 positionWS)
{
    Light light = (Light)0;
    return light;
}

// Kept for the legacy Common/Common.hlsl surface and for any user shader that calls them; the
// *_BIRP passes go through FUR_GET_MAIN_LIGHT and the shadow-caster helper below instead.
float4 TransformWorldToShadowCoord(float3 positionWS) { return float4(positionWS, 1.0); }
Light  GetMainLight(float4 shadowCoord)               { return FurBuiltInGetLight(shadowCoord.xyz, float4(0, 0, 0, 1)); }
Light  GetMainLight()                                 { return GetMainLight(float4(0, 0, 0, 1)); }

float3 ApplyShadowBias(float3 positionWS, float3 normalWS, float3 lightDirectionWS)
{
    return positionWS + normalWS * 0.001;
}

// ---- shadow caster ----------------------------------------------------------
// UnityClipSpaceShadowCasterPos takes an object-space vertex; the fur shaders have already left
// object space by the time the shells/ribbons are extruded, so apply the same normal-offset and
// linear bias to a world-space position instead.
float4 FurBuiltInShadowCasterClipPos(float3 positionWS, float3 normalWS)
{
    if (unity_LightShadowBias.z != 0.0)
    {
        float3 lightDirWS = normalize(UnityWorldSpaceLightDir(positionWS));
        float  shadowCos  = dot(normalWS, lightDirWS);
        float  shadowSine = sqrt(saturate(1.0 - shadowCos * shadowCos));
        positionWS -= normalWS * (unity_LightShadowBias.z * shadowSine);
    }
    return UnityApplyLinearShadowBias(mul(UNITY_MATRIX_VP, float4(positionWS, 1.0)));
}

#endif // FURBRUSH_BUILTIN_INCLUDED
