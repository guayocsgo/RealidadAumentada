#if UNITY_EDITOR
using System;
using System.Collections.Generic;
using System.Reflection;
using UnityEditor;
using UnityEditor.Animations;
using UnityEditor.SceneManagement;
using UnityEditor.XR.ARSubsystems;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.XR.ARFoundation;
using UnityEngine.XR.ARSubsystems;
using UnityEngine.XR.Interaction.Toolkit.Samples.StarterAssets;
using UnityEngine.XR.Templates.AR;
using Unity.XR.CoreUtils;

namespace RealidadAumentada.Prototype.Editor
{
    [InitializeOnLoad]
    public static class ARImageTargetLabBuilder
    {
        private const string VersionPrefKey = "ARImageTargetLabBuilder_DogCat_v3";
        private const string LibraryAssetPath = "Assets/AR/TargetsLibrary.asset";
        private const string TargetDogImagePath = "Assets/AR/Images/TarjetaLaboratorio_A.png";
        private const string TargetCatImagePath = "Assets/AR/Images/TarjetaLaboratorio_B.png";

        private const string SourceDogPrefabPath = "Assets/RSG_DogsPack/HDRP/Prefabs/P_GermanShepherd.prefab";
        private const string SourceCatPrefabPath = "Assets/Realistic Cat Demo/Prefabs/URP/Mobile/Cat_05.prefab";

        private const string DogMatOpaquePath = "Assets/RSG_DogsPack/HDRP/Materials/M_GermanShepherd.mat";
        private const string DogMatTranspPath = "Assets/RSG_DogsPack/HDRP/Materials/M_GermanShepherd_Transparent.mat";
        private const string DogAlbedoTexPath = "Assets/RSG_DogsPack/HDRP/Textures/T_GermanShepherd_B.png";
        private const string DogNormalTexPath = "Assets/RSG_DogsPack/HDRP/Textures/T_GermanShepherd_N.png";

        private const string PrefabDogOutPath = "Assets/AR/Prefabs/ContentOnTarget.prefab";
        private const string PrefabCatOutPath = "Assets/AR/Prefabs/ContentOnTarget_B.prefab";
        private const string LabScenePath = "Assets/Scenes/ImageTargetLab.unity";
        private const string SourceScenePath = "Assets/Scenes/SampleScene.unity";

        static ARImageTargetLabBuilder()
        {
            EditorApplication.delayCall += AutoBuildIfMissing;
            EditorApplication.playModeStateChanged += OnPlayModeStateChanged;
        }

        private static void OnPlayModeStateChanged(PlayModeStateChange state)
        {
            if (state == PlayModeStateChange.EnteredEditMode)
            {
                EditorApplication.delayCall += AutoBuildIfMissing;
            }
        }

        private static void AutoBuildIfMissing()
        {
            ConfigureHighResPortraitGameView();

            if (EditorApplication.isPlayingOrWillChangePlaymode || EditorApplication.isCompiling)
                return;

            bool libraryMissing = AssetDatabase.LoadAssetAtPath<XRReferenceImageLibrary>(LibraryAssetPath) == null;
            bool sceneMissing = AssetDatabase.LoadAssetAtPath<SceneAsset>(LabScenePath) == null;
            bool needsDogCatUpdate = !EditorPrefs.GetBool(VersionPrefKey, false);

            if (libraryMissing || sceneMissing || needsDogCatUpdate)
            {
                BuildCompleteImageTargetLab();
                EditorPrefs.SetBool(VersionPrefKey, true);
            }
        }

