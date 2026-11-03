using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.XR.ARSubsystems;

namespace RealidadAumentada.Prototype
{
    public class ARPrototypeUIManager : MonoBehaviour
    {
        [SerializeField]
        private ARPlaneTrackerController planeTracker;

        [SerializeField]
        private ARObjectInteractionController interactionController;

        [SerializeField]
        private ARLiveCameraFeedController liveCameraController;

        [SerializeField]
        private bool autoBuildRuntimeHUD = true;

        [SerializeField]
        private Color panelBackgroundColor = new Color(0.08f, 0.10f, 0.14f, 0.86f);

        [SerializeField]
        private Color accentColor = new Color(0.16f, 0.58f, 0.96f, 1f);

        [SerializeField]
        private Color neutralButtonColor = new Color(0.20f, 0.24f, 0.30f, 1f);

        [SerializeField]
        private Color dangerButtonColor = new Color(0.82f, 0.24f, 0.26f, 1f);

        private Canvas hudCanvas;
        private Text telemetryLabel;
        private Text planesVisibilityButtonLabel;
        private Image planesVisibilityButtonImage;
        private Text detectionModeButtonLabel;
        private Text liveCameraButtonLabel;
        private Image liveCameraButtonImage;
        private Text shapeSelectorButtonLabel;

        private GameObject objectInspectorPanel;
        private Text selectedObjectTitleLabel;
        private Slider scaleSlider;
        private Text scaleValueLabel;
        private Text autoRotateButtonLabel;
        private Image autoRotateButtonImage;
        private Text floatButtonLabel;
        private Image floatButtonImage;

        private Font defaultFont;
        private bool suppressSliderCallback;

        private void Awake()
        {
            if (planeTracker == null)
            {
                planeTracker = GetComponent<ARPlaneTrackerController>();
                if (planeTracker == null)
                {
                    planeTracker = FindFirstObjectByType<ARPlaneTrackerController>();
                }
            }

            if (interactionController == null)
            {
                interactionController = GetComponent<ARObjectInteractionController>();
                if (interactionController == null)
                {
                    interactionController = FindFirstObjectByType<ARObjectInteractionController>();
                }
            }

            if (liveCameraController == null)
            {
                liveCameraController = GetComponent<ARLiveCameraFeedController>();
                if (liveCameraController == null)
                {
                    liveCameraController = FindFirstObjectByType<ARLiveCameraFeedController>();
                }
            }

            defaultFont = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf");
            if (defaultFont == null)
            {
                defaultFont = Font.CreateDynamicFontFromOSFont("Arial", 16);
            }

            if (autoBuildRuntimeHUD)
            {
                BuildRuntimeHUD();
            }
        }

        private void OnEnable()
        {
            if (planeTracker != null)
            {
                planeTracker.OnPlaneStatsUpdated += HandlePlaneStatsUpdated;
            }

            if (interactionController != null)
            {
                interactionController.OnSelectedObjectChanged += HandleSelectedObjectChanged;
                interactionController.OnSpawnedCountChanged += HandleSpawnedCountChanged;
            }

            if (liveCameraController != null)
            {
                liveCameraController.OnCameraFeedStateChanged += HandleCameraFeedStateChanged;
            }
        }

        private void OnDisable()
        {
            if (planeTracker != null)
            {
                planeTracker.OnPlaneStatsUpdated -= HandlePlaneStatsUpdated;
            }

            if (interactionController != null)
            {
                interactionController.OnSelectedObjectChanged -= HandleSelectedObjectChanged;
                interactionController.OnSpawnedCountChanged -= HandleSpawnedCountChanged;
            }

            if (liveCameraController != null)
            {
                liveCameraController.OnCameraFeedStateChanged -= HandleCameraFeedStateChanged;
            }
        }

        private void Start()
        {
            RefreshTelemetryText();
            if (shapeSelectorButtonLabel != null && interactionController != null)
            {
                shapeSelectorButtonLabel.text = $"Forma: {interactionController.CurrentPrefabDisplayName}";
            }
            if (liveCameraController != null)
            {
                HandleCameraFeedStateChanged(liveCameraController.IsLiveFeedActive, liveCameraController.ActiveDeviceName);
            }
            HandleSelectedObjectChanged(interactionController != null ? interactionController.CurrentSelectedObject : null);
        }

