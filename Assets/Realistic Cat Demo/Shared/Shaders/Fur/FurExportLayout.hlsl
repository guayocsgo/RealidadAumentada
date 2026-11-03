#ifndef FURBRUSH_EXPORT_LAYOUT_INCLUDED
#define FURBRUSH_EXPORT_LAYOUT_INCLUDED

// Vertex layout of a fur mesh that has travelled through an FBX file.
//
// The plugin's fur meshes pack per-vertex data into 4-component UV channels and, on cards, into
// TANGENT.w. FBX carries neither: every UV set is 2D and a tangent has no w. The exporter
// therefore splits each packed channel over a pair of 2D sets, and the structs below put the
// halves back together before the unchanged FurBrush shading code reads them.
//
// Shell   UV0 strand / albedo UV       UV1 control-map UV        UV2 (layer t, shell index)
//         UV3 control frame xy         UV5 control frame zw (handedness, valid flag)
// Cards   UV0 (edge 0/1, v)            UV1 (half width, height)  UV2 surface UV
//         UV3 control-map UV           UV7 (yaw, plane flag)     UV5 (theta, base tangent sign)
//         UV6 (atlas cell, atlas columns)
//
// UV4 is reserved for Unity skinned previous positions, including forward rendering.
// Keep UV4 zero-filled in every mesh: a hole aliases higher UV bindings on skinned draws.
// The FBX exporter also needs this padding so later UV sets are not renumbered.
// Keep this in step with FurExportMeshes.cs, which writes the same layout.

#ifdef FURBRUSH_SHELL_INCLUDED

struct FurExportAttributes
{
    float4 positionOS     : POSITION;
    float3 normalOS       : NORMAL;
    float4 tangentOS      : TANGENT;
    float2 uv             : TEXCOORD0;
    float2 uvControl      : TEXCOORD1;
    float2 shell          : TEXCOORD2;
    float2 controlFrameXY : TEXCOORD3;
    float2 controlFrameZW : TEXCOORD5;
};

// How many of the baked shell layers to draw. The mesh carries every layer it was exported with and
// _ShellCount says how many the material wants, so layer count stays a live quality control on a
// published model instead of being frozen into the geometry: the layers outside the reduced set
// collapse onto a point below and cost no fragments. The ones that remain are the layers a mesh
// built with that count would have had, so lowering it matches lowering Shell Layers in FurBrush.
//
// The baked count comes from the vertex itself: layer s of B stores t = (s + 1) / B in shell.x and s
// in shell.y, so B = (s + 1) / t. FurShellRenderer writes that pair and FurExportMeshes keeps it.
FurAttributes FurExportUnpack(FurExportAttributes v)
{
    FurAttributes a;
    // A model exported with runtime layers carries one copy of the coat and is drawn once per layer,
    // so the layer comes from the renderer rather than the vertex. _ShellCount then has no baked
    // ceiling: the coat is exactly as thick as the material asks for, and nothing has to be dropped.
    bool runtime = _ShellLayers > 0.5;
    float2 shell = runtime ? float2((_ShellLayer + 1.0) / _ShellLayers, _ShellLayer) : v.shell;

    // Static fur carries two tiny triangles on the far corners of its bounds, so the imported mesh
    // bounds cover the extruded coat. They are marked with shell index -1 and collapsed onto one
    // point here, which leaves them nothing to draw - and so are the layers _ShellCount drops.
    bool draw             = v.shell.y > -0.5 && true;
    a.positionOS          = draw ? v.positionOS : float4(0.0, 0.0, 0.0, 1.0);
    a.normalOS            = v.normalOS;
    a.tangentOS           = v.tangentOS;
    a.uv                  = v.uv;
    a.uvControl           = v.uvControl;
    a.shell               = shell;
    a.controlTangentFrame = float4(v.controlFrameXY, v.controlFrameZW);
    return a;
}

#ifdef FURBRUSH_FORWARD_LIGHTING
FurVaryings FurExportVertForward(FurExportAttributes v)
{
    return FurVertForward(FurExportUnpack(v));
}
#endif

#endif // FURBRUSH_SHELL_INCLUDED

#ifdef FURBRUSH_CARD_INCLUDED

// A card's vertices all sit on its root - the shader builds the card from there. FBX merges vertices
// that share a position into one control point, and a polygon over a single control point does not
// survive import, so the exporter spreads each vertex by this much along the card's width axis and
// normal. CardExportUnpack takes the spread back off. FurExportMeshes.CardSpread must match.
#define FUR_EXPORT_CARD_SPREAD 1e-4

struct CardExportAttributes
{
    float4 positionOS : POSITION;
    float3 normalOS   : NORMAL;
    float4 tangentOS  : TANGENT;     // xyz = width axis; w is not used, FBX cannot carry it
    float2 uv         : TEXCOORD0;
    float2 rootSize   : TEXCOORD1;
    float2 baseUV     : TEXCOORD2;
    float2 controlUV  : TEXCOORD3;
    float2 rootExtra  : TEXCOORD7;
    float2 baseFrame  : TEXCOORD5;
    float2 atlasCell  : TEXCOORD6;
};

// Cards thin out by dropping whole cards: _CardDensity is the share that stays, chosen by a hash of
// the card's root UV, which every vertex of that card carries and no pass or frame changes. A card
// left out collapses onto a point and costs no fragments, so density is to card fur what the layer
// count is to shells - a quality control that survives the export.
bool CardExportDraw(float2 baseUV)
{
    return _CardDensity >= 0.999 || FurHash21(floor(baseUV * 4096.0)) < _CardDensity;
}

CardAttributes CardExportUnpack(CardExportAttributes v)
{
    CardAttributes a;
    float3 spread = v.tangentOS.xyz * ((v.uv.x - 0.5) * FUR_EXPORT_CARD_SPREAD) +
                    v.normalOS * (v.uv.y * FUR_EXPORT_CARD_SPREAD);
    a.positionOS = CardExportDraw(v.baseUV) ? float4(v.positionOS.xyz - spread, v.positionOS.w)
                                            : float4(0.0, 0.0, 0.0, 1.0);
    a.normalOS   = v.normalOS;
    a.tangentOS  = float4(v.tangentOS.xyz, v.rootExtra.y);
    a.uv         = v.uv;
    a.uv1        = float4(v.rootSize, v.rootExtra.x, 1.0);
    a.baseUV     = float4(v.baseUV, v.baseFrame);
    a.controlUV  = float4(v.controlUV, v.atlasCell);
    return a;
}

#ifdef FURBRUSH_FORWARD_LIGHTING
CardVaryings CardExportVert(CardExportAttributes v)
{
    return CardVert(CardExportUnpack(v));
}
#endif

#endif // FURBRUSH_CARD_INCLUDED

#endif // FURBRUSH_EXPORT_LAYOUT_INCLUDED
