using System;
using System.Collections;
using UnityEngine;
using UnityEngine.UI;
using Unity.XR.CoreUtils;

namespace RealidadAumentada.Prototype
{
    public class ARLiveCameraFeedController : MonoBehaviour
    {
        [SerializeField] private bool startLiveCameraInEditor = false;
        [SerializeField] private int xrSimulationEnvironmentLayer = 30;
        [SerializeField] private float backgroundPlaneDistance = 18f;

        private Camera arCamera;
        private XROrigin xrOrigin;
        private Canvas backgroundCanvas;
        private RawImage cameraRawImage;
        private AspectRatioFitter aspectRatioFitter;
        private WebCamTexture activeWebCamTexture;
        private Coroutine autoScanCoroutine;

        private int originalCullingMask;
        private CameraClearFlags originalClearFlags;
        private bool isLiveFeedActive;
        private int currentDeviceIndex = -1;
        private string activeDeviceName = "Sin cámara";

        public event Action<bool, string> OnCameraFeedStateChanged;

        public bool IsLiveFeedActive => isLiveFeedActive;
        public string ActiveDeviceName => activeDeviceName;

        private void Awake()
        {
            arCamera = Camera.main;
            if (arCamera == null)
            {
                arCamera = FindFirstObjectByType<Camera>();
            }

            xrOrigin = FindFirstObjectByType<XROrigin>();

            if (arCamera != null)
            {
                originalCullingMask = arCamera.cullingMask;
                originalClearFlags = arCamera.clearFlags;
            }

            BuildBackgroundVideoCanvas();
        }

        private void Start()
        {
#if UNITY_EDITOR || UNITY_STANDALONE
            if (startLiveCameraInEditor)
            {
                EnableLiveCameraFeed();
            }
#endif
        }

        private void OnDisable()
        {
            if (autoScanCoroutine != null)
            {
                StopCoroutine(autoScanCoroutine);
                autoScanCoroutine = null;
            }

            StopWebCam();
            RestoreSimulationEnvironmentVisuals();
        }

        private void Update()
        {
            if (!isLiveFeedActive || activeWebCamTexture == null || !activeWebCamTexture.isPlaying)
                return;

            if (activeWebCamTexture.width > 16 && activeWebCamTexture.height > 16)
            {
                if (aspectRatioFitter != null)
                {
                    aspectRatioFitter.aspectRatio = (float)activeWebCamTexture.width / activeWebCamTexture.height;
                }

                if (cameraRawImage != null)
                {
                    float scaleY = activeWebCamTexture.videoVerticallyMirrored ? -1f : 1f;
                    cameraRawImage.rectTransform.localScale = new Vector3(1f, scaleY, 1f);
                }
            }
        }

        public void TriggerSurfaceScanSweep()
        {
            if (autoScanCoroutine != null)
            {
                StopCoroutine(autoScanCoroutine);
            }

            autoScanCoroutine = StartCoroutine(AutoScanSurfaceRoutine());
        }

        public void ToggleOrCycleLiveCamera()
        {
            WebCamDevice[] devices = WebCamTexture.devices;
            if (devices == null || devices.Length == 0)
            {
                activeDeviceName = "No se detectó cámara";
                OnCameraFeedStateChanged?.Invoke(false, activeDeviceName);
                return;
            }

            if (!isLiveFeedActive)
            {
                currentDeviceIndex = FindPreferredDeviceIndex(devices);
                StartCameraAtIndex(devices, currentDeviceIndex);
            }
            else if (devices.Length > 1)
            {
                int nextIndex = (currentDeviceIndex + 1) % devices.Length;
                if (nextIndex == FindPreferredDeviceIndex(devices))
                {
                    DisableLiveCameraFeed();
                }
                else
                {
                    currentDeviceIndex = nextIndex;
                    StartCameraAtIndex(devices, currentDeviceIndex);
                }
            }
            else
            {
                DisableLiveCameraFeed();
            }
        }

        public void EnableLiveCameraFeed()
        {
            WebCamDevice[] devices = WebCamTexture.devices;
            if (devices == null || devices.Length == 0)
            {
                activeDeviceName = "Sin cámara";
                OnCameraFeedStateChanged?.Invoke(false, activeDeviceName);
                return;
            }

            if (currentDeviceIndex < 0 || currentDeviceIndex >= devices.Length)
            {
                currentDeviceIndex = FindPreferredDeviceIndex(devices);
            }

            StartCameraAtIndex(devices, currentDeviceIndex);
        }

        public void DisableLiveCameraFeed()
        {
            StopWebCam();
            RestoreSimulationEnvironmentVisuals();

            if (backgroundCanvas != null)
            {
                backgroundCanvas.gameObject.SetActive(false);
            }

            isLiveFeedActive = false;
            activeDeviceName = "Simulación XR";
            OnCameraFeedStateChanged?.Invoke(false, activeDeviceName);
        }

