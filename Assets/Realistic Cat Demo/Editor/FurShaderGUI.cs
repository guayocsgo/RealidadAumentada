using UnityEditor;
using UnityEngine;
namespace RealisticCatDemo.Editor
{
    public sealed class FurShaderGUI : ShaderGUI
    {
        bool grooming, lighting, textures;
        public override void OnGUI(MaterialEditor editor, MaterialProperty[] properties)
        {
            void Field(string name,string label) { var p=FindProperty(name,properties,false);if(p!=null) editor.ShaderProperty(p,label); }
            EditorGUILayout.LabelField("Realistic Cat Demo • Baked fur",EditorStyles.boldLabel);
            EditorGUILayout.HelpBox("Quality and distance are controlled by the prefab's LOD Group. Its lower LODs contain fewer vertices; the final LOD has no fur.",MessageType.Info);
            Field("_BaseColor","Tint"); Field("_LengthScale","Length"); Field("_Density","Strand density");
            Field("_Thinness","Tip taper"); Field("_RootColor","Root shade");Field("_TipColor","Tip shade");
            lighting=EditorGUILayout.Foldout(lighting,"Lighting",true);
            if(lighting) foreach(var n in new[]{"_RootAO","_Smoothness","_AnisoSpecular","_Rim","_DiffuseWrap","_ShadowOpacity","_AlbedoInfluence","_ColorVar"}) Field(n,n.TrimStart('_'));
            grooming=EditorGUILayout.Foldout(grooming,"Grooming",true);
            if(grooming) foreach(var n in new[]{"_MaxLength","_LengthJitter","_Clumping","_DirRandom","_Gravity","_GravityStrength","_CombStrength","_CombSurfaceAdherence","_CombUprightness","_CombJitter"}) Field(n,n.TrimStart('_'));
            textures=EditorGUILayout.Foldout(textures,"Texture maps",true);
            if(textures) foreach(var n in new[]{"_BaseMap","_FurControlMap","_FurWidthMap","_UseNormalMap","_BumpMap","_UseSmoothnessMap","_SmoothnessMap","_RoughnessInput","_SmoothnessChannel"}) Field(n,n.TrimStart('_'));
        }
    }
}