        private void Update()
        {
            if (shapeSelectorButtonLabel != null && interactionController != null)
            {
                string expectedText = $"Forma: {interactionController.CurrentPrefabDisplayName}";
                if (shapeSelectorButtonLabel.text != expectedText)
                {
                    shapeSelectorButtonLabel.text = expectedText;
                }
            }

            if (interactionController != null &&
                interactionController.CurrentSelectedObject != null &&
                scaleSlider != null &&
                objectInspectorPanel != null &&
                objectInspectorPanel.activeSelf)
            {
                float liveScale = interactionController.CurrentSelectedObject.CurrentScaleMultiplier;
                if (Mathf.Abs(scaleSlider.value - liveScale) > 0.01f)
                {
                    suppressSliderCallback = true;
                    scaleSlider.value = liveScale;
                    if (scaleValueLabel != null)
                    {
                        scaleValueLabel.text = $"Escala: {liveScale:F2}x";
                    }
                    suppressSliderCallback = false;
                }
            }
        }

        private void HandlePlaneStatsUpdated(int horizontal, int vertical, float areaSqM, bool visible)
        {
            RefreshTelemetryText();
        }

        private void HandleSpawnedCountChanged(int count)
        {
            RefreshTelemetryText();
        }

        private void HandleCameraFeedStateChanged(bool isActive, string deviceName)
        {
            if (liveCameraButtonLabel != null)
            {
                liveCameraButtonLabel.text = isActive ? $"Cam: {deviceName}" : "Cam: Simulación";
            }

            if (liveCameraButtonImage != null)
            {
                liveCameraButtonImage.color = isActive ? accentColor : neutralButtonColor;
            }
        }

        private void HandleSelectedObjectChanged(ARManipulableObject selected)
        {
            if (objectInspectorPanel == null)
                return;

            bool hasSelection = selected != null;
            objectInspectorPanel.SetActive(hasSelection);

            if (!hasSelection)
                return;

            if (selectedObjectTitleLabel != null)
            {
                selectedObjectTitleLabel.text = $"OBJETO: {selected.DisplayName.ToUpperInvariant()}";
            }

            if (scaleSlider != null)
            {
                suppressSliderCallback = true;
                scaleSlider.minValue = selected.MinScaleMultiplier;
                scaleSlider.maxValue = selected.MaxScaleMultiplier;
                scaleSlider.value = selected.CurrentScaleMultiplier;
                suppressSliderCallback = false;
            }

            if (scaleValueLabel != null)
            {
                scaleValueLabel.text = $"Escala: {selected.CurrentScaleMultiplier:F2}x";
            }

            if (autoRotateButtonLabel != null)
            {
                autoRotateButtonLabel.text = selected.IsAutoRotating ? "Giro Auto: ON" : "Giro Auto: OFF";
            }

            if (autoRotateButtonImage != null)
            {
                autoRotateButtonImage.color = selected.IsAutoRotating ? accentColor : neutralButtonColor;
            }

            if (floatButtonLabel != null)
            {
                floatButtonLabel.text = selected.IsFloating ? "Flotar: ON" : "Flotar: OFF";
            }

            if (floatButtonImage != null)
            {
                floatButtonImage.color = selected.IsFloating ? accentColor : neutralButtonColor;
            }
        }

        private void RefreshTelemetryText()
        {
            int horiz = planeTracker != null ? planeTracker.HorizontalPlanesCount : 0;
            int vert = planeTracker != null ? planeTracker.VerticalPlanesCount : 0;
            float area = planeTracker != null ? planeTracker.TotalAreaSquareMeters : 0f;
            bool visible = planeTracker == null || planeTracker.ArePlanesVisible;
            int objects = interactionController != null ? interactionController.SpawnedObjectsCount : 0;

            if (telemetryLabel != null)
            {
                telemetryLabel.text =
                    $"<b>ESTADO AR</b>  |  Planos H: <b>{horiz}</b>  V: <b>{vert}</b> ({area:F1} m²)  |  Objetos 3D: <b>{objects}</b>";
            }

            if (planesVisibilityButtonLabel != null)
            {
                planesVisibilityButtonLabel.text = visible ? "Planos: ON" : "Planos: OFF";
            }

            if (planesVisibilityButtonImage != null)
            {
                planesVisibilityButtonImage.color = visible ? accentColor : neutralButtonColor;
            }

            if (detectionModeButtonLabel != null && planeTracker != null)
            {
                PlaneDetectionMode mode = planeTracker.CurrentDetectionMode;
                string modeText = "Ambos";
                if (mode == PlaneDetectionMode.Horizontal)
                    modeText = "Horiz.";
                else if (mode == PlaneDetectionMode.Vertical)
                    modeText = "Vert.";

                detectionModeButtonLabel.text = $"Detectar: {modeText}";
            }
        }

