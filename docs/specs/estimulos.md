# Estímulos de ruido y luz — F0-3

Base: GDD §5 y tabla de §3. Esta spec define solamente la interfaz que StimulusService expone a la IA y los productores de estímulos. No define Patrullar/Investigar/Acechar/Atacar, umbrales de transición, despertar exacto, remates ni presupuesto de Pathfinding: pertenecen a F4-1/F4-2. No existe Remote `EmitNoise` ni `EmitLight` aceptado desde cliente.

## Autoridad y tipos internos

Productores servidor: PlayerService (movimiento, linterna, grito), ResourceService (golpes/aperturas), BuildingService (obra/fogata), InteractionService (revive), ObjectiveService (radio). El cliente reproduce audio/luz a partir de hechos aceptados; silenciar audio, esconder una luz o alterar volumen no cambia percepción.

Contrato de datos interno en `src/shared/types.luau` (solo el servidor lo escribe):

- `NoiseStimulus`: `{id: string, runId: string, kind: NoiseKind, sourceId: string, position: Vector3, emittedAt: number, expiresAt: number, scope: "Local" | "Global", radius: number?, strength: number}`.
- `LightStimulus`: `{id: string, runId: string, kind: "Flashlight" | "Campfire", sourceId: string, position: Vector3, direction: Vector3?, range: number, coneDegrees: number?, enabled: boolean, updatedAt: number}`.
- `SafeZone`: `{sourceId: string, center: Vector3, radius: number, protectsFrom: "MainCreature", enabled: boolean}`.
- `PerceptionContext`: `{night: number, detectionMultiplier: number, phase: Phase, mainCreatureUniqueId: string?, nestZoneId: string}`. Phase se define en remotes.

API servidor: `EmitNoise(kind, sourceId, position)`, `RegisterLight/UpdateLight/RemoveLight`, `QueryNoise(listenerPosition, context)`, `QueryLights(listenerPosition, context)`, `GetSafeZones(context)`, `IsProtectedFromMain(position)`. Los productores eligen un kind cerrado; el servicio deriva radio, strength y vigencia de config, no acepta radios del cliente. Posiciones proceden de entidades validadas: para jugadores, la posición validada de PlayerService. Zonas (agua, nido, zona segura) se resuelven con consultas espaciales del servidor, nunca con `Touched` (F0-4). Se limpia todo al cerrar run; estímulos efímeros caducan y fuentes continuas se eliminan al desaparecer su dueño.

## Ruido

Valores aprobados en `src/shared/config/StimuliConfig.luau`:

| NoiseKind | Radio base | Productor/condición |
|---|---:|---|
| `CrouchStep` | 0 | No se registra estímulo audible |
| `WalkStep` | 10 studs | Movimiento Walk verificado |
| `WaterStep` | 25 studs | Movimiento en volumen pantano/agua de Studio |
| `SprintStep` | 35 studs | Sprint autorizado y desplazamiento real |
| `ResourceHit` | 50 studs | Golpe aceptado a nodo |
| `BuildRepair` | 45 studs | Colocación aceptada o reparación mantenida |
| `MetalOpen` | 30 studs | Puerta metálica/contenedor de gasolinera abierto |
| `Revive` | 30 studs | Revive mantenido válido |
| `DownedShout` | 60 studs | Caído y cooldown cumplido |
| `RadioTransmission` | Global (todo mapa) | Fuente continua Transmitting |
| `PieceImpact` | 60 studs | Pieza soltada que cae más de `ObjectivesConfig.ImpactMinDropStuds` y toca el suelo (caso típico: Antena desde la torre, ver [objetivos](objetivos.md)). Impulso único en el punto de impacto |

**Decisión de spec:** clases adicionales necesarias: `IgniteCampfire`=45 studs, `WoodDoor`=10 studs. Feedback de instalar pieza y crafting son cosméticos y no crean ruido de IA adicional. `StimuliConfig` contiene estos radios, `ShoutCooldownSeconds=5`, `ImpulseLifetimeSeconds=2`, `ContinuousRefreshSeconds=0.5`, `MovementStepSeconds=0.5`, `InteractionNoiseSeconds=1`. Revive/reparación/encendido emiten al inicio y cada segundo válido; cancelar no borra ruido ya emitido. Ruido de construcción solo al confirmar; intentos inválidos no atraen enemigos artificialmente.

**Decisión de spec:** agua tiene precedencia sobre crouch silencioso; en agua agachado emite 25, corriendo emite max(25,35)=35. En suelo seco agachado/gateando emite 0. Movimiento quieto no genera pasos. El origen y zona se derivan del desplazamiento y volúmenes de servidor.

**F0-4 — el ruido sale de la velocidad medida, no del modo declarado:** el modo lo pide el cliente con `SetMovementMode`, así que alternarlo entre muestras no puede silenciar pasos. En cada paso (`MovementStepSeconds`) el tipo es el más ruidoso entre (a) el del modo declarado y (b) el que corresponde a la velocidad horizontal medida sobre la posición validada en la última ventana de 0.5 s: por encima de la velocidad de agachado + 1 stud/s cuenta al menos como `WalkStep`, y por encima de la de caminar + 1 stud/s como `SprintStep`. La regla del agua se aplica después. No hay ruido por voz, chat o volumen del micrófono.

