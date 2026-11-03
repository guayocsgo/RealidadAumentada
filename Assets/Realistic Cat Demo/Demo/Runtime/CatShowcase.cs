using System;
using System.Collections;
using System.IO;
using UnityEngine;
using UnityEngine.Animations;
using UnityEngine.Playables;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

namespace RealisticCatDemo
{
    /// <summary>Self-contained recording showcase. Only the selected cat animates.</summary>
    public sealed class CatShowcase : MonoBehaviour
    {
        [Serializable] public sealed class Entry
        {
            public string displayName;
            public GameObject model;
            public Animator animator;
            public AnimationClip[] clips;
        }
        public Entry[] cats = Array.Empty<Entry>();
        public Camera showcaseCamera;
        public Transform cameraTarget;
        public string pipelineLabel;
        public int selectedCat = 0;
        public bool showInterface = true;
        public bool orbit;
        [Range(0.1f,2)] public float animationSpeed = 1;
        public int SelectedAnimation => clipIndex;
        public bool Paused => paused;
        int clipIndex;
        bool paused;
        double clock;
        PlayableGraph graph;
        AnimationClipPlayable clipPlayable;
        Vector3 cameraHome;
        Quaternion cameraRotation;
        GUIStyle title, sub, small;

        Vector3 lastMousePosition;
        string notificationText;
        float notificationTimer;
        bool isCapturing;

        void OnEnable()
        {
            if (!showcaseCamera) showcaseCamera = Camera.main ?? FindAnyObjectByType<Camera>();
            if (showcaseCamera) { cameraHome=showcaseCamera.transform.position; cameraRotation=showcaseCamera.transform.rotation; }
            SelectCat(selectedCat);
        }
        void OnDisable() { Release(); }
        void Release() { if(graph.IsValid()) graph.Destroy(); }
        public void SelectCat(int index)
        {
            Release();
            if(cats.Length==0) return;
            selectedCat=(index%cats.Length+cats.Length)%cats.Length;
            for(int i=0;i<cats.Length;i++) if(cats[i].model) cats[i].model.SetActive(i==selectedCat);
            var clips=cats[selectedCat].clips;
            int idle=Array.FindIndex(clips,c=>c && c.name.IndexOf("idle",StringComparison.OrdinalIgnoreCase)>=0);
            SelectAnimation(idle>=0?idle:0);
        }
        public void SelectAnimation(int index)
        {
            Release();
            if(cats.Length==0) return;
            var entry=cats[selectedCat];
            if(!entry.animator || entry.clips==null || entry.clips.Length==0) return;
            clipIndex=(index%entry.clips.Length+entry.clips.Length)%entry.clips.Length;
            var clip=entry.clips[clipIndex]; if(!clip) return;
            // Clear the previous clip's blend shapes (eyelids, seated corrective) before evaluating the next clip.
            foreach(var skin in entry.model.GetComponentsInChildren<SkinnedMeshRenderer>(true)) {
                if(!skin.sharedMesh)continue;
                for(int s=0;s<skin.sharedMesh.blendShapeCount;s++)skin.SetBlendShapeWeight(s,0f);
            }
            entry.animator.applyRootMotion=false;
            entry.animator.runtimeAnimatorController=null;
            entry.animator.cullingMode=AnimatorCullingMode.AlwaysAnimate;
            graph=PlayableGraph.Create("Tabby Cat Demo");
            graph.SetTimeUpdateMode(DirectorUpdateMode.Manual);
            clipPlayable=AnimationClipPlayable.Create(graph,clip);
            clipPlayable.SetApplyFootIK(false);
            AnimationPlayableOutput.Create(graph,"Cat",entry.animator).SetSourcePlayable(clipPlayable);
            clock=0; graph.Play(); graph.Evaluate(0);
        }
        public void TogglePause() { paused=!paused; }

        void Update()
        {
            HandleInput();

            if(graph.IsValid() && !paused) {
                var length=cats[selectedCat].clips[clipIndex].length;
                clock=(clock+Time.unscaledDeltaTime*animationSpeed)%Math.Max(.001,length);
                clipPlayable.SetTime(clock); graph.Evaluate(0);
            }
            if(orbit && showcaseCamera) {
                Vector3 target = GetTargetPosition();
                showcaseCamera.transform.RotateAround(target,Vector3.up,Time.unscaledDeltaTime*8);
                showcaseCamera.transform.LookAt(target);
            }
        }