        private void BuildRuntimeHUD()
        {
            GameObject canvasGo = new GameObject("ARPrototype_HUD_Canvas");
            canvasGo.transform.SetParent(transform, false);

            hudCanvas = canvasGo.AddComponent<Canvas>();
            hudCanvas.renderMode = RenderMode.ScreenSpaceOverlay;
            hudCanvas.sortingOrder = 50;

            CanvasScaler scaler = canvasGo.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1080f, 1920f);
            scaler.matchWidthOrHeight = 0f;

            canvasGo.AddComponent<GraphicRaycaster>();

            BuildTopTelemetryBar(canvasGo.transform);
            BuildObjectInspectorPanel(canvasGo.transform);
        }

        private void BuildTopTelemetryBar(Transform canvasTransform)
        {
            GameObject topBar = CreatePanel(
                "TopTelemetryBar",
                canvasTransform,
                new Vector2(0.5f, 1f),
                new Vector2(0.5f, 1f),
                new Vector2(0.5f, 1f),
                new Vector2(0f, -20f),
                new Vector2(1040f, 225f)
            );

            VerticalLayoutGroup rootLayout = topBar.AddComponent<VerticalLayoutGroup>();
            rootLayout.padding = new RectOffset(20, 20, 14, 14);
            rootLayout.spacing = 12f;
            rootLayout.childAlignment = TextAnchor.MiddleCenter;
            rootLayout.childControlWidth = true;
            rootLayout.childControlHeight = true;
            rootLayout.childForceExpandWidth = true;
            rootLayout.childForceExpandHeight = false;

            telemetryLabel = CreateLabel(
                "TelemetryLabel",
                topBar.transform,
                "ESTADO AR | Hacé clic en la pantalla para spawnear objetos",
                25,
                TextAnchor.MiddleCenter
            );
            LayoutElement labelLayout = telemetryLabel.gameObject.AddComponent<LayoutElement>();
            labelLayout.preferredHeight = 40f;

            GameObject buttonRow = CreateLayoutRow("TopButtonsRow", topBar.transform, 12f, 64f);

            Button togglePlanesBtn = CreateButton(
                "TogglePlanesButton",
                buttonRow.transform,
                "Planos: ON",
                accentColor,
                out planesVisibilityButtonLabel,
                out planesVisibilityButtonImage
            );
            togglePlanesBtn.onClick.AddListener(() =>
            {
                if (planeTracker != null)
                {
                    planeTracker.TogglePlaneVisualization();
                }
            });

            Button modeBtn = CreateButton(
                "DetectionModeButton",
                buttonRow.transform,
                "Detectar: Ambos",
                neutralButtonColor,
                out detectionModeButtonLabel,
                out _
            );
            modeBtn.onClick.AddListener(() =>
            {
                if (planeTracker != null)
                {
                    planeTracker.CycleDetectionMode();
                }
            });

            Button liveCamBtn = CreateButton(
                "LiveCameraButton",
                buttonRow.transform,
                "Cam: Simulación",
                neutralButtonColor,
                out liveCameraButtonLabel,
                out liveCameraButtonImage
            );
            liveCamBtn.onClick.AddListener(() =>
            {
                if (liveCameraController != null)
                {
                    liveCameraController.ToggleOrCycleLiveCamera();
                }
            });

            Button clearAllBtn = CreateButton(
                "ClearAllButton",
                buttonRow.transform,
                "Limpiar Todo",
                dangerButtonColor,
                out _,
                out _
            );
            clearAllBtn.onClick.AddListener(() =>
            {
                if (interactionController != null)
                {
                    interactionController.ClearAllSpawnedObjects();
                }
            });

            GameObject spawnRow = CreateLayoutRow("QuickSpawnRow", topBar.transform, 12f, 64f);

            Button scanBtn = CreateButton(
                "ScanSurfaceButton",
                spawnRow.transform,
                "Escanear Piso",
                neutralButtonColor,
                out _,
                out _
            );
            scanBtn.onClick.AddListener(() =>
            {
                if (planeTracker != null)
                {
                    planeTracker.ScanSurfaceInFrontOfCamera();
                }

                if (liveCameraController != null)
                {
                    liveCameraController.TriggerSurfaceScanSweep();
                }
            });

            string initialShape = interactionController != null ? interactionController.CurrentPrefabDisplayName : "Cubo";
            Button shapeBtn = CreateButton(
                "ShapeSelectButton",
                spawnRow.transform,
                $"Forma: {initialShape}",
                neutralButtonColor,
                out shapeSelectorButtonLabel,
                out _
            );
            shapeBtn.onClick.AddListener(() =>
            {
                if (interactionController != null)
                {
                    interactionController.CycleNextSpawnPrefab();
                    if (shapeSelectorButtonLabel != null)
                    {
                        shapeSelectorButtonLabel.text = $"Forma: {interactionController.CurrentPrefabDisplayName}";
                    }
                }
            });

            Button spawnNowBtn = CreateButton(
                "SpawnNowButton",
                spawnRow.transform,
                "+ Spawnear Objeto",
                accentColor,
                out _,
                out _
            );
            spawnNowBtn.onClick.AddListener(() =>
            {
                if (interactionController != null)
                {
                    interactionController.SpawnObjectInFrontOfCamera();
                }
            });
        }

