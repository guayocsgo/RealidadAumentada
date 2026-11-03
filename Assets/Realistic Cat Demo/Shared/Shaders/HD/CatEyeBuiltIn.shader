Shader "Realistic Cat Demo/Built-in/Eye" {
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
SubShader { Tags { "RenderType"="Opaque" } LOD 350
CGPROGRAM
#pragma target 3.0
#pragma surface Surf Cat fullforwardshadows addshadow
#define CAT_EYE 1
#include "UnityPBSLighting.cginc"
#include "AutoLight.cginc"
#include "CatTissue.hlsl"
sampler2D _BaseMap,_IrisMap,_ScleraMap,_RoughnessMap,_TissueMap,_MicroMap;
float4 _MicroMap_TexelSize;
float4 _BaseColor, _TransmissionTint, _EyeRect, _IrisColor;
float _BumpScale, _RoughnessScale, _ThicknessMM, _Transmission, _VesselStrength, _Subsurface, _PoreSizeMM, _PoreNormalStrength, _PoreRoughnessStrength;
float4 _EyeForwardOS, _EyeUpOS, _ScleraColor;
float _LowerShadowStrength, _LowerShadowHeight, _CornerShadowStrength, _CornerShadowWidth;
float _IrisDepth, _ShadowStrength, _ShadowSoftness, _ShadowHeight;
float _Pupil, _PupilShape, _PupilWidth, _PupilHeight, _IrisRotation, _IrisUVSet, _IrisUVOffsetX, _IrisUVOffsetY, _IrisRadius, _CorneaSmoothness, _CorneaBulge, _IrisHue, _IrisSaturation;
struct Input { float2 uv_BaseMap; float2 uv2_BaseMap; float3 worldPos; float3 worldNormal; INTERNAL_DATA };
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

float2 uv0=i.uv_BaseMap;float2 uv1=i.uv2_BaseMap;
float pupil=0, limbus=0;
#ifdef CAT_EYE
float2 irisUV;float irisMask;
float2 eyeUV0=(uv0-_EyeRect.xy)/max(abs(_EyeRect.zw),float2(1e-5,1e-5));
float2 placementUV=lerp(eyeUV0,uv1,saturate(_IrisUVSet));
float2 eyeUV=placementUV-float2(_IrisUVOffsetX,_IrisUVOffsetY);

float3 normalWS=WorldNormalVector(i,float3(0,0,1));
float3 tangentWS=WorldNormalVector(i,float3(1,0,0));
float3 bitangentWS=WorldNormalVector(i,float3(0,1,0));
float3 viewWS=normalize(UnityWorldSpaceViewDir(i.worldPos));

float3 opticalNormalTS; float opticalCorneaMask;
float2 opticalOffset=CatEyeOptics(eyeUV,i.worldPos,normalWS,viewWS,tangentWS,bitangentWS,
    _CorneaBulge,_IrisDepth,_IrisRadius,opticalNormalTS,opticalCorneaMask);
CatEyeUV(eyeUV+opticalOffset, _Pupil, _IrisRadius, _PupilShape, _PupilWidth, _PupilHeight, _IrisRotation, irisUV, pupil, limbus, irisMask);
float2 uv1Atlas=_EyeRect.xy+irisUV*_EyeRect.zw;
// The sclera texture is an eye-local texture.  UV0 needs its atlas rectangle
// normalized first; UV1 is already authored as an eye-local layout.
float2 scleraUV=lerp(eyeUV0,uv1,saturate(_IrisUVSet));
half3 scleraColor=tex2D(_ScleraMap,scleraUV).rgb*_ScleraColor.rgb;
half3 uv1Color=tex2D(_IrisMap,irisUV).rgb;
half3 uv0Color=tex2D(_BaseMap,uv0+CatEyeUVOffset(placementUV,uv0,irisUV-placementUV)).rgb;
half3 irisColor=lerp(uv0Color,uv1Color,saturate(_IrisUVSet));
irisColor*=_IrisColor.rgb;
irisColor=CatIrisHueSaturation(irisColor,_IrisHue,_IrisSaturation);
half3 eyeColor=lerp(CatScleraColor(scleraColor,eyeUV,_IrisRadius),irisColor,irisMask);
float contactShadow = CatEyeContactShadow(placementUV, _ShadowHeight, _ShadowSoftness, _ShadowStrength,
    _LowerShadowHeight, _LowerShadowStrength, _CornerShadowWidth, _CornerShadowStrength);
#endif
half3 base = tex2D(_BaseMap,uv0).rgb * _BaseColor.rgb;
half4 tissue = tex2D(_TissueMap,uv0);
half rough = tex2D(_RoughnessMap,uv0).r;
half3 nts = half3(0,0,1);
#ifdef CAT_EYE
base=eyeColor*_BaseColor.rgb*(1.0 - contactShadow);rough=tex2D(_RoughnessMap,uv1Atlas).r;
#endif
half smoothness = 1-saturate(rough*_RoughnessScale);
#ifndef CAT_EYE
float3x3 objectMatrix=(float3x3)unity_ObjectToWorld;
float3 axisX=mul(objectMatrix,float3(1,0,0)),axisY=mul(objectMatrix,float3(0,1,0)),axisZ=mul(objectMatrix,float3(0,0,1));
float3 pOS=mul(unity_WorldToObject,float4(i.worldPos,1)).xyz*float3(length(axisX),length(axisY),length(axisZ))*(1000.0/max(_PoreSizeMM,0.1));
float3 nOS=normalize(mul((float3x3)transpose(unity_ObjectToWorld),WorldNormalVector(i,float3(0,0,1))));
float3 poreSlope;float poreRough;
float2 microStep=_MicroMap_TexelSize.xy*1.5;
float3 poreX=float3(tex2D(_MicroMap,pOS.yz).r,tex2D(_MicroMap,pOS.yz+microStep).r,tex2D(_MicroMap,pOS.yz+microStep.yx).r);
float3 poreY=float3(tex2D(_MicroMap,pOS.xz).r,tex2D(_MicroMap,pOS.xz+microStep).r,tex2D(_MicroMap,pOS.xz+microStep.yx).r);
float3 poreZ=float3(tex2D(_MicroMap,pOS.xy).r,tex2D(_MicroMap,pOS.xy+microStep).r,tex2D(_MicroMap,pOS.xy+microStep.yx).r);
CatMicroData(nOS,poreX,poreY,poreZ,poreSlope,poreRough);
float3 slopeWS=normalize(axisX)*poreSlope.x+normalize(axisY)*poreSlope.y+normalize(axisZ)*poreSlope.z;
nts.xy+=float2(dot(slopeWS,WorldNormalVector(i,float3(1,0,0))),dot(slopeWS,WorldNormalVector(i,float3(0,1,0))))*tissue.r*_PoreNormalStrength;
nts=normalize(nts);
smoothness=1-clamp(rough*_RoughnessScale+poreRough*.30*tissue.r*_PoreRoughnessStrength,.18,.95);
base*=1-tissue.b*tissue.a*exp(-tissue.g*6)*float3(.025,.07,.055);
#endif
#ifdef CAT_EYE
base=lerp(base*lerp(1,0.55,limbus),float3(0.002,0.003,0.004),pupil);
float corneaMask=opticalCorneaMask;
nts=opticalNormalTS;
smoothness=lerp(lerp(0.78, 0.50, irisMask), _CorneaSmoothness, corneaMask);
tissue=0;
#endif

o.Albedo=base;o.Normal=nts;o.Specular=lerp(0.025, 0.045, corneaMask);o.Smoothness=smoothness;o.Occlusion=1.0 - contactShadow*0.7;o.Alpha=1;o.Tissue=tissue;
o.WorldPosition=i.worldPos;o.WorldGeomNormal=WorldNormalVector(i,float3(0,0,1));
}
ENDCG
} Fallback "Diffuse" CustomEditor "RealisticCatDemo.Editor.CatShaderGUI" }
