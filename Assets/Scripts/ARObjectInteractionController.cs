using System;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;
using UnityEngine.XR.ARFoundation;
using UnityEngine.XR.Interaction.Toolkit.Interactables;
using UnityEngine.XR.Interaction.Toolkit.Interactors;
using UnityEngine.XR.Interaction.Toolkit.Samples.StarterAssets;
using UnityEngine.XR.Templates.AR;

namespace RealidadAumentada.Prototype
{
    public class ARObjectInteractionController : MonoBehaviour
    {
        [SerializeField] private ObjectSpawner objectSpawner;
        [SerializeField] private XRInteractionGroup interactionGroup;
        [SerializeField] private float rotationStepDegrees = 45f;
        [SerializeField] private Vector3 duplicateOffset = new Vector3(0.18f, 0f, 0.05f);
        [SerializeField] private bool enableDirectPointerSpawnAndDrag = true;
        [SerializeField] private float fallbackSpawnDistance = 1.15f;

        [SerializeField]
        private Color[] colorPalette = new Color[]
        {
            new Color(0.15f, 0.72f, 1.00f, 1f),
            new Color(1.00f, 0.25f, 0.30f, 1f),
            new Color(0.18f, 0.90f, 0.45f, 1f),
            new Color(1.00f, 0.80f, 0.12f, 1f),
            new Color(0.72f, 0.32f, 1.00f, 1f),
            new Color(1.00f, 0.48f, 0.12f, 1f),
            new Color(1.00f, 0.25f, 0.78f, 1f),
            new Color(0.96f, 0.97f, 1.00f, 1f)
        };

        private readonly List<ARManipulableObject> spawnedObjects = new List<ARManipulableObject>();
        private readonly Dictionary<Transform, ARManipulableObject> transformToManipulable = new Dictionary<Transform, ARManipulableObject>();

        private Camera arCamera;
        private ARManipulableObject currentSelectedObject;
        private IXRFocusInteractable lastFocusedInteractable;
        private int selectedPrefabIndex;

        private ARManipulableObject draggedObject;
        private Plane dragHorizontalPlane;
        private Plane dragViewPlane;
        private Vector3 dragOffset;
        private Vector2 pointerPressStartPos;
        private bool pointerStartedOnUI;
        private bool pointerHitExistingObject;
        private int spawnedCountAtPress;

        public event Action<ARManipulableObject> OnSelectedObjectChanged;
        public event Action<int> OnSpawnedCountChanged;

        public ARManipulableObject CurrentSelectedObject => currentSelectedObject;
        public int SpawnedObjectsCount => spawnedObjects.Count;
        public IReadOnlyList<Color> ColorPalette => colorPalette;
        public float RotationStepDegrees => rotationStepDegrees;

        public string CurrentPrefabDisplayName
        {
            get
            {
                if (objectSpawner == null || objectSpawner.objectPrefabs == null || objectSpawner.objectPrefabs.Count == 0)
                    return "Cubo";

                int index = Mathf.Clamp(selectedPrefabIndex, 0, objectSpawner.objectPrefabs.Count - 1);
                GameObject prefab = objectSpawner.objectPrefabs[index];
                return prefab != null ? ARManipulableObject.TranslateShapeName(prefab.name) : "Cubo";
            }
        }

        private GoalManager goalManager;

        private void Awake()
        {
            arCamera = Camera.main;
            if (arCamera == null)
            {
                arCamera = FindFirstObjectByType<Camera>();
            }

            if (objectSpawner == null)
            {
                objectSpawner = FindFirstObjectByType<ObjectSpawner>();
            }

            if (interactionGroup == null)
            {
                interactionGroup = FindFirstObjectByType<XRInteractionGroup>();
            }

            goalManager = FindFirstObjectByType<GoalManager>(FindObjectsInactive.Include);

            if (objectSpawner != null)
            {
                EnsureShapePrefabsWithSphere();
                objectSpawner.onlySpawnInView = false;
                selectedPrefabIndex = 0;
                objectSpawner.spawnOptionIndex = selectedPrefabIndex;
            }
        }