        private void BuildObjectInspectorPanel(Transform canvasTransform)
        {
            objectInspectorPanel = CreatePanel(
                "ObjectInspectorPanel",
                canvasTransform,
                new Vector2(0.5f, 0f),
                new Vector2(0.5f, 0f),
                new Vector2(0.5f, 0f),
                new Vector2(0f, 20f),
                new Vector2(1040f, 460f)
            );

            VerticalLayoutGroup layout = objectInspectorPanel.AddComponent<VerticalLayoutGroup>();
            layout.padding = new RectOffset(22, 22, 16, 16);
            layout.spacing = 10f;
            layout.childAlignment = TextAnchor.UpperCenter;
            layout.childControlWidth = true;
            layout.childControlHeight = true;
            layout.childForceExpandWidth = true;
            layout.childForceExpandHeight = false;

            selectedObjectTitleLabel = CreateLabel(
                "SelectedObjectTitle",
                objectInspectorPanel.transform,
                "OBJETO SELECCIONADO (Tocá la figura para ver partículas)",
                26,
                TextAnchor.MiddleCenter
            );
            LayoutElement titleLayout = selectedObjectTitleLabel.gameObject.AddComponent<LayoutElement>();
            titleLayout.preferredHeight = 36f;

            scaleValueLabel = CreateLabel(
                "ScaleValueLabel",
                objectInspectorPanel.transform,
                "Escala: 1.00x",
                23,
                TextAnchor.MiddleLeft
            );
            LayoutElement scaleLabelLayout = scaleValueLabel.gameObject.AddComponent<LayoutElement>();
            scaleLabelLayout.preferredHeight = 30f;

            scaleSlider = CreateSlider("ScaleSlider", objectInspectorPanel.transform, 0.35f, 2.5f, 1f);
            scaleSlider.onValueChanged.AddListener(value =>
            {
                if (suppressSliderCallback)
                    return;

                if (scaleValueLabel != null)
                {
                    scaleValueLabel.text = $"Escala: {value:F2}x";
                }

                if (interactionController != null)
                {
                    interactionController.SetSelectedScale(value);
                }
            });

            GameObject rotAnimRow = CreateLayoutRow("RotationAndAnimRow", objectInspectorPanel.transform, 10f, 64f);
            Button rotLeftBtn = CreateButton("RotateLeftBtn", rotAnimRow.transform, "Rotar -45°", neutralButtonColor, out _, out _);
            rotLeftBtn.onClick.AddListener(() =>
            {
                if (interactionController != null)
                    interactionController.RotateSelected(-1f);
            });

            Button rotRightBtn = CreateButton("RotateRightBtn", rotAnimRow.transform, "Rotar +45°", neutralButtonColor, out _, out _);
            rotRightBtn.onClick.AddListener(() =>
            {
                if (interactionController != null)
                    interactionController.RotateSelected(1f);
            });

            Button autoRotBtn = CreateButton(
                "AutoRotateBtn",
                rotAnimRow.transform,
                "Giro Auto: OFF",
                neutralButtonColor,
                out autoRotateButtonLabel,
                out autoRotateButtonImage
            );
            autoRotBtn.onClick.AddListener(() =>
            {
                if (interactionController != null)
                    interactionController.ToggleSelectedAutoRotate();
            });

            Button floatBtn = CreateButton(
                "FloatBtn",
                rotAnimRow.transform,
                "Flotar: OFF",
                neutralButtonColor,
                out floatButtonLabel,
                out floatButtonImage
            );
            floatBtn.onClick.AddListener(() =>
            {
                if (interactionController != null)
                    interactionController.ToggleSelectedFloating();
            });

            Text colorTitle = CreateLabel(
                "ColorPaletteLabel",
                objectInspectorPanel.transform,
                "Color del Material y Partículas (URP):",
                22,
                TextAnchor.MiddleLeft
            );
            LayoutElement colorTitleLayout = colorTitle.gameObject.AddComponent<LayoutElement>();
            colorTitleLayout.preferredHeight = 28f;

            GameObject colorRow = CreateLayoutRow("ColorRow", objectInspectorPanel.transform, 12f, 58f);
            IReadOnlyList<Color> palette = interactionController != null ? interactionController.ColorPalette : null;
            int colorCount = palette != null ? palette.Count : 0;

            for (int i = 0; i < colorCount; i++)
            {
                int capturedIndex = i;
                Color swatchColor = palette[i];
                Button swatchBtn = CreateButton(
                    $"ColorSwatch_{i}",
                    colorRow.transform,
                    string.Empty,
                    swatchColor,
                    out _,
                    out _
                );
                swatchBtn.onClick.AddListener(() =>
                {
                    if (interactionController != null)
                        interactionController.SetSelectedColorByIndex(capturedIndex);
                });
            }

            GameObject actionsRow = CreateLayoutRow("ActionsRow", objectInspectorPanel.transform, 12f, 64f);

            Button duplicateBtn = CreateButton("DuplicateBtn", actionsRow.transform, "Duplicar", accentColor, out _, out _);
            duplicateBtn.onClick.AddListener(() =>
            {
                if (interactionController != null)
                    interactionController.DuplicateSelectedObject();
            });

            Button resetBtn = CreateButton("ResetBtn", actionsRow.transform, "Resetear", neutralButtonColor, out _, out _);
            resetBtn.onClick.AddListener(() =>
            {
                if (interactionController != null)
                    interactionController.ResetSelectedTransform();
            });

            Button deleteBtn = CreateButton("DeleteBtn", actionsRow.transform, "Borrar", dangerButtonColor, out _, out _);
            deleteBtn.onClick.AddListener(() =>
            {
                if (interactionController != null)
                    interactionController.DeleteSelectedObject();
            });
        }

