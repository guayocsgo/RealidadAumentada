using System;
using UnityEngine;
using UnityEngine.XR.Interaction.Toolkit.Interactables;

namespace RealidadAumentada.Prototype
{
    [RequireComponent(typeof(Rigidbody))]
    public class ARManipulableObject : MonoBehaviour
    {
        private static readonly int BaseColorShaderId = Shader.PropertyToID("_BaseColor");
        private static readonly int ColorShaderId = Shader.PropertyToID("_Color");
        private static readonly int EdgeHighlightColorShaderId = Shader.PropertyToID("_EdgeHighlightColor");
        private static readonly int TintColorShaderId = Shader.PropertyToID("_TintColor");

        private static Texture2D sharedGlowParticleTexture;

        [SerializeField] private float minScaleMultiplier = 0.25f;
        [SerializeField] private float maxScaleMultiplier = 3.5f;
        [SerializeField] private float autoRotateSpeed = 45f;
        [SerializeField] private float floatAmplitude = 0.04f;
        [SerializeField] private float floatFrequency = 2.2f;

        private Rigidbody cachedRigidbody;
        private XRGrabInteractable cachedGrabInteractable;
        private Renderer[] cachedRenderers;
        private MaterialPropertyBlock propertyBlock;
        private Transform visualsTransform;

        private ParticleSystem burstParticleSystem;
        private ParticleSystem ringWaveParticleSystem;
        private Material instanceParticleMaterial;
        private float touchPulseTimer = -1f;
        private const float TouchPulseDuration = 0.42f;

        private Vector3 initialRootScale;
        private Quaternion initialRootRotation;
        private Vector3 initialVisualsLocalPos;

        private float currentScaleMultiplier = 1f;
        private bool isAutoRotating;
        private bool isFloating;
        private bool hasCustomColor;
        private Color currentColor = new Color(0.20f, 0.68f, 1.00f, 1f);
        private float floatTimer;

        private bool isPointerDragging;
        private Vector3 pointerTargetPosition;

        public string DisplayName { get; private set; }
        public float CurrentScaleMultiplier => currentScaleMultiplier;
        public float MinScaleMultiplier => minScaleMultiplier;
        public float MaxScaleMultiplier => maxScaleMultiplier;
        public bool IsAutoRotating => isAutoRotating;
        public bool IsFloating => isFloating;
        public Color CurrentColor => currentColor;

        private void Awake()
        {
            cachedRigidbody = GetComponent<Rigidbody>();
            cachedGrabInteractable = GetComponent<XRGrabInteractable>();
            cachedRenderers = GetComponentsInChildren<Renderer>(true);
            propertyBlock = new MaterialPropertyBlock();

            initialRootScale = transform.localScale;
            initialRootRotation = transform.localRotation;
            pointerTargetPosition = transform.position;

            Transform foundVisuals = transform.Find("Visuals");
            visualsTransform = foundVisuals != null ? foundVisuals : transform;
            initialVisualsLocalPos = visualsTransform.localPosition;

            if (cachedGrabInteractable != null)
            {
                cachedGrabInteractable.trackPosition = false;
                cachedGrabInteractable.trackRotation = false;
            }

            DisableTemplateColorAffordances();

            DisplayName = TranslateShapeName(gameObject.name);

            for (int i = 0; i < cachedRenderers.Length; i++)
            {
                if (cachedRenderers[i] != null && cachedRenderers[i].sharedMaterial != null)
                {
                    Material sharedMat = cachedRenderers[i].sharedMaterial;
                    if (sharedMat.HasProperty(BaseColorShaderId))
                    {
                        currentColor = sharedMat.GetColor(BaseColorShaderId);
                        break;
                    }
                }
            }

            BuildProfessionalParticleSystems();
        }

        private void Start()
        {
            TriggerTouchParticlesEffect();
        }

