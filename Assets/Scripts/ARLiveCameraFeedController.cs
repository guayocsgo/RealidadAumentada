using System;
using System.Collections;
using UnityEngine;
using UnityEngine.InputSystem;
using UnityEngine.UI;
using UnityEngine.XR.ARFoundation;
using Unity.XR.CoreUtils;

namespace RealidadAumentada.Prototype
{
    public class ARLiveCameraFeedController : MonoBehaviour
    {
        private static WebCamTexture sharedWebCamTexture;

        [SerializeField] private bool startLiveCameraInEditor = false;
        [SerializeField] private int xrSimulationEnvironmentLayer = 30;
        [SerializeField] private float backgroundPlaneDistance = 12f;

        private Camera arCamera;
        private XROrigin xrOrigin;
        private Canvas backgroundCanvas;
        private RawImage cameraRawImage;
        private AspectRatioFitter aspectRatioFitter;
        private WebCamTexture activeWebCamTexture;
        private Coroutine autoScanCoroutine;
        private Coroutine connectCameraCoroutine;

        private int originalCullingMask;
        private CameraClearFlags originalClearFlags;
        private bool isLiveFeedActive;
        private bool isConnectingCamera;
        private int currentDeviceIndex = -1;
        private int manualRotationOffset = 0;
        private string activeDeviceName = "Sin cámara";

        public event Action<bool, string> OnCameraFeedStateChanged;

        public bool IsLiveFeedActive => isLiveFeedActive;
        public string ActiveDeviceName => activeDeviceName;
        public WebCamTexture ActiveWebCamTexture => activeWebCamTexture;

        private void Awake()
        {
            ResolveCameraReference();
            BuildBackgroundVideoCanvas();
        }

        private void ResolveCameraReference()
        {
            if (xrOrigin == null)
            {
                xrOrigin = FindFirstObjectByType<XROrigin>();
            }

            Camera resolvedCam = Camera.main;
            if (resolvedCam == null && xrOrigin != null && xrOrigin.Camera != null)
            {
                resolvedCam = xrOrigin.Camera;
            }
            if (resolvedCam == null)
            {
                resolvedCam = FindFirstObjectByType<Camera>();
            }

            if (resolvedCam != null)
            {
                if (arCamera != resolvedCam)
                {
                    arCamera = resolvedCam;
                    originalCullingMask = arCamera.cullingMask;
                    originalClearFlags = arCamera.clearFlags;
                }

                if (arCamera.farClipPlane < 35f)
                {
                    arCamera.farClipPlane = 50f;
                }
            }
        }

        private void Start()
        {
            ResolveCameraReference();
            if (backgroundCanvas != null && arCamera != null)
            {
                backgroundCanvas.worldCamera = arCamera;
            }

#if UNITY_EDITOR || UNITY_STANDALONE
            if (startLiveCameraInEditor)
            {
                EnableLiveCameraFeed();
            }
#endif
        }

        private void OnDisable()
        {
            CleanupCameraAndCoroutines();
            RestoreSimulationEnvironmentVisuals();
        }

        private void OnDestroy()
        {
            CleanupCameraAndCoroutines();
        }

        private void OnApplicationQuit()
        {
            CleanupCameraAndCoroutines();
        }

        private void CleanupCameraAndCoroutines()
        {
            if (autoScanCoroutine != null)
            {
                StopCoroutine(autoScanCoroutine);
                autoScanCoroutine = null;
            }

            if (connectCameraCoroutine != null)
            {
                StopCoroutine(connectCameraCoroutine);
                connectCameraCoroutine = null;
            }

            isConnectingCamera = false;
            StopWebCam();
        }

        private void Update()
        {
            if (!isLiveFeedActive || activeWebCamTexture == null || !activeWebCamTexture.isPlaying)
                return;

            if (Keyboard.current != null && Keyboard.current.rKey.wasPressedThisFrame)
            {
                manualRotationOffset = (manualRotationOffset + 90) % 360;
            }

            if (activeWebCamTexture.width > 16 && activeWebCamTexture.height > 16)
            {
                int totalRot = (activeWebCamTexture.videoRotationAngle + manualRotationOffset) % 360;
                bool isRotated90 = (totalRot == 90 || totalRot == 270);

                if (aspectRatioFitter != null)
                {
                    float w = activeWebCamTexture.width;
                    float h = activeWebCamTexture.height;
                    aspectRatioFitter.aspectRatio = isRotated90 ? (h / w) : (w / h);
                }

                if (cameraRawImage != null)
                {
                    float scaleY = activeWebCamTexture.videoVerticallyMirrored ? -1f : 1f;
                    cameraRawImage.rectTransform.localEulerAngles = new Vector3(0f, 0f, -totalRot);
                    cameraRawImage.rectTransform.localScale = new Vector3(1f, scaleY, 1f);
                }
            }
        }

