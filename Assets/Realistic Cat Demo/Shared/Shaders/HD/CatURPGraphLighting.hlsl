#ifndef CAT_URP_GRAPH_LIGHTING_INCLUDED
#define CAT_URP_GRAPH_LIGHTING_INCLUDED
#include "CatTissue.hlsl"
#ifndef SHADERGRAPH_PREVIEW
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
float3 CatGraphContribution(Light front,Light back,float3 n,float3 v,float3 albedo,float4 t,
 float mm,float transmission,float vessels,float scatter)
{
#ifdef _LIGHT_LAYERS
 if(!IsMatchingLightLayer(front.layerMask,GetMeshRenderingLayer()))return 0;
#endif
 return CatScatter(n,front.direction,albedo,t.r,scatter)*front.color*front.distanceAttenuation*front.shadowAttenuation
 +CatTransmission(n,v,back.direction,t.g*mm,t.b*vessels,t.r*t.a,transmission,float3(1,.8,.7))*back.color*back.distanceAttenuation*back.shadowAttenuation;
}
#endif
void CatURPLighting_float(float3 PositionWS,float3 NormalWS,float3 TangentWS,float3 BitangentWS,
 float3 ViewWS,float3 NormalTS,float3 Albedo,float2 UV,UnityTexture2D TissueMap,
 float ThicknessMM,float Transmission,float VesselStrength,float Subsurface,out float3 Lighting)
{
 Lighting=0;
#if defined(SHADERPASS) && defined(SHADERPASS_META) && (SHADERPASS == SHADERPASS_META)
 return;
#endif
#ifndef SHADERGRAPH_PREVIEW
 float4 t=SAMPLE_TEXTURE2D(TissueMap.tex,TissueMap.samplerstate,UV);
 float3 n=normalize(TangentWS*NormalTS.x+BitangentWS*NormalTS.y+NormalWS*NormalTS.z);
 float3 back=PositionWS-normalize(NormalWS)*(t.g*ThicknessMM*.001+.0003);
 float4 screen=ComputeScreenPos(TransformWorldToHClip(PositionWS));
 InputData inputData=(InputData)0;inputData.positionWS=PositionWS;inputData.normalizedScreenSpaceUV=screen.xy/max(screen.w,1e-5);
 Lighting=CatGraphContribution(GetMainLight(TransformWorldToShadowCoord(PositionWS),PositionWS,half4(1,1,1,1)),GetMainLight(TransformWorldToShadowCoord(back),back,half4(1,1,1,1)),n,normalize(ViewWS),Albedo,t,ThicknessMM,Transmission,VesselStrength,Subsurface);
#if defined(_ADDITIONAL_LIGHTS)
 uint pixelLightCount=GetAdditionalLightsCount();
#if USE_CLUSTER_LIGHT_LOOP
 [loop] for(uint lightIndex=0;lightIndex<min(URP_FP_DIRECTIONAL_LIGHTS_COUNT,MAX_VISIBLE_LIGHTS);lightIndex++)
 {
  CLUSTER_LIGHT_LOOP_SUBTRACTIVE_LIGHT_CHECK
  Lighting+=CatGraphContribution(GetAdditionalLight(lightIndex,PositionWS,half4(1,1,1,1)),GetAdditionalLight(lightIndex,back,half4(1,1,1,1)),n,normalize(ViewWS),Albedo,t,ThicknessMM,Transmission,VesselStrength,Subsurface);
 }
#endif
 LIGHT_LOOP_BEGIN(pixelLightCount)
 Lighting+=CatGraphContribution(GetAdditionalLight(lightIndex,PositionWS,half4(1,1,1,1)),GetAdditionalLight(lightIndex,back,half4(1,1,1,1)),n,normalize(ViewWS),Albedo,t,ThicknessMM,Transmission,VesselStrength,Subsurface);
 LIGHT_LOOP_END
#endif
#endif
}
#endif
