// FurBrush Developer - export template for Fur Cards.
//
// Same arrangement as FurExport_Shell.shader: one shader for all three pipelines, URP and HDRP
// SubShaders guarded by PackageRequirements, a vertex input in the FBX-safe CardExportAttributes
// layout (FurExportLayout.hlsl), and passes that otherwise match FurCard_URP/_HDRP/_BIRP exactly.
// The exporter renames the shader and drops the ../../Runtime/Shaders/ include prefix.
Shader "Realistic Cat Demo/Fur/Whiskers"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base / Albedo (inherited)", 2D) = "white" {}
        [MainColor]   _BaseColor ("Base Color", Color) = (1,1,1,1)
        [Toggle(_SMOOTHNESSMAP)] _UseSmoothnessMap ("Use Smoothness Map", Float) = 0
        _SmoothnessMap ("Smoothness / Roughness", 2D) = "white" {}
        [Toggle(_ROUGHNESS_INPUT)] _RoughnessInput ("Map is Roughness", Float) = 0
        _SmoothnessChannel ("Smoothness Channel (0R 1G 2B 3A)", Float) = 3
        [Toggle(_ALPHATEX)] _UseAlphaTex ("Use Alpha Texture", Float) = 0
        [Toggle(_ALPHALUM)] _AlphaFromLuminance ("Alpha from Grayscale (Luminance)", Float) = 1
        _FurAlpha ("Fur Alpha (strands)", 2D) = "white" {}
        [Toggle] _AlphaFlipY ("Flip Alpha Vertically", Float) = 1
        _AlphaMipBias ("Alpha Mip Bias", Range(-3,0)) = -2
        _AlphaShading ("Alpha Detail Shading", Range(0,1)) = 0.15

        _RootColor ("Root Shade", Color) = (1,1,1,1)
        _TipColor ("Tip Shade", Color) = (1,1,1,1)
        _AlbedoInfluence ("Albedo Influence", Range(0,1)) = 1
        _RootAO ("Root AO", Range(0,2)) = 0.5

        _Smoothness ("Smoothness", Range(0,1)) = 0.469
        _AnisoSpecular ("Aniso Specular", Range(0,2)) = 0.062
        _Rim ("Rim / Transmission", Range(0,1)) = 0.495
        _DiffuseWrap ("Diffuse Wrap (1 = fur look, 0 = match Lit)", Range(0,1)) = 1
        _ShadowOpacity ("Fur Cast Shadow Opacity", Range(0,1)) = 0.45

        _CardStrands ("Strands per Card", Range(1,40)) = 12
        _Thinness ("Tip Thinness", Range(0,1)) = 0.6
        _Cutoff ("Alpha Cutoff", Range(0,1)) = 0.35
        _AlphaDither ("Alpha Dither Strength", Range(0,1)) = 0.5

        _ColorVar ("Color Variation", Range(0,1)) = 0.25

        _FurControlMap ("Control Map (R:len, G:mask, B:comb)", 2D) = "white" {}
        _CombStrength ("Card Comb Response", Range(0,5)) = 2.19
        _CombSurfaceAdherence ("Card Lay Flatness", Range(0,1)) = 1.0
        _CombTipBend ("Card Bend", Range(0,1)) = 0.5
        _CombJitter ("Micro Flow Noise", Range(0,0.35)) = 0.0
        [Toggle] _CurlEnabled ("Curly", Float) = 1
        _Curl ("Curl / Wave", Range(0,1)) = 0
        _CurlAmountRandomness ("Curl Amount Randomness", Range(0,1)) = 0
        [Enum(Horizontal,0,Vertical,1)] _CurlDirection ("Curl Direction", Float) = 0
        _CurlFrequency ("Curl Frequency", Range(0,6)) = 2
        _CurlFrequencyRandomness ("Curl Frequency Randomness", Range(0,1)) = 0
        _CurlShape ("Curl Shape (Wavy to Curly)", Range(0,1)) = 1
        _CurlShapeRandomness ("Curl Shape Randomness", Range(0,1)) = 0
        [HideInInspector] _CardSegments ("Card Bend Segments (baked into the mesh)", Float) = 1
        _CardDensity ("Card Density", Range(0,1)) = 1
        _Gravity ("Gravity", Vector) = (0,-1,0,0)
        _GravityStrength ("Gravity Strength", Range(0,1)) = 0.0
        [HideInInspector] _DynamicMotion ("Dynamic Motion (runtime)", Vector) = (0,0,0,0)
        [HideInInspector] _Wind ("Wind (runtime)", Vector) = (0,0,0,0)
        _MaxLength ("Max Length", Float) = 0.1
        _LengthScale ("Length Scale", Float) = 1
        _AlbedoProjection ("Albedo Projection", Float) = 1
        _HasControlMap ("Has Control Map", Float) = 0
        _FurWidthMap("Width Map", 2D) = "white" {}
        _HasWidthMap("Has Width Map", Float) = 0
    }

    // ======================================================================
    // HDRP
    // ======================================================================
    SubShader
    {
        PackageRequirements
        {
            "com.unity.render-pipelines.high-definition"
        }
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" "RenderPipeline"="HDRenderPipeline" }
        LOD 300

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="ForwardOnly" }
            Cull Off
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex CardExportVert
            #pragma fragment CardFrag

            #pragma shader_feature_local _ALPHATEX
            #pragma shader_feature_local _ALPHALUM
            #pragma shader_feature_local _SMOOTHNESSMAP
            #pragma shader_feature_local _ROUGHNESS_INPUT
            #if UNITY_VERSION >= 600000
                #pragma multi_compile_fragment PUNCTUAL_SHADOW_LOW PUNCTUAL_SHADOW_MEDIUM PUNCTUAL_SHADOW_HIGH
                #pragma multi_compile_fragment DIRECTIONAL_SHADOW_LOW DIRECTIONAL_SHADOW_MEDIUM DIRECTIONAL_SHADOW_HIGH
            #else
                #pragma multi_compile_fragment SHADOW_LOW SHADOW_MEDIUM SHADOW_HIGH
            #endif
            #pragma multi_compile_fragment AREA_SHADOW_MEDIUM AREA_SHADOW_HIGH
            #pragma multi_compile_fog

            #define FURBRUSH_HDRP_AVAILABLE
            #define FURBRUSH_HDRP_COMPAT
            #define FURBRUSH_FORWARD_LIGHTING
            #include "FurCard.hlsl"
            #include "FurExportLayout.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            Cull Off
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex CardExportShadowVert
            #pragma fragment ShadowFrag
            #pragma shader_feature_local _ALPHATEX
            #pragma shader_feature_local _ALPHALUM
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #define FURBRUSH_HDRP_AVAILABLE
            #define FURBRUSH_HDRP_COMPAT
            #include "FurCard.hlsl"
            #include "FurExportLayout.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            CardDepthVaryings CardExportShadowVert(CardExportAttributes v)
            {
                CardAttributes IN = CardExportUnpack(v);
                CardDepthVaryings o = (CardDepthVaryings)0;
                float3 posOS = CardScaleAndApplyCombAndGravity(IN.positionOS.xyz, IN.normalOS, IN.tangentOS, IN.uv1, IN.uv, IN.controlUV.xy, IN.baseUV);
                float3 positionWS = TransformObjectToWorld(posOS);
                float3 normalWS   = TransformObjectToWorldNormal(IN.normalOS);
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirWS = _LightDirection;
                #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirWS));
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                o.positionCS = positionCS;
                o.uv = IN.uv;
                o.normalWS = normalWS;
                o.controlUV = IN.controlUV;
                return o;
            }

            half4 ShadowFrag(CardDepthVaryings IN) : SV_Target { CardClip(IN.uv, IN.controlUV, IN.positionCS); CardClipShadowOpacity(IN.controlUV); return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthForwardOnly"
            Tags { "LightMode"="DepthForwardOnly" }
            Cull Off
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex CardExportDepthVert
            #pragma fragment DepthFrag
            #pragma shader_feature_local _ALPHATEX
            #pragma shader_feature_local _ALPHALUM

            #define FURBRUSH_HDRP_AVAILABLE
            #define FURBRUSH_HDRP_COMPAT
            #include "FurCard.hlsl"
            #include "FurExportLayout.hlsl"

            CardDepthVaryings CardExportDepthVert(CardExportAttributes v)
            {
                CardAttributes IN = CardExportUnpack(v);
                CardDepthVaryings o = (CardDepthVaryings)0;
                float3 posOS = CardScaleAndApplyCombAndGravity(IN.positionOS.xyz, IN.normalOS, IN.tangentOS, IN.uv1, IN.uv, IN.controlUV.xy, IN.baseUV);
                float3 positionWS = TransformObjectToWorld(posOS);
                o.positionCS = TransformWorldToHClip(positionWS);
                o.uv = IN.uv;
                o.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                o.controlUV = IN.controlUV;
                return o;
            }

            half4 DepthFrag(CardDepthVaryings IN) : SV_Target { CardClip(IN.uv, IN.controlUV, IN.positionCS); return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "SceneSelectionPass"
            Tags { "LightMode"="SceneSelectionPass" }
            Cull Off
            ZWrite On

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex CardExportSelectionVert
            #pragma fragment SelectionFrag
            #pragma editor_sync_compilation
            #pragma shader_feature_local _ALPHATEX
            #pragma shader_feature_local _ALPHALUM

            #define FURBRUSH_HDRP_AVAILABLE
            #define FURBRUSH_HDRP_COMPAT
            #include "FurCard.hlsl"
            #include "FurExportLayout.hlsl"

            int _ObjectId;
            int _PassValue;

            CardDepthVaryings CardExportSelectionVert(CardExportAttributes v)
            {
                CardAttributes IN = CardExportUnpack(v);
                CardDepthVaryings o = (CardDepthVaryings)0;
                float3 posOS = CardScaleAndApplyCombAndGravity(IN.positionOS.xyz, IN.normalOS, IN.tangentOS, IN.uv1, IN.uv, IN.controlUV.xy, IN.baseUV);
                float3 positionWS = TransformObjectToWorld(posOS);
                o.positionCS = TransformWorldToHClip(positionWS);
                o.uv = IN.uv;
                o.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                o.controlUV = IN.controlUV;
                return o;
            }

            float4 SelectionFrag(CardDepthVaryings IN) : SV_Target
            {
                clip(CardAlpha(IN.uv, IN.controlUV) - _Cutoff);
                return float4(_ObjectId, _PassValue, 1.0, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            Cull Off
            ZWrite On

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex CardExportDepthNormalsVert
            #pragma fragment DepthNormalsFrag
            #pragma shader_feature_local _ALPHATEX
            #pragma shader_feature_local _ALPHALUM

            #define FURBRUSH_HDRP_AVAILABLE
            #define FURBRUSH_HDRP_COMPAT
            #include "FurCard.hlsl"
            #include "FurExportLayout.hlsl"

            CardDepthVaryings CardExportDepthNormalsVert(CardExportAttributes v)
            {
                CardAttributes IN = CardExportUnpack(v);
                CardDepthVaryings o = (CardDepthVaryings)0;
                float3 posOS = CardScaleAndApplyCombAndGravity(IN.positionOS.xyz, IN.normalOS, IN.tangentOS, IN.uv1, IN.uv, IN.controlUV.xy, IN.baseUV);
                float3 positionWS = TransformObjectToWorld(posOS);
                o.positionCS = TransformWorldToHClip(positionWS);
                o.uv = IN.uv;
                o.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                o.controlUV = IN.controlUV;
                return o;
            }

            half4 DepthNormalsFrag(CardDepthVaryings IN) : SV_Target
            {
                CardClip(IN.uv, IN.controlUV, IN.positionCS);
                return half4(normalize(IN.normalWS), 0.0);
            }
            ENDHLSL
        }
    }

    // ======================================================================
    // URP
    // ======================================================================
    SubShader
    {
        PackageRequirements
        {
            "com.unity.render-pipelines.universal"
        }
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" "RenderPipeline"="UniversalPipeline" }
        LOD 300

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Cull Off
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex CardExportVert
            #pragma fragment CardFrag

            #pragma shader_feature_local _ALPHATEX
            #pragma shader_feature_local _ALPHALUM
            #pragma shader_feature_local _SMOOTHNESSMAP
            #pragma shader_feature_local _ROUGHNESS_INPUT
            #pragma multi_compile_fragment _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #define FURBRUSH_URP_AVAILABLE
            #define FURBRUSH_FORWARD_LIGHTING
            #include "FurCard.hlsl"
            #include "FurExportLayout.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            Cull Off
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex CardExportShadowVert
            #pragma fragment ShadowFrag
            #pragma shader_feature_local _ALPHATEX
            #pragma shader_feature_local _ALPHALUM
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #define FURBRUSH_URP_AVAILABLE
            #include "FurCard.hlsl"
            #include "FurExportLayout.hlsl"
#ifdef FURBRUSH_URP_NATIVE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
#endif

            float3 _LightDirection;
            float3 _LightPosition;

            CardDepthVaryings CardExportShadowVert(CardExportAttributes v)
            {
                CardAttributes IN = CardExportUnpack(v);
                CardDepthVaryings o = (CardDepthVaryings)0;
                float3 posOS = CardScaleAndApplyCombAndGravity(IN.positionOS.xyz, IN.normalOS, IN.tangentOS, IN.uv1, IN.uv, IN.controlUV.xy, IN.baseUV);
                float3 positionWS = TransformObjectToWorld(posOS);
                float3 normalWS   = TransformObjectToWorldNormal(IN.normalOS);
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirWS = _LightDirection;
                #endif
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirWS));
                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                o.positionCS = positionCS;
                o.uv = IN.uv;
                o.normalWS = normalWS;
                o.controlUV = IN.controlUV;
                return o;
            }

            half4 ShadowFrag(CardDepthVaryings IN) : SV_Target { CardClip(IN.uv, IN.controlUV, IN.positionCS); CardClipShadowOpacity(IN.controlUV); return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            Cull Off
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex CardExportDepthVert
            #pragma fragment DepthFrag
            #pragma shader_feature_local _ALPHATEX
            #pragma shader_feature_local _ALPHALUM

            #define FURBRUSH_URP_AVAILABLE
            #include "FurCard.hlsl"
            #include "FurExportLayout.hlsl"

            CardDepthVaryings CardExportDepthVert(CardExportAttributes v)
            {
                CardAttributes IN = CardExportUnpack(v);
                CardDepthVaryings o = (CardDepthVaryings)0;
                float3 posOS = CardScaleAndApplyCombAndGravity(IN.positionOS.xyz, IN.normalOS, IN.tangentOS, IN.uv1, IN.uv, IN.controlUV.xy, IN.baseUV);
                float3 positionWS = TransformObjectToWorld(posOS);
                o.positionCS = TransformWorldToHClip(positionWS);
                o.uv = IN.uv;
                o.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                o.controlUV = IN.controlUV;
                return o;
            }

            half4 DepthFrag(CardDepthVaryings IN) : SV_Target { CardClip(IN.uv, IN.controlUV, IN.positionCS); return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            Cull Off
            ZWrite On

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex CardExportDepthNormalsVert
            #pragma fragment DepthNormalsFrag
            #pragma shader_feature_local _ALPHATEX
            #pragma shader_feature_local _ALPHALUM

            #define FURBRUSH_URP_AVAILABLE
            #include "FurCard.hlsl"
            #include "FurExportLayout.hlsl"

            CardDepthVaryings CardExportDepthNormalsVert(CardExportAttributes v)
            {
                CardAttributes IN = CardExportUnpack(v);
                CardDepthVaryings o = (CardDepthVaryings)0;
                float3 posOS = CardScaleAndApplyCombAndGravity(IN.positionOS.xyz, IN.normalOS, IN.tangentOS, IN.uv1, IN.uv, IN.controlUV.xy, IN.baseUV);
                float3 positionWS = TransformObjectToWorld(posOS);
                o.positionCS = TransformWorldToHClip(positionWS);
                o.uv = IN.uv;
                o.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                o.controlUV = IN.controlUV;
                return o;
            }

            half4 DepthNormalsFrag(CardDepthVaryings IN) : SV_Target
            {
                CardClip(IN.uv, IN.controlUV, IN.positionCS);
                return half4(normalize(IN.normalWS), 0.0);
            }
            ENDHLSL
        }
    }

    // ======================================================================
    // Built-in Render Pipeline: one light per pass, so ForwardBase + ForwardAdd.
    // ======================================================================
    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" }
        LOD 300

        Pass
        {
            Name "ForwardBase"
            Tags { "LightMode"="ForwardBase" }
            Cull Off
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex CardExportVert
            #pragma fragment CardFrag

            #pragma shader_feature_local _ALPHATEX
            #pragma shader_feature_local _ALPHALUM
            #pragma shader_feature_local _SMOOTHNESSMAP
            #pragma shader_feature_local _ROUGHNESS_INPUT

            #pragma multi_compile_fwdbase
            #pragma multi_compile_fog
            #pragma skip_variants LIGHTMAP_ON DIRLIGHTMAP_COMBINED DYNAMICLIGHTMAP_ON LIGHTMAP_SHADOW_MIXING SHADOWS_SHADOWMASK VERTEXLIGHT_ON

            #define FURBRUSH_BIRP_COMPAT
            #define FURBRUSH_FORWARD_LIGHTING
            #include "FurCard.hlsl"
            #include "FurExportLayout.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ForwardAdd"
            Tags { "LightMode"="ForwardAdd" }
            Cull Off
            ZWrite Off
            ZTest LEqual
            Blend One One

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex CardExportVert
            #pragma fragment CardFrag

            #pragma shader_feature_local _ALPHATEX
            #pragma shader_feature_local _ALPHALUM
            #pragma shader_feature_local _SMOOTHNESSMAP
            #pragma shader_feature_local _ROUGHNESS_INPUT

            #pragma multi_compile_fwdadd_fullshadows
            #pragma multi_compile_fog

            #define FURBRUSH_BIRP_COMPAT
            #define FURBRUSH_FORWARD_LIGHTING
            #include "FurCard.hlsl"
            #include "FurExportLayout.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            Cull Off
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex CardExportShadowVert
            #pragma fragment ShadowFrag
            #pragma shader_feature_local _ALPHATEX
            #pragma shader_feature_local _ALPHALUM
            #pragma multi_compile_shadowcaster

            #define FURBRUSH_BIRP_COMPAT
            #include "FurCard.hlsl"
            #include "FurExportLayout.hlsl"

            struct CardShadowVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float4 controlUV  : TEXCOORD1;
                float3 lightVec   : TEXCOORD2;
            };

            CardShadowVaryings CardExportShadowVert(CardExportAttributes v)
            {
                CardAttributes IN = CardExportUnpack(v);
                CardShadowVaryings o = (CardShadowVaryings)0;
                float3 posOS = CardScaleAndApplyCombAndGravity(IN.positionOS.xyz, IN.normalOS, IN.tangentOS, IN.uv1, IN.uv, IN.controlUV.xy, IN.baseUV);
                float3 positionWS = TransformObjectToWorld(posOS);
                float3 normalWS   = TransformObjectToWorldNormal(IN.normalOS);

                o.positionCS = FurBuiltInShadowCasterClipPos(positionWS, normalWS);
                o.uv         = IN.uv;
                o.controlUV  = IN.controlUV;
                o.lightVec   = positionWS - _LightPositionRange.xyz;
                return o;
            }

            float4 ShadowFrag(CardShadowVaryings IN) : SV_Target
            {
                CardClip(IN.uv, IN.controlUV, IN.positionCS);
                CardClipShadowOpacity(IN.controlUV);

                #if defined(SHADOWS_CUBE) && !defined(SHADOWS_CUBE_IN_DEPTH_TEX)
                    return UnityEncodeCubeShadowDepth((length(IN.lightVec) + unity_LightShadowBias.x) * _LightPositionRange.w);
                #else
                    return 0;
                #endif
            }
            ENDHLSL
        }
    }

    FallBack Off
}

