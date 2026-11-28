# Arquitectura del MVP — F0-3

Base normativa: [GDD aprobado](../GDD.md), [plan](../PLAN_DE_TRABAJO.md) y `AGENTS.md`. Ante conflicto, manda el GDD aprobado. Esta entrega define contratos; no implementa código ni aprueba D4. Los valores nuevos identificados como **decisión de spec** son iniciales para playtest. Las referencias a archivos `.luau` son archivos futuros.

## Autoridad y límites

El servidor decide fases, movimiento permitido, salud, batería, inventario, interacciones, construcción, objetivos, estímulos y resultados. El cliente captura intención, predice presentación y dibuja cámara, HUD, fantasmas, iluminación y sonido. Ninguna animación, atributo escrito por cliente o fin de barra autoriza un resultado.

**F0-4 — autoridad física:** el personaje es el único ensamblaje que simula el cliente, y su posición solo se usa a través de la posición validada de PlayerService ([jugador](jugador.md)). Todo lo demás que el servidor usa como autoridad está anclado; los enemigos reciben `SetNetworkOwner(nil)` al aparecer y tras cualquier cambio de ensamblaje. Ningún resultado de juego (daño, recogida, zona) se decide con `Touched`; se usan consultas espaciales del servidor. Sin `Tool`/Backpack de Roblox ni handlers de ProximityPrompt en servidor. Detalle en «Autoridad física y replicación» de [remotes](remotes.md).

Una run pertenece a un servidor y admite de 1 a 4 participantes. No hay mundo persistente, teletransporte a otros places ni matchmaking en el MVP. Todos los nuevos scripts y módulos usarán `--!strict`. No se crean scripts manuales en Studio.

## Servicios de servidor

| Servicio futuro en `src/server/services/` | Propiedad y responsabilidad | Dependencias operativas |
|---|---|---|
| `WorldService` | Valida contenido de Studio, registra IDs opacos, clona prefabs, reinicia mundo y nodos por run. Nunca fabrica modelos faltantes. | Configs |
| `DataService` | Perfil meta, carga y guardado; nunca restaura una run. | Adaptador DataStore; detalle de concurrencia en F6-1 |
| `SessionService` | Lobby, roster congelado, `runId`, resultado terminal único, reinicio. | Data, World, DayNight, Player, Objective |
| `PlayerService` | Estado vital, estamina, movimiento, linterna, equipamiento visual, mochila al morir, reaparición. | Inventory, Stimulus, World |
| `InventoryService` | Único escritor de cantidades; transacciones de consumo/entrega, recetas y capacidad. | Configs |
| `ResourceService` | Nodos, golpes, contenedores, loot y agotamiento. | World, Inventory, Player, Stimulus |
| `BuildingService` | Snapping canónico, colocación, ocupación, HP, reparación, puertas, fogata y combustible. | World, Inventory, Player, Stimulus |
| `ObjectiveService` | Las cuatro piezas, portadores, instalaciones y transmisión. | World, Player, Stimulus |
| `InteractionService` | Reservas y temporizadores de acciones mantenidas; despacha a su servicio propietario. | Player y servicios interactuables |
| `StimulusService` | Registro consultable de ruido, luz y seguridad para la IA. | Configs; recibe hechos de otros servicios |
| `DayNightService` | Reloj de fases, tabla de noches y director simple. | Configs; emite cambios internos |
| `AIService` | Consumidor de contratos de fase/estímulos; aplica daño mediante servicios propietarios. Requisitos F0-4 para F4-2: `SetNetworkOwner(nil)` en todo enemigo, daño por consulta de distancia/hitbox en servidor contra la posición validada del jugador (nunca `Touched`). | World, Stimulus, Player, Building, Objective; implementación bloqueada hasta F4-1/F4-2 |
| `ReplicationService` | Snapshots privados/compartidos, resultados y señales cosméticas por Remotes. | Lectura de servicios; no decide gameplay |

Las dependencias se inyectan al inicializar: no se hacen `require` circulares entre servicios. `src/shared/types.luau` contiene tipos de contratos y `Remotes.luau` el registro único de red. Señales internas son callbacks o señales en memoria, nunca Remotes usados como bus servidor-servidor. Métodos mutantes son síncronos y sin yield dentro de una transacción; operaciones DataStore ocurren fuera de ellas.

## Arranque y cierre

