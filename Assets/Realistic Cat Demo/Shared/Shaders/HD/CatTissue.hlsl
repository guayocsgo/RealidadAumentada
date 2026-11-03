#ifndef CAT_TISSUE_INCLUDED
#define CAT_TISSUE_INCLUDED
// Triplanar pore height samples. Each sample is center,+U,+V from the same
// grayscale height map, allowing independent normal and roughness strength.
void CatMicroData(float3 nOS,float3 xSample,float3 ySample,float3 zSample,
 out float3 slopeOS,out float roughVariation)
{
    float3 w=pow(abs(nOS),4);w/=max(dot(w,1),1e-5);
    float3 sx=float3(0,xSample.y-xSample.x,xSample.z-xSample.x);
    float3 sy=float3(ySample.y-ySample.x,0,ySample.z-ySample.x);
    float3 sz=float3(zSample.y-zSample.x,zSample.z-zSample.x,0);
    // Height decreases inside a pore, so the tangent-space gradient is
    // negated to make the pore read as a depression rather than a bump.
    slopeOS=-(sx*w.x+sy*w.y+sz*w.z)*2.2;
    roughVariation=dot(float3(xSample.x,ySample.x,zSample.x)-.5,w)*2;
}
// Reoriented detail normals preserve the base wrinkles instead of flattening
// their Z component when a pore perturbation is added.
float3 CatBlendSkinNormal(float3 baseNormal,float2 detailSlope)
{
    float3 t=normalize(baseNormal)+float3(0,0,1);
    float3 u=normalize(float3(-detailSlope,1));
    return normalize(t*dot(t,u)/max(t.z,1e-4)-u);
}

// Filter unresolved normal variation into roughness, rather than allowing
// tiny specular highlights to sparkle. Input/output are perceptual smoothness.
float CatSkinSpecularAA(float smoothness,float3 normalWS,float strength)
{
    float3 dx=ddx(normalWS),dy=ddy(normalWS);
    float variance=min(.1,max(strength,0)*.5*(dot(dx,dx)+dot(dy,dy)));
    float roughness=1-saturate(smoothness);
    float filtered=sqrt(sqrt(saturate(pow(roughness,4)+variance)));
    return 1-filtered;
}

// Normalized wrapped diffuse redistributes energy near the terminator. This is
// a local diffusion approximation, not HDRP's spatial subsurface filter.
float3 CatScatter(float3 N,float3 L,float3 albedo,float mask,float strength)
{
    float nl=dot(N,L);
    float3 width=float3(.45,.22,.12);
    float3 wrapped=saturate((nl+width)/(1+width))/(1+width);
    return albedo*(1.0/3.14159265)*(wrapped-saturate(nl))*mask*strength;
}
// Thickness is optical path length in millimetres. Vessels absorb green/blue
// more strongly than red; they are revealed by illumination, never emission.
float3 CatTransmission(float3 N, float3 V, float3 L, float mm, float vessel,
    float mask, float strength, float3 tint)
{
    float back = saturate(dot(-N, L));
    float forwardLobe = pow(saturate(dot(-L, V)), 3.0);
    float3 extinction = float3(0.42, 1.15, 1.85);
    float3 absorb = exp(-max(mm, 0.05) * extinction);
    absorb *= exp(-vessel * float3(0.7, 2.8, 3.8));
    return mask * strength * tint * absorb * back * (0.45 + 0.55 * forwardLobe);
}
// UV in an iris disk, centre .5,.5. Pupil shape is a procedural blend from
// vertical slit to round, with independent width and height multipliers.
// Sampling the original radial iris outside its painted pupil preserves detail.
void CatEyeUV(float2 uv, float dilation, float irisRadius, float pupilShape,
    float pupilWidth, float pupilHeight, float rotationDegrees, out float2 sampleUV,
    out float pupil, out float limbus, out float irisMask)
{
    float angle = radians(rotationDegrees);
    float sine, cosine;
    sincos(angle, sine, cosine);
    float2 centered = (uv - 0.5) / max(irisRadius, 0.01);
    // Inverse UV rotation makes positive values rotate the visible iris and
    // procedural pupil counter-clockwise around the eye centre.
    float2 p = float2(cosine * centered.x + sine * centered.y,
        -sine * centered.x + cosine * centered.y);
    float r = length(p);
    float b = lerp(0.46, 0.88, dilation) * max(pupilHeight, 0.01);
    float slitWidth = lerp(0.045, 0.85, dilation) * max(pupilWidth, 0.01);
    float a = lerp(slitWidth, lerp(0.46, 0.88, dilation) * max(pupilWidth, 0.01), saturate(pupilShape));
    float2 axes = clamp(float2(a, b), 0.02, 0.98);
    float e = length(p / axes);
    float aa = max(fwidth(e), 0.006);
    pupil = 1 - smoothstep(1-aa, 1+aa, e);
    float2 dir = p / max(r, 0.00001);
    float border = rsqrt(dot(dir / axes, dir / axes) + 1e-6);
 float irisT = saturate((r-border)/max(1-border, 0.02));
 float sourceR = lerp(0.53, 1.0, irisT);
 sampleUV = 0.5 + dir * sourceR * irisRadius;
 // irisT remaps detail from the pupil to the iris edge; it is not an iris
 // coverage mask. Keep the sclera on the original projected eye outside the
 // requested iris radius.
 float irisEdgeAA = max(fwidth(r), 0.025);
 irisMask = 1.0 - smoothstep(1.0 - irisEdgeAA, 1.0 + irisEdgeAA, r);
 limbus = smoothstep(0.90, 0.99, r) * irisMask;
}
// Compatibility overload for the skin shaders' legacy embedded-eye path.
void CatEyeUV(float2 uv, float dilation, float irisRadius, float pupilShape,
    float pupilWidth, float pupilHeight, out float2 sampleUV,
    out float pupil, out float limbus, out float irisMask)
{
    CatEyeUV(uv, dilation, irisRadius, pupilShape, pupilWidth, pupilHeight, 0,
        sampleUV, pupil, limbus, irisMask);
}
// UV1 controls the tissue transition independently of the iris albedo UVs.
float3 CatScleraColor(float3 color, float2 uv, float irisRadius)
{
    float radius = length(uv - 0.5) / max(irisRadius, 0.01);
    float periphery = smoothstep(1.05, 1.85, radius);
    return color * lerp(float3(0.88, 0.85, 0.79), float3(0.79, 0.66, 0.61), periphery);
}

