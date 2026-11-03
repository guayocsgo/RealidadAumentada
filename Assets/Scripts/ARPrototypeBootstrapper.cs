using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.XR.ARFoundation;

namespace RealidadAumentada.Prototype
{
    [DisallowMultipleComponent]
    [RequireComponent(typeof(ARPlaneTrackerController))]
    [RequireComponent(typeof(ARObjectInteractionController))]
    [RequireComponent(typeof(ARLiveCameraFeedController))]
    [RequireComponent(typeof(ARPrototypeUIManager))]
    public class ARPrototypeBootstrapper : MonoBehaviour
    {
        [SerializeField]
        private ARPlaneTrackerController planeTrackerController;

        [SerializeField]
        private ARObjectInteractionController objectInteractionController;

        [SerializeField]
        private ARLiveCameraFeedController liveCameraFeedController;

        [SerializeField]
        private ARPrototypeUIManager prototypeUIManager;

        private void Awake()
        {
            if (planeTrackerController == null)
            {
                planeTrackerController = GetComponent<ARPlaneTrackerController>();
            }

            if (objectInteractionController == null)
            {
                objectInteractionController = GetComponent<ARObjectInteractionController>();
            }

            if (liveCameraFeedController == null)
            {
                liveCameraFeedController = GetComponent<ARLiveCameraFeedController>();
            }

            if (prototypeUIManager == null)
            {
                prototypeUIManager = GetComponent<ARPrototypeUIManager>();
            }
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void EnsurePrototypeRunningInARScene()
        {
            Scene activeScene = SceneManager.GetActiveScene();
            if (activeScene.name == "ImageTargetLab" || FindFirstObjectByType<ImageTargetContent>() != null)
                return;

            ARPlaneManager planeMgr = FindFirstObjectByType<ARPlaneManager>(FindObjectsInactive.Include);
            if (planeMgr == null)
                return;

            if (!planeMgr.enabled)
            {
                planeMgr.enabled = true;
            }

            if (FindFirstObjectByType<ARPrototypeBootstrapper>() != null)
                return;

            GameObject bootstrapperGo = new GameObject("[AR Prototype System]");
            bootstrapperGo.AddComponent<ARPrototypeBootstrapper>();
        }
    }
}
