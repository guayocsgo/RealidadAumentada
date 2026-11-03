using UnityEditor;
using UnityEngine;
namespace RealisticCatDemo.Editor
{
    public sealed class CatShaderGUI : ShaderGUI
    {
        bool textures, shadows = true, advanced;
        public override void OnGUI(MaterialEditor editor, MaterialProperty[] properties)
        {
            bool eye=((Material)editor.target).shader.name.Contains("Eye");
            MaterialProperty P(string n)=>FindProperty(n,properties,false);
            void Slider(string n,string label,float min,float max)
            {
                var p=P(n);if(p==null)return;
                EditorGUI.showMixedValue=p.hasMixedValue;EditorGUI.BeginChangeCheck();
                float value=EditorGUILayout.Slider(new GUIContent(label),p.floatValue,min,max);
                if(EditorGUI.EndChangeCheck()){editor.RegisterPropertyChangeUndo(label);p.floatValue=value;}
                EditorGUI.showMixedValue=false;
            }
            void Map(string n,string label){var p=P(n);if(p!=null)editor.TexturePropertySingleLine(new GUIContent(label),p);}
            if(eye)
            {
                var scleraTint=P("_ScleraColor");if(scleraTint!=null)editor.ColorProperty(scleraTint,"Sclera color");
                var irisTint=P("_IrisColor");if(irisTint!=null)editor.ColorProperty(irisTint,"Iris color");
                Slider("_IrisHue","Iris hue",-180,180);Slider("_IrisSaturation","Iris saturation",0,2);
                Slider("_Pupil","Pupil dilation",0,1);Slider("_PupilShape","Pupil shape (slit to round)",0,1);
                Slider("_PupilWidth","Pupil width",.25f,1.5f);Slider("_PupilHeight","Pupil height",.25f,1.5f);
                Slider("_IrisRotation","Iris / pupil rotation (degrees)",-180,180);

                EditorGUILayout.Space(4);
                EditorGUILayout.LabelField("Cornea and reflections", EditorStyles.boldLabel);
                Slider("_IrisDepth","Iris depth under cornea",0,.08f);
                Slider("_CorneaBulge","Cornea bulge (dome curvature)",0,1);
                Slider("_CorneaSmoothness","Cornea smoothness (coating gloss)",.7f,.99f);

                var irisUVSet=P("_IrisUVSet");
                if(irisUVSet!=null)
                {
                    EditorGUI.showMixedValue=irisUVSet.hasMixedValue;EditorGUI.BeginChangeCheck();
                    int selected=EditorGUILayout.Popup("Iris placement UV set",Mathf.RoundToInt(irisUVSet.floatValue),new[]{"UV0","UV1"});
                    if(EditorGUI.EndChangeCheck()){editor.RegisterPropertyChangeUndo("Iris placement UV set");irisUVSet.floatValue=selected;}
                    EditorGUI.showMixedValue=false;
                }
                Slider("_IrisUVOffsetX","Iris UV offset X",-.5f,.5f);Slider("_IrisUVOffsetY","Iris UV offset Y",-.5f,.5f);

                EditorGUILayout.Space(4);
                shadows = EditorGUILayout.Foldout(shadows, "Contact & Eyelid Shadows", true);
                if (shadows)
                {
                    EditorGUI.indentLevel++;
                    Slider("_ShadowStrength", "Upper eyelid shadow strength", 0f, 1f);
                    Slider("_ShadowHeight", "Upper eyelid height", 0.3f, 1f);
                    Slider("_ShadowSoftness", "Upper eyelid softness", 0.01f, 0.4f);
                    EditorGUILayout.Space(2);
                    Slider("_LowerShadowStrength", "Lower eyelid shadow strength", 0f, 1f);
                    Slider("_LowerShadowHeight", "Lower eyelid height", 0f, 0.7f);
                    EditorGUILayout.Space(2);
                    Slider("_CornerShadowStrength", "Corners shadow strength", 0f, 1f);
                    Slider("_CornerShadowWidth", "Corners shadow width", 0.01f, 0.4f);
                    EditorGUI.indentLevel--;
                }

                EditorGUILayout.Space(4);
                EditorGUILayout.HelpBox("Cornea bulge shapes specular reflections and clearcoat over the eye dome. Contact shadow sliders shade eyelid seams.", MessageType.None);
            }
            else
            {
                var diffusion=P("_DiffusionProfileHash");if(diffusion!=null)editor.ShaderProperty(diffusion,"Diffusion Profile");
                Slider("_RoughnessScale","Skin roughness",.5f,1.8f);Slider("_PoreSizeMM","Pore size (mm)",4,100);Slider("_PoreNormalStrength","Pore normal strength",0,2);Slider("_PoreRoughnessStrength","Pore roughness strength",0,1);
                Slider("_Subsurface","Local diffusion",0,1);Slider("_Transmission","Ear transmission",0,3);Slider("_VesselStrength","Vessel definition",0,3);
            }
            textures=EditorGUILayout.Foldout(textures,"Textures",true);
            if(textures)
            {
                Map("_BaseMap",eye?"UV0 iris / albedo atlas":"Albedo");
                if(eye)Map("_ScleraMap","Sclera");
                if(eye)Map("_IrisMap","Iris texture (UV1)");
                if(!eye){Map("_BumpMap","Normal");Map("_RoughnessMap","Roughness (linear)");Map("_MicroMap","Pore microdetail (linear)");Map("_TissueMap","Skin / thickness / vessels / transmission");}
            }
            advanced=EditorGUILayout.Foldout(advanced,"Advanced",true);
            if(advanced)
            {
                if(eye){
                    Slider("_IrisRadius","Iris radius",.1f,.5f);
                    
                    EditorGUILayout.HelpBox("Cornea orientation is derived automatically from the eye mesh.",MessageType.None);
                }
                else{Slider("_BumpScale","Normal strength",0,2);Slider("_ThicknessMM","Thickness scale (mm)",.1f,30);}
                var color=P("_BaseColor");if(color!=null)editor.ColorProperty(color,"Albedo tint");
                editor.EnableInstancingField();
            }
        }
    }
}