        private void FixedUpdate()
        {
            if (cachedRigidbody != null)
            {
                if (!cachedRigidbody.isKinematic)
                {
                    cachedRigidbody.isKinematic = true;
                }

                if (isPointerDragging)
                {
                    cachedRigidbody.MovePosition(pointerTargetPosition);
                }
            }
        }

        private void Update()
        {
            if (isPointerDragging)
            {
                transform.position = pointerTargetPosition;
            }

            float pulseScaleFactor = 1f;
            if (touchPulseTimer >= 0f)
            {
                touchPulseTimer += Time.deltaTime;
                if (touchPulseTimer <= TouchPulseDuration)
                {
                    float t = touchPulseTimer / TouchPulseDuration;
                    pulseScaleFactor = 1f + 0.15f * Mathf.Sin(t * Mathf.PI * 2.5f) * (1f - t);
                }
                else
                {
                    touchPulseTimer = -1f;
                }
            }

            transform.localScale = initialRootScale * (currentScaleMultiplier * pulseScaleFactor);

            if (isAutoRotating)
            {
                transform.Rotate(Vector3.up, autoRotateSpeed * Time.deltaTime, Space.Self);
            }

            if (isFloating && visualsTransform != transform)
            {
                floatTimer += Time.deltaTime * floatFrequency;
                float offsetY = (Mathf.Sin(floatTimer) + 1f) * 0.5f * floatAmplitude;
                visualsTransform.localPosition = initialVisualsLocalPos + new Vector3(0f, offsetY, 0f);
            }
            else if (visualsTransform != transform)
            {
                visualsTransform.localPosition = initialVisualsLocalPos;
            }
        }

        private void LateUpdate()
        {
            if (isPointerDragging)
            {
                transform.position = pointerTargetPosition;
                if (visualsTransform != transform && !isFloating)
                {
                    visualsTransform.localPosition = initialVisualsLocalPos;
                }
            }

            if (hasCustomColor)
            {
                ApplyColorToRenderers(currentColor);
            }
        }

        private void DisableTemplateColorAffordances()
        {
            MonoBehaviour[] allBehaviours = GetComponentsInChildren<MonoBehaviour>(true);
            for (int i = 0; i < allBehaviours.Length; i++)
            {
                MonoBehaviour mb = allBehaviours[i];
                if (mb == null || mb == this)
                    continue;

                string typeName = mb.GetType().Name;
                if (typeName.IndexOf("Affordance", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    mb.enabled = false;
                }
            }

            Transform interactionAffordance = transform.Find("Interaction Affordance");
            if (interactionAffordance != null)
            {
                interactionAffordance.gameObject.SetActive(false);
            }
        }

        public void TriggerTouchParticlesEffect()
        {
            touchPulseTimer = 0f;

            if (burstParticleSystem == null || ringWaveParticleSystem == null)
            {
                BuildProfessionalParticleSystems();
            }

            ApplyColorToParticleSystems(currentColor);

            if (burstParticleSystem != null)
            {
                burstParticleSystem.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
                burstParticleSystem.Play(true);
            }

            if (ringWaveParticleSystem != null)
            {
                ringWaveParticleSystem.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);
                ringWaveParticleSystem.Play(true);
            }
        }

