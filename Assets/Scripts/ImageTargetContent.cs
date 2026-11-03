using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.UI;
using UnityEngine.XR.ARFoundation;
using UnityEngine.XR.ARSubsystems;
using RealidadAumentada.Prototype;

[RequireComponent(typeof(ARTrackedImageManager))]
public class ImageTargetContent : MonoBehaviour
{
    public const string DogTargetName = "Perro";
    public const string CatTargetName = "Gato";
    public const string LegacyDogTargetName = "TarjetaLaboratorio_A";
    public const string LegacyCatTargetName = "TarjetaLaboratorio_B";

    public enum AnimalAnimationMode
    {
        Idle = 0,
        SitOrPlay = 1,
        Walk = 2,
        Run = 3,
        JumpOrAction = 4
    }

    [Serializable]
    public struct NamedTargetPrefab
    {
        public string referenceImageName;
        public GameObject prefab;
    }

    [SerializeField]
    private GameObject contentPrefab;

    [SerializeField]
    private List<NamedTargetPrefab> targetPrefabs = new List<NamedTargetPrefab>();

    [SerializeField]
    private float rotationStepDegrees = 35f;

    [SerializeField]
    private float minContentScale = 0.4f;

    [SerializeField]
    private float maxContentScale = 2.5f;

    [SerializeField]
    private bool enableWebcamOpticalScannerInEditor = true;

    private ARTrackedImageManager manager;
    private Camera arCamera;
    private ARLiveCameraFeedController liveCameraFeed;

    private readonly Dictionary<TrackableId, GameObject> content = new Dictionary<TrackableId, GameObject>();
    private readonly Dictionary<TrackableId, TrackingState> lastTrackingStates = new Dictionary<TrackableId, TrackingState>();
    private readonly Dictionary<string, int> detectionCounts = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

    private readonly Dictionary<string, GameObject> simulatedContent = new Dictionary<string, GameObject>();
    private string activeSimulatedTargetName;
    private TrackingState simulatedTrackingState = TrackingState.None;
    private Vector3 lastSimulatedBaseWorldPos;
    private float opticalScanTimer;
    private int consecutiveDogMatches;
    private int consecutiveCatMatches;
    private int consecutiveNoMatches;

    private AnimalAnimationMode currentAnimationMode = AnimalAnimationMode.Idle;
    private bool catActionUseAttack;
    private float jumpArcTimer = -1f;
    private const float JumpArcDuration = 0.65f;
    private readonly List<Image> animButtonImages = new List<Image>();

    private const int GridSize = 12;
    private Color[] dogRefGrid;
    private Color[] catRefGrid;
    private Texture2D dogPreviewTex;
    private Texture2D catPreviewTex;

    private float userScaleMultiplier = 1f;
    private float userYawOffsetDegrees;
    private bool autoSpinContent;

    private Canvas statusCanvas;
    private Image bannerBackground;
    private Text statusTitleText;
    private Text statusDetailText;
    private Text countersText;
    private Text scaleLabelText;
    private GameObject previewModalPanel;
    private Font uiFont;

    private readonly Color colorWaiting = new Color(0.14f, 0.42f, 0.78f, 0.92f);
    private readonly Color colorTracking = new Color(0.12f, 0.65f, 0.36f, 0.92f);
    private readonly Color colorLimited = new Color(0.85f, 0.48f, 0.10f, 0.92f);
    private readonly Color colorAnimBtnIdle = new Color(0.20f, 0.25f, 0.34f, 1f);
    private readonly Color colorAnimBtnActive = new Color(0.16f, 0.68f, 0.42f, 1f);

    private void Awake()
    {
        manager = GetComponent<ARTrackedImageManager>();
        arCamera = Camera.main != null ? Camera.main : FindFirstObjectByType<Camera>();
        liveCameraFeed = FindFirstObjectByType<ARLiveCameraFeedController>();
        if (liveCameraFeed == null && arCamera != null)
        {
            liveCameraFeed = gameObject.AddComponent<ARLiveCameraFeedController>();
        }

        uiFont = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
        if (uiFont == null)
        {
            uiFont = Font.CreateDynamicFontFromOSFont("Arial", 16);
        }

        LoadReferenceTexturesAndBuildGrids();
        EnsureDefaultPrefabsIfEmpty();
        BuildImageTrackingUI();
    }

    private void OnEnable()
    {
        if (manager != null)
        {
            manager.trackablesChanged.AddListener(OnImagesChanged);
        }
    }

    private void OnDisable()
    {
        if (manager != null)
        {
            manager.trackablesChanged.RemoveListener(OnImagesChanged);
        }
    }

    private void Start()
    {
        UpdateStatusUIWaiting();
        RefreshCountersUI();
        UpdateAnimationButtonsVisualState();
    }

    private void Update()
    {
        if (Mouse.current != null)
        {
            float scrollY = Mouse.current.scroll.ReadValue().y;
            if (Mathf.Abs(scrollY) > 0.01f)
            {
                SetUserScale(userScaleMultiplier + Mathf.Sign(scrollY) * 0.12f);
            }
        }

        AnimateAndTransformActiveContent();
        MaintainSelectedAnimalAnimation();

#if UNITY_EDITOR || UNITY_STANDALONE
        if (enableWebcamOpticalScannerInEditor &&
            content.Count == 0 &&
            liveCameraFeed != null &&
            liveCameraFeed.IsLiveFeedActive)
        {
            opticalScanTimer += Time.deltaTime;
            if (opticalScanTimer >= 0.18f)
            {
                opticalScanTimer = 0f;
                RunOpticalWebcamTargetCheck();
            }
        }
#endif
    }

    private void OnImagesChanged(ARTrackablesChangedEventArgs<ARTrackedImage> args)
    {
        foreach (ARTrackedImage image in args.added)
        {
            RegisterDetectionIfTracking(image);
            UpdateContent(image);
        }

        foreach (ARTrackedImage image in args.updated)
        {
            RegisterDetectionIfTracking(image);
            UpdateContent(image);
        }

        foreach (KeyValuePair<TrackableId, ARTrackedImage> removed in args.removed)
        {
            if (content.TryGetValue(removed.Key, out GameObject go))
            {
                Destroy(go);
                content.Remove(removed.Key);
            }

            lastTrackingStates.Remove(removed.Key);
        }

        RefreshOverallStatusFromTrackables();
    }

    private void UpdateContent(ARTrackedImage image)
    {
        string targetName = NormalizeTargetName(image.referenceImage.name);
        GameObject prefabToUse = ResolvePrefabForTarget(targetName);
        if (prefabToUse == null)
            return;

        if (!content.TryGetValue(image.trackableId, out GameObject go))
        {
            go = Instantiate(prefabToUse, image.transform);
            go.name = $"ARTracked_{targetName}";
            go.transform.localPosition = Vector3.zero;
            go.transform.localRotation = Quaternion.Euler(0f, userYawOffsetDegrees, 0f);
            go.transform.localScale = Vector3.one * userScaleMultiplier;
            EnsureRenderersAndMaterialsValid(go);
            ApplyAnimationToAnimalInstance(go, currentAnimationMode, true);
            content.Add(image.trackableId, go);
        }

        bool isTracking = image.trackingState == TrackingState.Tracking;
        go.SetActive(isTracking);
    }