float3 CatRgbToHsv(float3 color)
{
    float4 K=float4(0.,-1./3.,2./3.,-1.);
    float4 p=lerp(float4(color.bg,K.wz),float4(color.gb,K.xy),step(color.b,color.g));
    float4 q=lerp(float4(p.xyw,color.r),float4(color.r,p.yzx),step(p.x,color.r));
    float d=q.x-min(q.w,q.y),epsilon=1e-10;
    return float3(abs(q.z+(q.w-q.y)/(6.*d+epsilon)),d/(q.x+epsilon),q.x);
}
float3 CatHsvToRgb(float3 hsv)
{
    float3 p=abs(frac(hsv.xxx+float3(0.,2./3.,1./3.))*6.-3.);
    return hsv.z*lerp(float3(1.,1.,1.),saturate(p-1.),hsv.y);
}
float3 CatIrisHueSaturation(float3 color,float hueDegrees,float saturation)
{
    float3 hsv=CatRgbToHsv(max(color,0));
    hsv.x=frac(hsv.x+hueDegrees/360.);
    float3 shifted=CatHsvToRgb(hsv);
    float luminance=dot(shifted,float3(.2126,.7152,.0722));
    return max(0,float3(luminance,luminance,luminance)+(shifted-luminance)*max(saturation,0));
}
// Reproject a physical iris-plane shift into the selected UV chart. Unlike a
// raw UV offset, this remains correctly oriented when UV0 and UV1 have
// different rotation, scale, or mirroring on the eye mesh.
float2 CatEyeParallaxUV(float2 uv, float3 positionOS, float3 viewOS,
    float3 forwardOS, float3 upOS, float depth)
{
    float3 f=dot(forwardOS,forwardOS)>1e-6?normalize(forwardOS):float3(0,0,1);
    float3 right=cross(upOS,f);
    if(dot(right,right)<1e-6) right=cross(abs(f.y)<.9?float3(0,1,0):float3(1,0,0),f);
    right=normalize(right);float3 up=cross(f,right);
    float3 v=viewOS*rsqrt(max(dot(viewOS,viewOS),1e-12));
    float facing=dot(v,f);
    float2 planeDx=float2(dot(ddx(positionOS),right),dot(ddx(positionOS),up));
    float2 planeDy=float2(dot(ddy(positionOS),right),dot(ddy(positionOS),up));
    float planeDet=planeDx.x*planeDy.y-planeDy.x*planeDx.y;
    if(abs(planeDet)<1e-8) return 0;

    float2 uvDx=ddx(uv),uvDy=ddy(uv);
    float2 uvPerRight=(uvDx*planeDy.y-uvDy*planeDx.y)/planeDet;
    float2 uvPerUp=(uvDy*planeDx.x-uvDx*planeDy.x)/planeDet;
    float uvDet=uvPerRight.x*uvPerUp.y-uvPerUp.x*uvPerRight.y;
    if(abs(uvDet)<1e-8) return 0;

    // One UV unit expressed in object-space iris-plane units, used to keep
    // the existing depth slider meaningful across either UV chart.
    float2 osPerUvX=float2(uvPerUp.y,-uvPerRight.y)/uvDet;
    float2 osPerUvY=float2(-uvPerUp.x,uvPerRight.x)/uvDet;
    float uvSpanOS=max(.5*(length(osPerUvX)+length(osPerUvY)),1e-5);
    float2 shiftOS=-float2(dot(v,right),dot(v,up))*max(depth,0)*uvSpanOS/max(facing,.35);
    float cap=.06*uvSpanOS;
    shiftOS*=rsqrt(1+dot(shiftOS,shiftOS)/(cap*cap));
    return (uvPerRight*shiftOS.x+uvPerUp*shiftOS.y)*smoothstep(0,.2,facing);
}

