# Trabajo Práctico — Realidad Aumentada Móvil en Unity 6 (Image Tracking & Plane Tracking)

**Cátedra:** Simulaciones — Universidad Abierta Interamericana (UAI)  
**Plantilla Base:** Unity AR Mobile Template (`2.1.3`) + Universal Render Pipeline (URP `17.0.4`)

---

## 1. Especificaciones Técnicas del Entorno

| Componente / Paquete | Versión | Identificador |
| :--- | :--- | :--- |
| **Versión del Editor de Unity** | `6000.0.48f1` (Unity 6) | `6000.0.48f1 (170d2541580d)` |
| **AR Foundation** | `6.5.0` | `com.unity.xr.arfoundation` |
| **ARCore XR Plug-in (Android)** | `6.5.0` | `com.unity.xr.arcore` |
| **ARKit XR Plug-in (iOS)** | `6.5.0` | `com.unity.xr.arkit` |
| **XR Interaction Toolkit** | `3.5.1` | `com.unity.xr.interaction.toolkit` |
| **Input System** | `1.19.0` | `com.unity.inputsystem` |
| **Universal Render Pipeline (URP)** | `17.0.4` | `com.unity.render-pipelines.universal` |

---

## 2. Organización del Proyecto

El repositorio está estructurado siguiendo la guía práctica de la cátedra:

- **`Assets/Scenes/ImageTargetLab.unity`**: Escena principal de **Image Tracking** derivada de `SampleScene`, donde se conserva `AR Session` y `XR Origin` con `ARTrackedImageManager` + `ImageTargetContent`, y se desactivan el `ObjectSpawner`, `ARPlaneManager` y los menús de colocación por planos para aislar la experiencia de reconocimiento de imágenes.
- **`Assets/Scenes/SampleScene.unity`**: Escena de **Detección de Planos y Manipulación de Objetos 3D** con interfaz interactiva de transformación, colores URP y animaciones.
- **`Assets/AR/Images/`**:
  - `TarjetaLaboratorio_A.png` (**Target 1: `Perro`**): Fotografía de Pastor Alemán de alto contraste (`0.15 m × 0.15 m`).
  - `TarjetaLaboratorio_B.png` (**Target 2: `Gato`**): Fotografía de Gato Tabby de alto contraste (`0.15 m × 0.15 m`).
- **`Assets/AR/TargetsLibrary.asset`**: `XRReferenceImageLibrary` configurada con ambas imágenes (`Perro` y `Gato`), con `Specify Size = true` (`0.15 m` de ancho para impresiones o pantallas de `15 × 15 cm`) y `Keep Texture at Runtime = true`.
- **`Assets/AR/Prefabs/`**:
  - `ContentOnTarget.prefab`: Prefab 3D para la imagen del **Perro** (envuelve el modelo animado `P_GermanShepherd` de `Assets/RSG_DogsPack/HDRP/Prefabs/P_GermanShepherd.prefab` con materiales convertidos a URP Lit y escala normalizada a `13 cm` sobre la imagen).
  - `ContentOnTarget_B.prefab`: Prefab 3D para la imagen del **Gato** (envuelve el modelo animado `Cat_05` de `Assets/Realistic Cat Demo/Prefabs/URP/Mobile/Cat_05.prefab` con escala normalizada a `12 cm` sobre la imagen).
- **`Assets/Scripts/ImageTargetContent.cs`**:
  - Utiliza `[RequireComponent(typeof(ARTrackedImageManager))]` y la API recomendada de **AR Foundation 6.x** (`manager.trackablesChanged.AddListener(OnImagesChanged)`).
  - Distingue eventos `args.added`, `args.updated` y `args.removed`.
  - Asocia cada `ARTrackedImage` con su prefab específico mediante `image.referenceImage.name` (`Perro` → Pastor Alemán 3D; `Gato` → Gato Tabby 3D).
  - Gestiona los estados de seguimiento (`TrackingState.Tracking`, `TrackingState.Limited`, `TrackingState.None`): mantiene el objeto en un `Dictionary<TrackableId, GameObject>` y alterna su visibilidad con `SetActive(image.trackingState == TrackingState.Tracking)` sin destruir ni duplicar instancias en cada frame.
  - **Extensiones implementadas:**
    1. **Contador de detecciones por target:** Registra cuántas veces entró en estado `Tracking` cada imagen (`Perro` y `Gato`).
    2. **Control de Rotación y Escala del contenido:** Permite escalar (`0.4x` a `2.5x`) y rotar (`±35°`) el modelo 3D del perro o del gato anclado sobre el target.
    3. **UI de Estado en Tiempo Real:** Muestra el mensaje de ayuda inicial (*Esperando Imagen*), el estado activo (*Tracking Activo*) y la alerta cuando se pierde el seguimiento (*Seguimiento Perdido — Limited*).

---

## 3. Dispositivo de Prueba y Dificultades Encontradas

### Dispositivo utilizado
- **Captura y Cámara Móvil:** iPhone (iOS) / Dispositivo móvil compatible con ARKit/ARCore + prueba asistida en PC mediante transmisión de cámara en vivo (`Iriun Webcam` / `XR Simulation`).

### Dificultades encontradas y cómo se resolvieron
1. **Diferencia entre API de AR Foundation 5.x y 6.x (`trackablesChanged`):**
   - Muchos ejemplos antiguos utilizan el evento obsoleto `trackedImagesChanged += ...`. En **AR Foundation 6.5.0** se implementó correctamente `manager.trackablesChanged.AddListener(OnImagesChanged)` recibiendo `ARTrackablesChangedEventArgs<ARTrackedImage>`, donde `args.removed` expone pares `KeyValuePair<TrackableId, ARTrackedImage>`.
2. **Gestión del estado `Limited` al tapar o retirar la imagen del cuadro:**
   - Cuando una imagen sale del encuadre de la cámara, el subsistema AR no dispara inmediatamente `removed`, sino `updated` con `TrackingState.Limited`. Para evitar que el objeto 3D quede flotando en una pose congelada o que se instancien duplicados al volver a enfocar la tarjeta, se almacenó cada instancia en un diccionario indexado por `TrackableId` y se alternó su visibilidad con `go.SetActive(image.trackingState == TrackingState.Tracking)`.
3. **Posicionamiento local y escala en metros del Prefab (`ContentOnTarget`):**
   - Al trabajar con un target físico de `0.15 m` (`15 cm`), un cubo por defecto de Unity (`1 m` de lado) cubriría toda la cámara y atravesaría el plano de la imagen. Se ajustó la escala del mesh hijo a `0.05 m` (`5 cm`) y se elevó su posición local en el eje `Y` (`y = 0.035 m`) para que apoye exactamente sobre el centro del target.
4. **Pruebas desde Windows con iPhone:**
   - Dado que la compilación nativa de ARKit para iOS requiere firma con Xcode en macOS y que `XR Simulation` en el Editor no procesa por sí solo la cámara física de un teléfono por USB sin compilar la app, se integró además un puente de cámara en vivo (`WebCamTexture` con `Iriun Webcam`) y un visor de tarjetas en pantalla para validar el flujo completo de estados (`Esperando` → `Tracking` → `Limited`) tanto en el Editor como en el dispositivo.
