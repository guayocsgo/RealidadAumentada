Shader "Realistic Cat Demo/URP/Skin" {
Properties { 
 _BaseMap("Albedo", 2D) = "white" {}
 _BaseColor("Tint", Color) = (1,1,1,1)
 _BumpMap("Normal", 2D) = "bump" {}
 _BumpScale("Normal Strength", Range(0,2)) = 0.7
 _RoughnessMap("Roughness (linear R)", 2D) = "white" {}
 _RoughnessScale("Skin roughness", Range(0.5,1.8)) = 1.15
 _MicroMap("Pore height (grayscale)", 2D) = "gray" {}
 _PoreSizeMM("Pore size (mm)", Range(4,100)) = 18
 _PoreNormalStrength("Pore normal strength", Range(0,2)) = 0.75
 _PoreRoughnessStrength("Pore roughness strength", Range(0,1)) = 0.55
 _TissueMap("R Skin G Thickness B Vessels A Transmission", 2D) = "white" {}
 _ThicknessMM("Maximum thickness (mm)", Range(0.1,30)) = 12
 _Transmission("Transmission", Range(0,5)) = 1.6
 _Subsurface("Local Diffusion", Range(0,1)) = 0.35
 _VesselStrength("Vessel Absorption", Range(0,3)) = 1 }
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

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "CatTissue.hlsl"
TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
TEXTURE2D(_RoughnessMap); SAMPLER(sampler_RoughnessMap);
TEXTURE2D(_TissueMap); SAMPLER(sampler_TissueMap);
TEXTURE2D(_MicroMap); SAMPLER(sampler_MicroMap);
CBUFFER_START(UnityPerMaterial)
float4 _MicroMap_TexelSize;
float4 _BaseColor, _BaseMap_ST, _TransmissionTint, _EyeRect;
float _BumpScale, _RoughnessScale, _ThicknessMM, _Transmission, _VesselStrength, _Subsurface, _PoreSizeMM, _PoreNormalStrength, _PoreRoughnessStrength;
float _Pupil, _IrisRadius, _CorneaSmoothness;
CBUFFER_END
struct A { float4 pos:POSITION; float3 n:NORMAL; float4 t:TANGENT; float2 uv:TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
struct V { float4 pos:SV_POSITION; float3 ws:TEXCOORD0; half3 n:TEXCOORD1; half4 t:TEXCOORD2; float2 uv:TEXCOORD3; half fog:TEXCOORD4; UNITY_VERTEX_INPUT_INSTANCE_ID UNITY_VERTEX_OUTPUT_STEREO };
V Vert(A i) { V o=(V)0; UNITY_SETUP_INSTANCE_ID(i); UNITY_TRANSFER_INSTANCE_ID(i,o); UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
VertexPositionInputs p=GetVertexPositionInputs(i.pos.xyz); VertexNormalInputs n=GetVertexNormalInputs(i.n,i.t);
o.pos=p.positionCS;o.ws=p.positionWS;o.n=n.normalWS;o.t=half4(n.tangentWS,i.t.w*GetOddNegativeScale());o.uv=TRANSFORM_TEX(i.uv,_BaseMap);o.fog=ComputeFogFactor(o.pos.z);return o; }
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

float2 uv=i.uv;
float pupil=0, limbus=0;
#ifdef CAT_EYE
float2 irisUV;
float irisMask;CatEyeUV(uv, _Pupil, _IrisRadius, 0, 1, 1, irisUV, pupil, limbus, irisMask);
uv = _EyeRect.xy + irisUV * _EyeRect.zw;
#endif
half3 base = SAMPLE_TEXTURE2D(_BaseMap,sampler_BaseMap,uv).rgb * _BaseColor.rgb;
half4 tissue = SAMPLE_TEXTURE2D(_TissueMap,sampler_TissueMap,i.uv);
half rough = SAMPLE_TEXTURE2D(_RoughnessMap,sampler_RoughnessMap,uv).r;
half3 nts = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap,sampler_BumpMap,uv),_BumpScale);
half smoothness = 1-saturate(rough*_RoughnessScale);
#ifndef CAT_EYE
float3x3 objectMatrix=(float3x3)GetObjectToWorldMatrix();
float3 axisX=mul(objectMatrix,float3(1,0,0)),axisY=mul(objectMatrix,float3(0,1,0)),axisZ=mul(objectMatrix,float3(0,0,1));
float3 pOS=TransformWorldToObject(i.ws)*float3(length(axisX),length(axisY),length(axisZ))*(1000.0/max(_PoreSizeMM,0.1));
float3 nOS=normalize(mul((float3x3)transpose(GetObjectToWorldMatrix()),i.n));
float3 poreSlope;float poreRough;
float2 microStep=_MicroMap_TexelSize.xy*1.5;
float3 poreX=float3(SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.yz).r,SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.yz+float2(microStep.x,0)).r,SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.yz+float2(0,microStep.y)).r);
float3 poreY=float3(SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.xz).r,SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.xz+float2(microStep.x,0)).r,SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.xz+float2(0,microStep.y)).r);
float3 poreZ=float3(SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.xy).r,SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.xy+float2(microStep.x,0)).r,SAMPLE_TEXTURE2D(_MicroMap,sampler_MicroMap,pOS.xy+float2(0,microStep.y)).r);
CatMicroData(nOS,poreX,poreY,poreZ,poreSlope,poreRough);
float3 slopeWS=normalize(axisX)*poreSlope.x+normalize(axisY)*poreSlope.y+normalize(axisZ)*poreSlope.z;
nts=CatBlendSkinNormal(nts,float2(dot(slopeWS,normalize(i.t.xyz)),dot(slopeWS,normalize(cross(i.n,i.t.xyz)*i.t.w)))*tissue.r*_PoreNormalStrength);
nts=normalize(nts);
smoothness=1-clamp(rough*_RoughnessScale+poreRough*.30*tissue.r*_PoreRoughnessStrength,.18,.95);
base*=1-tissue.b*tissue.a*exp(-tissue.g*6)*float3(.025,.07,.055);
#endif
#ifdef CAT_EYE
base=lerp(base*lerp(1,0.32,limbus),float3(0.002,0.003,0.004),pupil);
nts=half3(0,0,1); smoothness=_CorneaSmoothness; tissue=0;
#endif

InputData inputData=(InputData)0; inputData.positionWS=i.ws;
inputData.normalWS=NormalizeNormalPerPixel(mul(nts,half3x3(normalize(i.t.xyz),normalize(cross(i.n,i.t.xyz)*i.t.w),normalize(i.n))));
smoothness=CatSkinSpecularAA(smoothness,inputData.normalWS,.15);
inputData.viewDirectionWS=GetWorldSpaceNormalizeViewDir(i.ws);
inputData.shadowCoord=TransformWorldToShadowCoord(i.ws);
inputData.bakedGI=SampleSH(inputData.normalWS); inputData.shadowMask=half4(1,1,1,1);
inputData.normalizedScreenSpaceUV=GetNormalizedScreenSpaceUV(i.pos);
inputData.vertexLighting=VertexLighting(i.ws,inputData.normalWS);
SurfaceData s=(SurfaceData)0;s.albedo=base;s.specular=0.028;s.smoothness=smoothness;s.normalTS=nts;s.occlusion=1;s.alpha=1;
#ifdef CAT_EYE
s.specular=0.025;s.clearCoatMask=1;s.clearCoatSmoothness=_CorneaSmoothness;
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