// A smooth analytic corneal cap, not a sampled normal map. The cap is built
// in eye-local space and reoriented through the active UV chart, so a rotated
// or mirrored UV1 does not make the highlight lean in the wrong direction.
void CatEyeCorneaNormalOS(float2 uv, float3 positionOS, float irisRadius,
    float strength, float3 forwardOS, float3 upOS,
    out float3 corneaNormalOS, out float corneaMask)
{
    float3 f=dot(forwardOS,forwardOS)>1e-6?normalize(forwardOS):float3(0,0,1);
    float3 right=cross(upOS,f);
    if(dot(right,right)<1e-6) right=cross(abs(f.y)<.9?float3(0,1,0):float3(1,0,0),f);
    right=normalize(right);float3 up=cross(f,right);
    corneaNormalOS=f;corneaMask=0;

    float2 planeDx=float2(dot(ddx(positionOS),right),dot(ddx(positionOS),up));
    float2 planeDy=float2(dot(ddy(positionOS),right),dot(ddy(positionOS),up));
    float planeDet=planeDx.x*planeDy.y-planeDy.x*planeDx.y;
    if(abs(planeDet)<1e-8) return;
    float2 uvDx=ddx(uv),uvDy=ddy(uv);
    float2 uvPerRight=(uvDx*planeDy.y-uvDy*planeDx.y)/planeDet;
    float2 uvPerUp=(uvDy*planeDx.x-uvDx*planeDy.x)/planeDet;
    float uvDet=uvPerRight.x*uvPerUp.y-uvPerUp.x*uvPerRight.y;
    if(abs(uvDet)<1e-8) return;

    float2 osPerUvX=float2(uvPerUp.y,-uvPerRight.y)/uvDet;
    float2 osPerUvY=float2(-uvPerUp.x,uvPerRight.x)/uvDet;
    float3 uvX=right*osPerUvX.x+up*osPerUvX.y;
    float3 uvY=right*osPerUvY.x+up*osPerUvY.y;
    float uvXLength=max(length(uvX),1e-5),uvYLength=max(length(uvY),1e-5);
    uvX/=uvXLength;uvY/=uvYLength;

    // The cornea extends a little beyond the limbus, with a soft transition
    // to the mesh's real normal rather than a hard circular normal-map edge.
    float lensRadius=min(max(irisRadius*1.28,0.05),0.5);
    float2 disk=(uv-float2(.5,.5))/lensRadius;
    float radius=length(disk);
    corneaMask=(1-smoothstep(.72,1.04,radius))*saturate(strength*5.0);
    corneaNormalOS=normalize(f+(disk.x*uvX+disk.y*uvY)*strength*.90);
}

// Geometry profile for the cornea.
float CatEyeCorneaVertexProfile(float2 uv,float irisRadius)
{
    float lensRadius=min(max(irisRadius*1.6,0.42),0.62);
    float radius=length((uv-float2(.5,.5))/lensRadius);
    float profile=1-smoothstep(.18,1.0,radius);
    return profile*profile*profile;
}

// Contact and eyelid shadow calculation on eye-local UV (placementUV).
// Darkens upper eyelid, lower eyelid, and corner seams to ground the eyeball in the socket.
float CatEyeContactShadow(float2 eyeUV, float shadowHeight, float shadowSoftness, float shadowStrength,
    float lowerShadowHeight, float lowerShadowStrength,
    float cornerShadowWidth, float cornerShadowStrength)
{
    float upper = smoothstep(shadowHeight - shadowSoftness, shadowHeight + shadowSoftness, eyeUV.y) * shadowStrength;
    float lowerSoftness = max(shadowSoftness * 0.75, 0.04);
    float lower = (1.0 - smoothstep(lowerShadowHeight - lowerSoftness, lowerShadowHeight + lowerSoftness, eyeUV.y)) * lowerShadowStrength;
    float cornerDist = abs(eyeUV.x - 0.5);
    float corner = smoothstep(0.5 - cornerShadowWidth, 0.5, cornerDist) * cornerShadowStrength;
    // Independent soft contacts overlap without crushing their junctions to solid black.
    return 1.0 - (1.0-saturate(upper))*(1.0-saturate(lower))*(1.0-saturate(corner));
}