1. `src/server/init.server.luau` carga y valida configs, tipos estructurales y catálogo de Remotes. Crea los RemoteEvents en el servidor una sola vez.
2. Construye todos los servicios; llama `Init(context)` sin comenzar bucles. World valida prefabs, pivotes, sockets, volúmenes y marcadores. Un requisito ausente bloquea el inicio de run con diagnóstico del path; no genera un sustituto.
3. Inicia World, Data, Inventory, Stimulus, Player, Resource, Building, Objective e Interaction. Atiende también jugadores ya presentes al conectar `PlayerAdded`.
4. Inicia Replication y conecta handlers validados; después DayNight y AI quedan inactivos hasta una run; Session habilita el lobby al final. Los perfiles pendientes no entran al roster.
5. Al comenzar: fija roster y escalado, reinicia World y servicios por `runId`, crea personajes, entrega kit inicial, publica snapshot y empieza Día 1. Cada callback asíncrono comprueba su `runId` antes de modificar estado.
6. Al terminar: Session fija un único resultado, cancela acciones/director/daño, toma resumen meta y solicita guardado. Muestra resultado antes del próximo lobby. Al abandonar o cerrar servidor, Data solicita su flush acotado (F6-1); no bloquea indefinidamente el ciclo de juego.

**Decisión de spec:** orden de actualización autoritativo por tick: validar movimiento e interacciones; aplicar acciones y daño pendientes en orden de aceptación; avanzar transmisión hasta el límite temporal; evaluar aniquilación; resolver cambio de fase y victoria/tiempo; reaparecer; publicar. La derrota por aniquilación ya ocurrida no se revierte al amanecer. Quién gana entre eventos del mismo tick (fin de hold contra daño, revive contra bleedout, desconexión, watchdog) se decide por tiempo de servidor según «Orden temporal y carreras» de [remotes](remotes.md). Los límites de fase usan tiempo monotónico de servidor, no suma de frames del cliente.

## Cliente

| Controller futuro en `src/client/controllers/` | Responsabilidad |
|---|---|
| `StateController` | Solicita snapshot, descarta revisiones viejas y distribuye estado confirmado. |
| `InputController` | Enruta teclado, mando y táctil a intenciones; respeta bloqueos visuales. |
| `CameraController` | Cámara primera/tercera persona (V), agachado visual, viewbobbing, cuerpo propio visible en primera persona y colisión de la tercera persona (antes `FirstPersonController`). |
| `HeldItemController` | Pose local de sostener y golpe cosmético para todos los personajes con `HeldRight`/`HeldLeft` y `SwingSeq`. |
| `MovementController` | Solicita modo de movimiento y reconcilia estamina/velocidad autorizada. |
| `FlashlightController` | Luz local, batería y orientación; los efectos en IA dependen del servidor. |
| `InteractionController` | Foco y barra de acciones, inicio/cancelación, prompts. |
| `InventoryController` | Inventario, herramienta equipada y recetas; no altera cantidades. |
| `BuildPreviewController` | Raycast y preview; envía propuesta, espera colocación confirmada. |
| `EnvironmentController` | Presets de Lighting/Atmosphere por fase y noche. |
| `SoundController` | Audio 3D, ambiente y señales de amenaza confirmadas. |
| `HUDController` | Vida, estamina, batería, reloj, objetivos, lobby y resultado. |
| `SpectatorController` | Cámaras sobre compañeros; sin autoridad sobre respawn. |

`init.client.luau` espera Shared y Remotes con timeout, carga módulos UI, conecta recepción antes de pedir `RequestSnapshot`; después habilita input. Una respuesta perdida se recupera con snapshot, no repitiendo mutaciones. Los controllers limpian conexiones y vistas en cada cambio de personaje/run.

## Mapeo para el futuro `default.project.json`

| Ruta del repo | Destino Roblox | Convención |
|---|---|---|
| `src/server/` | `ServerScriptService/Server` | `init.server.luau` convierte el nodo Server en Script; `services/` queda como hijo. |
| `src/client/` | `StarterPlayer/StarterPlayerScripts/Client` | `init.client.luau` convierte Client en LocalScript; controllers son hijos. |
| `src/shared/` | `ReplicatedStorage/Shared` | Folder con ModuleScripts y configs; solo lectura conceptual en cliente. |
| `src/ui/` | `StarterGui/UI` | Folder de ModuleScripts de vistas; el bootstrap cliente los requiere desde `PlayerGui/UI` y crea ScreenGuis con `ResetOnSpawn=false`. Sin otro LocalScript de arranque. |

Rojo administra solo estos subárboles, preservando instancias desconocidas en servicios/contenedores ancestros (`$ignoreUnknownInstances` en los nodos apropiados). No mapear ni sobrescribir Workspace, Lighting ni ServerStorage/Prefabs. `ReplicatedStorage/Remotes` y `ReplicatedStorage/BuildPreviews` son carpetas de runtime creadas por el servidor, fuera de Shared. **Decisión de spec:** Building publica copias visuales saneadas de los cuatro prefabs para preview (sin scripts, colisión, lógica ni autoridad); clona las construcciones reales desde ServerStorage.

## Contenido de Studio