        void HandleInput()
        {
            float scroll = 0f;
            Vector2 mouseDelta = Vector2.zero;
            bool isRotating = false;

#if ENABLE_INPUT_SYSTEM
            var k = Keyboard.current;
            if (k != null)
            {
                if (k.upArrowKey.wasPressedThisFrame) SelectAnimation(clipIndex + 1);
                if (k.downArrowKey.wasPressedThisFrame) SelectAnimation(clipIndex - 1);
                if (k.spaceKey.wasPressedThisFrame) TogglePause();
                if (k.hKey.wasPressedThisFrame) showInterface = !showInterface;
                if (k.oKey.wasPressedThisFrame) orbit = !orbit;
                if (k.rKey.wasPressedThisFrame) ResetCamera();

                bool ctrl = k.leftCtrlKey.isPressed || k.rightCtrlKey.isPressed;
                bool shift = k.leftShiftKey.isPressed || k.rightShiftKey.isPressed;
                if (ctrl && shift && k.kKey.wasPressedThisFrame) TakeScreenshot();
            }

            var mouse = Mouse.current;
            if (mouse != null)
            {
                float scrollVal = mouse.scroll.ReadValue().y;
                if (Mathf.Abs(scrollVal) > 0.01f)
                {
                    scroll = Mathf.Abs(scrollVal) >= 10f ? scrollVal / 120f : scrollVal;
                }

                isRotating = mouse.rightButton.isPressed;
                if (isRotating)
                {
                    mouseDelta = mouse.delta.ReadValue();
                    if (mouseDelta.sqrMagnitude > 10000f) mouseDelta = Vector2.zero;
                }
            }
#elif ENABLE_LEGACY_INPUT_MANAGER
            if (Input.GetKeyDown(KeyCode.UpArrow)) SelectAnimation(clipIndex + 1);
            if (Input.GetKeyDown(KeyCode.DownArrow)) SelectAnimation(clipIndex - 1);
            if (Input.GetKeyDown(KeyCode.Space)) TogglePause();
            if (Input.GetKeyDown(KeyCode.H)) showInterface = !showInterface;
            if (Input.GetKeyDown(KeyCode.O)) orbit = !orbit;
            if (Input.GetKeyDown(KeyCode.R)) ResetCamera();

            bool ctrl = Input.GetKey(KeyCode.LeftControl) || Input.GetKey(KeyCode.RightControl);
            bool shift = Input.GetKey(KeyCode.LeftShift) || Input.GetKey(KeyCode.RightShift);
            if (ctrl && shift && Input.GetKeyDown(KeyCode.K)) TakeScreenshot();

            scroll = Input.mouseScrollDelta.y;
            bool pressed = Input.GetMouseButtonDown(1);
            if (pressed) lastMousePosition = Input.mousePosition;
            isRotating = Input.GetMouseButton(1);
            if (isRotating && !pressed)
            {
                mouseDelta = (Vector2)(Input.mousePosition - lastMousePosition);
            }
            lastMousePosition = Input.mousePosition;
#endif

            if (Mathf.Abs(scroll) > 0.001f)
            {
                ZoomCamera(scroll);
            }

            if (isRotating && mouseDelta.sqrMagnitude > 0.01f)
            {
                orbit = false;
                RotateCamera(mouseDelta.x, mouseDelta.y);
            }
        }

        void ZoomCamera(float scroll)
        {
            if (!showcaseCamera || Mathf.Abs(scroll) < 0.0001f) return;
            Vector3 target = GetTargetPosition();
            Vector3 offset = showcaseCamera.transform.position - target;
            float dist = offset.magnitude;
            if (dist < 0.01f) dist = 0.01f;

            float zoomFactor = 1f - Mathf.Clamp(scroll, -3f, 3f) * 0.1f;
            float newDist = Mathf.Clamp(dist * zoomFactor, 0.2f, 40f);
            showcaseCamera.transform.position = target + offset.normalized * newDist;
        }

        void RotateCamera(float deltaX, float deltaY)
        {
            if (!showcaseCamera) return;
            Vector3 target = GetTargetPosition();
            float sensitivity = 0.25f;

            showcaseCamera.transform.RotateAround(target, Vector3.up, deltaX * sensitivity);

            Vector3 right = showcaseCamera.transform.right;
            float pitch = -deltaY * sensitivity;
            Vector3 forward = showcaseCamera.transform.forward;
            Vector3 newForward = Quaternion.AngleAxis(pitch, right) * forward;

            if (Mathf.Abs(Vector3.Dot(newForward, Vector3.up)) < 0.96f)
            {
                showcaseCamera.transform.RotateAround(target, right, pitch);
            }
            showcaseCamera.transform.LookAt(target);
        }