    private void RegisterDetectionIfTracking(ARTrackedImage image)
    {
        string targetName = NormalizeTargetName(image.referenceImage.name);

        lastTrackingStates.TryGetValue(image.trackableId, out TrackingState previousState);
        TrackingState currentState = image.trackingState;
        lastTrackingStates[image.trackableId] = currentState;

        if (currentState == TrackingState.Tracking && previousState != TrackingState.Tracking)
        {
            IncrementDetectionCount(targetName);
        }
    }

    private void IncrementDetectionCount(string targetName)
    {
        string normalized = NormalizeTargetName(targetName);
        if (!detectionCounts.TryGetValue(normalized, out int currentCount))
        {
            currentCount = 0;
        }

        detectionCounts[normalized] = currentCount + 1;
        RefreshCountersUI();
    }

    private string NormalizeTargetName(string rawName)
    {
        if (string.IsNullOrEmpty(rawName))
            return DogTargetName;

        if (rawName.IndexOf("Perro", StringComparison.OrdinalIgnoreCase) >= 0 ||
            rawName.IndexOf("Dog", StringComparison.OrdinalIgnoreCase) >= 0 ||
            string.Equals(rawName, LegacyDogTargetName, StringComparison.OrdinalIgnoreCase))
        {
            return DogTargetName;
        }

        if (rawName.IndexOf("Gato", StringComparison.OrdinalIgnoreCase) >= 0 ||
            rawName.IndexOf("Cat", StringComparison.OrdinalIgnoreCase) >= 0 ||
            string.Equals(rawName, LegacyCatTargetName, StringComparison.OrdinalIgnoreCase))
        {
            return CatTargetName;
        }

        return rawName;
    }

    private GameObject ResolvePrefabForTarget(string targetName)
    {
        string normalized = NormalizeTargetName(targetName);

        if (targetPrefabs != null)
        {
            for (int i = 0; i < targetPrefabs.Count; i++)
            {
                string entryNormalized = NormalizeTargetName(targetPrefabs[i].referenceImageName);
                if (string.Equals(entryNormalized, normalized, StringComparison.OrdinalIgnoreCase) &&
                    targetPrefabs[i].prefab != null)
                {
                    return targetPrefabs[i].prefab;
                }
            }
        }

        return contentPrefab;
    }

    public void SetAnimalAnimationMode(AnimalAnimationMode mode)
    {
        if (mode == AnimalAnimationMode.JumpOrAction && currentAnimationMode == AnimalAnimationMode.JumpOrAction)
        {
            catActionUseAttack = !catActionUseAttack;
        }

        currentAnimationMode = mode;
        if (mode == AnimalAnimationMode.JumpOrAction)
        {
            jumpArcTimer = 0f;
        }

        UpdateAnimationButtonsVisualState();

        foreach (KeyValuePair<TrackableId, GameObject> kvp in content)
        {
            if (kvp.Value != null && kvp.Value.activeSelf)
            {
                ApplyAnimationToAnimalInstance(kvp.Value, currentAnimationMode, true);
            }
        }

        foreach (KeyValuePair<string, GameObject> kvp in simulatedContent)
        {
            if (kvp.Value != null && kvp.Value.activeSelf)
            {
                ApplyAnimationToAnimalInstance(kvp.Value, currentAnimationMode, true);
            }
        }

        string animDisplayName = GetAnimationModeSpanishLabel(mode);
        if (statusDetailText != null && (content.Count > 0 || simulatedTrackingState == TrackingState.Tracking))
        {
            string activeAnimal = !string.IsNullOrEmpty(activeSimulatedTargetName) ? activeSimulatedTargetName : "Animal 3D";
            statusDetailText.text = $"Animación activa en {activeAnimal}: {animDisplayName}";
        }
    }

    private void ApplyAnimationToAnimalInstance(GameObject instance, AnimalAnimationMode mode, bool forceRestart)
    {
        if (instance == null)
            return;

        Animator animator = instance.GetComponentInChildren<Animator>(true);
        if (animator == null)
            return;

        animator.enabled = true;
        animator.cullingMode = AnimatorCullingMode.AlwaysAnimate;
        animator.applyRootMotion = false;

        bool isCat = IsCatInstance(instance, animator);
        string stateName = GetAnimatorStateName(isCat, mode);

        if (forceRestart)
        {
            animator.CrossFadeInFixedTime(stateName, 0.15f, 0, 0f);
        }
        else
        {
            animator.CrossFadeInFixedTime(stateName, 0.18f);
        }
    }

    private void MaintainSelectedAnimalAnimation()
    {
        foreach (KeyValuePair<TrackableId, GameObject> kvp in content)
        {
            if (kvp.Value != null && kvp.Value.activeSelf)
            {
                EnsureAnimatorStaysInState(kvp.Value);
            }
        }

        foreach (KeyValuePair<string, GameObject> kvp in simulatedContent)
        {
            if (kvp.Value != null && kvp.Value.activeSelf)
            {
                EnsureAnimatorStaysInState(kvp.Value);
            }
        }
    }

    private void EnsureAnimatorStaysInState(GameObject instance)
    {
        Animator animator = instance.GetComponentInChildren<Animator>();
        if (animator == null || animator.IsInTransition(0))
            return;

        bool isCat = IsCatInstance(instance, animator);
        string desiredState = GetAnimatorStateName(isCat, currentAnimationMode);

        AnimatorStateInfo stateInfo = animator.GetCurrentAnimatorStateInfo(0);
        if (!stateInfo.IsName(desiredState))
        {
            animator.CrossFadeInFixedTime(desiredState, 0.15f, 0, 0f);
        }
        else if (stateInfo.normalizedTime >= 0.96f && !stateInfo.loop)
        {
            animator.Play(desiredState, 0, 0f);
        }
    }

