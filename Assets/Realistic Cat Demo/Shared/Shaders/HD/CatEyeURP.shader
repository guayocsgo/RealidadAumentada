Shader "Realistic Cat Demo/URP/Eye" {
Properties {  _BaseMap("UV0 iris / albedo atlas", 2D) = "white" {}
 _IrisMap("Iris texture (UV1)", 2D) = "white" {}
 _ScleraMap("Sclera", 2D) = "white" {}
 _ScleraColor("Sclera color", Color) = (1,1,1,1)
 _IrisColor("Iris color", Color) = (1,1,1,1)
 _IrisHue("Iris hue", Range(-180,180)) = 0
 _IrisSaturation("Iris saturation", Range(0,2)) = 1
 _BaseColor("Tint", Color) = (1,1,1,1)
 _LowerShadowStrength("Lower eyelid shadow strength", Range(0,1)) = 0.1
 _LowerShadowHeight("Lower eyelid height", Range(0,0.7)) = 0.22
 _CornerShadowStrength("Corners shadow strength", Range(0,1)) = 0.18
 _CornerShadowWidth("Corners shadow width", Range(0.01,0.4)) = 0.18
 _EyeForwardOS("Eye forward (local XYZ)", Vector) = (0,0,1,0)
 _EyeUpOS("Eye up (local XYZ)", Vector) = (0,1,0,0)
 _IrisDepth("Iris depth (parallax)", Range(0,0.08)) = 0.025
 _ShadowStrength("Eyelid shadow strength", Range(0,1)) = 0.35
 _ShadowSoftness("Eyelid shadow softness", Range(0.01,0.4)) = 0.15
 _ShadowHeight("Upper eyelid height (UV1)", Range(0.3,1)) = 0.72
 _Pupil("Pupil dilation", Range(0,1)) = 0.25
 _PupilShape("Pupil shape (slit to round)", Range(0,1)) = 0
 _PupilWidth("Pupil width", Range(0.25,1.5)) = 1
 _PupilHeight("Pupil height", Range(0.25,1.5)) = 1
 _IrisRotation("Iris / pupil rotation (degrees)", Range(-180,180)) = 0
 [Enum(UV0,0,UV1,1)] _IrisUVSet("Iris placement UV set", Float) = 1
 _IrisUVOffsetX("Iris UV offset X", Range(-0.5,0.5)) = 0
 _IrisUVOffsetY("Iris UV offset Y", Range(-0.5,0.5)) = 0
 _IrisRadius("Iris radius in normalized eye UV", Range(0.1,0.5)) = 0.4
 [HideInInspector] _EyeRect("Atlas eye rect xy=min zw=size", Vector) = (0,0,1,1)
 _CorneaSmoothness("Cornea Smoothness", Range(0.7,0.99)) = 0.94
 _CorneaBulge("Cornea bulge", Range(0,1)) = 0.22 }
SubShader {
Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }
Pass {
Name "ForwardLit"
Tags { "LightMode"="UniversalForwardOnly" }
HLSLPROGRAM
#pragma target 3.5
#pragma vertex Vert
#pragma fragment Frag
#pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
#pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
#pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
#pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
#pragma multi_compile _ _CLUSTER_LIGHT_LOOP
#pragma multi_compile_fragment _ _LIGHT_COOKIES
#pragma multi_compile_fragment _ _LIGHT_LAYERS
#pragma multi_compile_fog
#pragma multi_compile_instancing
#define _SPECULAR_SETUP 1
#define CAT_EYE 1
#define _CLEARCOAT 1
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "CatTissue.hlsl"
TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
TEXTURE2D(_IrisMap); SAMPLER(sampler_IrisMap);
TEXTURE2D(_ScleraMap); SAMPLER(sampler_ScleraMap);
TEXTURE2D(_RoughnessMap); SAMPLER(sampler_RoughnessMap);
TEXTURE2D(_TissueMap); SAMPLER(sampler_TissueMap);
TEXTURE2D(_MicroMap); SAMPLER(sampler_MicroMap);
CBUFFER_START(UnityPerMaterial)
float4 _BaseColor, _BaseMap_ST, _TransmissionTint, _EyeRect, _IrisColor;
float _BumpScale, _RoughnessScale, _ThicknessMM, _Transmission, _VesselStrength, _Subsurface, _PoreSizeMM, _PoreNormalStrength, _PoreRoughnessStrength;
float4 _EyeForwardOS, _EyeUpOS, _ScleraColor;
float _LowerShadowStrength, _LowerShadowHeight, _CornerShadowStrength, _CornerShadowWidth;
float _IrisDepth, _ShadowStrength, _ShadowSoftness, _ShadowHeight;
float _Pupil, _PupilShape, _PupilWidth, _PupilHeight, _IrisRotation, _IrisUVSet, _IrisUVOffsetX, _IrisUVOffsetY, _IrisRadius, _CorneaSmoothness, _CorneaBulge, _IrisHue, _IrisSaturation;
CBUFFER_END
struct A { float4 pos:POSITION; float3 n:NORMAL; float4 t:TANGENT; float2 uv:TEXCOORD0; float2 uv1:TEXCOORD1; UNITY_VERTEX_INPUT_INSTANCE_ID };
struct V { float4 pos:SV_POSITION; float3 ws:TEXCOORD0; half3 n:TEXCOORD1; half4 t:TEXCOORD2; float2 uv0:TEXCOORD3; float2 uv1:TEXCOORD4; half fog:TEXCOORD5; UNITY_VERTEX_INPUT_INSTANCE_ID UNITY_VERTEX_OUTPUT_STEREO };
V Vert(A i) { V o=(V)0; UNITY_SETUP_INSTANCE_ID(i); UNITY_TRANSFER_INSTANCE_ID(i,o); UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
#ifdef CAT_EYE
// Zero vertex displacement: eyeball geometry remains 100% spherical and intact.
// Cornea bulge operates optically via Snell refraction parallax and dome normals.
#endif
VertexPositionInputs p=GetVertexPositionInputs(i.pos.xyz); VertexNormalInputs n=GetVertexNormalInputs(i.n,i.t);
o.pos=p.positionCS;o.ws=p.positionWS;o.n=n.normalWS;o.t=half4(n.tangentWS,i.t.w*GetOddNegativeScale());o.uv0=TRANSFORM_TEX(i.uv,_BaseMap);o.uv1=i.uv1;o.fog=ComputeFogFactor(o.pos.z);return o; }
half3 Trans(Light l, InputData d, half4 tissue) {
#ifdef _LIGHT_LAYERS
if(!IsMatchingLightLayer(l.layerMask,GetMeshRenderingLayer())) return 0;
#endif
return CatTransmission(d.normalWS,d.viewDirectionWS,l.direction,tissue.g*_ThicknessMM,tissue.b*_VesselStrength,tissue.r*tissue.a,_Transmission,float3(1,.8,.7))*l.color*l.distanceAttenuation*l.shadowAttenuation;
}
half3 Scatter(Light l,InputData d,half4 tissue,half3 base) {
#ifdef _LIGHT_LAYERS
if(!IsMatchingLightLayer(l.layerMask,GetMeshRenderingLayer())) return 0;
#endif
return CatScatter(d.normalWS,l.direction,base,tissue.r,_Subsurface)*l.color*l.distanceAttenuation*l.shadowAttenuation;
}
half4 Frag(V i):SV_Target {
UNITY_SETUP_INSTANCE_ID(i); UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

float2 uv0=i.uv0;float2 uv1=i.uv1;
float pupil=0, limbus=0;
#ifdef CAT_EYE
float2 irisUV;float irisMask;
float2 eyeUV0=(uv0-_EyeRect.xy)/max(abs(_EyeRect.zw),float2(1e-5,1e-5));
float2 placementUV=lerp(eyeUV0,uv1,saturate(_IrisUVSet));
float2 eyeUV=placementUV-float2(_IrisUVOffsetX,_IrisUVOffsetY);

float3 viewWS=GetWorldSpaceNormalizeViewDir(i.ws);
float3 normalWS=normalize(i.n);
float3 tangentWS=normalize(i.t.xyz);
float3 bitangentWS=normalize(cross(normalWS,tangentWS)*i.t.w);

float3 opticalNormalTS; float opticalCorneaMask;
float2 opticalOffset=CatEyeOptics(eyeUV,i.ws,normalWS,viewWS,tangentWS,bitangentWS,
    _CorneaBulge,_IrisDepth,_IrisRadius,opticalNormalTS,opticalCorneaMask);
CatEyeUV(eyeUV+opticalOffset, _Pupil, _IrisRadius, _PupilShape, _PupilWidth, _PupilHeight, _IrisRotation, irisUV, pupil, limbus, irisMask);
float2 uv1Atlas=_EyeRect.xy+irisUV*_EyeRect.zw;
// The sclera texture is an eye-local texture.  UV0 needs its atlas rectangle
// normalized first; UV1 is already authored as an eye-local layout.
float2 scleraUV=lerp(eyeUV0,uv1,saturate(_IrisUVSet));
float3 scleraColor=SAMPLE_TEXTURE2D(_ScleraMap,sampler_ScleraMap,scleraUV).rgb*_ScleraColor.rgb;
float3 uv1Color=SAMPLE_TEXTURE2D(_IrisMap,sampler_IrisMap,irisUV).rgb;
float3 uv0Color=SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,uv0+CatEyeUVOffset(placementUV,uv0,irisUV-placementUV)).rgb;
float3 irisColor=lerp(uv0Color,uv1Color,saturate(_IrisUVSet));
irisColor*=_IrisColor.rgb;
irisColor=CatIrisHueSaturation(irisColor,_IrisHue,_IrisSaturation);
float3 eyeColor=lerp(CatScleraColor(scleraColor,eyeUV,_IrisRadius),irisColor,irisMask);
float contactShadow = CatEyeContactShadow(placementUV, _ShadowHeight, _ShadowSoftness, _ShadowStrength,
    _LowerShadowHeight, _LowerShadowStrength, _CornerShadowWidth, _CornerShadowStrength);
#endif
half3 base = SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,uv0).rgb * _BaseColor.rgb;
half4 tissue = SAMPLE_TEXTURE2D(_TissueMap,sampler_TissueMap,uv0);
half rough = SAMPLE_TEXTURE2D(_RoughnessMap,sampler_RoughnessMap,uv0).r;
half3 nts = half3(0,0,1);
#ifdef CAT_EYE
base=eyeColor*_BaseColor.rgb*(1.0 - contactShadow);rough=SAMPLE_TEXTURE2D(_RoughnessMap,sampler_RoughnessMap,uv1Atlas).r;
#endif
half smoothness = 1-saturate(rough*_RoughnessScale);
#ifndef CAT_EYE
float3x3 objectMatrix=(float3x3)GetObjectToWorldMatrix();
float3 axisX=mul(objectMatrix,float3(1,0,0)),axisY=mul(objectMatrix,float3(0,1,0)),axisZ=mul(objectMatrix,float3(0,0,1));
float3 pOS=TransformWorldToObject(i.ws)*float3(length(axisX),length(axisY),length(axisZ))*(1000.0/max(_PoreSizeMM,0.1));
float3 nOS=normalize(mul((float3x3)transpose(GetObjectToWorldMatrix()),i.n));
float3 poreSlope;float poreRough;
float2 microStep=_MicroMap_TexelSize.xy*1.5;
float3 poreX=float3(SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.yz).r,SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.yz+microStep).r,SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.yz+microStep.yx).r);
float3 poreY=float3(SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.xz).r,SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.xz+microStep).r,SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.xz+microStep.yx).r);
float3 poreZ=float3(SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.xy).r,SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.xy+microStep).r,SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.xy+microStep.yx).r);
CatMicroData(nOS,poreX,poreY,poreZ,poreSlope,poreRough);
float3 slopeWS=normalize(axisX)*poreSlope.x+normalize(axisY)*poreSlope.y+normalize(axisZ)*poreSlope.z;
nts.xy+=float2(dot(slopeWS,normalize(i.t.xyz)),dot(slopeWS,normalize(cross(i.n,i.t.xyz)*i.t.w)))*tissue.r*_PoreNormalStrength;
nts=normalize(nts);
smoothness=1-clamp(rough*_RoughnessScale+poreRough*.30*tissue.r*_PoreRoughnessStrength,.18,.95);
base*=1-tissue.b*tissue.a*exp(-tissue.g*6)*float3(.025,.07,.055);
#endif
#ifdef CAT_EYE
base=lerp(base*lerp(1,0.55,limbus),float3(0.002,0.003,0.004),pupil);
float corneaMask=opticalCorneaMask;
nts=opticalNormalTS;
smoothness=lerp(0.78, 0.50, irisMask);
tissue=0;
#endif