        Vector3 GetTargetPosition()
        {
            if (cameraTarget) return cameraTarget.position;
            if (cats != null && selectedCat >= 0 && selectedCat < cats.Length && cats[selectedCat] != null && cats[selectedCat].model)
                return cats[selectedCat].model.transform.position + Vector3.up * 0.4f;
            return Vector3.zero;
        }

        public void TakeScreenshot()
        {
            if (isCapturing) return;
            StartCoroutine(CaptureRoutine());
        }

        IEnumerator CaptureRoutine()
        {
            isCapturing = true;
            bool prevInterface = showInterface;
            showInterface = false;

            yield return null;

            string folder = Path.Combine(Directory.GetCurrentDirectory(), "Screenshots");
            if (!Directory.Exists(folder))
            {
                Directory.CreateDirectory(folder);
            }

            string catName = "Unknown";
            if (cats != null && selectedCat >= 0 && selectedCat < cats.Length && cats[selectedCat] != null)
            {
                catName = cats[selectedCat].displayName.Replace(" ", "_").Replace("&", "and");
            }
            string filename = Path.Combine(folder, $"Cat_{catName}_{DateTime.Now:yyyyMMdd_HHmmss}.png");

            ScreenCapture.CaptureScreenshot(filename);

            yield return new WaitForEndOfFrame();
            yield return null;

            showInterface = prevInterface;
            notificationText = $"SCREENSHOT SAVED: {Path.GetFileName(filename)}";
            notificationTimer = 3.5f;
            isCapturing = false;
            Debug.Log($"[CatShowcase] Screenshot saved: {filename}");
        }

        public void ResetCamera() { orbit=false;if(showcaseCamera) showcaseCamera.transform.SetPositionAndRotation(cameraHome,cameraRotation); }

        void OnGUI()
        {
            if(title==null) {
                title=new GUIStyle(GUI.skin.label){fontSize=38,fontStyle=FontStyle.Bold};
                sub=new GUIStyle(GUI.skin.label){fontSize=19};
                small=new GUIStyle(GUI.skin.label){fontSize=13};
                title.normal.textColor=new Color(.94f,.91f,.83f);
                sub.normal.textColor=new Color(.82f,.69f,.46f);
                small.normal.textColor=new Color(.77f,.79f,.80f);
            }
            var old=GUI.matrix;GUI.matrix=Matrix4x4.Scale(Vector3.one*(Screen.width/1920f));
            float h=Screen.height*1920f/Screen.width;

            if(notificationTimer > 0 && !isCapturing) {
                notificationTimer -= Time.unscaledDeltaTime;
                var notifStyle = new GUIStyle(GUI.skin.box){fontSize=16,fontStyle=FontStyle.Bold,alignment=TextAnchor.MiddleCenter};
                notifStyle.normal.textColor = new Color(0.35f, 0.95f, 0.55f);
                GUI.Box(new Rect(1920f/2f - 350, 24, 700, 40), notificationText, notifStyle);
            }

            if(!showInterface || cats.Length==0) {
                GUI.matrix=old;
                return;
            }

            GUI.Label(new Rect(64,44,900,32),"R E A L I S T I C   C A T   D E M O",sub);
            GUI.Label(new Rect(64,82,1000,64),cats[selectedCat].displayName,title);
            var clips=cats[selectedCat].clips;
            GUI.Label(new Rect(66,146,900,30),pipelineLabel+"   /   "+(clips.Length>0?clips[clipIndex].name:"")+ (paused?"   /   PAUSED":""),small);
            GUI.Label(new Rect(64,h-65,1800,30),"↑ ↓  ANIMATION     SPACE  PAUSE     O  ORBIT     RMB  ROTATE     SCROLL  ZOOM     CTRL+SHIFT+K  SCREENSHOT     R  RESET     H  CLEAN VIEW",small);
            if (GUI.Button(new Rect(64, 195, 140, 34), "Previous animation")) SelectAnimation(clipIndex - 1);
            if (GUI.Button(new Rect(214, 195, 140, 34), "Next animation")) SelectAnimation(clipIndex + 1);
            if (GUI.Button(new Rect(364, 195, 100, 34), paused ? "Play" : "Pause")) TogglePause();
            if (GUI.Button(new Rect(474, 195, 100, 34), "Reset view")) ResetCamera();
            GUI.matrix=old;
        }
    }
}
