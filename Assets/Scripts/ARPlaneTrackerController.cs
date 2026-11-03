using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.XR.ARFoundation;
using UnityEngine.XR.ARSubsystems;
using UnityEngine.XR.Templates.AR;

namespace RealidadAumentada.Prototype
{
    public class ARPlaneTrackerController : MonoBehaviour
    {
        [SerializeField] private ARPlaneManager planeManager;
        [SerializeField] private bool visualizePlanesOnStart = true;
        [SerializeField] private bool useSmoothPlaneFading = true;

        private readonly List<ARPlane> trackedPlanes = new List<ARPlane>();
        private readonly Dictionary<ARPlane, ARPlaneMeshVisualizer> planeVisualizers = new Dictionary<ARPlane, ARPlaneMeshVisualizer>();
        private readonly Dictionary<ARPlane, ARPlaneMeshVisualizerFader> planeFaders = new Dictionary<ARPlane, ARPlaneMeshVisualizerFader>();

        private bool arePlanesVisible;
        private int horizontalPlanesCount;
        private int verticalPlanesCount;
        private float totalAreaSquareMeters;

        public event Action<int, int, float, bool> OnPlaneStatsUpdated;

        public int HorizontalPlanesCount => horizontalPlanesCount;
        public int VerticalPlanesCount => verticalPlanesCount;
        public int TotalPlanesCount => horizontalPlanesCount + verticalPlanesCount;
        public float TotalAreaSquareMeters => totalAreaSquareMeters;
        public bool ArePlanesVisible => arePlanesVisible;

        public PlaneDetectionMode CurrentDetectionMode =>
            planeManager != null ? planeManager.requestedDetectionMode : PlaneDetectionMode.None;

        private void Awake()
        {
            if (planeManager == null)
            {
                planeManager = FindFirstObjectByType<ARPlaneManager>();
            }

            arePlanesVisible = visualizePlanesOnStart;
        }

        private void OnEnable()
        {
            if (planeManager != null)
            {
                planeManager.trackablesChanged.AddListener(HandleTrackablesChanged);
                SyncExistingPlanes();
            }
        }

        private void OnDisable()
        {
            if (planeManager != null)
            {
                planeManager.trackablesChanged.RemoveListener(HandleTrackablesChanged);
            }
        }

        private void Start()
        {
            ApplyVisibilityToAllPlanes(arePlanesVisible);
            RecalculatePlaneStats();
        }

        public void TogglePlaneVisualization()
        {
            SetPlaneVisualization(!arePlanesVisible);
        }

        public void SetPlaneVisualization(bool visible)
        {
            arePlanesVisible = visible;
            ApplyVisibilityToAllPlanes(arePlanesVisible);
            NotifyStatsUpdated();
        }

        public void CycleDetectionMode()
        {
            if (planeManager == null)
                return;

            PlaneDetectionMode current = planeManager.requestedDetectionMode;
            if (current == (PlaneDetectionMode.Horizontal | PlaneDetectionMode.Vertical))
            {
                planeManager.requestedDetectionMode = PlaneDetectionMode.Horizontal;
            }
            else if (current == PlaneDetectionMode.Horizontal)
            {
                planeManager.requestedDetectionMode = PlaneDetectionMode.Vertical;
            }
            else
            {
                planeManager.requestedDetectionMode = PlaneDetectionMode.Horizontal | PlaneDetectionMode.Vertical;
            }

            NotifyStatsUpdated();
        }

        public void ScanSurfaceInFrontOfCamera()
        {
            SyncExistingPlanes();
            RecalculatePlaneStats();
        }

        private void HandleTrackablesChanged(ARTrackablesChangedEventArgs<ARPlane> eventArgs)
        {
            foreach (ARPlane addedPlane in eventArgs.added)
            {
                RegisterPlane(addedPlane);
            }

            foreach (KeyValuePair<TrackableId, ARPlane> removedPair in eventArgs.removed)
            {
                UnregisterPlane(removedPair.Value);
            }

            if (planeManager != null && planeManager.trackables.count != trackedPlanes.Count)
            {
                SyncExistingPlanes();
            }

            RecalculatePlaneStats();
        }

        private void SyncExistingPlanes()
        {
            trackedPlanes.Clear();
            planeVisualizers.Clear();
            planeFaders.Clear();

            if (planeManager == null)
                return;

            foreach (ARPlane plane in planeManager.trackables)
            {
                RegisterPlane(plane);
            }
        }

        private void RegisterPlane(ARPlane plane)
        {
            if (plane == null || trackedPlanes.Contains(plane))
                return;

            trackedPlanes.Add(plane);

            if (plane.TryGetComponent(out ARPlaneMeshVisualizer visualizer))
            {
                planeVisualizers[plane] = visualizer;
            }

            if (!plane.TryGetComponent(out ARPlaneMeshVisualizerFader fader))
            {
                fader = plane.gameObject.AddComponent<ARPlaneMeshVisualizerFader>();
            }

            planeFaders[plane] = fader;
            ApplyVisibilityToPlane(plane, arePlanesVisible);
        }

        private void UnregisterPlane(ARPlane plane)
        {
            if (plane == null)
                return;

            trackedPlanes.Remove(plane);
            planeVisualizers.Remove(plane);
            planeFaders.Remove(plane);
        }

        private void ApplyVisibilityToAllPlanes(bool visible)
        {
            for (int i = 0; i < trackedPlanes.Count; i++)
            {
                ApplyVisibilityToPlane(trackedPlanes[i], visible);
            }
        }

        private void ApplyVisibilityToPlane(ARPlane plane, bool visible)
        {
            if (plane == null)
                return;

            if (planeVisualizers.TryGetValue(plane, out ARPlaneMeshVisualizer visualizer) && visualizer != null)
            {
                visualizer.enabled = useSmoothPlaneFading || visible;
            }

            if (planeFaders.TryGetValue(plane, out ARPlaneMeshVisualizerFader fader) && fader != null)
            {
                if (useSmoothPlaneFading)
                {
                    fader.visualizeSurfaces = visible;
                }
                else
                {
                    fader.SetVisualsImmediate(visible ? 1f : 0f);
                }
            }
        }

        private void RecalculatePlaneStats()
        {
            horizontalPlanesCount = 0;
            verticalPlanesCount = 0;
            totalAreaSquareMeters = 0f;

            for (int i = trackedPlanes.Count - 1; i >= 0; i--)
            {
                ARPlane plane = trackedPlanes[i];
                if (plane == null || !plane.gameObject.activeInHierarchy)
                    continue;

                if (plane.alignment == PlaneAlignment.Vertical)
                {
                    verticalPlanesCount++;
                }
                else
                {
                    horizontalPlanesCount++;
                }

                Vector2 size = plane.size;
                totalAreaSquareMeters += Mathf.Max(0f, size.x * size.y);
            }

            NotifyStatsUpdated();
        }

        private void NotifyStatsUpdated()
        {
            OnPlaneStatsUpdated?.Invoke(
                horizontalPlanesCount,
                verticalPlanesCount,
                totalAreaSquareMeters,
                arePlanesVisible
            );
        }
    }
}
