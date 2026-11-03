using UnityEditor;
using UnityEngine;

namespace RealisticCatDemo.Editor
{
    /// <summary>Author screen-relative LOD thresholds from reference distances, with no runtime script.</summary>
    public sealed class LODDistanceSetup : EditorWindow
    {
        Camera referenceCamera;
        float fullFurDistance=3, noFurDistance=8, cullDistance=60, referenceFov=60;
        [MenuItem("Tools/Realistic Cat Demo/Configure LOD distances")]
        static void Open()=>GetWindow<LODDistanceSetup>("Cat LOD distances");
        void OnGUI()
        {
            EditorGUILayout.HelpBox("Select cats with a LOD Group. Distances are converted to Unity's native screen-size thresholds for the reference camera. Other FOVs, object scales and Quality LOD Bias still affect the switch. No per-frame script is added.",MessageType.Info);
            referenceCamera=(Camera)EditorGUILayout.ObjectField("Reference camera",referenceCamera,typeof(Camera),true);
            referenceFov=EditorGUILayout.Slider("Fallback vertical FOV",referenceFov,15,100);
            fullFurDistance=EditorGUILayout.FloatField("16 → 8 layers (metres)",fullFurDistance);
            noFurDistance=EditorGUILayout.FloatField("8 → no fur (metres)",noFurDistance);
            cullDistance=EditorGUILayout.FloatField("Cull (metres)",cullDistance);
            bool valid=fullFurDistance>0 && noFurDistance>fullFurDistance && cullDistance>noFurDistance;
            using(new EditorGUI.DisabledScope(!valid || Selection.gameObjects.Length==0 || (referenceCamera && referenceCamera.orthographic))) {
                if(GUILayout.Button("Apply to selected LOD Groups")) {
                    float fov=referenceCamera?referenceCamera.fieldOfView:referenceFov;
                    foreach(var go in Selection.gameObjects)foreach(var group in go.GetComponentsInChildren<LODGroup>(true)) {
                        var levels=group.GetLODs();if(levels.Length!=3)continue;
                        Undo.RecordObject(group,"Configure cat LOD distances");
                        Vector3 s=group.transform.lossyScale;
                        float worldSize=group.size*Mathf.Max(Mathf.Abs(s.x),Mathf.Abs(s.y),Mathf.Abs(s.z));
                        float projection=worldSize*Mathf.Max(QualitySettings.lodBias,.01f)/(2*Mathf.Tan(fov*Mathf.Deg2Rad*.5f));
                        levels[0].screenRelativeTransitionHeight=Mathf.Clamp(projection/fullFurDistance,.003f,.99f);
                        levels[1].screenRelativeTransitionHeight=Mathf.Clamp(projection/noFurDistance,.002f,levels[0].screenRelativeTransitionHeight-.001f);
                        levels[2].screenRelativeTransitionHeight=Mathf.Clamp(projection/cullDistance,.001f,levels[1].screenRelativeTransitionHeight-.001f);
                        group.SetLODs(levels);EditorUtility.SetDirty(group);PrefabUtility.RecordPrefabInstancePropertyModifications(group);
                    }
                }
            }
        }
    }
}