// Resolve the active eye UV chart from screen derivatives. Mesh tangents belong
// to UV0, while the projected iris is usually UV1 (possibly rotated/mirrored).
// A physical refracted ray through the convex cap meets a recessed iris plane.
// The limbus and eyelid stay fixed; only the tissue below the cornea parallaxes.
float2 CatEyeOptics(float2 eyeUV, float3 positionWS, float3 normalWS, float3 viewWS,
    float3 tangentWS, float3 bitangentWS, float bulge, float depth, float radius,
    out float3 corneaNormalTS, out float corneaMask)
{
    float3 n=normalize(normalWS), t=normalize(tangentWS), b=normalize(bitangentWS);
    float2 dx=ddx(eyeUV), dy=ddy(eyeUV);
    float3 px=ddx(positionWS), py=ddy(positionWS);
    float det=dx.x*dy.y-dx.y*dy.x;
    float safeDet=abs(det)>1e-10?det:(det<0?-1e-10:1e-10);
    float3 chartT=(px*dy.y-py*dx.y)/safeDet;
    float3 chartB=(py*dx.x-px*dy.x)/safeDet;
    chartT-=n*dot(chartT,n); chartB-=n*dot(chartB,n);
    float lenT=length(chartT), lenB=length(chartB);
    bool valid=abs(det)>1e-10 && lenT>1e-7 && lenB>1e-7;
    chartT=valid?chartT/max(lenT,1e-7):t;
    chartB=valid?chartB/max(lenB,1e-7):b;
    float lensRadius=clamp(radius*1.28,0.08,0.6);
    float2 disk=(eyeUV-.5)/lensRadius;
    corneaMask=1-smoothstep(.72,1.05,length(disk));
    float3 cap=normalize(n+(chartT*disk.x+chartB*disk.y)*saturate(bulge)*.65);
    float3 coatNormal=normalize(lerp(n,cap,corneaMask));
    corneaNormalTS=normalize(float3(dot(coatNormal,t),dot(coatNormal,b),dot(coatNormal,n)));
    float3 ray=refract(-normalize(viewWS),coatNormal,1.0/1.336);
    float span=max(.5*(lenT+lenB),1e-7);
    float2 shift=float2(dot(ray,chartT)*span/max(lenT,1e-7),dot(ray,chartB)*span/max(lenB,1e-7));
    shift*=max(depth,0)/max(-dot(ray,n),.35);
    shift*=rsqrt(1+dot(shift,shift)/(.06*.06));
    float inset=1-smoothstep(.75,1.02,length(eyeUV-.5)/max(radius,.01));
    return valid?shift*inset*smoothstep(0,.2,dot(n,viewWS)):0;
}

// Outward-curving surface normal of the convex cornea dome in Tangent Space.
// Curves specular catchlight & clearcoat over the cornea without displacing geometry.
float3 CatEyeCorneaNormalTS(float2 eyeUV, float corneaBulge, float irisRadius, out float corneaMask)
{
    float lensRadius = min(max(irisRadius * 1.35, 0.1), 0.6);
    float2 disk = (eyeUV - float2(0.5, 0.5)) / lensRadius;
    float r = length(disk);

    // Smooth transition from cornea dome to sclera
    corneaMask = 1.0 - smoothstep(0.70, 1.05, r);

    // Parabolic dome slope tilting outward from center
    float2 domeSlope = disk * (saturate(corneaBulge) * 0.85);
    float3 domeNormalTS = normalize(float3(domeSlope.x, domeSlope.y, 1.0));
    return lerp(float3(0, 0, 1), domeNormalTS, corneaMask * saturate(corneaBulge * 4.0));
}

// Map the complete pupil/detail warp to UV0, preserving its atlas placement.
float2 CatEyeUVOffset(float2 fromUV, float2 toUV, float2 offset)
{
    float2 dx=ddx(fromUV),dy=ddy(fromUV);
    float det=dx.x*dy.y-dx.y*dy.x;
    if(abs(det)<1e-12) return 0;
    float2 screen=float2(offset.x*dy.y-offset.y*dy.x,dx.x*offset.y-dx.y*offset.x)/det;
    return ddx(toUV)*screen.x+ddy(toUV)*screen.y;
}

#endif