        private void EnsureShapePrefabsWithSphere()
        {
            if (objectSpawner == null || objectSpawner.objectPrefabs == null || objectSpawner.objectPrefabs.Count == 0)
                return;

            GameObject cubePrefab = objectSpawner.objectPrefabs[0];
            for (int i = 0; i < objectSpawner.objectPrefabs.Count; i++)
            {
                GameObject p = objectSpawner.objectPrefabs[i];
                if (p != null && p.name.IndexOf("Cube", StringComparison.OrdinalIgnoreCase) >= 0 &&
                    p.name.IndexOf("Debug", StringComparison.OrdinalIgnoreCase) < 0)
                {
                    cubePrefab = p;
                    break;
                }
            }

            GameObject spherePrefab = CreateSphereVariantTemplate(cubePrefab);
            if (spherePrefab == null)
                return;

            bool replacedDebug = false;
            for (int i = 0; i < objectSpawner.objectPrefabs.Count; i++)
            {
                GameObject p = objectSpawner.objectPrefabs[i];
                if (p != null && p.name.IndexOf("Debug", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    objectSpawner.objectPrefabs[i] = spherePrefab;
                    replacedDebug = true;
                    break;
                }
            }

            if (!replacedDebug)
            {
                objectSpawner.objectPrefabs.Add(spherePrefab);
            }
        }

        private GameObject CreateSphereVariantTemplate(GameObject baseCubePrefab)
        {
            if (baseCubePrefab == null)
                return null;

            GameObject tempSphere = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            Mesh sphereMesh = tempSphere.GetComponent<MeshFilter>().sharedMesh;
            Destroy(tempSphere);

            GameObject sphereTemplate = Instantiate(baseCubePrefab, transform);
            sphereTemplate.name = "SphereVariant";
            sphereTemplate.SetActive(false);

            MeshFilter[] meshFilters = sphereTemplate.GetComponentsInChildren<MeshFilter>(true);
            for (int i = 0; i < meshFilters.Length; i++)
            {
                meshFilters[i].sharedMesh = sphereMesh;
                meshFilters[i].transform.localPosition = new Vector3(0f, 0.075f, 0f);
                meshFilters[i].transform.localScale = new Vector3(0.15f, 0.15f, 0.15f);
            }

            MeshCollider[] meshCols = sphereTemplate.GetComponentsInChildren<MeshCollider>(true);
            for (int i = 0; i < meshCols.Length; i++)
            {
                meshCols[i].sharedMesh = sphereMesh;
            }

            return sphereTemplate;
        }

        private void OnEnable()
        {
            if (objectSpawner != null)
            {
                objectSpawner.objectSpawned += HandleObjectSpawned;
            }
        }

        private void OnDisable()
        {
            if (objectSpawner != null)
            {
                objectSpawner.objectSpawned -= HandleObjectSpawned;
            }
        }

        private void Update()
        {
            if (objectSpawner != null && objectSpawner.objectPrefabs != null && objectSpawner.objectPrefabs.Count > 0)
            {
                if (objectSpawner.spawnOptionIndex >= 0 &&
                    objectSpawner.spawnOptionIndex < objectSpawner.objectPrefabs.Count &&
                    objectSpawner.spawnOptionIndex != selectedPrefabIndex)
                {
                    selectedPrefabIndex = objectSpawner.spawnOptionIndex;
                }

                selectedPrefabIndex = Mathf.Clamp(selectedPrefabIndex, 0, objectSpawner.objectPrefabs.Count - 1);
                objectSpawner.spawnOptionIndex = selectedPrefabIndex;
            }

            PruneDestroyedObjects();
            SyncFocusedObjectFromXR();

            if (enableDirectPointerSpawnAndDrag)
            {
                HandleDirectPointerInteraction();
            }
        }

        public void CycleNextSpawnPrefab()
        {
            if (objectSpawner == null || objectSpawner.objectPrefabs == null || objectSpawner.objectPrefabs.Count == 0)
                return;

            selectedPrefabIndex = (selectedPrefabIndex + 1) % objectSpawner.objectPrefabs.Count;
            objectSpawner.spawnOptionIndex = selectedPrefabIndex;
        }

        public void SpawnObjectInFrontOfCamera()
        {
            if (objectSpawner == null || arCamera == null)
                return;

            Vector3 screenCenter = new Vector3(Screen.width * 0.5f, Screen.height * 0.45f, 0f);
            Vector3 spawnPos = CalculateWorldSpawnPointFromScreen(screenCenter);
            SpawnSelectedPrefabAt(spawnPos);
        }

        public void SelectSpawnPrefabByIndex(int prefabIndex)
        {
            if (objectSpawner == null || objectSpawner.objectPrefabs == null || objectSpawner.objectPrefabs.Count == 0)
                return;

            selectedPrefabIndex = Mathf.Clamp(prefabIndex, 0, objectSpawner.objectPrefabs.Count - 1);
            objectSpawner.spawnOptionIndex = selectedPrefabIndex;
        }

        private void SpawnSelectedPrefabAt(Vector3 worldPos)
        {
            if (objectSpawner == null || objectSpawner.objectPrefabs == null || objectSpawner.objectPrefabs.Count == 0)
                return;

            selectedPrefabIndex = Mathf.Clamp(selectedPrefabIndex, 0, objectSpawner.objectPrefabs.Count - 1);
            objectSpawner.spawnOptionIndex = selectedPrefabIndex;
            GameObject prefabToSpawn = objectSpawner.objectPrefabs[selectedPrefabIndex];
            if (prefabToSpawn == null)
                return;

            GameObject instance = Instantiate(prefabToSpawn, worldPos, Quaternion.identity, objectSpawner.transform);
            instance.name = prefabToSpawn.name;
            instance.SetActive(true);

            if (arCamera != null)
            {
                Vector3 lookDir = arCamera.transform.position - worldPos;
                lookDir.y = 0f;
                if (lookDir.sqrMagnitude > 0.001f)
                {
                    instance.transform.rotation = Quaternion.LookRotation(lookDir.normalized, Vector3.up);
                }
            }

            HandleObjectSpawned(instance);

            if (goalManager != null &&
                goalManager.stepList != null &&
                goalManager.stepList.Count > 1 &&
                goalManager.stepList[1].stepObject != null &&
                goalManager.stepList[1].stepObject.activeInHierarchy)
            {
                goalManager.ForceCompleteGoal();
            }
        }

        public void RotateSelected(float directionMultiplier)
        {
            if (currentSelectedObject == null)
                return;

            currentSelectedObject.RotateAroundUp(rotationStepDegrees * directionMultiplier);
        }

        public void SetSelectedScale(float scaleMultiplier)
        {
            if (currentSelectedObject == null)
                return;

            currentSelectedObject.SetUniformScaleMultiplier(scaleMultiplier);
        }

        public void SetSelectedColorByIndex(int paletteIndex)
        {
            if (currentSelectedObject == null || colorPalette == null || paletteIndex < 0 || paletteIndex >= colorPalette.Length)
                return;

            currentSelectedObject.SetCustomColor(colorPalette[paletteIndex]);
            OnSelectedObjectChanged?.Invoke(currentSelectedObject);
        }

        public void ToggleSelectedAutoRotate()
        {
            if (currentSelectedObject == null)
                return;

            currentSelectedObject.SetAutoRotate(!currentSelectedObject.IsAutoRotating);
            OnSelectedObjectChanged?.Invoke(currentSelectedObject);
        }

        public void ToggleSelectedFloating()
        {
            if (currentSelectedObject == null)
                return;

            currentSelectedObject.SetFloating(!currentSelectedObject.IsFloating);
            OnSelectedObjectChanged?.Invoke(currentSelectedObject);
        }

        public void ResetSelectedTransform()
        {
            if (currentSelectedObject == null)
                return;

            currentSelectedObject.ResetManipulations();
            OnSelectedObjectChanged?.Invoke(currentSelectedObject);
        }

        public void DuplicateSelectedObject()
        {
            if (currentSelectedObject == null)
                return;

            Transform sourceTransform = currentSelectedObject.transform;
            Vector3 spawnPos = sourceTransform.position + sourceTransform.TransformDirection(duplicateOffset);
            GameObject duplicateGo = Instantiate(
                currentSelectedObject.gameObject,
                spawnPos,
                sourceTransform.rotation,
                sourceTransform.parent
            );
            duplicateGo.name = currentSelectedObject.gameObject.name;

            HandleObjectSpawned(duplicateGo);
        }

        public void DeleteSelectedObject()
        {
            if (currentSelectedObject == null)
                return;

            ARManipulableObject toDestroy = currentSelectedObject;
            UnregisterManipulable(toDestroy);
            SetSelectedObject(spawnedObjects.Count > 0 ? spawnedObjects[spawnedObjects.Count - 1] : null);
            Destroy(toDestroy.gameObject);
            OnSpawnedCountChanged?.Invoke(spawnedObjects.Count);
        }

        public void ClearAllSpawnedObjects()
        {
            for (int i = spawnedObjects.Count - 1; i >= 0; i--)
            {
                if (spawnedObjects[i] != null)
                {
                    Destroy(spawnedObjects[i].gameObject);
                }
            }

            spawnedObjects.Clear();
            transformToManipulable.Clear();

            if (objectSpawner != null)
            {
                foreach (Transform child in objectSpawner.transform)
                {
                    Destroy(child.gameObject);
                }
            }

            SetSelectedObject(null);
            OnSpawnedCountChanged?.Invoke(0);
        }

        private void HandleDirectPointerInteraction()
        {
            if (arCamera == null || objectSpawner == null)
                return;

            if (Mouse.current != null)
            {
                float scrollY = Mouse.current.scroll.ReadValue().y;
                if (Mathf.Abs(scrollY) > 0.01f)
                {
                    ARManipulableObject targetToScale = currentSelectedObject;
                    if (targetToScale == null && spawnedObjects.Count > 0)
                    {
                        targetToScale = spawnedObjects[spawnedObjects.Count - 1];
                        SetSelectedObject(targetToScale);
                    }

                    if (targetToScale != null)
                    {
                        float step = Mathf.Sign(scrollY) * 0.12f;
                        float newScale = targetToScale.CurrentScaleMultiplier + step;
                        targetToScale.SetUniformScaleMultiplier(newScale);
                        OnSelectedObjectChanged?.Invoke(targetToScale);
                    }
                }
            }

            if (Pointer.current == null)
                return;

            Vector2 screenPos = Pointer.current.position.ReadValue();

            if (Pointer.current.press.wasPressedThisFrame)
            {
                pointerPressStartPos = screenPos;
                spawnedCountAtPress = spawnedObjects.Count;
                pointerStartedOnUI = IsPointerOverUI(screenPos) || IsInitialScanPromptActive();
                pointerHitExistingObject = false;
                draggedObject = null;

                if (pointerStartedOnUI)
                    return;

                Ray ray = arCamera.ScreenPointToRay(screenPos);
                ARManipulableObject hitManipulable = RaycastForManipulableObject(ray, screenPos);

                if (hitManipulable != null)
                {
                    pointerHitExistingObject = true;
                    SetSelectedObject(hitManipulable);
                    draggedObject = hitManipulable;
                    draggedObject.BeginPointerDrag();

                    dragHorizontalPlane = new Plane(Vector3.up, hitManipulable.transform.position);
                    dragViewPlane = new Plane(-arCamera.transform.forward, hitManipulable.transform.position);

                    if (dragViewPlane.Raycast(ray, out float viewDist))
                    {
                        dragOffset = hitManipulable.transform.position - ray.GetPoint(viewDist);
                    }
                    else
                    {
                        dragOffset = Vector3.zero;
                    }
                }
            }
            else if (Pointer.current.press.isPressed && draggedObject != null && !pointerStartedOnUI)
            {
                Ray ray = arCamera.ScreenPointToRay(screenPos);
                Vector3 targetPos = draggedObject.transform.position;

                if (TryRaycastARPlane(ray, out Vector3 planeHitPoint))
                {
                    targetPos = planeHitPoint;
                }
                else if (ray.direction.y < -0.12f &&
                         dragHorizontalPlane.Raycast(ray, out float horizDist) &&
                         horizDist > 0.2f && horizDist < 4.5f)
                {
                    targetPos = ray.GetPoint(horizDist);
                }
                else if (dragViewPlane.Raycast(ray, out float viewDist) && viewDist > 0.2f && viewDist < 12f)
                {
                    targetPos = ray.GetPoint(viewDist) + dragOffset;
                }

                draggedObject.UpdatePointerDragPosition(targetPos);
            }
            else if (Pointer.current.press.wasReleasedThisFrame)
            {
                if (draggedObject != null)
                {
                    draggedObject.EndPointerDrag();
                    draggedObject = null;
                }

                if (pointerStartedOnUI || pointerHitExistingObject)
                    return;

                float dragDistance = Vector2.Distance(pointerPressStartPos, screenPos);
                if (dragDistance < 25f && spawnedObjects.Count == spawnedCountAtPress)
                {
                    Vector3 spawnPos = CalculateWorldSpawnPointFromScreen(screenPos);
                    SpawnSelectedPrefabAt(spawnPos);
                }
            }
        }

        private ARManipulableObject RaycastForManipulableObject(Ray ray, Vector2 screenPos)
        {
            RaycastHit[] hits = Physics.RaycastAll(ray, 25f);
            float closestDist = float.MaxValue;
            ARManipulableObject closestObj = null;

            for (int i = 0; i < hits.Length; i++)
            {
                ARManipulableObject candidate = FindManipulableFromCollider(hits[i].collider);
                if (candidate != null && hits[i].distance < closestDist)
                {
                    closestDist = hits[i].distance;
                    closestObj = candidate;
                }
            }

            if (closestObj != null)
                return closestObj;

            float minScreenDist = 75f;
            for (int i = 0; i < spawnedObjects.Count; i++)
            {
                ARManipulableObject obj = spawnedObjects[i];
                if (obj == null)
                    continue;

                Vector3 worldPos = obj.transform.position + new Vector3(0f, 0.08f, 0f);
                Vector3 sp = arCamera.WorldToScreenPoint(worldPos);
                if (sp.z > 0f)
                {
                    float d = Vector2.Distance(screenPos, new Vector2(sp.x, sp.y));
                    if (d < minScreenDist)
                    {
                        minScreenDist = d;
                        closestObj = obj;
                    }
                }
            }

            return closestObj;
        }

        private static bool TryRaycastARPlane(Ray ray, out Vector3 hitPoint)
        {
            RaycastHit[] hits = Physics.RaycastAll(ray, 15f);
            for (int i = 0; i < hits.Length; i++)
            {
                if (hits[i].collider != null && hits[i].collider.GetComponentInParent<ARPlane>() != null)
                {
                    hitPoint = hits[i].point;
                    return true;
                }
            }

            hitPoint = Vector3.zero;
            return false;
        }

        private Vector3 CalculateWorldSpawnPointFromScreen(Vector2 screenPos)
        {
            Ray ray = arCamera.ScreenPointToRay(screenPos);

            if (Physics.Raycast(ray, out RaycastHit hit, 15f))
            {
                if (hit.collider.GetComponentInParent<ARPlane>() != null ||
                    hit.collider.name.StartsWith("ARScannedPlane_"))
                {
                    return hit.point;
                }
            }

            float planeY = arCamera.transform.position.y - 0.35f;
            if (spawnedObjects.Count > 0 && spawnedObjects[spawnedObjects.Count - 1] != null)
            {
                planeY = spawnedObjects[spawnedObjects.Count - 1].transform.position.y;
            }

            Plane virtualDeskPlane = new Plane(Vector3.up, new Vector3(0f, planeY, 0f));
            if (virtualDeskPlane.Raycast(ray, out float dist) && dist > 0.25f && dist < 4.5f)
            {
                return ray.GetPoint(dist);
            }

            return ray.GetPoint(fallbackSpawnDistance);
        }

        private ARManipulableObject FindManipulableFromCollider(Collider col)
        {
            if (col == null)
                return null;

            Transform current = col.transform;
            while (current != null)
            {
                if (transformToManipulable.TryGetValue(current, out ARManipulableObject found))
                {
                    return found;
                }
                current = current.parent;
            }

            return null;
        }

        private bool IsInitialScanPromptActive()
        {
            if (goalManager == null)
                return false;

            if (goalManager.greetingPrompt != null && goalManager.greetingPrompt.activeInHierarchy)
                return true;

            if (goalManager.stepList != null &&
                goalManager.stepList.Count > 0 &&
                goalManager.stepList[0].stepObject != null &&
                goalManager.stepList[0].stepObject.activeInHierarchy)
            {
                return true;
            }

            return false;
        }

        private static bool IsPointerOverUI(Vector2 screenPosition)
        {
            if (EventSystem.current == null)
                return false;

            if (EventSystem.current.IsPointerOverGameObject(-1))
                return true;

            PointerEventData eventData = new PointerEventData(EventSystem.current)
            {
                position = screenPosition
            };
            List<RaycastResult> results = new List<RaycastResult>();
            EventSystem.current.RaycastAll(eventData, results);
            return results.Count > 0;
        }

        private void HandleObjectSpawned(GameObject spawnedGo)
        {
            if (spawnedGo == null)
                return;

            spawnedGo.SetActive(true);

            if (!spawnedGo.TryGetComponent(out ARManipulableObject manipulable))
            {
                manipulable = spawnedGo.AddComponent<ARManipulableObject>();
            }

            if (!spawnedObjects.Contains(manipulable))
            {
                spawnedObjects.Add(manipulable);
                transformToManipulable[spawnedGo.transform] = manipulable;
            }

            SetSelectedObject(manipulable);
            OnSpawnedCountChanged?.Invoke(spawnedObjects.Count);
        }

        private void SyncFocusedObjectFromXR()
        {
            if (interactionGroup == null)
                return;

            IXRFocusInteractable currentFocus = interactionGroup.focusInteractable;
            if (currentFocus == lastFocusedInteractable)
                return;

            lastFocusedInteractable = currentFocus;
            if (currentFocus != null && currentFocus.transform != null)
            {
                if (transformToManipulable.TryGetValue(currentFocus.transform, out ARManipulableObject focusedManipulable))
                {
                    SetSelectedObject(focusedManipulable);
                    focusedManipulable.TriggerTouchParticlesEffect();
                }
            }
        }

        private void PruneDestroyedObjects()
        {
            bool removedAny = false;
            for (int i = spawnedObjects.Count - 1; i >= 0; i--)
            {
                if (spawnedObjects[i] == null)
                {
                    spawnedObjects.RemoveAt(i);
                    removedAny = true;
                }
            }

            if (currentSelectedObject == null && !ReferenceEquals(currentSelectedObject, null))
            {
                currentSelectedObject = null;
                OnSelectedObjectChanged?.Invoke(null);
            }

            if (removedAny)
            {
                OnSpawnedCountChanged?.Invoke(spawnedObjects.Count);
            }
        }

        private void UnregisterManipulable(ARManipulableObject manipulable)
        {
            if (manipulable == null)
                return;

            spawnedObjects.Remove(manipulable);
            transformToManipulable.Remove(manipulable.transform);
        }

        private void SetSelectedObject(ARManipulableObject newSelection)
        {
            if (currentSelectedObject == newSelection)
                return;

            currentSelectedObject = newSelection;
            OnSelectedObjectChanged?.Invoke(currentSelectedObject);
        }
    }
}