        private void ApplyColorToParticleSystems(Color baseCol)
        {
            Color vibrantColor = new Color(baseCol.r, baseCol.g, baseCol.b, 1f);
            Color brightHighlight = Color.Lerp(vibrantColor, Color.white, 0.38f);
            brightHighlight.a = 1f;
            Color deepTip = Color.Lerp(vibrantColor, Color.black, 0.15f);
            deepTip.a = 1f;

            if (instanceParticleMaterial != null)
            {
                instanceParticleMaterial.color = Color.white;
                if (instanceParticleMaterial.HasProperty(BaseColorShaderId))
                    instanceParticleMaterial.SetColor(BaseColorShaderId, Color.white);
                if (instanceParticleMaterial.HasProperty(ColorShaderId))
                    instanceParticleMaterial.SetColor(ColorShaderId, Color.white);
                if (instanceParticleMaterial.HasProperty(TintColorShaderId))
                    instanceParticleMaterial.SetColor(TintColorShaderId, Color.white);
            }

            if (burstParticleSystem != null)
            {
                ParticleSystem.MainModule main = burstParticleSystem.main;
                main.startColor = new ParticleSystem.MinMaxGradient(vibrantColor, brightHighlight);

                ParticleSystem.ColorOverLifetimeModule col = burstParticleSystem.colorOverLifetime;
                col.enabled = true;
                Gradient grad = new Gradient();
                grad.SetKeys(
                    new GradientColorKey[]
                    {
                        new GradientColorKey(brightHighlight, 0f),
                        new GradientColorKey(vibrantColor, 0.35f),
                        new GradientColorKey(deepTip, 1f)
                    },
                    new GradientAlphaKey[]
                    {
                        new GradientAlphaKey(0f, 0f),
                        new GradientAlphaKey(1f, 0.10f),
                        new GradientAlphaKey(0.90f, 0.65f),
                        new GradientAlphaKey(0f, 1f)
                    }
                );
                col.color = new ParticleSystem.MinMaxGradient(grad);
            }

            if (ringWaveParticleSystem != null)
            {
                ParticleSystem.MainModule ringMain = ringWaveParticleSystem.main;
                ringMain.startColor = new ParticleSystem.MinMaxGradient(vibrantColor, brightHighlight);

                ParticleSystem.ColorOverLifetimeModule ringCol = ringWaveParticleSystem.colorOverLifetime;
                ringCol.enabled = true;
                Gradient ringGrad = new Gradient();
                ringGrad.SetKeys(
                    new GradientColorKey[]
                    {
                        new GradientColorKey(brightHighlight, 0f),
                        new GradientColorKey(vibrantColor, 0.5f),
                        new GradientColorKey(vibrantColor, 1f)
                    },
                    new GradientAlphaKey[]
                    {
                        new GradientAlphaKey(1f, 0f),
                        new GradientAlphaKey(0.8f, 0.5f),
                        new GradientAlphaKey(0f, 1f)
                    }
                );
                ringCol.color = new ParticleSystem.MinMaxGradient(ringGrad);
            }
        }

        private void BuildProfessionalParticleSystems()
        {
            if (burstParticleSystem != null)
                return;

            EnsureSharedParticleTexture();

            Shader particleShader = Shader.Find("Sprites/Default");
            if (particleShader == null)
                particleShader = Shader.Find("Universal Render Pipeline/Particles/Unlit");
            if (particleShader == null)
                particleShader = Shader.Find("Particles/Standard Unlit");

            instanceParticleMaterial = new Material(particleShader)
            {
                name = "AR_ObjectParticle_MatInstance",
                mainTexture = sharedGlowParticleTexture,
                color = Color.white
            };
            if (instanceParticleMaterial.HasProperty("_BaseMap"))
                instanceParticleMaterial.SetTexture("_BaseMap", sharedGlowParticleTexture);
            if (instanceParticleMaterial.HasProperty("_MainTex"))
                instanceParticleMaterial.SetTexture("_MainTex", sharedGlowParticleTexture);

            GameObject burstGo = new GameObject("TouchBurstParticles_VFX");
            burstGo.transform.SetParent(transform, false);
            burstGo.transform.localPosition = new Vector3(0f, 0.08f, 0f);

            burstParticleSystem = burstGo.AddComponent<ParticleSystem>();
            burstParticleSystem.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);