        public void TriggerSurfaceScanSweep()
        {
            ARPlaneManager planeMgr = FindFirstObjectByType<ARPlaneManager>();
            if (planeMgr == null || !planeMgr.enabled)
                return;

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

            currentDeviceIndex = FindPreferredDeviceIndex(devices);
            StartCameraAtIndex(devices, currentDeviceIndex);
        }

        public void DisableLiveCameraFeed()
        {
            if (connectCameraCoroutine != null)
            {
                StopCoroutine(connectCameraCoroutine);
                connectCameraCoroutine = null;
            }

            isConnectingCamera = false;
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
            if (connectCameraCoroutine != null)
            {
                StopCoroutine(connectCameraCoroutine);
                connectCameraCoroutine = null;
            }

            connectCameraCoroutine = StartCoroutine(ConnectWorkingCameraRoutine(devices, index));
        }

        private IEnumerator ConnectWorkingCameraRoutine(WebCamDevice[] devices, int preferredIndex)
        {
            isConnectingCamera = true;
            ResolveCameraReference();

            if (backgroundCanvas == null)
            {
                BuildBackgroundVideoCanvas();
            }
            else if (arCamera != null)
            {
                backgroundCanvas.worldCamera = arCamera;
                backgroundCanvas.planeDistance = backgroundPlaneDistance;
            }

            bool hadExistingWebCam = activeWebCamTexture != null || sharedWebCamTexture != null;
            StopWebCam();
            if (hadExistingWebCam)
            {
                yield return null;
                yield return null;
            }

            int safeIndex = Mathf.Clamp(preferredIndex, 0, devices.Length - 1);
            string deviceName = devices[safeIndex].name;

            StartRawWebCam(deviceName);
            FinalizeActiveCamera(safeIndex, deviceName);

            float checkTimer = 0f;
            while (checkTimer < 0.6f)
            {
                checkTimer += Time.deltaTime;
                if (activeWebCamTexture != null && activeWebCamTexture.isPlaying)
                {
                    connectCameraCoroutine = null;
                    yield break;
                }
                yield return null;
            }

            if (activeWebCamTexture == null || !activeWebCamTexture.isPlaying)
            {
                StopWebCam();
                yield return null;
                yield return null;
                StartRawWebCam(deviceName);
                FinalizeActiveCamera(safeIndex, deviceName);
            }

            connectCameraCoroutine = null;
        }

        private void StartRawWebCam(string deviceName)
        {
            StopWebCam();
            ResolveCameraReference();

            activeWebCamTexture = new WebCamTexture(deviceName);
            sharedWebCamTexture = activeWebCamTexture;
            activeWebCamTexture.filterMode = FilterMode.Trilinear;
            activeWebCamTexture.Play();

            if (cameraRawImage != null)
            {
                cameraRawImage.texture = activeWebCamTexture;
                cameraRawImage.color = Color.white;
            }

            if (backgroundCanvas != null)
            {
                if (arCamera != null)
                {
                    backgroundCanvas.worldCamera = arCamera;
                    backgroundCanvas.planeDistance = backgroundPlaneDistance;
                }
                backgroundCanvas.gameObject.SetActive(true);
            }

            HideSimulationEnvironmentVisuals();
            isLiveFeedActive = true;
        }

        private void FinalizeActiveCamera(int index, string deviceName)
        {
            isConnectingCamera = false;
            currentDeviceIndex = index;

            if (cameraRawImage != null)
            {
                cameraRawImage.texture = activeWebCamTexture;
                cameraRawImage.color = Color.white;
            }

            if (backgroundCanvas != null)
            {
                if (arCamera != null)
                {
                    backgroundCanvas.worldCamera = arCamera;
                    backgroundCanvas.planeDistance = backgroundPlaneDistance;
                }
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

                if (sharedWebCamTexture == activeWebCamTexture)
                {
                    sharedWebCamTexture = null;
                }

                Destroy(activeWebCamTexture);
                activeWebCamTexture = null;
            }

            if (sharedWebCamTexture != null)
            {
                if (sharedWebCamTexture.isPlaying)
                {
                    sharedWebCamTexture.Stop();
                }

                Destroy(sharedWebCamTexture);
                sharedWebCamTexture = null;
            }
        }

        private void HideSimulationEnvironmentVisuals()
        {
            if (arCamera == null)
                return;

            arCamera.cullingMask &= ~(1 << xrSimulationEnvironmentLayer);
            arCamera.cullingMask |= (1 << 0) | (1 << 5);
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
            canvasGo.layer = 0;
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
            rawImageGo.layer = 0;
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
                        !devices[i].name.Contains("#") &&
                        devices[i].name.ToLowerInvariant().Contains(keyword))
                    {
                        return i;
                    }
                }
            }

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

            for (int i = 0; i < devices.Length; i++)
            {
                if (!string.IsNullOrEmpty(devices[i].name) && !devices[i].name.Contains("#"))
                {
                    return i;
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
