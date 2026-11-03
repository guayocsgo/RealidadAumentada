// Stand-alone build of the fur shaders: nothing generates this header here.
//
// Inside FurBrush an editor script writes FURBRUSH_URP_AVAILABLE / FURBRUSH_HDRP_AVAILABLE into
// FurPipelineDefines.hlsl. These shaders get that answer from ShaderLab instead: the URP and HDRP
// SubShaders declare PackageRequirements, so they only compile where that package is installed,
// and every one of their passes defines its own pipeline. The Built-in SubShader needs no package.