        private void StartCameraAtIndex(WebCamDevice[] devices, int index)
        {
            StopWebCam();

            string deviceName = devices[index].name;
            activeWebCamTexture = new WebCamTexture(deviceName, 1920, 1080, 60)
            {
                filterMode = FilterMode.Trilinear,
                anisoLevel = 4
            };
            activeWebCamTexture.Play();

            if (cameraRawImage != null)
            {
                cameraRawImage.texture = activeWebCamTexture;
            }

            if (backgroundCanvas != null)
            {
                backgroundCanvas.gameObject.SetActive(true);
            }

            HideSimulationEnvironmentVisuals();

            isLiveFeedActive = true;
            activeDeviceName = ShortenDeviceName(deviceName);
            OnCameraFeedStateChanged?.Invoke(true, activeDeviceName);

            TriggerSurfaceScanSweep();
        }

        private IEnumerator AutoScanSurfaceRoutine()
        {
            Transform targetTransform = arCamera != null ? arCamera.transform : null;
            if (xrOrigin != null && xrOrigin.CameraFloorOffsetObject != null)
            {
                targetTransform = xrOrigin.CameraFloorOffsetObject.transform;
            }

            if (targetTransform == null)
                yield break;

            Vector3 startPos = targetTransform.localPosition;
            Quaternion startRot = targetTransform.localRotation;
            Quaternion tiltedRot = Quaternion.Euler(22f, startRot.eulerAngles.y, 0f);

            float duration = 0.85f;
            float elapsed = 0f;

            while (elapsed < duration)
            {
                elapsed += Time.deltaTime;
                float t = elapsed / duration;
                float swayX = Mathf.Sin(t * Mathf.PI * 2f) * 0.18f;
                float swayZ = Mathf.Cos(t * Mathf.PI * 2f) * 0.12f;

                targetTransform.localPosition = startPos + new Vector3(swayX, 0f, swayZ);
                if (arCamera != null)
                {
                    arCamera.transform.localRotation = Quaternion.Slerp(arCamera.transform.localRotation, tiltedRot, t);
                }

                yield return null;
            }

            targetTransform.localPosition = startPos;
        }

        private void StopWebCam()
        {
            if (activeWebCamTexture != null)
            {
                if (activeWebCamTexture.isPlaying)
                {
                    activeWebCamTexture.Stop();
                }

                Destroy(activeWebCamTexture);
                activeWebCamTexture = null;
            }
        }

        private void HideSimulationEnvironmentVisuals()
        {
            if (arCamera == null)
                return;

            arCamera.cullingMask &= ~(1 << xrSimulationEnvironmentLayer);
        }

        private void RestoreSimulationEnvironmentVisuals()
        {
            if (arCamera == null)
                return;

            arCamera.cullingMask = originalCullingMask;
            arCamera.clearFlags = originalClearFlags;
        }

        private void BuildBackgroundVideoCanvas()
        {
            if (arCamera == null)
                return;

            GameObject canvasGo = new GameObject("ARLiveCamera_BackgroundCanvas");
            canvasGo.transform.SetParent(transform, false);

            backgroundCanvas = canvasGo.AddComponent<Canvas>();
            backgroundCanvas.renderMode = RenderMode.ScreenSpaceCamera;
            backgroundCanvas.worldCamera = arCamera;
            backgroundCanvas.planeDistance = backgroundPlaneDistance;
            backgroundCanvas.sortingOrder = -100;

            CanvasScaler scaler = canvasGo.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1080f, 1920f);

            GameObject rawImageGo = new GameObject("LiveVideoRawImage");
            rawImageGo.transform.SetParent(canvasGo.transform, false);

            RectTransform rect = rawImageGo.AddComponent<RectTransform>();
            rect.anchorMin = Vector2.zero;
            rect.anchorMax = Vector2.one;
            rect.offsetMin = Vector2.zero;
            rect.offsetMax = Vector2.zero;

            cameraRawImage = rawImageGo.AddComponent<RawImage>();
            cameraRawImage.color = Color.white;
            cameraRawImage.raycastTarget = false;

            aspectRatioFitter = rawImageGo.AddComponent<AspectRatioFitter>();
            aspectRatioFitter.aspectMode = AspectRatioFitter.AspectMode.EnvelopeParent;
            aspectRatioFitter.aspectRatio = 16f / 9f;

            canvasGo.SetActive(false);
        }

        private static int FindPreferredDeviceIndex(WebCamDevice[] devices)
        {
            string[] preferredKeywords = { "iphone", "iriun", "camo", "epoc", "droidcam", "continuity" };

            for (int k = 0; k < preferredKeywords.Length; k++)
            {
                string keyword = preferredKeywords[k];
                for (int i = 0; i < devices.Length; i++)
                {
                    if (!string.IsNullOrEmpty(devices[i].name) &&
                        devices[i].name.ToLowerInvariant().Contains(keyword))
                    {
                        return i;
                    }
                }
            }

            return 0;
        }

        private static string ShortenDeviceName(string fullName)
        {
            if (string.IsNullOrEmpty(fullName))
                return "Cámara";

            return fullName.Length > 14 ? fullName.Substring(0, 14) + "…" : fullName;
        }
    }
}
