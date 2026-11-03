#ifndef CAT_HDRP_SURFACE_INCLUDED
#define CAT_HDRP_SURFACE_INCLUDED
#include "CatTissue.hlsl"
void CatSkinSurface_float(float2 UV, UnityTexture2D BaseMap, UnityTexture2D BumpMap,
 UnityTexture2D RoughnessMap, UnityTexture2D TissueMap, UnityTexture2D MicroMap,
 float3 PositionOS,float3 NormalOS,float3 TangentOS,float3 BitangentOS,
 float BumpScale, float RoughnessScale, float PoreSizeMM, float PoreNormalStrength, float PoreRoughnessStrength,
 float VesselStrength, out float3 Color, out float3 Normal, out float Gloss,
 out float Mask, out float Thickness)
{
 float4 t=SAMPLE_TEXTURE2D(TissueMap.tex,TissueMap.samplerstate,UV);
 Color=SAMPLE_TEXTURE2D(BaseMap.tex,BaseMap.samplerstate,UV).rgb;
 Normal=UnpackNormalScale(SAMPLE_TEXTURE2D(BumpMap.tex,BumpMap.samplerstate,UV),BumpScale);
 float3x3 objectMatrix=(float3x3)GetObjectToWorldMatrix();
 float3 objectScale=float3(length(mul(objectMatrix,float3(1,0,0))),length(mul(objectMatrix,float3(0,1,0))),length(mul(objectMatrix,float3(0,0,1))));
 float3 p=PositionOS*objectScale*(1000.0/max(PoreSizeMM,0.1));float3 slope;float rough;
 float2 microStep=MicroMap.texelSize.xy*1.5;
 float3 poreX=float3(SAMPLE_TEXTURE2D(MicroMap.tex,MicroMap.samplerstate,p.yz).r,SAMPLE_TEXTURE2D(MicroMap.tex,MicroMap.samplerstate,p.yz+float2(microStep.x,0)).r,SAMPLE_TEXTURE2D(MicroMap.tex,MicroMap.samplerstate,p.yz+float2(0,microStep.y)).r);
 float3 poreY=float3(SAMPLE_TEXTURE2D(MicroMap.tex,MicroMap.samplerstate,p.xz).r,SAMPLE_TEXTURE2D(MicroMap.tex,MicroMap.samplerstate,p.xz+float2(microStep.x,0)).r,SAMPLE_TEXTURE2D(MicroMap.tex,MicroMap.samplerstate,p.xz+float2(0,microStep.y)).r);
 float3 poreZ=float3(SAMPLE_TEXTURE2D(MicroMap.tex,MicroMap.samplerstate,p.xy).r,SAMPLE_TEXTURE2D(MicroMap.tex,MicroMap.samplerstate,p.xy+float2(microStep.x,0)).r,SAMPLE_TEXTURE2D(MicroMap.tex,MicroMap.samplerstate,p.xy+float2(0,microStep.y)).r);
 CatMicroData(NormalOS,poreX,poreY,poreZ,slope,rough);
 Normal=CatBlendSkinNormal(Normal,float2(dot(slope,normalize(TangentOS)),dot(slope,normalize(BitangentOS)))*PoreNormalStrength*t.r);
 Gloss=1-clamp(SAMPLE_TEXTURE2D(RoughnessMap.tex,RoughnessMap.samplerstate,UV).r*RoughnessScale+rough*.30*t.r*PoreRoughnessStrength,.18,.95);
 float3 shadingNormalOS=normalize(normalize(TangentOS)*Normal.x+normalize(BitangentOS)*Normal.y+normalize(NormalOS)*Normal.z);
 Gloss=CatSkinSpecularAA(Gloss,TransformObjectToWorldNormal(shadingNormalOS),.15);
 Color*=1-t.b*t.a*exp(-t.g*6)*float3(.025,.07,.055);
 Mask=t.r;
 // Native HDRP integrates this optical thickness per punctual/area/directional light.
 Thickness=lerp(1,saturate(t.g+t.b*VesselStrength*.15),t.a);
}
void CatEyeSurface_float(float2 UV0,UnityTexture2D BaseMap,float4 EyeRect,float Pupil,
 float IrisRadius,float CorneaSmoothness,float2 UV1,UnityTexture2D ScleraMap,
 float PupilShape,float PupilWidth,float PupilHeight,
 float IrisDepth,float ShadowStrength,float ShadowSoftness,float ShadowHeight,
 float3 PositionWS,float3 NormalWS,float3 ViewWS,
 float LowerShadowStrength,float LowerShadowHeight,float CornerShadowStrength,float CornerShadowWidth,
 float3 EyeForwardOS,float3 EyeUpOS,
 float4 ScleraColor,
 float IrisRotation,
 float IrisUVSet,float IrisUVOffsetX,float IrisUVOffsetY,
 float3 NormalOS,float3 TangentOS,float3 BitangentOS,float CorneaBulge,
 float4 IrisColor,
 UnityTexture2D IrisMap,
 float IrisHue,float IrisSaturation,
 out float3 Color,out float3 Normal,out float Gloss)
{
 float2 eyeUV0=(UV0-EyeRect.xy)/max(abs(EyeRect.zw),float2(1e-5,1e-5));
 float2 placementUV=lerp(eyeUV0,UV1,saturate(IrisUVSet));
 float2 eyeUV=placementUV-float2(IrisUVOffsetX,IrisUVOffsetY);

 float3 normalWS=normalize(NormalWS);
 float3 viewWS=normalize(ViewWS);
 float3 tangentWS=normalize(TransformObjectToWorldDir(TangentOS));
 float3 bitangentWS=normalize(TransformObjectToWorldDir(BitangentOS));

 float3 opticalNormalTS; float opticalCorneaMask;
 float2 opticalOffset=CatEyeOptics(eyeUV,PositionWS,normalWS,viewWS,tangentWS,bitangentWS,
     CorneaBulge,IrisDepth,IrisRadius,opticalNormalTS,opticalCorneaMask);
 float2 u;float pupil,limbus,irisMask;CatEyeUV(eyeUV+opticalOffset,Pupil,IrisRadius,PupilShape,PupilWidth,PupilHeight,IrisRotation,u,pupil,limbus,irisMask);
 float2 uv1Atlas=EyeRect.xy+u*EyeRect.zw;
 // The sclera texture is eye-local: normalize UV0's atlas region, while
 // UV1 remains the model-authored eye layout.
 float2 scleraUV=lerp(eyeUV0,UV1,saturate(IrisUVSet));
 float3 scleraColor=SAMPLE_TEXTURE2D(ScleraMap.tex,ScleraMap.samplerstate,scleraUV).rgb;
 float3 uv1Color=SAMPLE_TEXTURE2D(IrisMap.tex,IrisMap.samplerstate,u).rgb;
 float3 uv0Color=SAMPLE_TEXTURE2D(BaseMap.tex,BaseMap.samplerstate,UV0+CatEyeUVOffset(placementUV,UV0,u-placementUV)).rgb;
 float3 irisColor=lerp(uv0Color,uv1Color,saturate(IrisUVSet));
 irisColor*=IrisColor.rgb;
 irisColor=CatIrisHueSaturation(irisColor,IrisHue,IrisSaturation);
 scleraColor=CatScleraColor(scleraColor,eyeUV,IrisRadius)*ScleraColor.rgb;
 float3 c=lerp(scleraColor,irisColor,irisMask);
 Color=lerp(c*lerp(1,.55,limbus),float3(.002,.003,.004),pupil);
 float contactShadow = CatEyeContactShadow(placementUV, ShadowHeight, ShadowSoftness, ShadowStrength,
    LowerShadowHeight, LowerShadowStrength, CornerShadowWidth, CornerShadowStrength);
 Color *= (1.0 - contactShadow);
 float corneaMask=opticalCorneaMask;
 Normal=opticalNormalTS;
 Gloss=lerp(min(CorneaSmoothness,0.82),CorneaSmoothness,max(irisMask,corneaMask));
}
#endif