            ParticleSystem.MainModule main = burstParticleSystem.main;
            main.duration = 0.90f;
            main.loop = false;
            main.playOnAwake = false;
            main.simulationSpace = ParticleSystemSimulationSpace.World;
            main.startLifetime = new ParticleSystem.MinMaxCurve(0.50f, 1.00f);
            main.startSpeed = new ParticleSystem.MinMaxCurve(0.20f, 0.70f);
            main.startSize = new ParticleSystem.MinMaxCurve(0.025f, 0.058f);
            main.startRotation = new ParticleSystem.MinMaxCurve(0f, Mathf.PI * 2f);
            main.gravityModifier = -0.18f;
            main.maxParticles = 150;

            ParticleSystem.EmissionModule emission = burstParticleSystem.emission;
            emission.enabled = true;
            emission.rateOverTime = 0f;
            emission.SetBursts(new ParticleSystem.Burst[]
            {
                new ParticleSystem.Burst(0.0f, 45),
                new ParticleSystem.Burst(0.14f, 22)
            });

            ParticleSystem.ShapeModule shape = burstParticleSystem.shape;
            shape.enabled = true;
            shape.shapeType = ParticleSystemShapeType.Sphere;
            shape.radius = 0.075f;

            ParticleSystem.VelocityOverLifetimeModule vel = burstParticleSystem.velocityOverLifetime;
            vel.enabled = true;
            vel.space = ParticleSystemSimulationSpace.Local;
            vel.orbitalY = new ParticleSystem.MinMaxCurve(0.8f, 1.8f);

            ParticleSystem.SizeOverLifetimeModule sizeOverLife = burstParticleSystem.sizeOverLifetime;
            sizeOverLife.enabled = true;
            AnimationCurve sizeCurve = new AnimationCurve(
                new Keyframe(0f, 0.25f),
                new Keyframe(0.18f, 1.0f),
                new Keyframe(0.75f, 0.60f),
                new Keyframe(1f, 0f)
            );
            sizeOverLife.size = new ParticleSystem.MinMaxCurve(1f, sizeCurve);

            ParticleSystem.RotationOverLifetimeModule rotOverLife = burstParticleSystem.rotationOverLifetime;
            rotOverLife.enabled = true;
            rotOverLife.z = new ParticleSystem.MinMaxCurve(-2.5f, 2.5f);

            if (burstGo.TryGetComponent(out ParticleSystemRenderer burstRenderer))
            {
                burstRenderer.renderMode = ParticleSystemRenderMode.Billboard;
                burstRenderer.sharedMaterial = instanceParticleMaterial;
                burstRenderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                burstRenderer.receiveShadows = false;
            }

            GameObject ringGo = new GameObject("TouchShockwaveRing_VFX");
            ringGo.transform.SetParent(transform, false);
            ringGo.transform.localPosition = new Vector3(0f, 0.02f, 0f);
            ringGo.transform.localRotation = Quaternion.Euler(-90f, 0f, 0f);

            ringWaveParticleSystem = ringGo.AddComponent<ParticleSystem>();
            ringWaveParticleSystem.Stop(true, ParticleSystemStopBehavior.StopEmittingAndClear);

            ParticleSystem.MainModule ringMain = ringWaveParticleSystem.main;
            ringMain.duration = 0.65f;
            ringMain.loop = false;
            ringMain.playOnAwake = false;
            ringMain.simulationSpace = ParticleSystemSimulationSpace.World;
            ringMain.startLifetime = new ParticleSystem.MinMaxCurve(0.38f, 0.60f);
            ringMain.startSpeed = new ParticleSystem.MinMaxCurve(0.35f, 0.60f);
            ringMain.startSize = new ParticleSystem.MinMaxCurve(0.026f, 0.045f);
            ringMain.gravityModifier = 0f;
            ringMain.maxParticles = 70;

            ParticleSystem.EmissionModule ringEmission = ringWaveParticleSystem.emission;
            ringEmission.enabled = true;
            ringEmission.rateOverTime = 0f;
            ringEmission.SetBursts(new ParticleSystem.Burst[]
            {
                new ParticleSystem.Burst(0.0f, 32)
            });

