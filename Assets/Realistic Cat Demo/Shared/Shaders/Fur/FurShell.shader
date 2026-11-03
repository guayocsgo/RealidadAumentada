// FurBrush Developer - export template for Shell fur.
//
// The exporter copies this file, renamed, into a published model's Shaders/ folder, where the fur
// has to render with no FurBrush installed. It differs from FurShell_URP/_HDRP/_BIRP in three
// ways and in nothing else:
//
//  * One shader serves all three pipelines. The URP and HDRP SubShaders open with a
//    PackageRequirements block, so Unity only compiles them in a project that has that package and
//    never reaches their pipeline #includes anywhere else; the Built-in SubShader needs no package.
//    That stands in for FurPipelineDefines.hlsl, which the plugin keeps current with an editor
//    script a published model does not carry, so every pass names its pipeline itself.
//  * The vertex input is FurExportAttributes (FurExportLayout.hlsl), the FBX-safe layout the
//    exporter writes, unpacked into the plugin's FurAttributes before any shading code runs.
//  * On export the ../../Runtime/Shaders/ include prefix is dropped: the shading code travels in
//    the same folder as this file.
Shader "Realistic Cat Demo/Fur/Shell"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base / Albedo (harvested)", 2D) = "white" {}
        [MainColor]   _BaseColor ("Base Color", Color) = (1,1,1,1)
        [Toggle(_SMOOTHNESSMAP)] _UseSmoothnessMap ("Use Smoothness Map", Float) = 0
        _SmoothnessMap ("Smoothness / Roughness", 2D) = "white" {}
        _Smoothness ("Smoothness", Range(0,1)) = 0.35
        [Toggle(_ROUGHNESS_INPUT)] _RoughnessInput ("Map is Roughness", Float) = 0
        _SmoothnessChannel ("Smoothness Channel (0R 1G 2B 3A)", Float) = 3
        [Toggle(_NORMALMAP)] _UseNormalMap ("Use Normal Map", Float) = 0
        [Normal] _BumpMap ("Normal Map", 2D) = "bump" {}

        [NoScaleOffset] _FurControlMap ("Control Map (R=len G=mask B,A=comb)", 2D) = "black" {}

        _MaxLength ("Max Length", Float) = 0.05
        _LengthScale ("Length Scale", Range(0,3)) = 0.2
        _Density ("Strand Density", Range(1,2048)) = 450
        _Thinness ("Tip Thinness", Range(0,1)) = 0.65
        _LengthJitter ("Length Jitter", Range(0,1)) = 0.35
        _Clumping ("Clumping", Range(0,4)) = 1
        _DirRandom ("Direction Randomness", Range(0,1)) = 0.3
        _ColorVar ("Color Variation", Range(0,1)) = 0.25

        _RootColor ("Root Shade", Color) = (0.5,0.5,0.5,1)
        _TipColor ("Tip Shade", Color) = (1,1,1,1)
        _AlbedoInfluence ("Albedo Influence", Range(0,1)) = 1
        _RootAO ("Root AO", Range(0,2)) = 0.5

        _AnisoSpecular ("Aniso Specular", Range(0,2)) = 0.6
        _Rim ("Rim / Transmission", Range(0,1)) = 0.4
        _DiffuseWrap ("Diffuse Wrap (1 = fur look, 0 = match Lit)", Range(0,1)) = 1
        _ShadowOpacity ("Fur Cast Shadow Opacity", Range(0,1)) = 0.45

        _Gravity ("Gravity (local)", Vector) = (0,-1,0,0)
        _GravityStrength ("Gravity Strength", Range(0,1)) = 0.3
        [HideInInspector] _DynamicMotion ("Dynamic Motion (runtime)", Vector) = (0,0,0,0)
        [HideInInspector] _Wind ("Wind (runtime)", Vector) = (0,0,0,0)
        _CombStrength ("Comb Bend Strength", Range(0,5)) = 1.2
        _CombSurfaceAdherence ("Comb Surface Adherence", Range(0,1)) = 0.65
        _CombJitter ("Micro Flow Noise", Range(0,0.35)) = 0.0
        _CombUprightness ("Combing Uprightness", Range(0,1)) = 0.3
        // Live quality control: the mesh carries every baked layer and the shader draws this
        // many of them, evenly spaced. The exporter narrows the range to what the mesh carries.
        [HideInInspector] _ShellCount ("Baked layers (mesh metadata)", Float) = 16
        // Written per renderer by Fur Shell Layers when the model carries one copy of its coat.
        [HideInInspector] _ShellLayer ("Shell Layer (runtime)", Float) = 0
        [HideInInspector] _ShellLayers ("Shell Layer Count (runtime)", Float) = 0
        _ParallaxScale ("View Projection", Range(0,8)) = 0.5
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
            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex FurExportVertForward
            #pragma fragment FurFragForward

            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _SMOOTHNESSMAP
            #pragma shader_feature_local _ROUGHNESS_INPUT
            #pragma shader_feature_local _CONTROL_UV1

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
            // The layer a draw stands for is a per-renderer value only a published model has.
            #define FURBRUSH_EXPORT_SHELL_LAYERS
            #include "FurShell.hlsl"
            #include "FurExportLayout.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            Cull Back
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex FurExportShadowVert
            #pragma fragment FurShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #pragma shader_feature_local _CONTROL_UV1

            #define FURBRUSH_HDRP_AVAILABLE
            #define FURBRUSH_HDRP_COMPAT
            // The layer a draw stands for is a per-renderer value only a published model has.
            #define FURBRUSH_EXPORT_SHELL_LAYERS
            #include "FurShell.hlsl"
            #include "FurExportLayout.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            FurDepthVaryings FurExportShadowVert(FurExportAttributes v)
            {
                FurAttributes IN = FurExportUnpack(v);
                FurDepthVaryings o = (FurDepthVaryings)0;
                float3 posOS, nOS; float2 cuv, auv; float t; FurControl ctrl;
                FurExtrude(IN, posOS, nOS, cuv, auv, t, ctrl, o.strandDirWS);

                float3 positionWS = TransformObjectToWorld(posOS);
                float3 normalWS   = TransformObjectToWorldNormal(nOS);

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
                o.controlUV = cuv; o.strandUV = auv; o.t = t; o.normalWS = normalWS;
                o.positionWS = positionWS;
                o.tangentWS = float4(TransformObjectToWorldDir(IN.tangentOS.xyz), IN.tangentOS.w);
                return o;
            }

            half4 FurShadowFrag(FurDepthVaryings IN) : SV_Target
            {
                FurControl ctrl = DecodeFurControl(SAMPLE_TEXTURE2D(_FurControlMap, sampler_FurControlMap, IN.controlUV), _HasControlMap);
                float widthLoc = 1.0;
                if (_HasWidthMap > 0.5)
                {
                    widthLoc = SAMPLE_TEXTURE2D(_FurWidthMap, sampler_FurWidthMap, IN.controlUV).r;
                }
                FurClip(IN.strandUV, ctrl.mask, IN.t, IN.positionCS, widthLoc, ctrl.length);
                FurClipShadowOpacity(IN.strandUV, IN.t);
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthForwardOnly"
            Tags { "LightMode"="DepthForwardOnly" }
            Cull Back
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex FurExportDepthVert
            #pragma fragment FurDepthFrag
            #pragma shader_feature_local _CONTROL_UV1

            #define FURBRUSH_HDRP_AVAILABLE
            #define FURBRUSH_HDRP_COMPAT
            // The layer a draw stands for is a per-renderer value only a published model has.
            #define FURBRUSH_EXPORT_SHELL_LAYERS
            #include "FurShell.hlsl"
            #include "FurExportLayout.hlsl"

            FurDepthVaryings FurExportDepthVert(FurExportAttributes v)
            {
                FurAttributes IN = FurExportUnpack(v);
                FurDepthVaryings o = (FurDepthVaryings)0;
                float3 posOS, nOS; float2 cuv, auv; float t; FurControl ctrl;
                FurExtrude(IN, posOS, nOS, cuv, auv, t, ctrl, o.strandDirWS);
                VertexPositionInputs vpi = GetVertexPositionInputs(posOS);
                o.positionCS = vpi.positionCS;
                o.controlUV = cuv; o.strandUV = auv; o.t = t;
                o.normalWS = TransformObjectToWorldNormal(nOS);
                o.positionWS = vpi.positionWS;
                o.tangentWS = float4(TransformObjectToWorldDir(IN.tangentOS.xyz), IN.tangentOS.w);
                return o;
            }

            half4 FurDepthFrag(FurDepthVaryings IN) : SV_Target
            {
                FurControl ctrl = DecodeFurControl(SAMPLE_TEXTURE2D(_FurControlMap, sampler_FurControlMap, IN.controlUV), _HasControlMap);
                float widthLoc = 1.0;
                if (_HasWidthMap > 0.5)
                {
                    widthLoc = SAMPLE_TEXTURE2D(_FurWidthMap, sampler_FurWidthMap, IN.controlUV).r;
                }
                FurClip(IN.strandUV, ctrl.mask, IN.t, IN.positionCS, widthLoc, ctrl.length);
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "SceneSelectionPass"
            Tags { "LightMode"="SceneSelectionPass" }
            Cull Back
            ZWrite On

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex FurExportSelectionVert
            #pragma fragment FurSelectionFrag
            #pragma editor_sync_compilation
            #pragma shader_feature_local _CONTROL_UV1

            #define FURBRUSH_HDRP_AVAILABLE
            #define FURBRUSH_HDRP_COMPAT
            // The layer a draw stands for is a per-renderer value only a published model has.
            #define FURBRUSH_EXPORT_SHELL_LAYERS
            #include "FurShell.hlsl"
            #include "FurExportLayout.hlsl"

            int _ObjectId;
            int _PassValue;

            FurDepthVaryings FurExportSelectionVert(FurExportAttributes v)
            {
                FurAttributes IN = FurExportUnpack(v);
                FurDepthVaryings o = (FurDepthVaryings)0;
                float3 posOS, nOS; float2 cuv, auv; float t; FurControl ctrl;
                FurExtrude(IN, posOS, nOS, cuv, auv, t, ctrl, o.strandDirWS);
                VertexPositionInputs vpi = GetVertexPositionInputs(posOS);
                o.positionCS = vpi.positionCS;
                o.controlUV = cuv; o.strandUV = auv; o.t = t;
                o.normalWS = TransformObjectToWorldNormal(nOS);
                o.positionWS = vpi.positionWS;
                o.tangentWS = float4(TransformObjectToWorldDir(IN.tangentOS.xyz), IN.tangentOS.w);
                return o;
            }

            float4 FurSelectionFrag(FurDepthVaryings IN) : SV_Target
            {
                FurControl ctrl = DecodeFurControl(SAMPLE_TEXTURE2D(_FurControlMap, sampler_FurControlMap, IN.controlUV), _HasControlMap);
                float widthLoc = 1.0;
                if (_HasWidthMap > 0.5)
                {
                    widthLoc = SAMPLE_TEXTURE2D(_FurWidthMap, sampler_FurWidthMap, IN.controlUV).r;
                }
                float cov = FurCoverage(IN.strandUV, ctrl.mask, IN.t, float2(1.0, 0.0), 1.0, widthLoc, ctrl.length);
                clip(cov - FUR_CLIP_THRESHOLD);
                return float4(_ObjectId, _PassValue, 1.0, 1.0);
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            Cull Back
            ZWrite On

            HLSLPROGRAM
            #pragma target 4.5
            #pragma vertex FurExportDepthNormalsVert
            #pragma fragment FurDepthNormalsFrag
            #pragma shader_feature_local _CONTROL_UV1

            #define FURBRUSH_HDRP_AVAILABLE
            #define FURBRUSH_HDRP_COMPAT
            // The layer a draw stands for is a per-renderer value only a published model has.
            #define FURBRUSH_EXPORT_SHELL_LAYERS
            #include "FurShell.hlsl"
            #include "FurExportLayout.hlsl"

            FurDepthVaryings FurExportDepthNormalsVert(FurExportAttributes v)
            {
                FurAttributes IN = FurExportUnpack(v);
                FurDepthVaryings o = (FurDepthVaryings)0;
                float3 posOS, nOS; float2 cuv, auv; float t; FurControl ctrl;
                FurExtrude(IN, posOS, nOS, cuv, auv, t, ctrl, o.strandDirWS);
                VertexPositionInputs vpi = GetVertexPositionInputs(posOS);
                o.positionCS = vpi.positionCS;
                o.controlUV = cuv; o.strandUV = auv; o.t = t;
                o.normalWS = TransformObjectToWorldNormal(nOS);
                o.positionWS = vpi.positionWS;
                o.tangentWS = float4(TransformObjectToWorldDir(IN.tangentOS.xyz), IN.tangentOS.w);
                return o;
            }

            half4 FurDepthNormalsFrag(FurDepthVaryings IN) : SV_Target
            {
                FurControl ctrl = DecodeFurControl(SAMPLE_TEXTURE2D(_FurControlMap, sampler_FurControlMap, IN.controlUV), _HasControlMap);
                float widthLoc = 1.0;
                if (_HasWidthMap > 0.5)
                {
                    widthLoc = SAMPLE_TEXTURE2D(_FurWidthMap, sampler_FurWidthMap, IN.controlUV).r;
                }
                FurClip(IN.strandUV, ctrl.mask, IN.t, IN.positionCS, widthLoc, ctrl.length);
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
            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex FurExportVertForward
            #pragma fragment FurFragForward

            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _SMOOTHNESSMAP
            #pragma shader_feature_local _ROUGHNESS_INPUT
            #pragma shader_feature_local _CONTROL_UV1

            #pragma multi_compile_fragment _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #define FURBRUSH_URP_AVAILABLE
            #define FURBRUSH_FORWARD_LIGHTING
            // The layer a draw stands for is a per-renderer value only a published model has.
            #define FURBRUSH_EXPORT_SHELL_LAYERS
            #include "FurShell.hlsl"
            #include "FurExportLayout.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            Cull Back
            ZWrite On
            ZTest LEqual
            ColorMask 0

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex FurExportShadowVert
            #pragma fragment FurShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #pragma shader_feature_local _CONTROL_UV1

            #define FURBRUSH_URP_AVAILABLE
            // The layer a draw stands for is a per-renderer value only a published model has.
            #define FURBRUSH_EXPORT_SHELL_LAYERS
            #include "FurShell.hlsl"
            #include "FurExportLayout.hlsl"
#ifdef FURBRUSH_URP_NATIVE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
#endif

            float3 _LightDirection;
            float3 _LightPosition;

            FurDepthVaryings FurExportShadowVert(FurExportAttributes v)
            {
                FurAttributes IN = FurExportUnpack(v);
                FurDepthVaryings o = (FurDepthVaryings)0;
                float3 posOS, nOS; float2 cuv, auv; float t; FurControl ctrl;
                FurExtrude(IN, posOS, nOS, cuv, auv, t, ctrl, o.strandDirWS);

                float3 positionWS = TransformObjectToWorld(posOS);
                float3 normalWS   = TransformObjectToWorldNormal(nOS);

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
                o.controlUV = cuv; o.strandUV = auv; o.t = t; o.normalWS = normalWS;
                o.positionWS = positionWS;
                o.tangentWS = float4(TransformObjectToWorldDir(IN.tangentOS.xyz), IN.tangentOS.w);
                return o;
            }

            half4 FurShadowFrag(FurDepthVaryings IN) : SV_Target
            {
                FurControl ctrl = DecodeFurControl(SAMPLE_TEXTURE2D(_FurControlMap, sampler_FurControlMap, IN.controlUV), _HasControlMap);
                float widthLoc = 1.0;
                if (_HasWidthMap > 0.5)
                {
                    widthLoc = SAMPLE_TEXTURE2D(_FurWidthMap, sampler_FurWidthMap, IN.controlUV).r;
                }
                FurClip(IN.strandUV, ctrl.mask, IN.t, IN.positionCS, widthLoc, ctrl.length);
                FurClipShadowOpacity(IN.strandUV, IN.t);
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            Cull Back
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex FurExportDepthVert
            #pragma fragment FurDepthFrag
            #pragma shader_feature_local _CONTROL_UV1

            #define FURBRUSH_URP_AVAILABLE
            // The layer a draw stands for is a per-renderer value only a published model has.
            #define FURBRUSH_EXPORT_SHELL_LAYERS
            #include "FurShell.hlsl"
            #include "FurExportLayout.hlsl"

            FurDepthVaryings FurExportDepthVert(FurExportAttributes v)
            {
                FurAttributes IN = FurExportUnpack(v);
                FurDepthVaryings o = (FurDepthVaryings)0;
                float3 posOS, nOS; float2 cuv, auv; float t; FurControl ctrl;
                FurExtrude(IN, posOS, nOS, cuv, auv, t, ctrl, o.strandDirWS);
                VertexPositionInputs vpi = GetVertexPositionInputs(posOS);
                o.positionCS = vpi.positionCS;
                o.controlUV = cuv; o.strandUV = auv; o.t = t;
                o.normalWS = TransformObjectToWorldNormal(nOS);
                o.positionWS = vpi.positionWS;
                o.tangentWS = float4(TransformObjectToWorldDir(IN.tangentOS.xyz), IN.tangentOS.w);
                return o;
            }

            half4 FurDepthFrag(FurDepthVaryings IN) : SV_Target
            {
                FurControl ctrl = DecodeFurControl(SAMPLE_TEXTURE2D(_FurControlMap, sampler_FurControlMap, IN.controlUV), _HasControlMap);
                float widthLoc = 1.0;
                if (_HasWidthMap > 0.5)
                {
                    widthLoc = SAMPLE_TEXTURE2D(_FurWidthMap, sampler_FurWidthMap, IN.controlUV).r;
                }
                float2 projectionDir; float projectionAmount;
                float2 strandUV = FurViewProjectedStrandUV(IN.strandUV, IN.t, ctrl, IN.strandDirWS, IN.positionWS, IN.normalWS, IN.tangentWS, projectionDir, projectionAmount);
                FurClipSilhouette(strandUV, ctrl.mask, ctrl.comb, IN.t, IN.positionCS, IN.positionWS, IN.strandDirWS, projectionDir, projectionAmount, widthLoc, ctrl.length);
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            Cull Back
            ZWrite On

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex FurExportDepthNormalsVert
            #pragma fragment FurDepthNormalsFrag
            #pragma shader_feature_local _CONTROL_UV1

            #define FURBRUSH_URP_AVAILABLE
            // The layer a draw stands for is a per-renderer value only a published model has.
            #define FURBRUSH_EXPORT_SHELL_LAYERS
            #include "FurShell.hlsl"
            #include "FurExportLayout.hlsl"

            FurDepthVaryings FurExportDepthNormalsVert(FurExportAttributes v)
            {
                FurAttributes IN = FurExportUnpack(v);
                FurDepthVaryings o = (FurDepthVaryings)0;
                float3 posOS, nOS; float2 cuv, auv; float t; FurControl ctrl;
                FurExtrude(IN, posOS, nOS, cuv, auv, t, ctrl, o.strandDirWS);
                VertexPositionInputs vpi = GetVertexPositionInputs(posOS);
                o.positionCS = vpi.positionCS;
                o.controlUV = cuv; o.strandUV = auv; o.t = t;
                o.normalWS = TransformObjectToWorldNormal(nOS);
                o.positionWS = vpi.positionWS;
                o.tangentWS = float4(TransformObjectToWorldDir(IN.tangentOS.xyz), IN.tangentOS.w);
                return o;
            }

            half4 FurDepthNormalsFrag(FurDepthVaryings IN) : SV_Target
            {
                FurControl ctrl = DecodeFurControl(SAMPLE_TEXTURE2D(_FurControlMap, sampler_FurControlMap, IN.controlUV), _HasControlMap);
                float widthLoc = 1.0;
                if (_HasWidthMap > 0.5)
                {
                    widthLoc = SAMPLE_TEXTURE2D(_FurWidthMap, sampler_FurWidthMap, IN.controlUV).r;
                }
                float2 projectionDir; float projectionAmount;
                float2 strandUV = FurViewProjectedStrandUV(IN.strandUV, IN.t, ctrl, IN.strandDirWS, IN.positionWS, IN.normalWS, IN.tangentWS, projectionDir, projectionAmount);
                FurClipSilhouette(strandUV, ctrl.mask, ctrl.comb, IN.t, IN.positionCS, IN.positionWS, IN.strandDirWS, projectionDir, projectionAmount, widthLoc, ctrl.length);
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
            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex FurExportVertForward
            #pragma fragment FurFragForward

            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _SMOOTHNESSMAP
            #pragma shader_feature_local _ROUGHNESS_INPUT
            #pragma shader_feature_local _CONTROL_UV1

            #pragma multi_compile_fwdbase
            #pragma multi_compile_fog
            #pragma skip_variants LIGHTMAP_ON DIRLIGHTMAP_COMBINED DYNAMICLIGHTMAP_ON LIGHTMAP_SHADOW_MIXING SHADOWS_SHADOWMASK VERTEXLIGHT_ON

            #define FURBRUSH_BIRP_COMPAT
            #define FURBRUSH_FORWARD_LIGHTING
            // The layer a draw stands for is a per-renderer value only a published model has.
            #define FURBRUSH_EXPORT_SHELL_LAYERS
            #include "FurShell.hlsl"
            #include "FurExportLayout.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ForwardAdd"
            Tags { "LightMode"="ForwardAdd" }
            Cull Back
            ZWrite Off
            ZTest LEqual
            Blend One One

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex FurExportVertForward
            #pragma fragment FurFragForward

            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _SMOOTHNESSMAP
            #pragma shader_feature_local _ROUGHNESS_INPUT
            #pragma shader_feature_local _CONTROL_UV1

            #pragma multi_compile_fwdadd_fullshadows
            #pragma multi_compile_fog

            #define FURBRUSH_BIRP_COMPAT
            #define FURBRUSH_FORWARD_LIGHTING
            // The layer a draw stands for is a per-renderer value only a published model has.
            #define FURBRUSH_EXPORT_SHELL_LAYERS
            #include "FurShell.hlsl"
            #include "FurExportLayout.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex FurExportShadowVert
            #pragma fragment FurShadowFrag
            #pragma multi_compile_shadowcaster
            #pragma shader_feature_local _CONTROL_UV1

            #define FURBRUSH_BIRP_COMPAT
            // The layer a draw stands for is a per-renderer value only a published model has.
            #define FURBRUSH_EXPORT_SHELL_LAYERS
            #include "FurShell.hlsl"
            #include "FurExportLayout.hlsl"

            struct FurShadowVaryings
            {
                float4 positionCS : SV_POSITION;
                float2 controlUV  : TEXCOORD0;
                float2 strandUV   : TEXCOORD1;
                float  t          : TEXCOORD2;
                float3 lightVec   : TEXCOORD3;
            };

            FurShadowVaryings FurExportShadowVert(FurExportAttributes v)
            {
                FurAttributes IN = FurExportUnpack(v);
                FurShadowVaryings o = (FurShadowVaryings)0;
                float3 posOS, nOS; float2 cuv, auv; float t; FurControl ctrl; float3 strandDirWS;
                FurExtrude(IN, posOS, nOS, cuv, auv, t, ctrl, strandDirWS);

                float3 positionWS = TransformObjectToWorld(posOS);
                float3 normalWS   = TransformObjectToWorldNormal(nOS);

                o.positionCS = FurBuiltInShadowCasterClipPos(positionWS, normalWS);
                o.controlUV  = cuv;
                o.strandUV   = auv;
                o.t          = t;
                o.lightVec   = positionWS - _LightPositionRange.xyz;
                return o;
            }

            float4 FurShadowFrag(FurShadowVaryings IN) : SV_Target
            {
                FurControl ctrl = DecodeFurControl(SAMPLE_TEXTURE2D(_FurControlMap, sampler_FurControlMap, IN.controlUV), _HasControlMap);
                float widthLoc = 1.0;
                if (_HasWidthMap > 0.5)
                {
                    widthLoc = SAMPLE_TEXTURE2D(_FurWidthMap, sampler_FurWidthMap, IN.controlUV).r;
                }
                FurClip(IN.strandUV, ctrl.mask, IN.t, IN.positionCS, widthLoc, ctrl.length);
                FurClipShadowOpacity(IN.strandUV, IN.t);

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
    CustomEditor "RealisticCatDemo.Editor.FurShaderGUI"
}

