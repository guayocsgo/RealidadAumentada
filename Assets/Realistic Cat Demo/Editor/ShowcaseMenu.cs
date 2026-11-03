using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;

namespace RealisticCatDemo.Editor
{
    public static class ShowcaseMenu
    {
        const string Root="Assets/Realistic Cat Demo";
        [MenuItem("Tools/Realistic Cat Demo/Open URP showcase")]
        public static void URP()=>Open("URP");
        [MenuItem("Tools/Realistic Cat Demo/Open HDRP showcase")]
        public static void HDRP()=>Open("HDRP");
        [MenuItem("Tools/Realistic Cat Demo/Open Built-in showcase")]
        public static void BuiltIn()=>Open("Built-in");
        static void Open(string pipeline)
        {
            string scene=Root+"/Demo/Scenes/Showcase_"+pipeline+".unity";
            if(!AssetDatabase.LoadAssetAtPath<SceneAsset>(scene)) {
                EditorUtility.DisplayDialog("Realistic Cat Demo","Import the "+pipeline+" edition of the collection first.","OK");return;
            }
            var asset=AssetDatabase.LoadAssetAtPath<RenderPipelineAsset>(Root+"/Demo/Settings/Showcase_"+pipeline+".asset");
            if(pipeline!="Built-in"&&!asset) {
                EditorUtility.DisplayDialog("Render pipeline missing","Install the matching Unity render pipeline package, then reopen the showcase.","OK");return;
            }
            if(!EditorSceneManager.SaveCurrentModifiedScenesIfUserWantsTo())return;
            // Explicit editor menu action configures this project's current quality level.
            QualitySettings.renderPipeline=null;GraphicsSettings.defaultRenderPipeline=asset;
            EditorSceneManager.OpenScene(scene);
        }
    }
}