        private GameObject CreatePanel(
            string name,
            Transform parent,
            Vector2 anchorMin,
            Vector2 anchorMax,
            Vector2 pivot,
            Vector2 anchoredPosition,
            Vector2 sizeDelta)
        {
            GameObject panelGo = new GameObject(name);
            panelGo.transform.SetParent(parent, false);

            RectTransform rect = panelGo.AddComponent<RectTransform>();
            rect.anchorMin = anchorMin;
            rect.anchorMax = anchorMax;
            rect.pivot = pivot;
            rect.anchoredPosition = anchoredPosition;
            rect.sizeDelta = sizeDelta;

            Image bg = panelGo.AddComponent<Image>();
            bg.color = panelBackgroundColor;

            return panelGo;
        }

        private GameObject CreateLayoutRow(string name, Transform parent, float spacing, float preferredHeight)
        {
            GameObject rowGo = new GameObject(name);
            rowGo.transform.SetParent(parent, false);

            rowGo.AddComponent<RectTransform>();
            HorizontalLayoutGroup hLayout = rowGo.AddComponent<HorizontalLayoutGroup>();
            hLayout.spacing = spacing;
            hLayout.childAlignment = TextAnchor.MiddleCenter;
            hLayout.childControlWidth = true;
            hLayout.childControlHeight = true;
            hLayout.childForceExpandWidth = true;
            hLayout.childForceExpandHeight = true;

            LayoutElement element = rowGo.AddComponent<LayoutElement>();
            element.preferredHeight = preferredHeight;

            return rowGo;
        }

        private Text CreateLabel(string name, Transform parent, string content, int fontSize, TextAnchor alignment)
        {
            GameObject labelGo = new GameObject(name);
            labelGo.transform.SetParent(parent, false);

            labelGo.AddComponent<RectTransform>();
            Text textComp = labelGo.AddComponent<Text>();
            textComp.font = defaultFont;
            textComp.text = content;
            textComp.fontSize = fontSize;
            textComp.fontStyle = FontStyle.Bold;
            textComp.alignment = alignment;
            textComp.color = Color.white;
            textComp.supportRichText = true;
            textComp.resizeTextForBestFit = true;
            textComp.resizeTextMinSize = 16;
            textComp.resizeTextMaxSize = fontSize + 4;

            Outline outline = labelGo.AddComponent<Outline>();
            outline.effectColor = new Color(0f, 0f, 0f, 0.85f);
            outline.effectDistance = new Vector2(1.5f, -1.5f);

            return textComp;
        }