Radio efectivo local = radio base × DetectionMultiplier de la noche actual; durante Día/Atardecer/Amanecer x1.0. `QueryNoise` solo devuelve estímulos vigentes dentro de rango, o globales. **Decisión de spec:** paredes no atenúan ruido en MVP. Strength local = radio base; global tiene prioridad explícita por scope. Orden determinista: global primero, mayor strength, menor distancia, más reciente, ID. Esto permite a IA investigar el más fuerte audible sin definir su máquina de estados. Registro coalescido por sourceId/kind cada 0.5 s y cap 256 impulsos (`StimuliConfig.MaxActiveImpulses`); al superar cap expiran primero los más antiguos; fuentes globales continuas se almacenan aparte.

## Luz, seguridad y contrato de IA

**Decisión de spec:** `StimuliConfig.Flashlight` tiene Range=60 studs y ConeDegrees=50 (ángulo completo). Posición sale del anclaje de pecho/cabeza en servidor; dirección unitaria finita llega por `SetFlashlightAim` y se limita a giro máximo 1800°/s (`NetworkConfig.FlashlightMaxTurnDegPerSecond`, subido desde 720 en F0-4 porque girar 180° de golpe es un gesto legítimo) y pitch ±80° (NetworkConfig), sin cambiar origen. Si no hay aim válido durante 1 s, se usa dirección frontal del personaje, no se borra luz. Apagada/batería 0/Downed retira fuente.

`NetworkConfig.FlashlightAimTimeoutSeconds=1` es el propietario del timeout; el primer aim tras encender usa frente del personaje como referencia angular. Cliente envía aim a 10 Hz como máximo, usando la misma tasa declarada en NetworkConfig.

Para percepción de linterna: alcance × DetectionMultiplier; requiere dentro del cono y raycast sin obstáculo opaco entre fuente y receptor. Los menores reciben además predicado `IsDirectFlashlightOn(enemyPosition)` con alcance base 60, sin multiplicador; desde noche 3 pueden retroceder. Intensidad/duración de retroceso y efectos de iluminación en el nido son reglas de F4-2; esta API solo aporta evidencia. La criatura principal no se aturde con linterna en MVP.

Fogata encendida: luz local visual y fuente de localización global de base para la criatura, independientemente de LOS. `StimuliConfig.Campfire.VisualRange=40` studs inicial; alcance visual no cambia el hecho de que IA conoce la base ni equivale a zona segura. Apagarla retira emisión activa, pero no borra conocimiento ya adquirido por IA.

Radio seguro de la principal proviene únicamente de NightsConfig: Noche 1=12, 2=10, 3=8, 4=6, 5=0 studs. **Decisión de spec:** durante Día/Atardecer/Amanecer se usa radio de la noche correspondiente al ciclo (Amanecer conserva la noche que termina). Zona es esfera alrededor de CampfireSocket, sin inmunidad a través de obstáculos: requiere LOS a fogata; radio 0 siempre deshabilitado, incluso en el centro.

Solo protege de la criatura principal; los menores pueden entrar y apagarla desde noche 3. `IsProtectedFromMain` es contrato tanto para evitar entrada como para rechazar daño de la principal a un jugador protegido; no da invulnerabilidad general. Si se enciende estando la principal dentro, IA debe retirarse y no hacer daño mientras sale (F4-2 resolverá movimiento). No se cancela daño legítimo anterior al encendido. Curación es independiente y la aplica Building/PlayerService según construcción, no StimulusService.

`ExtinguishByEnemy` valida identidad/tipo, noche ≥3, contacto y fuente existente; la IA no modifica atributos arbitrariamente. Fogata sin combustible o HP también se apaga. Reencender dura 5 s; radio seguro se activa solo tras commit. No se comunica «IA debe atacar» desde cliente.

## Mina y frontera con F4

World identifica volumen Nest. Query devuelve luces incidentes y ruidos audibles en él también de día. F4-1/F4-2 debe definir qué cuenta como ruido fuerte para despertar, duración de caza, avisos y retorno, además de respuesta a fuentes de luz. F0-3 no puede convertir simplemente todo ruido en ataque diurno. Hasta tener esas specs, pruebas usan un consumidor ficticio servidor que inspecciona entradas, no una IA improvisada.

## Pruebas futuras en Studio

Con dos jugadores y consumidor de prueba, comparar radios base y multiplicados en borde, expiración y prioridad global; caminar/agachar en seco y agua; spam de acciones rechazadas sin ruido; visión bloqueada de linterna y aim obsoleto. Encender/apagar fogata en cada noche verifica 12/10/8/6/0, excepción de menores y ausencia de seguridad tras agotarse combustible. Ninguna modificación local del brillo/volumen debe alterar resultados.