        [MenuItem("Tools/TP Realidad Aumentada/Activar Resolución Full HD Portrait (1080x1920)")]
        public static void ConfigureHighResPortraitGameView()
        {
            try
            {
                Assembly editorAsm = typeof(EditorWindow).Assembly;
                Type gameViewType = editorAsm.GetType("UnityEditor.GameView");
                if (gameViewType == null)
                    return;

                UnityEngine.Object[] gameViews = Resources.FindObjectsOfTypeAll(gameViewType);
                if (gameViews == null || gameViews.Length == 0)
                    return;

                Type sizesType = editorAsm.GetType("UnityEditor.GameViewSizes");
                Type singleType = typeof(ScriptableSingleton<>).MakeGenericType(sizesType);
                PropertyInfo instanceProp = singleType.GetProperty("instance");
                object sizesInstance = instanceProp?.GetValue(null, null);
                PropertyInfo currentGroupProp = sizesType?.GetProperty("currentGroup");
                object currentGroup = currentGroupProp?.GetValue(sizesInstance, null);

                int targetSizeIndex = -1;
                if (currentGroup != null)
                {
                    Type groupType = currentGroup.GetType();
                    MethodInfo getTotalCount = groupType.GetMethod("GetTotalCount");
                    MethodInfo getGameViewSize = groupType.GetMethod("GetGameViewSize");
                    int totalCount = (int)getTotalCount.Invoke(currentGroup, null);

                    for (int i = 0; i < totalCount; i++)
                    {
                        object gvSize = getGameViewSize.Invoke(currentGroup, new object[] { i });
                        PropertyInfo wProp = gvSize.GetType().GetProperty("width");
                        PropertyInfo hProp = gvSize.GetType().GetProperty("height");
                        int w = (int)wProp.GetValue(gvSize, null);
                        int h = (int)hProp.GetValue(gvSize, null);
                        if (w == 1080 && h == 1920)
                        {
                            targetSizeIndex = i;
                            break;
                        }
                    }

                    if (targetSizeIndex < 0)
                    {
                        Type gvSizeType = editorAsm.GetType("UnityEditor.GameViewSize");
                        Type gvSizeTypeEnum = editorAsm.GetType("UnityEditor.GameViewSizeType");
                        object fixedResEnum = Enum.Parse(gvSizeTypeEnum, "FixedResolution");
                        ConstructorInfo ctor = gvSizeType.GetConstructor(new[] { gvSizeTypeEnum, typeof(int), typeof(int), typeof(string) });
                        if (ctor != null)
                        {
                            object newSize = ctor.Invoke(new object[] { fixedResEnum, 1080, 1920, "Full HD Portrait (1080x1920)" });
                            MethodInfo addCustomSize = groupType.GetMethod("AddCustomSize");
                            addCustomSize?.Invoke(currentGroup, new object[] { newSize });
                            targetSizeIndex = (int)getTotalCount.Invoke(currentGroup, null) - 1;
                        }
                    }
                }

                foreach (UnityEngine.Object gv in gameViews)
                {
                    FieldInfo lowResField = gameViewType.GetField("m_LowResolutionForAspectRatios", BindingFlags.Instance | BindingFlags.NonPublic);
                    if (lowResField != null && lowResField.GetValue(gv) is bool[] lowResArr)
                    {
                        for (int i = 0; i < lowResArr.Length; i++)
                        {
                            lowResArr[i] = false;
                        }
                    }

                    if (targetSizeIndex >= 0)
                    {
                        MethodInfo sizeSelCallback = gameViewType.GetMethod("SizeSelectionCallback", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
                        sizeSelCallback?.Invoke(gv, new object[] { targetSizeIndex, null });
                    }

                    PropertyInfo minScaleProp = gameViewType.GetProperty("minScale", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);
                    MethodInfo snapZoomMethod = gameViewType.GetMethod("SnapZoom", BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);
                    if (minScaleProp != null && snapZoomMethod != null)
                    {
                        float minScale = (float)minScaleProp.GetValue(gv, null);
                        snapZoomMethod.Invoke(gv, new object[] { minScale });
                    }

                    if (gv is EditorWindow win)
                    {
                        win.Repaint();
                    }
                }
            }
            catch
            {
            }
        }

        [MenuItem("Tools/TP Realidad Aumentada/Construir Escena ImageTargetLab (Perro y Gato)")]
        public static void BuildCompleteImageTargetLab()
        {
            string previousScenePath = SceneManager.GetActiveScene().path;

            EnsureFoldersExist();
            UpgradeDogMaterialsToURP();
            ConfigureAnimalAnimations();
            ConfigureTargetTextures();

            XRReferenceImageLibrary library = CreateOrUpdateReferenceLibrary();
            GameObject prefabDog = CreateOrUpdateAnimalTargetPrefab(
                PrefabDogOutPath,
                "ContentOnTarget_Perro",
                SourceDogPrefabPath,
                0.13f,
                new Color(0.85f, 0.58f, 0.24f, 1f)
            );
            GameObject prefabCat = CreateOrUpdateAnimalTargetPrefab(
                PrefabCatOutPath,
                "ContentOnTarget_Gato",
                SourceCatPrefabPath,
                0.12f,
                new Color(0.35f, 0.68f, 0.85f, 1f)
            );

            CreateOrUpdateImageTargetLabScene(library, prefabDog, prefabCat);
            RegisterSceneInBuildSettings();

            if (!string.IsNullOrEmpty(previousScenePath) && previousScenePath != LabScenePath)
            {
                EditorSceneManager.OpenScene(previousScenePath, OpenSceneMode.Single);
            }

            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
        }

        private static void ConfigureAnimalAnimations()
        {
            AnimatorController dogCtrl = AssetDatabase.LoadAssetAtPath<AnimatorController>("Assets/RSG_DogsPack/HDRP/Animations/AC_Dogs_Type_01.controller");
            if (dogCtrl != null && dogCtrl.layers.Length > 0)
            {
                AnimatorStateMachine sm = dogCtrl.layers[0].stateMachine;
                bool changed = false;
                for (int i = 0; i < sm.states.Length; i++)
                {
                    AnimatorState st = sm.states[i].state;
                    if (st != null && st.transitions != null && st.transitions.Length > 0)
                    {
                        st.transitions = Array.Empty<AnimatorStateTransition>();
                        changed = true;
                    }
                }
                if (changed)
                {
                    EditorUtility.SetDirty(dogCtrl);
                }
            }

            string[] catLoopAnims =
            {
                "Assets/Realistic Cat Demo/Cats/Cat_05/Animations/Idle.anim",
                "Assets/Realistic Cat Demo/Cats/Cat_05/Animations/Sitting_Idle.anim",
                "Assets/Realistic Cat Demo/Cats/Cat_05/Animations/Walk.anim",
                "Assets/Realistic Cat Demo/Cats/Cat_05/Animations/Run.anim"
            };

            for (int i = 0; i < catLoopAnims.Length; i++)
            {
                AnimationClip clip = AssetDatabase.LoadAssetAtPath<AnimationClip>(catLoopAnims[i]);
                if (clip != null)
                {
                    AnimationClipSettings settings = AnimationUtility.GetAnimationClipSettings(clip);
                    if (!settings.loopTime)
                    {
                        settings.loopTime = true;
                        AnimationUtility.SetAnimationClipSettings(clip, settings);
                        EditorUtility.SetDirty(clip);
                    }
                }
            }
        }

        private static void EnsureFoldersExist()
        {
            if (!AssetDatabase.IsValidFolder("Assets/AR"))
                AssetDatabase.CreateFolder("Assets", "AR");
            if (!AssetDatabase.IsValidFolder("Assets/AR/Images"))
                AssetDatabase.CreateFolder("Assets/AR", "Images");
            if (!AssetDatabase.IsValidFolder("Assets/AR/Prefabs"))
                AssetDatabase.CreateFolder("Assets/AR", "Prefabs");
        }

        private static void UpgradeDogMaterialsToURP()
        {
            Shader urpLit = Shader.Find("Universal Render Pipeline/Lit");
            if (urpLit == null)
                return;

            Texture2D albedoTex = AssetDatabase.LoadAssetAtPath<Texture2D>(DogAlbedoTexPath);
            Texture2D normalTex = AssetDatabase.LoadAssetAtPath<Texture2D>(DogNormalTexPath);

            ConvertSingleDogMaterial(DogMatOpaquePath, urpLit, albedoTex, normalTex, false);
            ConvertSingleDogMaterial(DogMatTranspPath, urpLit, albedoTex, normalTex, true);
        }

        private static void ConvertSingleDogMaterial(
            string matPath,
            Shader urpLit,
            Texture2D albedoTex,
            Texture2D normalTex,
            bool alphaClip)
        {
            Material mat = AssetDatabase.LoadAssetAtPath<Material>(matPath);
            if (mat == null)
                return;

            mat.shader = urpLit;
            mat.SetColor("_BaseColor", Color.white);
            mat.SetColor("_Color", Color.white);
            mat.SetFloat("_Smoothness", 0.25f);
            mat.SetFloat("_Metallic", 0f);

            if (albedoTex != null)
            {
                mat.SetTexture("_BaseMap", albedoTex);
                mat.SetTexture("_MainTex", albedoTex);
            }

            if (normalTex != null)
            {
                mat.SetTexture("_BumpMap", normalTex);
                mat.EnableKeyword("_NORMALMAP");
            }

            if (alphaClip)
            {
                mat.SetFloat("_AlphaClip", 1f);
                mat.SetFloat("_Cutoff", 0.15f);
                mat.SetFloat("_Cull", 0f);
                mat.EnableKeyword("_ALPHATEST_ON");
            }
            else
            {
                mat.SetFloat("_AlphaClip", 0f);
                mat.SetFloat("_Cull", 2f);
            }

            EditorUtility.SetDirty(mat);
        }

        private static void ConfigureTargetTextures()
        {
            AssetDatabase.ImportAsset(TargetDogImagePath, ImportAssetOptions.ForceUpdate);
            AssetDatabase.ImportAsset(TargetCatImagePath, ImportAssetOptions.ForceUpdate);

            ConfigureReadableTexture(TargetDogImagePath);
            ConfigureReadableTexture(TargetCatImagePath);
        }

        private static void ConfigureReadableTexture(string path)
        {
            if (AssetImporter.GetAtPath(path) is TextureImporter importer)
            {
                bool changed = false;
                if (!importer.isReadable)
                {
                    importer.isReadable = true;
                    changed = true;
                }
                if (importer.textureCompression != TextureImporterCompression.Uncompressed)
                {
                    importer.textureCompression = TextureImporterCompression.Uncompressed;
                    changed = true;
                }
                if (changed)
                {
                    importer.SaveAndReimport();
                }
            }
        }

        private static XRReferenceImageLibrary CreateOrUpdateReferenceLibrary()
        {
            XRReferenceImageLibrary library = AssetDatabase.LoadAssetAtPath<XRReferenceImageLibrary>(LibraryAssetPath);
            if (library == null)
            {
                library = ScriptableObject.CreateInstance<XRReferenceImageLibrary>();
                AssetDatabase.CreateAsset(library, LibraryAssetPath);
            }

            while (library.count > 0)
            {
                library.RemoveAt(library.count - 1);
            }

            Texture2D texDog = AssetDatabase.LoadAssetAtPath<Texture2D>(TargetDogImagePath);
            Texture2D texCat = AssetDatabase.LoadAssetAtPath<Texture2D>(TargetCatImagePath);

            library.Add();
            library.SetName(0, ImageTargetContent.DogTargetName);
            library.SetTexture(0, texDog, true);
            library.SetSpecifySize(0, true);
            library.SetSize(0, new Vector2(0.15f, 0.15f));

            library.Add();
            library.SetName(1, ImageTargetContent.CatTargetName);
            library.SetTexture(1, texCat, true);
            library.SetSpecifySize(1, true);
            library.SetSize(1, new Vector2(0.15f, 0.15f));

            EditorUtility.SetDirty(library);
            return library;
        }

        private static GameObject CreateOrUpdateAnimalTargetPrefab(
            string outputPrefabPath,
            string rootName,
            string sourceAnimalPrefabPath,
            float desiredHeightMeters,
            Color pedestalRingColor)
        {
            GameObject root = new GameObject(rootName);

            Shader urpLit = Shader.Find("Universal Render Pipeline/Lit");
            GameObject baseDisc = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            baseDisc.name = "AR_TargetPedestal";
            baseDisc.transform.SetParent(root.transform, false);
            baseDisc.transform.localPosition = new Vector3(0f, 0.002f, 0f);
            baseDisc.transform.localScale = new Vector3(0.11f, 0.002f, 0.11f);
            if (baseDisc.TryGetComponent(out Collider discCol))
            {
                UnityEngine.Object.DestroyImmediate(discCol);
            }
            if (baseDisc.TryGetComponent(out Renderer discRend))
            {
                Material defaultMat = AssetDatabase.LoadAssetAtPath<Material>("Assets/MobileARTemplateAssets/Materials/ObjectMaterial.mat");
                if (defaultMat != null)
                {
                    discRend.sharedMaterial = defaultMat;
                }
                else if (urpLit != null)
                {
                    discRend.sharedMaterial = new Material(urpLit) { color = pedestalRingColor };
                }
            }

            GameObject sourceAnimalPrefab = AssetDatabase.LoadAssetAtPath<GameObject>(sourceAnimalPrefabPath);
            if (sourceAnimalPrefab != null)
            {
                GameObject animalInstance = (GameObject)PrefabUtility.InstantiatePrefab(sourceAnimalPrefab, root.transform);
                animalInstance.name = sourceAnimalPrefab.name;
                animalInstance.transform.localPosition = Vector3.zero;
                animalInstance.transform.localRotation = Quaternion.identity;
                animalInstance.transform.localScale = Vector3.one;

                LODGroup[] lodGroups = animalInstance.GetComponentsInChildren<LODGroup>(true);
                for (int i = 0; i < lodGroups.Length; i++)
                {
                    lodGroups[i].enabled = false;
                }

                Renderer[] renderers = animalInstance.GetComponentsInChildren<Renderer>(true);
                if (renderers.Length > 0)
                {
                    Bounds combined = renderers[0].bounds;
                    for (int i = 1; i < renderers.Length; i++)
                    {
                        combined.Encapsulate(renderers[i].bounds);
                    }

                    float currentHeight = Mathf.Max(0.01f, combined.size.y);
                    float scaleFactor = desiredHeightMeters / currentHeight;
                    animalInstance.transform.localScale = Vector3.one * scaleFactor;

                    Bounds scaledBounds = renderers[0].bounds;
                    for (int i = 1; i < renderers.Length; i++)
                    {
                        scaledBounds.Encapsulate(renderers[i].bounds);
                    }

                    float yOffset = 0.004f - scaledBounds.min.y;
                    animalInstance.transform.localPosition = new Vector3(
                        -scaledBounds.center.x,
                        yOffset,
                        -scaledBounds.center.z
                    );
                }
            }

            GameObject savedPrefab = PrefabUtility.SaveAsPrefabAsset(root, outputPrefabPath);
            UnityEngine.Object.DestroyImmediate(root);
            return savedPrefab;
        }

        private static void CreateOrUpdateImageTargetLabScene(
            XRReferenceImageLibrary library,
            GameObject prefabDog,
            GameObject prefabCat)
        {
            if (AssetDatabase.LoadAssetAtPath<SceneAsset>(LabScenePath) == null)
            {
                AssetDatabase.CopyAsset(SourceScenePath, LabScenePath);
            }

            Scene labScene = EditorSceneManager.OpenScene(LabScenePath, OpenSceneMode.Single);

            ObjectSpawner spawner = UnityEngine.Object.FindFirstObjectByType<ObjectSpawner>(FindObjectsInactive.Include);
            if (spawner != null)
            {
                spawner.gameObject.SetActive(false);
            }

            ARPlaneManager planeManager = UnityEngine.Object.FindFirstObjectByType<ARPlaneManager>(FindObjectsInactive.Include);
            if (planeManager != null)
            {
                planeManager.enabled = false;
            }

            GoalManager goalManager = UnityEngine.Object.FindFirstObjectByType<GoalManager>(FindObjectsInactive.Include);
            if (goalManager != null)
            {
                if (goalManager.greetingPrompt != null)
                    goalManager.greetingPrompt.SetActive(false);
                if (goalManager.createButton != null)
                    goalManager.createButton.SetActive(false);
                if (goalManager.optionsButton != null)
                    goalManager.optionsButton.SetActive(false);
                goalManager.enabled = false;
            }

            ARTemplateMenuManager menuManager = UnityEngine.Object.FindFirstObjectByType<ARTemplateMenuManager>(FindObjectsInactive.Include);
            if (menuManager != null)
            {
                menuManager.enabled = false;
            }

            XROrigin xrOrigin = UnityEngine.Object.FindFirstObjectByType<XROrigin>();
            if (xrOrigin != null)
            {
                if (!xrOrigin.gameObject.TryGetComponent(out ARTrackedImageManager trackedImageManager))
                {
                    trackedImageManager = xrOrigin.gameObject.AddComponent<ARTrackedImageManager>();
                }

                trackedImageManager.referenceLibrary = library;
                trackedImageManager.requestedMaxNumberOfMovingImages = 2;
                trackedImageManager.enabled = true;

                if (!xrOrigin.gameObject.TryGetComponent(out ImageTargetContent targetContent))
                {
                    targetContent = xrOrigin.gameObject.AddComponent<ImageTargetContent>();
                }

                SerializedObject so = new SerializedObject(targetContent);
                so.FindProperty("contentPrefab").objectReferenceValue = prefabDog;

                SerializedProperty listProp = so.FindProperty("targetPrefabs");
                listProp.ClearArray();

                listProp.InsertArrayElementAtIndex(0);
                SerializedProperty elem0 = listProp.GetArrayElementAtIndex(0);
                elem0.FindPropertyRelative("referenceImageName").stringValue = ImageTargetContent.DogTargetName;
                elem0.FindPropertyRelative("prefab").objectReferenceValue = prefabDog;

                listProp.InsertArrayElementAtIndex(1);
                SerializedProperty elem1 = listProp.GetArrayElementAtIndex(1);
                elem1.FindPropertyRelative("referenceImageName").stringValue = ImageTargetContent.CatTargetName;
                elem1.FindPropertyRelative("prefab").objectReferenceValue = prefabCat;

                so.ApplyModifiedPropertiesWithoutUndo();
            }

            EditorSceneManager.MarkSceneDirty(labScene);
            EditorSceneManager.SaveScene(labScene);
        }

        private static void RegisterSceneInBuildSettings()
        {
            List<EditorBuildSettingsScene> scenes = new List<EditorBuildSettingsScene>
            {
                new EditorBuildSettingsScene(LabScenePath, true),
                new EditorBuildSettingsScene(SourceScenePath, true)
            };
            EditorBuildSettings.scenes = scenes.ToArray();
        }
    }
}
#endif