InputData inputData=(InputData)0; inputData.positionWS=i.ws;
half3x3 tbn=half3x3(normalize(i.t.xyz),normalize(cross(i.n,i.t.xyz)*i.t.w),normalize(i.n));
inputData.normalWS=NormalizeNormalPerPixel(mul(nts,tbn));
inputData.viewDirectionWS=GetWorldSpaceNormalizeViewDir(i.ws);
inputData.shadowCoord=TransformWorldToShadowCoord(i.ws);
inputData.bakedGI=SampleSH(inputData.normalWS); inputData.shadowMask=half4(1,1,1,1);
inputData.normalizedScreenSpaceUV=GetNormalizedScreenSpaceUV(i.pos);
inputData.vertexLighting=VertexLighting(i.ws,inputData.normalWS);
SurfaceData s=(SurfaceData)0;s.albedo=base;s.specular=0.028;s.smoothness=smoothness;s.normalTS=nts;s.occlusion=1;s.alpha=1;
#ifdef CAT_EYE
s.specular=0.025;s.clearCoatMask=corneaMask*(1.0 - contactShadow);s.clearCoatSmoothness=_CorneaSmoothness;s.occlusion=1.0 - contactShadow*0.7;
#endif
half4 col=UniversalFragmentPBR(inputData,s);
#ifndef CAT_EYE
// Sample visibility on the far surface so an ear does not shadow its own transmission.
float3 backWS=i.ws-normalize(i.n)*(tissue.g*_ThicknessMM*0.001+0.0003);
col.rgb+=Trans(GetMainLight(TransformWorldToShadowCoord(backWS),backWS,inputData.shadowMask),inputData,tissue);
col.rgb+=Scatter(GetMainLight(inputData.shadowCoord,i.ws,inputData.shadowMask),inputData,tissue,base);
#if defined(_ADDITIONAL_LIGHTS)
uint pixelLightCount=GetAdditionalLightsCount();
#if USE_CLUSTER_LIGHT_LOOP
[loop] for(uint lightIndex=0;lightIndex<min(URP_FP_DIRECTIONAL_LIGHTS_COUNT,MAX_VISIBLE_LIGHTS);lightIndex++) {
CLUSTER_LIGHT_LOOP_SUBTRACTIVE_LIGHT_CHECK
col.rgb+=Trans(GetAdditionalLight(lightIndex,backWS,inputData.shadowMask),inputData,tissue);
col.rgb+=Scatter(GetAdditionalLight(lightIndex,i.ws,inputData.shadowMask),inputData,tissue,base); }
#endif
LIGHT_LOOP_BEGIN(pixelLightCount)
col.rgb+=Trans(GetAdditionalLight(lightIndex,backWS,inputData.shadowMask),inputData,tissue);
col.rgb+=Scatter(GetAdditionalLight(lightIndex,i.ws,inputData.shadowMask),inputData,tissue,base);
LIGHT_LOOP_END
#endif
#endif
col.rgb=MixFog(col.rgb,i.fog);return col;
}
ENDHLSL
}
UsePass "Universal Render Pipeline/Lit/ShadowCaster"
UsePass "Universal Render Pipeline/Lit/DepthOnly"
UsePass "Universal Render Pipeline/Lit/DepthNormals"
}
Fallback Off
CustomEditor "RealisticCatDemo.Editor.CatShaderGUI"
}