            ParticleSystem.ShapeModule ringShape = ringWaveParticleSystem.shape;
            ringShape.enabled = true;
            ringShape.shapeType = ParticleSystemShapeType.Circle;
            ringShape.radius = 0.045f;
            ringShape.radiusThickness = 0f;
            ringShape.arcMode = ParticleSystemShapeMultiModeValue.BurstSpread;

            ParticleSystem.SizeOverLifetimeModule ringSize = ringWaveParticleSystem.sizeOverLifetime;
            ringSize.enabled = true;
            ringSize.size = new ParticleSystem.MinMaxCurve(1f, sizeCurve);

            if (ringGo.TryGetComponent(out ParticleSystemRenderer ringRenderer))
            {
                ringRenderer.renderMode = ParticleSystemRenderMode.Billboard;
                ringRenderer.sharedMaterial = instanceParticleMaterial;
                ringRenderer.shadowCastingMode = UnityEngine.Rendering.ShadowCastingMode.Off;
                ringRenderer.receiveShadows = false;
            }

            ApplyColorToParticleSystems(currentColor);
        }

        private static void EnsureSharedParticleTexture()
        {
            if (sharedGlowParticleTexture != null)
                return;

            const int size = 64;
            sharedGlowParticleTexture = new Texture2D(size, size, TextureFormat.RGBA32, false)
            {
                name = "ProceduralStarGlow_Tex",
                wrapMode = TextureWrapMode.Clamp,
                filterMode = FilterMode.Bilinear
            };

            float center = (size - 1) * 0.5f;
            for (int y = 0; y < size; y++)
            {
                for (int x = 0; x < size; x++)
                {
                    float dx = (x - center) / center;
                    float dy = (y - center) / center;
                    float dist = Mathf.Sqrt(dx * dx + dy * dy);

                    float radialGlow = Mathf.Clamp01(1f - dist);
                    radialGlow = Mathf.Pow(radialGlow, 2.0f);

                    float crossX = Mathf.Clamp01(1f - Mathf.Abs(dx) * 4.0f) * Mathf.Clamp01(1f - Mathf.Abs(dy) * 1.15f);
                    float crossY = Mathf.Clamp01(1f - Mathf.Abs(dy) * 4.0f) * Mathf.Clamp01(1f - Mathf.Abs(dx) * 1.15f);
                    float starSpike = Mathf.Max(crossX, crossY);

                    float alpha = Mathf.Clamp01(radialGlow + starSpike * 0.70f);
                    sharedGlowParticleTexture.SetPixel(x, y, new Color(1f, 1f, 1f, alpha));
                }
            }
            sharedGlowParticleTexture.Apply();
        }

        public void BeginPointerDrag()
        {
            isPointerDragging = true;
            pointerTargetPosition = transform.position;
            TriggerTouchParticlesEffect();
        }

        public void UpdatePointerDragPosition(Vector3 worldPosition)
        {
            isPointerDragging = true;
            pointerTargetPosition = worldPosition;
            transform.position = worldPosition;
        }

        public void EndPointerDrag()
        {
            isPointerDragging = false;
        }

        public void SetCustomColor(Color newColor)
        {
            currentColor = newColor;
            hasCustomColor = true;

            DisableTemplateColorAffordances();
            ApplyColorToRenderers(currentColor);
            ApplyColorToParticleSystems(currentColor);
            TriggerTouchParticlesEffect();
        }

        public void SetUniformScaleMultiplier(float multiplier)
        {
            currentScaleMultiplier = Mathf.Clamp(multiplier, minScaleMultiplier, maxScaleMultiplier);
            transform.localScale = initialRootScale * currentScaleMultiplier;
        }

        public void RotateAroundUp(float angleDegrees)
        {
            transform.Rotate(Vector3.up, angleDegrees, Space.Self);
        }

        public void SetAutoRotate(bool enabledState)
        {
            isAutoRotating = enabledState;
        }

