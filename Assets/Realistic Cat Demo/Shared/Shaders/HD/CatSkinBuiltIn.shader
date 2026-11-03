Shader "Realistic Cat Demo/Built-in/Skin" {
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
SubShader { Tags { "RenderType"="Opaque" } LOD 350
CGPROGRAM
#pragma target 3.0
#pragma surface Surf Cat fullforwardshadows addshadow

#include "UnityPBSLighting.cginc"
#include "AutoLight.cginc"
#include "CatTissue.hlsl"
sampler2D _BaseMap,_BumpMap,_RoughnessMap,_TissueMap,_MicroMap;
float4 _MicroMap_TexelSize;
float4 _BaseColor, _TransmissionTint, _EyeRect;
float _BumpScale, _RoughnessScale, _ThicknessMM, _Transmission, _VesselStrength, _Subsurface, _PoreSizeMM, _PoreNormalStrength, _PoreRoughnessStrength;
float _Pupil, _IrisRadius, _CorneaSmoothness;
struct Input { float2 uv_BaseMap; float3 worldPos; float3 worldNormal; INTERNAL_DATA };
struct SurfaceOutputCat { fixed3 Albedo; fixed3 Normal; half3 Emission; half3 Specular; half Smoothness; half Occlusion; fixed Alpha; half4 Tissue; float3 WorldPosition; float3 WorldGeomNormal; };
inline SurfaceOutputStandardSpecular StandardSurface(SurfaceOutputCat s) {
SurfaceOutputStandardSpecular p; p.Albedo=s.Albedo;p.Normal=s.Normal;p.Emission=s.Emission;p.Specular=s.Specular;p.Smoothness=s.Smoothness;p.Occlusion=s.Occlusion;p.Alpha=s.Alpha;return p; }
inline half4 LightingCat(SurfaceOutputCat s,half3 viewDir,UnityGI gi) {
SurfaceOutputStandardSpecular p=StandardSurface(s);
half4 c=LightingStandardSpecular(p,viewDir,gi);
#ifndef CAT_EYE
float3 safeGeomNormal=s.WorldGeomNormal*rsqrt(max(dot(s.WorldGeomNormal,s.WorldGeomNormal),1e-8));
float3 backWS=s.WorldPosition-safeGeomNormal*(s.Tissue.g*_ThicknessMM*0.001+0.0003);
float visibility=UnityComputeForwardShadows(0,backWS,ComputeScreenPos(mul(UNITY_MATRIX_VP,float4(backWS,1))));
float distanceAttenuation=1;
#if defined(POINT)
float3 lc=mul(unity_WorldToLight,float4(backWS,1)).xyz;
distanceAttenuation=tex2D(_LightTexture0,dot(lc,lc).rr).r;
#elif defined(SPOT)
float4 lc=mul(unity_WorldToLight,float4(backWS,1));
distanceAttenuation=(lc.z>0)*UnitySpotCookie(lc)*UnitySpotAttenuate(lc.xyz);
#elif defined(POINT_COOKIE)
float3 lc=mul(unity_WorldToLight,float4(backWS,1)).xyz;
distanceAttenuation=tex2D(_LightTextureB0,dot(lc,lc).rr).r*texCUBE(_LightTexture0,lc).w;
#elif defined(DIRECTIONAL_COOKIE)
distanceAttenuation=tex2D(_LightTexture0,mul(unity_WorldToLight,float4(backWS,1)).xy).w;
#endif
c.rgb+=CatTransmission(s.Normal,viewDir,gi.light.dir,s.Tissue.g*_ThicknessMM,s.Tissue.b*_VesselStrength,s.Tissue.r*s.Tissue.a,_Transmission,float3(1,.8,.7))*_LightColor0.rgb*distanceAttenuation*visibility;
c.rgb+=CatScatter(s.Normal,gi.light.dir,s.Albedo,s.Tissue.r,_Subsurface)*gi.light.color;
#endif
return c; }
inline void LightingCat_GI(SurfaceOutputCat s,UnityGIInput data,inout UnityGI gi) { SurfaceOutputStandardSpecular p=StandardSurface(s); LightingStandardSpecular_GI(p,data,gi); }
void Surf(Input i,inout SurfaceOutputCat o) {

float2 uv=i.uv_BaseMap;
float pupil=0, limbus=0;
#ifdef CAT_EYE
float2 irisUV;
float irisMask;CatEyeUV(uv, _Pupil, _IrisRadius, 0, 1, 1, irisUV, pupil, limbus, irisMask);
uv = _EyeRect.xy + irisUV * _EyeRect.zw;
#endif
half3 base = tex2D(_BaseMap,uv).rgb * _BaseColor.rgb;
half4 tissue = tex2D(_TissueMap,i.uv_BaseMap);
half rough = tex2D(_RoughnessMap,uv).r;
half3 nts = UnpackScaleNormal(tex2D(_BumpMap,uv),_BumpScale);
half smoothness = 1-saturate(rough*_RoughnessScale);
#ifndef CAT_EYE
float3x3 objectMatrix=(float3x3)unity_ObjectToWorld;
float3 axisX=mul(objectMatrix,float3(1,0,0)),axisY=mul(objectMatrix,float3(0,1,0)),axisZ=mul(objectMatrix,float3(0,0,1));
float3 pOS=mul(unity_WorldToObject,float4(i.worldPos,1)).xyz*float3(length(axisX),length(axisY),length(axisZ))*(1000.0/max(_PoreSizeMM,0.1));
float3 nOS=normalize(mul((float3x3)transpose(unity_ObjectToWorld),WorldNormalVector(i,float3(0,0,1))));
float3 poreSlope;float poreRough;
float2 microStep=_MicroMap_TexelSize.xy*1.5;
float3 poreX=float3(tex2D(_MicroMap,pOS.yz).r,tex2D(_MicroMap,pOS.yz+float2(microStep.x,0)).r,tex2D(_MicroMap,pOS.yz+float2(0,microStep.y)).r);
float3 poreY=float3(tex2D(_MicroMap,pOS.xz).r,tex2D(_MicroMap,pOS.xz+float2(microStep.x,0)).r,tex2D(_MicroMap,pOS.xz+float2(0,microStep.y)).r);
float3 poreZ=float3(tex2D(_MicroMap,pOS.xy).r,tex2D(_MicroMap,pOS.xy+float2(microStep.x,0)).r,tex2D(_MicroMap,pOS.xy+float2(0,microStep.y)).r);
CatMicroData(nOS,poreX,poreY,poreZ,poreSlope,poreRough);
float3 slopeWS=normalize(axisX)*poreSlope.x+normalize(axisY)*poreSlope.y+normalize(axisZ)*poreSlope.z;
nts=CatBlendSkinNormal(nts,float2(dot(slopeWS,WorldNormalVector(i,float3(1,0,0))),dot(slopeWS,WorldNormalVector(i,float3(0,1,0))))*tissue.r*_PoreNormalStrength);
nts=normalize(nts);
smoothness=1-clamp(rough*_RoughnessScale+poreRough*.30*tissue.r*_PoreRoughnessStrength,.18,.95);
base*=1-tissue.b*tissue.a*exp(-tissue.g*6)*float3(.025,.07,.055);
#endif
#ifdef CAT_EYE
base=lerp(base*lerp(1,0.32,limbus),float3(0.002,0.003,0.004),pupil);
nts=half3(0,0,1); smoothness=_CorneaSmoothness; tissue=0;
#endif

smoothness=CatSkinSpecularAA(smoothness,normalize(WorldNormalVector(i,nts)),.15);
o.Albedo=base;o.Normal=nts;o.Specular=0.028;o.Smoothness=smoothness;o.Occlusion=1;o.Alpha=1;o.Tissue=tissue;
o.WorldPosition=i.worldPos;o.WorldGeomNormal=WorldNormalVector(i,float3(0,0,1));
}
ENDCG
} Fallback "Diffuse" CustomEditor "RealisticCatDemo.Editor.CatShaderGUI" }