- `Workspace/Map`: terreno, caseta, radio fija indestructible, río con su barrera de jugadores, puente (`Map/Puente`, atributo `BridgeBuilt`), mina, complejo, volúmenes de zonas y superficie permitida para construir. Lighting inicial y assets de audio son contenido artístico de Studio.
- `Workspace/Markers`: `BaseSpawn`, `RadioSocket`, `CampfireSocket`, `ObjectiveSpawns/<PieceId>/01..03`, `ResourceSpawns`, `LootSpawns`, `EnemySpawns`, `Nest`, `WaterZones`, `BuildZones`, `NoBuildZones`, `PatrolPoints/<RouteId>/NN`, `Hideouts`, `BridgeSite`, `BridgeEnds`, `CreatureCrossings`, `AnomalyZones`, `LorePoints`. IDs de autoría únicos; distancias y distribución se validan contra configs. Marcadores no colisionan. Coordenadas, atributos y nombres exactos en [mapa](mapa.md).
- Tags de CollectionService (duplican las carpetas, que siguen siendo la fuente de verdad): `MapZone` (volúmenes de `Map/Zones`), `PieceSpawn`, `ResourceSpawn`, `LootSpawn`, `EnemySpawn`, `Nest`, `WaterZone`, `BuildZone`, `NoBuildZone`, `PatrolPoint`, `Hideout`, `BridgeSite`, `BridgeEnd`, `CreatureCrossing`, `AnomalyZone`, `LorePoint`. Además `PlayerBarrier` en las Parts de `Map/Rio` (colisionan con jugadores; el grupo de colisión que deja pasar a los enemigos lo asigna el servidor en F4). Los servicios pueden usar `GetTagged` o recorrer la carpeta; ambos deben dar el mismo conjunto.
- `ServerStorage/MapVariants/PuenteConstruido`: variante del tramo central del puente, contenido de Studio generado por MapBuilder. Solo el servidor la clona en `Map/Puente/Construido` (comando de debug en Studio en F1; construcción por tramos en Fase 3) y WorldService la retira al empezar cada run.
- `ServerStorage/Prefabs`: `Cimiento`, `Pared`, `MarcoPuerta`, `Fogata`, `CriaturaPrincipal`, `AcechadorMenor`, `Arbol`, `Roca`, `Arbusto`, `Contenedor`, `Mochila`, `Pila`, `Chatarra`, `PiezaBateria`, `PiezaAntena`, `PiezaTransceptor`, `PiezaCristal`. Subcarpeta `ServerStorage/Prefabs/Held` con los modelos en mano (`Hacha`, `Pico`, `Venda`, `Botiquin`, `Lata`, `Baya`, `Pila`, `Linterna`; contrato en [jugador](jugador.md)). Nombres de búsqueda en `WorldConfig`; prefabs sin Scripts. Hitboxes, pivotes y Attachments se detallan en cada spec.
- `Workspace/Runtime`: carpeta creada en servidor para clones de cada run. Nunca se borra Map al reiniciar. Nodos y loot se restauran desde marcadores/prefabs.

## Mapa de configs

Todos bajo `src/shared/config/`, sin crearlos en F0-3:

| Archivo | Valores que posee |
|---|---|
| `SessionConfig.luau` | Capacidad, lobby, fin y política de roster. |
| `PlayerConfig.luau` | Cámara, movimiento, salud, estamina, caída, linterna, kit inicial. |
| `ItemsConfig.luau`, `RecipesConfig.luau`, `ResourcesConfig.luau` | Ítems, stacks/capacidad, recetas, nodos y loot. |
| `StructuresConfig.luau` | Costos, HP, snapping, alcance, reparación, fogata. |
| `NightsConfig.luau` | Fases, tabla aprobada, escalado y temporizadores del director. |
| `ObjectivesConfig.luau` | Piezas, hold, distancias, transmisión y recuperación fuera del mapa. |
| `StimuliConfig.luau` | Radios, vigencia, luz, ruido e interfaz de percepción. |
| `NetworkConfig.luau` | Límites por Remote, tamaños, tolerancias y replicación. |
| `InteractionConfig.luau` | Rango/holds comunes, exclusión mutua e interrupciones. |
| `WorldConfig.luau` | Nombres de assets, tags, límites del mapa y zonas. |
| `PresentationConfig.luau` | Input bindings, IDs de audio, brillo, colores, niebla, HUD y feedback. Assets aún no elegidos se validan antes de la tarea que los use. |
| `DataConfig.luau` | Nombre/versionado del store, topes de estadísticas; parámetros de fiabilidad pendientes de F6-1. |
| `EnemiesConfig.luau` | Reservado a F4-1/F4-2: daño, velocidades, escalera de avisos y navegación. F0-3 no los inventa. |

Una magnitud tiene un único propietario: por ejemplo Stimuli consulta radios seguros en NightsConfig y no mantiene una copia. Configs replicadas no contienen secretos. Los IDs estables del protocolo no son valores de balance.

## Comprobación futura en Studio

Con Rojo conectado, verificar rutas en Explorer, iniciar Play y dos clientes, comprobar un único bootstrap por lado, snapshot inicial y reinicio sin conexiones duplicadas. Quitar temporalmente un prefab debe bloquear la run e indicar su nombre. Comprobar que publicar el proyecto Rojo no borra mapa ni prefabs. Esta entrega documental no modifica el place.