        private Button CreateButton(
            string name,
            Transform parent,
            string labelText,
            Color backgroundColor,
            out Text labelComponent,
            out Image backgroundImage)
        {
            GameObject btnGo = new GameObject(name);
            btnGo.transform.SetParent(parent, false);

            btnGo.AddComponent<RectTransform>();
            backgroundImage = btnGo.AddComponent<Image>();
            backgroundImage.color = backgroundColor;

            Button btn = btnGo.AddComponent<Button>();
            btn.targetGraphic = backgroundImage;

            if (!string.IsNullOrEmpty(labelText))
            {
                labelComponent = CreateLabel("Label", btnGo.transform, labelText, 23, TextAnchor.MiddleCenter);
                RectTransform labelRect = labelComponent.GetComponent<RectTransform>();
                labelRect.anchorMin = Vector2.zero;
                labelRect.anchorMax = Vector2.one;
                labelRect.offsetMin = new Vector2(8f, 4f);
                labelRect.offsetMax = new Vector2(-8f, -4f);
            }
            else
            {
                labelComponent = null;
            }

            return btn;
        }

        private Slider CreateSlider(string name, Transform parent, float minVal, float maxVal, float initialVal)
        {
            GameObject sliderGo = new GameObject(name);
            sliderGo.transform.SetParent(parent, false);

            sliderGo.AddComponent<RectTransform>();
            LayoutElement layoutElement = sliderGo.AddComponent<LayoutElement>();
            layoutElement.preferredHeight = 42f;

            GameObject bgGo = new GameObject("Background");
            bgGo.transform.SetParent(sliderGo.transform, false);
            RectTransform bgRect = bgGo.AddComponent<RectTransform>();
            bgRect.anchorMin = new Vector2(0f, 0.3f);
            bgRect.anchorMax = new Vector2(1f, 0.7f);
            bgRect.offsetMin = Vector2.zero;
            bgRect.offsetMax = Vector2.zero;
            Image bgImg = bgGo.AddComponent<Image>();
            bgImg.color = new Color(0.22f, 0.26f, 0.32f, 1f);

            GameObject fillAreaGo = new GameObject("Fill Area");
            fillAreaGo.transform.SetParent(sliderGo.transform, false);
            RectTransform fillAreaRect = fillAreaGo.AddComponent<RectTransform>();
            fillAreaRect.anchorMin = new Vector2(0f, 0.3f);
            fillAreaRect.anchorMax = new Vector2(1f, 0.7f);
            fillAreaRect.offsetMin = Vector2.zero;
            fillAreaRect.offsetMax = Vector2.zero;

            GameObject fillGo = new GameObject("Fill");
            fillGo.transform.SetParent(fillAreaGo.transform, false);
            RectTransform fillRect = fillGo.AddComponent<RectTransform>();
            fillRect.anchorMin = Vector2.zero;
            fillRect.anchorMax = Vector2.one;
            fillRect.offsetMin = Vector2.zero;
            fillRect.offsetMax = Vector2.zero;
            Image fillImg = fillGo.AddComponent<Image>();
            fillImg.color = accentColor;

            GameObject handleSlideAreaGo = new GameObject("Handle Slide Area");
            handleSlideAreaGo.transform.SetParent(sliderGo.transform, false);
            RectTransform handleAreaRect = handleSlideAreaGo.AddComponent<RectTransform>();
            handleAreaRect.anchorMin = Vector2.zero;
            handleAreaRect.anchorMax = Vector2.one;
            handleAreaRect.offsetMin = new Vector2(14f, 0f);
            handleAreaRect.offsetMax = new Vector2(-14f, 0f);

            GameObject handleGo = new GameObject("Handle");
            handleGo.transform.SetParent(handleSlideAreaGo.transform, false);
            RectTransform handleRect = handleGo.AddComponent<RectTransform>();
            handleRect.sizeDelta = new Vector2(34f, 34f);
            Image handleImg = handleGo.AddComponent<Image>();
            handleImg.color = Color.white;

            Slider slider = sliderGo.AddComponent<Slider>();
            slider.fillRect = fillRect;
            slider.handleRect = handleRect;
            slider.targetGraphic = handleImg;
            slider.direction = Slider.Direction.LeftToRight;
            slider.minValue = minVal;
            slider.maxValue = maxVal;
            slider.value = initialVal;

            return slider;
        }
    }
}