    private bool IsCatInstance(GameObject instance, Animator animator)
    {
        if (instance.name.IndexOf("Gato", StringComparison.OrdinalIgnoreCase) >= 0 ||
            instance.name.IndexOf("Cat", StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return true;
        }

        if (animator != null && animator.runtimeAnimatorController != null)
        {
            string ctrlName = animator.runtimeAnimatorController.name;
            if (ctrlName.IndexOf("Cat", StringComparison.OrdinalIgnoreCase) >= 0)
                return true;
        }

        return false;
    }

    private string GetAnimatorStateName(bool isCat, AnimalAnimationMode mode)
    {
        if (isCat)
        {
            switch (mode)
            {
                case AnimalAnimationMode.Idle:
                    return "Idle";
                case AnimalAnimationMode.SitOrPlay:
                    return "Sitting_Idle";
                case AnimalAnimationMode.Walk:
                    return "Walk";
                case AnimalAnimationMode.Run:
                    return "Run";
                case AnimalAnimationMode.JumpOrAction:
                    return catActionUseAttack ? "Attack_R" : "Jump";
                default:
                    return "Idle";
            }
        }
        else
        {
            switch (mode)
            {
                case AnimalAnimationMode.Idle:
                    return "1 type_Idle Breathing";
                case AnimalAnimationMode.SitOrPlay:
                    return "1 type_Idle_Playing";
                case AnimalAnimationMode.Walk:
                    return "1 type_Walk_Loop";
                case AnimalAnimationMode.Run:
                    return "1 type_Run Loop";
                case AnimalAnimationMode.JumpOrAction:
                    return "1 type_Run Lean Left";
                default:
                    return "1 type_Idle Breathing";
            }
        }
    }

    private string GetAnimationModeSpanishLabel(AnimalAnimationMode mode)
    {
        switch (mode)
        {
            case AnimalAnimationMode.Idle:
                return "Reposo (Idle)";
            case AnimalAnimationMode.SitOrPlay:
                return "Sentarse / Jugar";
            case AnimalAnimationMode.Walk:
                return "Caminar (Walk)";
            case AnimalAnimationMode.Run:
                return "Correr (Run)";
            case AnimalAnimationMode.JumpOrAction:
                return catActionUseAttack ? "Acción / Zarpazo" : "Saltar / Acción";
            default:
                return "Reposo";
        }
    }

    private void UpdateAnimationButtonsVisualState()
    {
        for (int i = 0; i < animButtonImages.Count; i++)
        {
            if (animButtonImages[i] != null)
            {
                animButtonImages[i].color = (i == (int)currentAnimationMode)
                    ? colorAnimBtnActive
                    : colorAnimBtnIdle;
            }
        }
    }

    private void RefreshOverallStatusFromTrackables()
    {
        if (manager == null)
            return;

        int activeTrackingCount = 0;
        int limitedCount = 0;
        string lastActiveName = string.Empty;
        string lastLimitedName = string.Empty;

        foreach (ARTrackedImage trackedImage in manager.trackables)
        {
            if (trackedImage.trackingState == TrackingState.Tracking)
            {
                activeTrackingCount++;
                lastActiveName = NormalizeTargetName(trackedImage.referenceImage.name);
            }
            else if (trackedImage.trackingState == TrackingState.Limited)
            {
                limitedCount++;
                lastLimitedName = NormalizeTargetName(trackedImage.referenceImage.name);
            }
        }

        if (activeTrackingCount > 0)
        {
            SetBannerState(
                colorTracking,
                $"TRACKING ACTIVO — Imagen detectada: {lastActiveName}",
                $"Mostrando el Prefab 3D del {lastActiveName} ({GetAnimationModeSpanishLabel(currentAnimationMode)})."
            );
        }
        else if (limitedCount > 0)
        {
            SetBannerState(
                colorLimited,
                $"SEGUIMIENTO PERDIDO — Estado: Limited ({lastLimitedName})",
                "La imagen salió de cuadro o fue tapada. Se ocultó el modelo 3D sin destruirlo; volvé a enfocar la foto."
            );
        }
        else
        {
            UpdateStatusUIWaiting();
        }
    }

    public void SimulateTargetDetected(string targetName, Vector3 viewportPos)
    {
        if (arCamera == null)
            return;

        string normalized = NormalizeTargetName(targetName);

        foreach (KeyValuePair<string, GameObject> kvp in simulatedContent)
        {
            if (kvp.Value != null && !string.Equals(kvp.Key, normalized, StringComparison.OrdinalIgnoreCase))
            {
                kvp.Value.SetActive(false);
            }
        }

        if (!simulatedContent.TryGetValue(normalized, out GameObject go) || go == null)
        {
            GameObject prefabToUse = ResolvePrefabForTarget(normalized);
            if (prefabToUse == null)
                return;

            go = Instantiate(prefabToUse);
            go.name = $"Prefab3D_{normalized}";
            EnsureRenderersAndMaterialsValid(go);
            simulatedContent[normalized] = go;
        }

        bool wasAlreadyTrackingThis =
            string.Equals(activeSimulatedTargetName, normalized, StringComparison.OrdinalIgnoreCase) &&
            simulatedTrackingState == TrackingState.Tracking;

        activeSimulatedTargetName = normalized;
        simulatedTrackingState = TrackingState.Tracking;

        Vector3 clampedViewport = new Vector3(
            Mathf.Clamp(viewportPos.x, 0.25f, 0.75f),
            Mathf.Clamp(viewportPos.y, 0.28f, 0.68f),
            0f
        );

        Ray ray = arCamera.ViewportPointToRay(clampedViewport);
        Vector3 targetWorldPos = ray.GetPoint(0.55f);

        if (!wasAlreadyTrackingThis)
        {
            lastSimulatedBaseWorldPos = targetWorldPos;
        }
        else
        {
            lastSimulatedBaseWorldPos = Vector3.Lerp(lastSimulatedBaseWorldPos, targetWorldPos, 0.35f);
        }

        go.transform.position = lastSimulatedBaseWorldPos;

        Vector3 lookDir = arCamera.transform.position - go.transform.position;
        lookDir.y = 0f;
        Quaternion faceCameraRot = lookDir.sqrMagnitude > 0.001f
            ? Quaternion.LookRotation(lookDir.normalized, Vector3.up)
            : Quaternion.Euler(0f, arCamera.transform.eulerAngles.y + 180f, 0f);

        go.transform.rotation = faceCameraRot * Quaternion.Euler(0f, userYawOffsetDegrees, 0f);
        go.transform.localScale = Vector3.one * (userScaleMultiplier * 2.2f);
        go.SetActive(true);

        if (!wasAlreadyTrackingThis)
        {
            ApplyAnimationToAnimalInstance(go, currentAnimationMode, true);
            IncrementDetectionCount(normalized);
        }

        SetBannerState(
            colorTracking,
            $"TRACKING ACTIVO — Imagen detectada: {normalized.ToUpperInvariant()}",
            $"Prefab 3D '{go.name}' activo | Animación: {GetAnimationModeSpanishLabel(currentAnimationMode)}"
        );
    }

    public void SimulateTargetLostLimited()
    {
        if (string.IsNullOrEmpty(activeSimulatedTargetName))
        {
            SetBannerState(
                colorLimited,
                "SEGUIMIENTO PERDIDO — Estado: Limited",
                "Imagen fuera de cuadro. El modelo 3D se oculta con SetActive(false) sin destruirse."
            );
            return;
        }

        if (simulatedContent.TryGetValue(activeSimulatedTargetName, out GameObject go) && go != null)
        {
            go.SetActive(false);
        }

        simulatedTrackingState = TrackingState.Limited;
        SetBannerState(
            colorLimited,
            $"SEGUIMIENTO PERDIDO (Limited) — Target: {activeSimulatedTargetName}",
            "El modelo 3D permanece en memoria listo para reaparecer apenas vuelvas a enfocar la foto."
        );
    }

    private void LoadReferenceTexturesAndBuildGrids()
    {
#if UNITY_EDITOR
        dogPreviewTex = UnityEditor.AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/AR/Images/TarjetaLaboratorio_A.png");
        catPreviewTex = UnityEditor.AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/AR/Images/TarjetaLaboratorio_B.png");
#endif
        if (dogPreviewTex == null && manager != null && manager.referenceLibrary != null && manager.referenceLibrary.count > 0)
        {
            dogPreviewTex = manager.referenceLibrary[0].texture;
        }
        if (catPreviewTex == null && manager != null && manager.referenceLibrary != null && manager.referenceLibrary.count > 1)
        {
            catPreviewTex = manager.referenceLibrary[1].texture;
        }

        if (dogPreviewTex != null && dogPreviewTex.isReadable)
        {
            dogRefGrid = BuildNormalizedGridFromTexture(dogPreviewTex);
        }
        if (catPreviewTex != null && catPreviewTex.isReadable)
        {
            catRefGrid = BuildNormalizedGridFromTexture(catPreviewTex);
        }
    }

    private Color[] BuildNormalizedGridFromTexture(Texture2D tex)
    {
        Color[] grid = new Color[GridSize * GridSize];
        int w = tex.width;
        int h = tex.height;

        for (int gy = 0; gy < GridSize; gy++)
        {
            for (int gx = 0; gx < GridSize; gx++)
            {
                float u = (gx + 0.5f) / GridSize;
                float v = (gy + 0.5f) / GridSize;
                int px = Mathf.Clamp(Mathf.RoundToInt(u * (w - 1)), 0, w - 1);
                int py = Mathf.Clamp(Mathf.RoundToInt(v * (h - 1)), 0, h - 1);
                grid[gy * GridSize + gx] = tex.GetPixel(px, py);
            }
        }

        return grid;
    }

    private void RunOpticalWebcamTargetCheck()
    {
        if (previewModalPanel != null && previewModalPanel.activeSelf)
            return;

        RawImage rawImg = FindFirstObjectByType<RawImage>();
        if (rawImg == null || !(rawImg.texture is WebCamTexture webCam) || !webCam.isPlaying || webCam.width < 64)
            return;

        int w = webCam.width;
        int h = webCam.height;

        int xMin = w / 5;
        int xMax = (w * 4) / 5;
        int yMin = h / 5;
        int yMax = (h * 4) / 5;

        int stepX = Mathf.Max(6, (xMax - xMin) / 24);
        int stepY = Mathf.Max(6, (yMax - yMin) / 24);

        int totalSamples = 0;
        int brightBgCount = 0;
        int warmGoldenFurCount = 0;
        int darkMuzzleBackCount = 0;
        int coolGraySkyCount = 0;
        int tabbyMutedFurCount = 0;

        float sumSubjectX = 0f;
        float sumSubjectY = 0f;
        int subjectSamples = 0;

        float minLuma = 1f;
        float maxLuma = 0f;

        for (int y = yMin; y < yMax; y += stepY)
        {
            for (int x = xMin; x < xMax; x += stepX)
            {
                Color c = webCam.GetPixel(x, y);
                float u = (float)x / w;
                float v = (float)y / h;
                float luma = 0.299f * c.r + 0.587f * c.g + 0.114f * c.b;
                float maxCh = Mathf.Max(c.r, Mathf.Max(c.g, c.b));
                float minCh = Mathf.Min(c.r, Mathf.Min(c.g, c.b));
                float sat = maxCh > 0.01f ? (maxCh - minCh) / maxCh : 0f;

                totalSamples++;
                if (luma < minLuma) minLuma = luma;
                if (luma > maxLuma) maxLuma = luma;

                if (luma > 0.76f && sat < 0.16f)
                {
                    brightBgCount++;
                }
                else if (luma > 0.52f && luma <= 0.84f && c.b >= c.r - 0.03f && sat < 0.24f)
                {
                    coolGraySkyCount++;
                }

                if (luma > 0.22f && luma < 0.75f && c.r > c.g + 0.06f && (c.r - c.b) > 0.16f && sat > 0.25f)
                {
                    warmGoldenFurCount++;
                    sumSubjectX += u;
                    sumSubjectY += v;
                    subjectSamples++;
                }
                else if (luma < 0.22f)
                {
                    darkMuzzleBackCount++;
                    sumSubjectX += u;
                    sumSubjectY += v;
                    subjectSamples++;
                }
                else if (luma >= 0.22f && luma <= 0.58f && (c.r - c.b) >= 0.02f && (c.r - c.b) <= 0.16f && sat >= 0.06f && sat <= 0.28f)
                {
                    tabbyMutedFurCount++;
                    sumSubjectX += u;
                    sumSubjectY += v;
                    subjectSamples++;
                }
            }
        }

        if (totalSamples == 0)
            return;

        float contrastRange = maxLuma - minLuma;
        float brightRatio = (float)brightBgCount / totalSamples;
        float coolSkyRatio = (float)coolGraySkyCount / totalSamples;
        float warmFurRatio = (float)warmGoldenFurCount / totalSamples;
        float darkRatio = (float)darkMuzzleBackCount / totalSamples;
        float tabbyFurRatio = (float)tabbyMutedFurCount / totalSamples;

        float dogTemplateScore = CompareCenterCropWithReferenceGrid(webCam, dogRefGrid);
        float catTemplateScore = CompareCenterCropWithReferenceGrid(webCam, catRefGrid);

        float dogScore =
            (brightRatio * 1.4f) +
            (warmFurRatio * 2.5f) +
            (darkRatio * 1.1f) +
            (dogTemplateScore * 1.2f);

        float catScore =
            (coolSkyRatio * 1.5f) +
            (tabbyFurRatio * 2.2f) +
            (catTemplateScore * 1.2f);

        bool hasEnoughContrastForTarget = contrastRange > 0.42f && (brightRatio + coolSkyRatio) > 0.14f && (warmFurRatio + tabbyFurRatio + darkRatio) > 0.14f;

        if (hasEnoughContrastForTarget)
        {
            Vector3 centroid = subjectSamples > 0
                ? new Vector3(sumSubjectX / subjectSamples, sumSubjectY / subjectSamples, 0f)
                : new Vector3(0.5f, 0.5f, 0f);

            bool isDog = (warmFurRatio >= 0.07f && brightRatio >= 0.15f && dogScore >= catScore * 0.92f) ||
                         (dogTemplateScore > catTemplateScore + 0.06f && warmFurRatio >= 0.04f);

            bool isCat = !isDog &&
                         ((tabbyFurRatio >= 0.12f && (coolSkyRatio + brightRatio) >= 0.14f) ||
                          (catTemplateScore > dogTemplateScore + 0.04f && tabbyFurRatio >= 0.08f));

            if (isDog)
            {
                consecutiveDogMatches++;
                consecutiveCatMatches = 0;
                consecutiveNoMatches = 0;

                if (consecutiveDogMatches >= 2)
                {
                    SimulateTargetDetected(DogTargetName, centroid);
                }
                return;
            }

            if (isCat)
            {
                consecutiveCatMatches++;
                consecutiveDogMatches = 0;
                consecutiveNoMatches = 0;

                if (consecutiveCatMatches >= 2)
                {
                    SimulateTargetDetected(CatTargetName, centroid);
                }
                return;
            }
        }

        consecutiveDogMatches = 0;
        consecutiveCatMatches = 0;
        consecutiveNoMatches++;

        if (simulatedTrackingState == TrackingState.Tracking && consecutiveNoMatches >= 6)
        {
            SimulateTargetLostLimited();
        }
    }

    private float CompareCenterCropWithReferenceGrid(WebCamTexture webCam, Color[] refGrid)
    {
        if (refGrid == null || refGrid.Length != GridSize * GridSize)
            return 0f;

        int w = webCam.width;
        int h = webCam.height;

        int cropSize = Mathf.RoundToInt(Mathf.Min(w, h) * 0.55f);
        int startX = (w - cropSize) / 2;
        int startY = (h - cropSize) / 2;

        float totalDiff = 0f;

        for (int gy = 0; gy < GridSize; gy++)
        {
            for (int gx = 0; gx < GridSize; gx++)
            {
                float u = (gx + 0.5f) / GridSize;
                float v = (gy + 0.5f) / GridSize;
                int px = Mathf.Clamp(startX + Mathf.RoundToInt(u * cropSize), 0, w - 1);
                int py = Mathf.Clamp(startY + Mathf.RoundToInt(v * cropSize), 0, h - 1);

                Color camCol = webCam.GetPixel(px, py);
                Color refCol = refGrid[gy * GridSize + gx];

                float dr = Mathf.Abs(camCol.r - refCol.r);
                float dg = Mathf.Abs(camCol.g - refCol.g);
                float db = Mathf.Abs(camCol.b - refCol.b);
                totalDiff += (dr + dg + db) / 3f;
            }
        }

        float meanDiff = totalDiff / (GridSize * GridSize);
        return Mathf.Clamp01(1f - meanDiff * 2.0f);
    }

    private void AnimateAndTransformActiveContent()
    {
        if (autoSpinContent)
        {
            userYawOffsetDegrees = (userYawOffsetDegrees + 35f * Time.deltaTime) % 360f;
        }

        float jumpOffsetY = 0f;
        if (jumpArcTimer >= 0f)
        {
            jumpArcTimer += Time.deltaTime;
            if (jumpArcTimer <= JumpArcDuration)
            {
                float t = jumpArcTimer / JumpArcDuration;
                jumpOffsetY = Mathf.Sin(t * Mathf.PI) * 0.08f;
            }
            else
            {
                jumpArcTimer = -1f;
            }
        }

        foreach (KeyValuePair<TrackableId, GameObject> kvp in content)
        {
            if (kvp.Value != null && kvp.Value.activeSelf)
            {
                kvp.Value.transform.localPosition = new Vector3(0f, jumpOffsetY, 0f);
                kvp.Value.transform.localScale = Vector3.one * userScaleMultiplier;
                kvp.Value.transform.localRotation = Quaternion.Euler(0f, userYawOffsetDegrees, 0f);
            }
        }

        foreach (KeyValuePair<string, GameObject> kvp in simulatedContent)
        {
            if (kvp.Value != null && kvp.Value.activeSelf)
            {
                kvp.Value.transform.position = lastSimulatedBaseWorldPos + new Vector3(0f, jumpOffsetY * 1.5f, 0f);
                kvp.Value.transform.localScale = Vector3.one * (userScaleMultiplier * 2.2f);
                if (arCamera != null)
                {
                    Vector3 lookDir = arCamera.transform.position - kvp.Value.transform.position;
                    lookDir.y = 0f;
                    Quaternion faceCameraRot = lookDir.sqrMagnitude > 0.001f
                        ? Quaternion.LookRotation(lookDir.normalized, Vector3.up)
                        : Quaternion.Euler(0f, arCamera.transform.eulerAngles.y + 180f, 0f);

                    kvp.Value.transform.rotation = faceCameraRot * Quaternion.Euler(0f, userYawOffsetDegrees, 0f);
                }
            }
        }
    }

    private void EnsureRenderersAndMaterialsValid(GameObject instance)
    {
        if (instance == null)
            return;

        LODGroup[] lodGroups = instance.GetComponentsInChildren<LODGroup>(true);
        for (int i = 0; i < lodGroups.Length; i++)
        {
            lodGroups[i].enabled = false;
        }

        Shader urpLit = Shader.Find("Universal Render Pipeline/Lit");
        if (urpLit == null)
        {
            urpLit = Shader.Find("Universal Render Pipeline/Simple Lit");
        }

#if UNITY_EDITOR
        Texture2D fallbackDogAlbedo = UnityEditor.AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/RSG_DogsPack/HDRP/Textures/T_GermanShepherd_B.png");
        Texture2D fallbackDogNormal = UnityEditor.AssetDatabase.LoadAssetAtPath<Texture2D>("Assets/RSG_DogsPack/HDRP/Textures/T_GermanShepherd_N.png");
#else
        Texture2D fallbackDogAlbedo = null;
        Texture2D fallbackDogNormal = null;
#endif

        Renderer[] renderers = instance.GetComponentsInChildren<Renderer>(true);
        for (int i = 0; i < renderers.Length; i++)
        {
            Renderer r = renderers[i];
            r.enabled = true;
            Material[] mats = r.sharedMaterials;
            bool modified = false;

            for (int m = 0; m < mats.Length; m++)
            {
                Material mat = mats[m];
                if (mat == null)
                    continue;

                bool needsUpgrade = mat.shader == null ||
                                    !mat.shader.isSupported ||
                                    mat.shader.name.IndexOf("HDRP", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                    mat.shader.name.IndexOf("Error", StringComparison.OrdinalIgnoreCase) >= 0;

                if (needsUpgrade && urpLit != null)
                {
                    Texture baseTex = mat.HasProperty("_BaseColorMap") ? mat.GetTexture("_BaseColorMap") : null;
                    if (baseTex == null && mat.HasProperty("_BaseMap")) baseTex = mat.GetTexture("_BaseMap");
                    if (baseTex == null && mat.HasProperty("_MainTex")) baseTex = mat.GetTexture("_MainTex");
                    if (baseTex == null) baseTex = fallbackDogAlbedo;

                    Texture normalTex = mat.HasProperty("_NormalMap") ? mat.GetTexture("_NormalMap") : null;
                    if (normalTex == null && mat.HasProperty("_BumpMap")) normalTex = mat.GetTexture("_BumpMap");
                    if (normalTex == null) normalTex = fallbackDogNormal;

                    bool isTransparentMat = mat.name.IndexOf("Transparent", StringComparison.OrdinalIgnoreCase) >= 0;

                    Material runtimeUrpMat = new Material(urpLit)
                    {
                        name = mat.name + "_URP_Runtime"
                    };

                    runtimeUrpMat.SetColor("_BaseColor", Color.white);
                    runtimeUrpMat.SetColor("_Color", Color.white);
                    runtimeUrpMat.SetFloat("_Smoothness", 0.25f);
                    runtimeUrpMat.SetFloat("_Metallic", 0f);

                    if (baseTex != null)
                    {
                        runtimeUrpMat.SetTexture("_BaseMap", baseTex);
                        runtimeUrpMat.SetTexture("_MainTex", baseTex);
                    }

                    if (normalTex != null)
                    {
                        runtimeUrpMat.SetTexture("_BumpMap", normalTex);
                        runtimeUrpMat.EnableKeyword("_NORMALMAP");
                    }

                    if (isTransparentMat)
                    {
                        runtimeUrpMat.SetFloat("_AlphaClip", 1f);
                        runtimeUrpMat.SetFloat("_Cutoff", 0.15f);
                        runtimeUrpMat.SetFloat("_Cull", 0f);
                        runtimeUrpMat.EnableKeyword("_ALPHATEST_ON");
                    }

                    mats[m] = runtimeUrpMat;
                    modified = true;
                }
            }

            if (modified)
            {
                r.sharedMaterials = mats;
            }
        }
    }

    private void EnsureDefaultPrefabsIfEmpty()
    {
        if (targetPrefabs == null)
        {
            targetPrefabs = new List<NamedTargetPrefab>();
        }

#if UNITY_EDITOR
        GameObject dogAsset = UnityEditor.AssetDatabase.LoadAssetAtPath<GameObject>("Assets/AR/Prefabs/ContentOnTarget.prefab");
        GameObject catAsset = UnityEditor.AssetDatabase.LoadAssetAtPath<GameObject>("Assets/AR/Prefabs/ContentOnTarget_B.prefab");

        if (dogAsset == null || dogAsset.transform.Find("Mesh_5cm") != null)
        {
            GameObject rawDog = UnityEditor.AssetDatabase.LoadAssetAtPath<GameObject>("Assets/RSG_DogsPack/HDRP/Prefabs/P_GermanShepherd.prefab");
            if (rawDog != null)
            {
                dogAsset = CreateNormalizedRuntimeAnimalWrapper(rawDog, "RuntimeWrapper_Perro", 0.13f);
            }
        }

        if (catAsset == null || catAsset.transform.Find("Mesh_5cm") != null)
        {
            GameObject rawCat = UnityEditor.AssetDatabase.LoadAssetAtPath<GameObject>("Assets/Realistic Cat Demo/Prefabs/URP/Mobile/Cat_05.prefab");
            if (rawCat != null)
            {
                catAsset = CreateNormalizedRuntimeAnimalWrapper(rawCat, "RuntimeWrapper_Gato", 0.12f);
            }
        }

        if (dogAsset != null && catAsset != null)
        {
            contentPrefab = dogAsset;
            targetPrefabs.Clear();
            targetPrefabs.Add(new NamedTargetPrefab { referenceImageName = DogTargetName, prefab = dogAsset });
            targetPrefabs.Add(new NamedTargetPrefab { referenceImageName = CatTargetName, prefab = catAsset });
        }
#endif
    }

    private GameObject CreateNormalizedRuntimeAnimalWrapper(GameObject sourcePrefab, string wrapperName, float desiredHeightMeters)
    {
        GameObject wrapper = new GameObject(wrapperName);
        wrapper.transform.position = Vector3.zero;
        wrapper.transform.rotation = Quaternion.identity;
        wrapper.transform.localScale = Vector3.one;

        GameObject child = Instantiate(sourcePrefab, wrapper.transform);
        child.name = sourcePrefab.name;
        child.transform.localPosition = Vector3.zero;
        child.transform.localRotation = Quaternion.identity;
        child.transform.localScale = Vector3.one;

        EnsureRenderersAndMaterialsValid(child);

        Renderer[] renderers = child.GetComponentsInChildren<Renderer>(true);
        if (renderers.Length > 0)
        {
            Bounds b = renderers[0].bounds;
            for (int i = 1; i < renderers.Length; i++)
            {
                b.Encapsulate(renderers[i].bounds);
            }

            float h = Mathf.Max(0.05f, b.size.y);
            float scale = desiredHeightMeters / h;
            child.transform.localScale = Vector3.one * scale;
        }

        wrapper.transform.SetParent(transform, false);
        wrapper.SetActive(false);
        return wrapper;
    }

    private void UpdateStatusUIWaiting()
    {
        SetBannerState(
            colorWaiting,
            "ESPERANDO IMAGEN — Apuntá la cámara a la foto del Perro o del Gato",
            "Enfocá la imagen del Pastor Alemán o la del Gato para que salte su Prefab 3D animado."
        );
    }

    private void SetBannerState(Color bgColor, string title, string detail)
    {
        if (bannerBackground != null)
        {
            bannerBackground.color = bgColor;
        }

        if (statusTitleText != null)
        {
            statusTitleText.text = title;
        }

        if (statusDetailText != null)
        {
            statusDetailText.text = detail;
        }
    }

    private void RefreshCountersUI()
    {
        if (countersText == null)
            return;

        detectionCounts.TryGetValue(DogTargetName, out int countDog);
        detectionCounts.TryGetValue(CatTargetName, out int countCat);

        countersText.text =
            $"<b>Contador de Detecciones:</b>   Imagen Perro (Pastor Alemán 3D): <b>{countDog}</b>   |   Imagen Gato (Gato 3D): <b>{countCat}</b>";
    }

    private void BuildImageTrackingUI()
    {
        ARPrototypeUIManager oldHud = FindFirstObjectByType<ARPrototypeUIManager>();
        if (oldHud != null)
        {
            oldHud.gameObject.SetActive(false);
        }

        GameObject canvasGo = new GameObject("ImageTargetLab_UI_Canvas");
        canvasGo.transform.SetParent(transform, false);

        statusCanvas = canvasGo.AddComponent<Canvas>();
        statusCanvas.renderMode = RenderMode.ScreenSpaceOverlay;
        statusCanvas.sortingOrder = 100;

        CanvasScaler scaler = canvasGo.AddComponent<CanvasScaler>();
        scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
        scaler.referenceResolution = new Vector2(1080f, 1920f);
        scaler.matchWidthOrHeight = 0f;

        canvasGo.AddComponent<GraphicRaycaster>();

        GameObject topBanner = CreatePanel(
            "TrackingStatusBanner",
            canvasGo.transform,
            new Vector2(0.5f, 1f),
            new Vector2(0.5f, 1f),
            new Vector2(0.5f, 1f),
            new Vector2(0f, -20f),
            new Vector2(1040f, 225f),
            colorWaiting,
            out bannerBackground
        );

        VerticalLayoutGroup topLayout = topBanner.AddComponent<VerticalLayoutGroup>();
        topLayout.padding = new RectOffset(24, 24, 16, 16);
        topLayout.spacing = 8f;
        topLayout.childAlignment = TextAnchor.MiddleCenter;
        topLayout.childControlWidth = true;
        topLayout.childControlHeight = true;
        topLayout.childForceExpandWidth = true;

        statusTitleText = CreateText("StatusTitle", topBanner.transform, "ESPERANDO IMAGEN...", 30, FontStyle.Bold, TextAnchor.MiddleCenter);
        statusDetailText = CreateText("StatusDetail", topBanner.transform, "Apuntá la cámara a la foto del Perro o del Gato", 24, FontStyle.Bold, TextAnchor.MiddleCenter);
        countersText = CreateText("CountersText", topBanner.transform, "Contador de Detecciones: Perro: 0 | Gato: 0", 23, FontStyle.Bold, TextAnchor.MiddleCenter);

        GameObject bottomPanel = CreatePanel(
            "BottomControlsPanel",
            canvasGo.transform,
            new Vector2(0.5f, 0f),
            new Vector2(0.5f, 0f),
            new Vector2(0.5f, 0f),
            new Vector2(0f, 20f),
            new Vector2(1040f, 410f),
            new Color(0.06f, 0.08f, 0.12f, 0.95f),
            out _
        );

        VerticalLayoutGroup bottomLayout = bottomPanel.AddComponent<VerticalLayoutGroup>();
        bottomLayout.padding = new RectOffset(20, 20, 16, 16);
        bottomLayout.spacing = 12f;
        bottomLayout.childAlignment = TextAnchor.MiddleCenter;
        bottomLayout.childControlWidth = true;
        bottomLayout.childControlHeight = true;
        bottomLayout.childForceExpandWidth = true;

        GameObject animRow = CreateRow("AnimSelectorRow", bottomPanel.transform, 10f, 72f);
        animButtonImages.Clear();

        Button idleBtn = CreateButton("AnimIdleBtn", animRow.transform, "Reposo", colorAnimBtnActive, out _, out Image idleImg);
        animButtonImages.Add(idleImg);
        idleBtn.onClick.AddListener(() => SetAnimalAnimationMode(AnimalAnimationMode.Idle));

        Button sitPlayBtn = CreateButton("AnimSitPlayBtn", animRow.transform, "Sentarse/Jugar", colorAnimBtnIdle, out _, out Image sitPlayImg);
        animButtonImages.Add(sitPlayImg);
        sitPlayBtn.onClick.AddListener(() => SetAnimalAnimationMode(AnimalAnimationMode.SitOrPlay));

        Button walkBtn = CreateButton("AnimWalkBtn", animRow.transform, "Caminar", colorAnimBtnIdle, out _, out Image walkImg);
        animButtonImages.Add(walkImg);
        walkBtn.onClick.AddListener(() => SetAnimalAnimationMode(AnimalAnimationMode.Walk));

        Button runBtn = CreateButton("AnimRunBtn", animRow.transform, "Correr", colorAnimBtnIdle, out _, out Image runImg);
        animButtonImages.Add(runImg);
        runBtn.onClick.AddListener(() => SetAnimalAnimationMode(AnimalAnimationMode.Run));

        Button jumpActionBtn = CreateButton("AnimJumpBtn", animRow.transform, "Saltar/Acción", colorAnimBtnIdle, out _, out Image jumpImg);
        animButtonImages.Add(jumpImg);
        jumpActionBtn.onClick.AddListener(() => SetAnimalAnimationMode(AnimalAnimationMode.JumpOrAction));

        GameObject transformRow = CreateRow("TransformRow", bottomPanel.transform, 12f, 68f);
        scaleLabelText = CreateText("ScaleLabel", transformRow.transform, "Escala: 1.00x", 24, FontStyle.Bold, TextAnchor.MiddleCenter);

        Button scaleDownBtn = CreateButton("ScaleDownBtn", transformRow.transform, "Achicar -", new Color(0.22f, 0.26f, 0.34f, 1f), out _, out _);
        scaleDownBtn.onClick.AddListener(() => SetUserScale(userScaleMultiplier - 0.2f));

        Button scaleUpBtn = CreateButton("ScaleUpBtn", transformRow.transform, "Agrandar +", new Color(0.22f, 0.26f, 0.34f, 1f), out _, out _);
        scaleUpBtn.onClick.AddListener(() => SetUserScale(userScaleMultiplier + 0.2f));

        Button rotLeftBtn = CreateButton("RotLeftBtn", transformRow.transform, "Girar -35°", new Color(0.22f, 0.26f, 0.34f, 1f), out _, out _);
        rotLeftBtn.onClick.AddListener(() =>
        {
            autoSpinContent = false;
            userYawOffsetDegrees -= rotationStepDegrees;
        });

        Button rotRightBtn = CreateButton("RotRightBtn", transformRow.transform, "Girar +35°", new Color(0.22f, 0.26f, 0.34f, 1f), out _, out _);
        rotRightBtn.onClick.AddListener(() =>
        {
            autoSpinContent = false;
            userYawOffsetDegrees += rotationStepDegrees;
        });

        GameObject cameraRow = CreateRow("CameraRow", bottomPanel.transform, 12f, 68f);

        Button camBtn = CreateButton("LiveCamBtn", cameraRow.transform, "Activar Cámara iPhone (Iriun)", new Color(0.16f, 0.58f, 0.96f, 1f), out Text camBtnLabel, out _);
        camBtn.onClick.AddListener(() =>
        {
            if (liveCameraFeed != null)
            {
                liveCameraFeed.ToggleOrCycleLiveCamera();
                camBtnLabel.text = liveCameraFeed.IsLiveFeedActive
                    ? $"Cámara Activa: {liveCameraFeed.ActiveDeviceName}"
                    : "Activar Cámara iPhone (Iriun)";
            }
        });

        Button showCardsBtn = CreateButton("ShowCardsBtn", cameraRow.transform, "Ver Fotos (Perro y Gato)", new Color(0.28f, 0.52f, 0.32f, 1f), out _, out _);
        showCardsBtn.onClick.AddListener(() =>
        {
            if (previewModalPanel != null)
            {
                previewModalPanel.SetActive(!previewModalPanel.activeSelf);
            }
        });

        GameObject testRow = CreateRow("TestRow", bottomPanel.transform, 12f, 68f);

        Button testDogBtn = CreateButton("DetectDogBtn", testRow.transform, "Escanear Perro", new Color(0.76f, 0.48f, 0.16f, 1f), out _, out _);
        testDogBtn.onClick.AddListener(() => SimulateTargetDetected(DogTargetName, new Vector3(0.5f, 0.45f, 0f)));

        Button testCatBtn = CreateButton("DetectCatBtn", testRow.transform, "Escanear Gato", new Color(0.20f, 0.55f, 0.68f, 1f), out _, out _);
        testCatBtn.onClick.AddListener(() => SimulateTargetDetected(CatTargetName, new Vector3(0.5f, 0.45f, 0f)));

        Button lostBtn = CreateButton("SimulateLostBtn", testRow.transform, "Quitar Imagen (Limited)", colorLimited, out _, out _);
        lostBtn.onClick.AddListener(SimulateTargetLostLimited);

        BuildTargetCardsPreviewModal(canvasGo.transform);
    }

    private void BuildTargetCardsPreviewModal(Transform canvasTransform)
    {
        previewModalPanel = CreatePanel(
            "TargetCardsPreviewModal",
            canvasTransform,
            new Vector2(0.5f, 0.5f),
            new Vector2(0.5f, 0.5f),
            new Vector2(0.5f, 0.5f),
            new Vector2(0f, 30f),
            new Vector2(920f, 580f),
            new Color(0.06f, 0.08f, 0.12f, 0.96f),
            out _
        );

        VerticalLayoutGroup vLayout = previewModalPanel.AddComponent<VerticalLayoutGroup>();
        vLayout.padding = new RectOffset(24, 24, 20, 20);
        vLayout.spacing = 14f;
        vLayout.childAlignment = TextAnchor.MiddleCenter;
        vLayout.childControlWidth = true;
        vLayout.childControlHeight = true;

        CreateText(
            "ModalTitle",
            previewModalPanel.transform,
            "IMÁGENES TARGET CONFIGURADAS EN TARGETSLIBRARY\nApuntá con la cámara a la foto del Perro o del Gato para que salte su Prefab 3D:",
            20,
            FontStyle.Bold,
            TextAnchor.MiddleCenter
        );

        GameObject cardsRow = CreateRow("CardsImagesRow", previewModalPanel.transform, 30f, 360f);

        CreateTargetCardPreview(cardsRow.transform, dogPreviewTex, "Assets/AR/Images/TarjetaLaboratorio_A.png", "Target 1: PERRO → Prefab Pastor Alemán", new Color(0.85f, 0.62f, 0.32f));
        CreateTargetCardPreview(cardsRow.transform, catPreviewTex, "Assets/AR/Images/TarjetaLaboratorio_B.png", "Target 2: GATO → Prefab Gato Realista", new Color(0.55f, 0.62f, 0.68f));

        Button closeBtn = CreateButton("CloseModalBtn", previewModalPanel.transform, "Cerrar Vista de Fotos", new Color(0.75f, 0.22f, 0.25f, 1f), out _, out _);
        LayoutElement closeLayout = closeBtn.gameObject.AddComponent<LayoutElement>();
        closeLayout.preferredHeight = 52f;
        closeBtn.onClick.AddListener(() => previewModalPanel.SetActive(false));

        previewModalPanel.SetActive(false);
    }

    private void CreateTargetCardPreview(Transform parent, Texture2D preloadedTex, string assetPath, string caption, Color fallbackTint)
    {
        GameObject col = new GameObject(caption);
        col.transform.SetParent(parent, false);
        col.AddComponent<RectTransform>();

        VerticalLayoutGroup layout = col.AddComponent<VerticalLayoutGroup>();
        layout.spacing = 8f;
        layout.childAlignment = TextAnchor.MiddleCenter;
        layout.childControlWidth = true;
        layout.childControlHeight = true;

        GameObject rawGo = new GameObject("TargetTexture");
        rawGo.transform.SetParent(col.transform, false);
        rawGo.AddComponent<RectTransform>();
        RawImage raw = rawGo.AddComponent<RawImage>();
        LayoutElement le = rawGo.AddComponent<LayoutElement>();
        le.preferredWidth = 310f;
        le.preferredHeight = 310f;

        Texture2D tex = preloadedTex;
#if UNITY_EDITOR
        if (tex == null)
        {
            tex = UnityEditor.AssetDatabase.LoadAssetAtPath<Texture2D>(assetPath);
        }
#endif
        if (tex != null)
        {
            raw.texture = tex;
        }
        else
        {
            raw.color = fallbackTint;
        }

        CreateText("Caption", col.transform, caption, 18, FontStyle.Bold, TextAnchor.MiddleCenter);
    }

    private void SetUserScale(float newScale)
    {
        userScaleMultiplier = Mathf.Clamp(newScale, minContentScale, maxContentScale);
        if (scaleLabelText != null)
        {
            scaleLabelText.text = $"Escala Modelo: {userScaleMultiplier:F2}x";
        }
    }

    private GameObject CreatePanel(
        string name,
        Transform parent,
        Vector2 anchorMin,
        Vector2 anchorMax,
        Vector2 pivot,
        Vector2 anchoredPos,
        Vector2 sizeDelta,
        Color color,
        out Image bgImage)
    {
        GameObject go = new GameObject(name);
        go.transform.SetParent(parent, false);
        RectTransform rect = go.AddComponent<RectTransform>();
        rect.anchorMin = anchorMin;
        rect.anchorMax = anchorMax;
        rect.pivot = pivot;
        rect.anchoredPosition = anchoredPos;
        rect.sizeDelta = sizeDelta;

        bgImage = go.AddComponent<Image>();
        bgImage.color = color;
        return go;
    }

    private GameObject CreateRow(string name, Transform parent, float spacing, float height)
    {
        GameObject row = new GameObject(name);
        row.transform.SetParent(parent, false);
        row.AddComponent<RectTransform>();

        HorizontalLayoutGroup hl = row.AddComponent<HorizontalLayoutGroup>();
        hl.spacing = spacing;
        hl.childAlignment = TextAnchor.MiddleCenter;
        hl.childControlWidth = true;
        hl.childControlHeight = true;
        hl.childForceExpandWidth = true;
        hl.childForceExpandHeight = true;

        LayoutElement le = row.AddComponent<LayoutElement>();
        le.preferredHeight = height;
        return row;
    }

    private Text CreateText(string name, Transform parent, string contentText, int fontSize, FontStyle style, TextAnchor align)
    {
        GameObject go = new GameObject(name);
        go.transform.SetParent(parent, false);
        go.AddComponent<RectTransform>();

        Text t = go.AddComponent<Text>();
        t.font = uiFont;
        t.text = contentText;
        t.fontSize = fontSize;
        t.fontStyle = style;
        t.alignment = align;
        t.color = Color.white;
        t.supportRichText = true;
        t.resizeTextForBestFit = true;
        t.resizeTextMinSize = 18;
        t.resizeTextMaxSize = fontSize + 4;

        Outline outline = go.AddComponent<Outline>();
        outline.effectColor = new Color(0f, 0f, 0f, 0.85f);
        outline.effectDistance = new Vector2(1.5f, -1.5f);

        return t;
    }

    private Button CreateButton(string name, Transform parent, string label, Color bgColor, out Text labelOut, out Image imgOut)
    {
        GameObject go = new GameObject(name);
        go.transform.SetParent(parent, false);
        go.AddComponent<RectTransform>();

        imgOut = go.AddComponent<Image>();
        imgOut.color = bgColor;

        Button btn = go.AddComponent<Button>();
        btn.targetGraphic = imgOut;

        labelOut = CreateText("Label", go.transform, label, 24, FontStyle.Bold, TextAnchor.MiddleCenter);
        RectTransform lRect = labelOut.GetComponent<RectTransform>();
        lRect.anchorMin = Vector2.zero;
        lRect.anchorMax = Vector2.one;
        lRect.offsetMin = new Vector2(8f, 4f);
        lRect.offsetMax = new Vector2(-8f, -4f);

        return btn;
    }
}