        public void SetFloating(bool enabledState)
        {
            isFloating = enabledState;
            if (!isFloating && visualsTransform != transform)
            {
                floatTimer = 0f;
                visualsTransform.localPosition = initialVisualsLocalPos;
            }
        }

        public void ResetManipulations()
        {
            SetUniformScaleMultiplier(1f);
            transform.localRotation = initialRootRotation;
            SetAutoRotate(false);
            SetFloating(false);
            TriggerTouchParticlesEffect();
        }

        private void ApplyColorToRenderers(Color color)
        {
            if (cachedRenderers == null)
                return;

            Color edgeColor = Color.Lerp(color, Color.white, 0.35f);

            for (int i = 0; i < cachedRenderers.Length; i++)
            {
                Renderer rend = cachedRenderers[i];
                if (rend == null || rend is ParticleSystemRenderer)
                    continue;

                Material matInstance = rend.material;
                if (matInstance != null)
                {
                    matInstance.color = color;
                    if (matInstance.HasProperty(BaseColorShaderId))
                        matInstance.SetColor(BaseColorShaderId, color);
                    if (matInstance.HasProperty(ColorShaderId))
                        matInstance.SetColor(ColorShaderId, color);
                    if (matInstance.HasProperty(EdgeHighlightColorShaderId))
                        matInstance.SetColor(EdgeHighlightColorShaderId, edgeColor);
                }

                if (propertyBlock != null)
                {
                    rend.GetPropertyBlock(propertyBlock);
                    propertyBlock.SetColor(BaseColorShaderId, color);
                    propertyBlock.SetColor(ColorShaderId, color);
                    propertyBlock.SetColor(EdgeHighlightColorShaderId, edgeColor);
                    rend.SetPropertyBlock(propertyBlock);
                }
            }
        }

        public static string TranslateShapeName(string rawName)
        {
            if (string.IsNullOrEmpty(rawName))
                return "Cubo";

            if (rawName.IndexOf("Sphere", StringComparison.OrdinalIgnoreCase) >= 0 ||
                rawName.IndexOf("Esfera", StringComparison.OrdinalIgnoreCase) >= 0)
                return "Esfera";

            if (rawName.IndexOf("Pyramid", StringComparison.OrdinalIgnoreCase) >= 0 ||
                rawName.IndexOf("Piramide", StringComparison.OrdinalIgnoreCase) >= 0)
                return "Pirámide";

            if (rawName.IndexOf("Cylinder", StringComparison.OrdinalIgnoreCase) >= 0 ||
                rawName.IndexOf("Cilindro", StringComparison.OrdinalIgnoreCase) >= 0)
                return "Cilindro";

            if (rawName.IndexOf("Torus", StringComparison.OrdinalIgnoreCase) >= 0 ||
                rawName.IndexOf("Dona", StringComparison.OrdinalIgnoreCase) >= 0)
                return "Dona / Toroide";

            if (rawName.IndexOf("Wedge", StringComparison.OrdinalIgnoreCase) >= 0 ||
                rawName.IndexOf("Rampa", StringComparison.OrdinalIgnoreCase) >= 0)
                return "Rampa / Cuña";

            if (rawName.IndexOf("Arch", StringComparison.OrdinalIgnoreCase) >= 0 ||
                rawName.IndexOf("Arco", StringComparison.OrdinalIgnoreCase) >= 0)
                return "Arco";

            if (rawName.IndexOf("Debug", StringComparison.OrdinalIgnoreCase) >= 0)
                return "Cubo Biselado";

            if (rawName.IndexOf("Cube", StringComparison.OrdinalIgnoreCase) >= 0 ||
                rawName.IndexOf("Cubo", StringComparison.OrdinalIgnoreCase) >= 0)
                return "Cubo";

            return rawName.Replace("(Clone)", string.Empty).Replace("Variant", string.Empty).Trim();
        }
    }
}
