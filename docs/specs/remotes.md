# Catálogo completo de Remotes del MVP — F0-3 (revisado en F0-4)

Único registro futuro: `src/shared/Remotes.luau`; instancias en `ReplicatedStorage/Remotes`, creadas por servidor y esperadas por cliente. Este catálogo es cerrado: no hay Remote de daño, hora, guardado, ruido, materiales, victoria, teleport ni un Remote genérico para invocar métodos. Todos son **RemoteEvent**, ninguno RemoteFunction: no bloquear servidor esperando respuesta de cliente. Los snippets son contratos documentales, no archivos de implementación.

## Envolvente y reglas comunes

Cliente → servidor (C→S): cada payload lleva `requestId: string` y `runId: string`. RequestId único por solicitud; runId es el token actual de sesión, también presente en Lobby/Result. `RequestSnapshot` permite runId vacío para bootstrap. El Player lo aporta Roblox en OnServerEvent; nunca llega userId como identidad del solicitante. Strings ID de hasta 64 bytes, ASCII alfanumérico/guion/underscore/dos puntos; sin texto libre. Enums por allowlist. Tablas planas o uniones documentadas, sin campos adicionales, ciclos, Instances, funciones, NaN, infinito o valores fuera de rango.

`src/shared/config/NetworkConfig.luau` posee todos los límites de esta spec (**decisión de spec**): solicitudes ≤1024 bytes lógicos, profundidad máxima 3, 16 claves totales, coordenadas de grid enteras con valor absoluto ≤1024 (además de bounds de BuildZone). Validar forma con recorrido acotado, no serializar una tabla atacante entera para medirla. Dirección Vector3 finita y módulo entre 0.99 y 1.01, normalizada por servidor. Mover hacia límites válidos no sustituye rechazar un payload inválido.

**Reglas de validación de valores (F0-4, obligatorias):**

- El handler acepta exactamente un argumento además del Player (`select("#", ...) == 1`); argumentos extra o ausentes → `InvalidPayload`.
- Comprobar `typeof` antes de leer cualquier campo. Una tabla con metatabla, claves no string o array mezclado → `InvalidPayload`.
- Números: primero `x == x` (descarta NaN) y `math.abs(x) ~= math.huge` (descarta infinito); después enteros con `math.floor(x) == x`; después rango escrito **en forma positiva** (`x >= min and x <= max` → aceptar). Nunca validar con la forma negativa (`if x < min or x > max then rechazar`), porque NaN la atraviesa.
- Vector3: las tres componentes pasan la regla de números antes de calcular el módulo.
- Strings: comprobar longitud antes de aplicar patrones.
- Un validador por Remote, generado desde la tabla de esta spec; ningún handler lee un campo que el validador no haya comprobado.

Antes de tocar gameplay: límite global por Player 30 tokens/s, burst 40; después bucket por Remote de tabla (tokens/s, capacidad burst); después cooldown de acción/dominio. Cada solicitud cuesta 1. Rechazos también consumen bucket, sin loops ni esperas costosas. Sin mensajes de error por cada paquete de un spammer: se limita respuesta de error a 2/s. No expulsar automáticamente por un único exceso.

**Cooldowns de gameplay con tolerancia sin acumulación (F0-4):** cada cooldown (golpe, crafteo, colocación, soltar, inicio de interacción) guarda `readyAt` por jugador. Se acepta si `now >= readyAt - NetworkConfig.CooldownToleranceSeconds` (0.1 s) y entonces `readyAt = max(now, readyAt) + cooldown`. Así dos paquetes que llegan juntos por jitter no se rechazan, pero la cadencia sostenida nunca supera `1 / cooldown`. `now` es tiempo del servidor al procesar el paquete.

Deduplicar por `(Player, runId, requestId)` solo los Remotes que devuelven `ActionResult` (no `SetFlashlightAim` ni `RequestSnapshot`), durante 30 s, máximo 128 entradas por jugador con desalojo FIFO. Repetición idéntica devuelve resultado previo sin reaplicar ni reemitir efectos. Mismo ID con otro payload se rechaza. Buckets se comprueban antes de cache. La deduplicación es una comodidad de idempotencia, **no una barrera de seguridad**: un replay desalojado o caducado se trata como solicitud nueva y pasa todas las validaciones de estado, materiales y cooldowns. Cliente nunca reintenta automáticamente una mutación con ID nuevo. Al cambiar runId, cancelar reservas y cache anterior.

Validación común `G`: tipos/tamaños, run vigente, fase y estado vital según la matriz de abajo, perfil Ready, participante no retirado, no resultado terminal, manos libres y no interacción incompatible; identidad/estado/posición/herramientas leídos del servidor. Cada tabla especifica excepciones. Distancia y materiales se validan incluso si el cliente ya mostró verde. «No aplica» significa que la operación no usa un blanco/material, no que se omita una validación necesaria. Para LOS/rango usar la **posición validada** de PlayerService (ver [jugador](jugador.md)) y hitbox registrada, nunca la posición instantánea del personaje replicado ni un origen enviado por cliente.

### Matriz de fase, estado vital y participación (F0-4)

`Juego` = Day, Dusk, Night, Dawn. `Participante` = miembro del roster congelado, conectado y no retirado (ver [ciclo de partida](ciclo-partida.md)); los que entran tarde o reconectan no lo son. Fuera de esta matriz → `WrongPhase`, `NotAlive` o `NotReady` según el caso.

| Remote | Fases | Estado vital | Exige participante |
|---|---|---|---|
| `RequestSnapshot` | Todas | Cualquiera, incluso sin personaje | No |
| `SetReady` | Lobby | No aplica (sin run) | No; exige perfil Ready |
| `SetMovementMode`, `SetFlashlight`, `SetFlashlightAim` | Juego | Alive | Sí |
| `EquipTool`, `HitResource`, `CraftItem`, `PlaceStructure`, `DropObjective` | Juego | Alive | Sí |
| `BeginInteraction` | Juego; `StartTransmission`/`ResumeTransmission` solo Night | Alive | Sí |
| `CancelInteraction` | Juego | Alive o Downed | Sí |
| `Shout` | Day, Dusk, Night | Downed | Sí |

En Result y con resultado terminal fijado, todo salvo `RequestSnapshot` se rechaza. Spectating (muerto, tardío o retirado) solo puede pedir snapshot.

**Interacción activa:** mientras el jugador tiene una acción mantenida, se rechazan con `Busy` `EquipTool`, `HitResource`, `CraftItem`, `PlaceStructure` y otro `BeginInteraction`. Se permiten `CancelInteraction`, `SetFlashlight`, `SetFlashlightAim`, `SetMovementMode` (moverse >1.5 studs la cancela igualmente) y `RequestSnapshot`. `DropObjective` cancela primero la interacción activa y luego suelta, en la misma operación.

## Todos los eventos C→S

`Req = {requestId: string, runId: string}`. En la tabla `Req & {...}` indica sus campos más los indicados. Tasas `r/b` = tokens por segundo / capacidad burst, no cooldown de gameplay.

| Nombre | Tipo | Dirección | Payload Luau | Validaciones del servidor (además de forma/bucket) | Límite r/b |
|---|---|---|---|---|---:|
| `RequestSnapshot` | RemoteEvent | C→S | `Req` | Puede usar runId vacío/viejo; no exige Alive/perfil Ready. Solo devuelve vista autorizada del solicitante; distancia/materiales no aplican. | 0.5/1 |
| `SetReady` | RemoteEvent | C→S | `Req & {ready: boolean}` | Solo Lobby, perfil Ready; no exige personaje. No inicia run por sí solo sin reglas de Session. Distancia/materiales no aplican. | 2/2 |
| `SetMovementMode` | RemoteEvent | C→S | `Req & {mode: "Walk" \| "Sprint" \| "Crouch"}` | Alive; permite pieza, pero antena bloquea Sprint; estamina y bloqueos de jugador. No cambia posición directamente. El modo declarado limita velocidad pero **no decide el ruido**: el ruido sale del desplazamiento medido (ver [estímulos](estimulos.md)). | 8/10 |
| `SetFlashlight` | RemoteEvent | C→S | `Req & {enabled: boolean}` | Alive, permite pieza; encender requiere batería>0, no se consume un ítem. Batería se descuenta por tiempo encendido acumulado con reloj servidor, no por ticks enteros. Sin blanco/distancia. | 4/4 |
| `SetFlashlightAim` | RemoteEvent | C→S | `Req & {direction: Vector3}` | Alive, linterna encendida; vector unitario, pitch ±80°, giro limitado a 1800°/s (`NetworkConfig.FlashlightMaxTurnDegPerSecond`), origen siempre servidor; permite pieza. No consume material; no lleva posición. | 10/15 |
| `EquipTool` | RemoteEvent | C→S | `Req & {slot: number}` | G; entero 0..12 (0 desequipa), slot propio con Hacha/Pico; no mueve ítems. Cliente agrupa cambios de slot (rueda del ratón) y envía solo el último tras 0.1 s. Rango espacial/materiales no aplican. | 6/6 |
| `HitResource` | RemoteEvent | C→S | `Req & {targetId: string}` | G; nodo activo run actual, LOS, distancia ≤10; herramienta correcta o mano vacía; cooldown con tolerancia sin acumulación y HP; salida cabe, aplica escalado servidor. No consume material. | 3/3 |
| `CraftItem` | RemoteEvent | C→S | `Req & {recipeId: string, count: number}` | G; receta existente, count entero 1..5; simular ingredientes y capacidad tras consumo, commit atómico. Sin estación ni rango espacial. Cooldown 0.5 s en RecipesConfig. | 2/2 |
| `PlaceStructure` | RemoteEvent | C→S | `Req & {placement: Placement}` | G; variante de Placement exacta (sin claves de otra variante), pieza/grid/socket válidos, parent Cimiento vivo de la run, distancia ≤15, LOS/soporte/volumen/cap/singleton; costos y ocupación revalidados al commit; cooldown 0.5 s StructuresConfig. | 2/2 |
| `DropObjective` | RemoteEvent | C→S | `Req` | Alive y portador (excepción manos ocupadas), pieza de la run; cancela interacción activa; servidor calcula suelo/drop desde posición validada. Sin material ni posición cliente. Cooldown 0.5 s ObjectivesConfig. Caída/desconexión no dependen del Remote. | 2/2 |
| `BeginInteraction` | RemoteEvent | C→S | `Req & {action: InteractionAction, targetId: string}` | G con excepciones de subtabla; rango ≤8, LOS cuando hay target; recursos/materiales propios del subcaso; una reserva por jugador y clave de reserva exclusiva. Servidor mide hold. | 3/3 |
| `CancelInteraction` | RemoteEvent | C→S | `Req & {interactionId: string}` | Solo una interacción propia; permite Downed o falta de manos libres para cancelar. No efectos de inventario. No exige rango: cancelar desde lejos es válido. | 4/4 |
| `Shout` | RemoteEvent | C→S | `Req` | Solo Downed participante; no Alive ni manos libres; cooldown 5 s StimuliConfig. Emite desde posición validada; sin blanco/materiales. | 0.2/1 |
| `DebugBridge` | RemoteEvent | C→S | `Req & {enabled: boolean}` | **Solo Studio:** el servidor rechaza con `Forbidden` si `RunService:IsStudio()` es falso. runId actual. Llama a `WorldService.setBridgeBuilt`. Sin efecto en servidores publicados. | 1/2 |

```luau
type Placement =
    {pieceId: "Cimiento", gridX: number, gridZ: number, quarterTurns: number}
    | {pieceId: "Pared" | "MarcoPuerta", parentId: string, socketId: "EdgeN" | "EdgeE" | "EdgeS" | "EdgeW"}
    | {pieceId: "Fogata"}
type InteractionAction = "PickupObjective" | "InstallObjective" | "StartTransmission"
    | "ResumeTransmission" | "RevivePlayer" | "UseItem"
    | "RepairStructure" | "FuelCampfire" | "IgniteCampfire"
    | "SearchContainer" | "PickupLoot" | "LootBackpack" | "OpenDoor" | "CloseDoor"
```

QuarterTurns entero 0..3. TargetIds son IDs opacos emitidos por servidor/atributos de entidades registradas; resolver solo en registry actual, nunca como path para buscar instancias arbitrarias. Para acciones personales targetId es el ID del propio jugador del snapshot; rechazar otro jugador. Excepción F2: en `UseItem` el targetId es el `ItemId` a usar (validado contra `ItemsConfig` y el inventario propio). Revive usa ID del jugador objetivo, no nombre visible ni UserId recibido como autoridad.

`ExtinguishCampfire` (apagar la fogata por un jugador) se retiró del MVP en F0-4 por ser un vector de griefing que puede provocar una aniquilación; el GDD no lo pide. **[pendiente de aprobar por Mario]** Ver hallazgo M6.

## Subcontrato de BeginInteraction

Estas son variantes del mismo Remote, no Remotes adicionales. Bucket compartido 3/3; cooldown global de nuevos inicios 0.25 s (`InteractionConfig.BeginCooldown`, con la tolerancia sin acumulación común), una acción activa. Aceptar otra requiere cancelación de la anterior. Un jugador no puede esquivar la cadencia cambiando de acción.

Cada acción toma una **clave de reserva** exclusiva; dos acciones con la misma clave no coexisten (la segunda recibe `Busy`). Además, cada jugador tiene una sola reserva activa.

| Action | Hold | Clave de reserva | Target y validaciones específicas | Material al commit |
|---|---:|---|---|---|
| PickupObjective | 2 s | `piece:<PieceId>` | Pieza World no reservada; sin otra pieza | Ninguno |
| InstallObjective | 2 s | `radio:<PieceId>` | Radio; excepción manos ocupadas, porta pieza no instalada y hueco de esa pieza vacío | Solo transfiere pieza a Installed |
| StartTransmission | 3 s | `radio:control` | Radio Ready, 4 piezas, Night; noche válida hasta fin | Ninguno |
| ResumeTransmission | 3 s | `radio:control` | Radio Paused y Night; nuevo golpe interrumpe | Ninguno |
| RevivePlayer | 4 s | `revive:<víctima>` | Compañero Downed, no uno mismo; sigue caído y ambos conectados. Mientras dura, el caído no puede arrastrarse (velocidad 0 en servidor). | Ninguno |
| UseItem | `ItemsConfig.Items[id].Use.HoldSeconds` | `self:<jugador>` | targetId = ItemId propio con `Use`; Alive, manos libres; el efecto no se desperdicia entero (HP/hambre/batería bajo el máximo). Sin LOS ni rango. Daño de enemigo cancela solo si `Use.CancelOnDamage` | 1 del ítem. Sustituye a `UseBandage` y `ReplaceBattery` (F2) |
| RepairStructure | 2 s | `structure:<id>` | Estructura registrada dañada, no destruida; fogata rota reparable | Tabla de StructuresConfig |
| FuelCampfire | 1 s | `structure:<id>` | Fogata, espacio para 30 s base completo; no acepta count cliente | 1 Madera |
| IgniteCampfire | 5 s | `structure:<id>` | Fogata apagada, HP>0, combustible>0 | Ninguno adicional |
| SearchContainer | 1.5 s | `container:<id>` | Contenedor de loot cerrado no abierto antes | Ninguno; solo abre y crea los lotes |
| PickupLoot | 0.25 s | `loot:<id>` | Lote accesible (contenedor abierto si aplica), capacidad completa | Transfiere lote; no cobra |
| LootBackpack | 1 s | `backpack:<id>` | Mochila no vacía, capacidad para al menos un ítem | Transfiere lo que cabe, resto permanece |
| OpenDoor | 0.25 s | `door:<id>` | Puerta cerrada registrada (MarcoPuerta o metálica del mapa) | Ninguno |
| CloseDoor | 0.25 s | `door:<id>` | Puerta abierta registrada y hueco libre de personajes **y enemigos** (consulta espacial servidor) | Ninguno |

Con claves por hueco, dos portadores pueden instalar piezas distintas a la vez; iniciar/reactivar la transmisión no compite con instalar porque exige las 4 piezas ya instaladas.

Holds comunes/rango/chequeo en `InteractionConfig`, holds de piezas/radio en ObjectivesConfig, reparación/fogata en StructuresConfig, personales/revive en PlayerConfig. No duplicar su valor en NetworkConfig. **Decisión de spec:** acción mantenida cancela al recibir daño el actor (excepto `UseItem` con `CancelOnDamage = false`; el daño por hambre nunca cancela), moverse >1.5 studs desde inicio, salir de rango/LOS, cambiar fase a una incompatible, caer/morir/desconectarse, cambiar run, perder target o perder reserva. Revalidación 0.1 s y al finalizar. Giro de cámara no cancela si LOS sigue válido. Abrir/cerrar puertas se valida de nuevo al commit.

El servidor asigna `interactionId`, `startedAt`, `endsAt`, avisa y programa finalización automática. Cliente no puede enviar «completado». Soltar botón emite Cancel; si lo omite, mantener posición/estado hasta cumplir hold es suficiente: no se pretende probar físicamente que la tecla siguió pulsada. Al completar se verifican materiales/capacidad y se consumen junto al efecto. Cancelar no consume; el ruido previo no se revierte. Un finalizador tardío de interacción cancelada no ejecuta nada.

### Orden temporal y carreras (F0-4)

Todos los hechos llevan tiempo de servidor `t` asignado al procesarlos. Los servicios procesan Remotes en serie (un handler sin yield termina antes del siguiente), así que «simultáneo» significa «mismo tick», no concurrencia real.

1. **Reserva:** dos `BeginInteraction` sobre la misma clave: gana el primero procesado; el segundo recibe `Busy`. No hay segundo intento automático.
2. **Hold contra evento que cancela:** una interacción se completa si ningún evento cancelador tiene `t < endsAt`. Un daño, caída o golpe a la radio con `t >= endsAt` llega tarde y no la deshace.
3. **Revive contra bleedout:** si `endsAt <= bleedoutAt` gana el revive; si no, el caído muere y el revive se cancela. Un remate de IA con `t < endsAt` también gana.
4. **Commit atómico:** cada commit (instalar, recoger, saquear, craftear, construir, golpe final de nodo) comprueba el estado y aplica el efecto sin yield; el segundo intento sobre el mismo recurso ve el estado ya cambiado y falla con `NotFound`, `InvalidState` u `Occupied`.
5. **Muerte o caída con pieza:** la pieza pasa a World en la posición validada del portador en la misma transacción que el cambio de estado vital, antes de crear la mochila. La interacción activa del portador se cancela sin commit.
6. **Desconexión:** el handler de `PlayerRemoving` es síncrono y sin yield: cancela la interacción activa sin commit, libera todas sus reservas, suelta la pieza en la posición validada, mueve el inventario a la mochila y borra el inventario en memoria. Un usuario que reconecta en la misma run es espectador sin inventario, así que no hay duplicación.
7. **Watchdog de piezas:** si el watchdog necesita mover una pieza World reservada, primero cancela la reserva (`Cancelled`) y después la mueve.
8. **Fin de run:** al fijar resultado terminal se cancelan todas las reservas antes de cualquier otro procesamiento del tick; ningún commit posterior se aplica.

## Eventos S→C

Sin handlers de mutación en estos nombres. **F0-4:** el servidor conecta en cada Remote S→C un `OnServerEvent` que solo descuenta del bucket global del jugador y descarta el paquete; así un cliente que les envía datos no llena la cola de eventos sin listener de Roblox. «Validación servidor» significa comprobar que el dato publicado provenga del estado canónico, pertenezca a la run y respete visibilidad. No se confía en una eco/respuesta cliente.

| Nombre | Tipo | Dirección | Payload Luau | Validación servidor / alcance | Límite de salida por destinatario |
|---|---|---|---|---|---|
| `StateSnapshot` | RemoteEvent | S→C | `Snapshot` | Vista completa autorizada; inventario/meta solo propios; objetivos sin revelar spawn oculto | Coalescer ≤5/s y además presupuesto de bytes (ver abajo); inicial a petición; 32 KiB máximo lógico |
| `ActionResult` | RemoteEvent | S→C | `{runId: string, requestId: string, ok: boolean, code: ResultCode, revision: number, entityId: string?}` | Solo solicitante; después del commit o rechazo; no enviar detalles internos | ≤30/s; errores ≤2/s |
| `InteractionState` | RemoteEvent | S→C | `{runId: string, interactionId: string, requestId: string, action: InteractionAction, targetId: string, state: "Started" \| "Completed" \| "Cancelled", startedAt: number, endsAt: number, code: ResultCode}` | Solo actor, IDs y tiempos de reserva servidor | ≤8/s, eventos terminales no descartados; limitar admisión antes de saturar |
| `Feedback` | RemoteEvent | S→C | `{runId: string, cueId: CueId, sourceId: string, position: Vector3, at: number}` | Solo hechos aceptados; audio cercano por audiencia o todos para objetivo; sin cambios jugables | ≤10/s, descartar/coalescer cosméticos repetidos |

**Presupuesto de snapshot (F0-4):** 32 KiB a 5/s serían hasta 160 KiB/s por jugador, muy por encima de lo que Roblox sostiene por cliente. `NetworkConfig.SnapshotBudgetBytesPerSecond = 24576` (24 KiB/s) por destinatario: el intervalo entre snapshots es `max(0.2 s, tamañoÚltimo / presupuesto)`. Los cambios de `self` (inventario, vida, interacción) y de `objectives` marcan el snapshot como prioritario dentro de ese presupuesto; cambios solo de HP de estructuras pueden esperar al siguiente envío, ya que el HP también replica por atributos del modelo.

RequestSnapshot devuelve snapshot; las demás solicitudes salvo SetFlashlightAim devuelven ActionResult. Aim válido no requiere ACK individual; estado se reconcilia en snapshot. Begin aceptado devuelve ok/code Accepted (reserva, no resultado final) y Started; Completed/Cancelled entrega resultado terminal en InteractionState ligado al requestId original. `ActionResult.revision` ayuda a esperar el siguiente snapshot, no supone que ya llegó. No usar orden relativo entre Remotes para aplicar transacciones en cliente. **F0-4:** como los errores se limitan a 2/s, el cliente no puede depender de recibir siempre un `ActionResult` de rechazo: toda solicitud pendiente en UI caduca a los 3 s (`NetworkConfig.PendingRequestTimeoutSeconds`) y se reconcilia con el siguiente snapshot.

`ResultCode` es unión cerrada: `"Ok" | "Accepted" | "InvalidPayload" | "RateLimited" | "StaleRun" | "NotReady" | "WrongPhase" | "NotAlive" | "HandsBusy" | "Busy" | "NotFound" | "OutOfRange" | "Blocked" | "WrongTool" | "Cooldown" | "InsufficientItems" | "InventoryFull" | "Occupied" | "LimitReached" | "InvalidState" | "Cancelled" | "Forbidden" | "InternalError"`. `Forbidden` solo lo usan los Remotes de debug fuera de Studio. Mensajes localizados en PresentationConfig; no enviar stacktrace. `CueId`: `"ResourceHit" | "ResourceDepleted" | "ItemUsed" | "StructureBuilt" | "StructureHit" | "StructureBroken" | "DoorOpened" | "DoorClosed" | "ContainerOpened" | "Revive" | "Shout" | "CampfireLit" | "CampfireOut" | "PieceInstalled" | "TransmissionStarted" | "TransmissionPaused" | "TransmissionComplete" | "ThreatPresence" | "ThreatFar" | "ThreatNear" | "ThreatVeryNear" | "ThreatAttack" | "DaySighting"`. Cues de amenaza se reservan para F4, sin inventar umbrales aquí.

## Tipos completos de Snapshot

Tipos compartidos futuros en `types.luau`. `number` de conteos/índices implica entero acotado; tiempos son segundos de reloj servidor y se muestran con estimación de `Workspace:GetServerTimeNow()`. No comparar con reloj de pared del dispositivo.

```luau
type Phase = "Lobby" | "Day" | "Dusk" | "Night" | "Dawn" | "Result"
type ItemId = string -- F2: data-driven; el servidor lo valida contra ItemsConfig.Items
type PieceId = "Bateria" | "Antena" | "Transceptor" | "Cristal"
type LifeState = "Alive" | "Downed" | "Spectating"
type Stack = {slot: number, itemId: ItemId, count: number}
type MetaView = {
    runsPlayed: number, wins: number, highestNightReached: number,
    piecesRecovered: number, earlyRescues: number, bestRescueNight: number?,
}
type PlayerView = {
    id: string, userId: number, participant: boolean, ready: boolean,
    life: LifeState, health: number, maxHealth: number,
    flashlightOn: boolean, flashlightDirection: Vector3,
    carrying: PieceId?,
}
type SelfView = {
    profile: "Loading" | "Ready" | "Unavailable",
    save: "Pending" | "Saved" | "Unavailable",
    stamina: number, maxStamina: number, battery: number, maxBattery: number,
    hunger: number, maxHunger: number,
    moveMode: "Walk" | "Sprint" | "Crouch", equippedSlot: number,
    inventory: {Stack}, meta: MetaView?, bleedoutAt: number?,
    soloChanceAvailable: boolean, autoReviveAt: number?,
    interaction: {
        id: string, action: InteractionAction, targetId: string,
        startedAt: number, endsAt: number,
    }?,
}
type PieceView = {
    id: PieceId, entityId: string, state: "World" | "Carried" | "Installed",
    discovered: boolean, carrierUserId: number?, droppedPosition: Vector3?,
}
type StructureView = {
    id: string, pieceId: "Cimiento" | "Pared" | "MarcoPuerta" | "Fogata",
    health: number, maxHealth: number, doorOpen: boolean?,
    fireLit: boolean?, fuelSeconds: number?,
}
type ContainerView = {
    id: string, kind: "LootContainer" | "Loot" | "Backpack",
    open: boolean, stacks: {Stack},
}
type RunResult = {
    outcome: "Rescued" | "Annihilation" | "OutOfTime",
    night: number, durationSeconds: number, installedPieces: number,
    transmissionSeconds: number, rescuedUserIds: {number},
}
type Snapshot = {
    protocolVersion: number, runId: string, revision: number, serverTime: number,
    phase: Phase, day: number, night: number, phaseEndsAt: number,
    rosterSize: number, players: {PlayerView}, self: SelfView,
    objectives: {
        radioId: string, pieces: {PieceView}, installedCount: number,
        transmissionState: "Incomplete" | "Ready" | "Transmitting" | "Paused" | "Complete",
        elapsedSeconds: number, requiredSeconds: number, completedNight: number?,
    },
    structures: {StructureView}, containers: {ContainerView}, result: RunResult?,
}
```

**Decisión de spec:** snapshots completos de la vista, no protocolo delta en MVP. Revisión monotónica por destinatario y run; descartar snapshot viejo, reiniciar al ver nuevo runId. Inventario lista solo slots ocupados (≤12), piezas siempre 4, players ≤4, structures ≤120. Containers solo abiertos/visibles por proximidad ≤30 studs (`NetworkConfig.ContainerViewRange`), máximo 24 y máximo 12 stacks cada uno. Si exceden, priorizar interacción actual y cercanos; no exponer contenido de cerrado. Un cambio de proximidad se refleja en siguiente snapshot. Validar límites de mundo en arranque para no truncar estructuras/objetivos; si un snapshot supera 32 KiB por contenido opcional, omitir containers más lejanos, nunca inventario propio ni resultado.

Modelos, poses y atributos públicos de nodos/puertas/estructuras replican normalmente por Roblox; no se duplica geometría en Snapshot. IDs de interactuables se colocan en atributos servidor y registry: un atributo alterado localmente no registra objeto nuevo. Nodos tienen ResourceId/HP/Active replicados, por lo que no requieren otra tabla en Snapshot. Perfil Loading y Lobby pueden omitir meta/usar inventario vacío, vida/estamina/batería 0, radioId vacío hasta World listo y rosterSize 0; pieces mantiene las cuatro definiciones sin spawn visible. TargetId vacío nunca sirve en una mutación.

## Autoridad física y replicación (F0-4)

Reglas que no son Remotes pero que, si no se cumplen, permiten saltarse todas las validaciones de esta spec:

1. **Propiedad de red:** toda parte que el servidor crea o usa como autoridad está anclada (estructuras, puertas, radio, nodos, piezas en World, loot, mochilas). Los enemigos, que no pueden estar anclados, reciben `SetNetworkOwner(nil)` al aparecer y después de cualquier cambio de su ensamblaje (soldar, desoldar, reparentar). Nunca se deja la asignación automática de Roblox, que entrega la física a un cliente cercano y le permite mover, congelar o tirar al vacío a la criatura.
2. **Personaje:** es el único ensamblaje que el cliente controla. Por eso su posición nunca es autoridad directa: se usa la posición validada (ver [jugador](jugador.md), validación de movimiento y ciclo de vida del personaje).
3. **Sin `Touched` como autoridad:** daño de enemigos, recogidas, zonas de agua, nido, zona segura y cualquier disparador se resuelven con consultas espaciales del servidor (distancia, `GetPartBoundsInRadius`/`GetPartBoundsInBox`, raycast) sobre posiciones validadas. Un cliente puede suprimir o falsear contactos de su propio personaje.
4. **Herramientas:** no se usan instancias `Tool` de Roblox ni la Backpack; se desactiva la Backpack del CoreGui. El hacha o pico visible es un modelo soldado por el servidor según `EquipTool`, sin colisión, sin `CanTouch` y sin `CanQuery`. Lo mismo vale para el consumible en uso y la linterna encendida (contrato en [jugador](jugador.md), «Herramienta en la mano»). Se replica como hijo del personaje (`HeldRight` y `HeldLeft`), junto con el atributo `SwingSeq` del personaje para el golpe cosmético; no hay Remote ni campo de `PlayerView` para esto.
5. **ProximityPrompts:** solo como UI local del cliente. El servidor no conecta `Triggered`, `TriggerEnded` ni eventos de hold de prompts; toda acción entra por `BeginInteraction`.
6. **Información oculta:** lo que el cliente no debe saber no se replica. La pieza de una zona permanece fuera de `Workspace` (en una carpeta de `ServerStorage`) hasta que un participante entra en su volumen de zona o se acerca a menos de `ObjectivesConfig.RevealRadius` (60 studs) por posición validada; los lotes de un contenedor se crean en `Workspace` solo al completar `SearchContainer`. Ver [objetivos](objetivos.md).
7. **Visual transportado:** la pieza cargada es un clon cosmético soldado al personaje, sin colisión, `CanTouch`/`CanQuery` falsos y sin masa; el servidor nunca lee su posición.

## Pruebas de seguridad

Probar payloads ausentes/extra, argumentos extra, tabla enorme/profunda/con metatabla, NaN/infinito en cada número y en cada componente de Vector3, IDs de otra run, requestId repetido y desalojado, rate limit por usuario (uno no bloquea al otro), cooldown con paquetes juntos (jitter) y sostenidos, distancias y raycasts, doble consumo/ocupación, cancelación y desconexión durante hold, falsa finalización e intentos de emitir S→C. Verificar que petición de snapshot no filtra otro inventario ni habilita edición. Con un cliente modificado: volar, atravesar paredes, teletransportarse y desconectarse cargando una pieza, mover la criatura, reiniciar personaje, buscar la pieza en `Workspace` antes de acercarse. Cada Remote fuera de su fase o estado vital debe devolver el código de la matriz.

## Revisión de seguridad F0-4

Revisión hecha sobre esta spec y las de [arquitectura](arquitectura.md), [jugador](jugador.md), [objetivos](objetivos.md), [construcción](construccion.md), [estímulos](estimulos.md), [recolección e inventario](recoleccion-inventario.md), [ciclo de partida](ciclo-partida.md) y [datos](datos.md). Lo que ya estaba bien cubierto (catálogo cerrado, sin RemoteFunction, holds medidos en servidor, materiales al commit, IDs opacos, construcción sin CFrame cliente, deduplicación, snapshot sin inventario ajeno, golpe final único en nodos) no se repite aquí.

### Severidad alta

| # | Problema | Cómo quedó resuelto |
|---|---|---|
| A1 | **Propiedad de red de enemigos.** Las specs no decían quién simula la física de la criatura y los acechadores. Por defecto Roblox se la da al cliente más cercano, que puede teletransportarla, congelarla o tirarla al vacío y anular toda la IA. | Regla 1 de «Autoridad física y replicación»: todo lo autoritativo anclado y enemigos con `SetNetworkOwner(nil)` al aparecer y tras cambios de ensamblaje. Añadido también a [arquitectura](arquitectura.md) como requisito de AIService para F4-2. |
| A2 | **Movimiento vertical, vuelo, atravesar paredes y teletransporte.** La validación de [jugador](jugador.md) solo limitaba desplazamiento horizontal y dejaba explícitamente la vertical para F0-4. Como todas las validaciones de rango y LOS dependen de la posición del jugador, volar o atravesar paredes permitía llegar a piezas, al nido o a la radio sin riesgo y recoger desde detrás de muros. | [jugador](jugador.md) define ahora la posición validada: límite de subida, comprobación de suelo con tiempo máximo en el aire, raycast entre muestras contra geometría sólida (mapa, estructuras, puertas cerradas), corrección a la última posición válida y gracia de 0.3 s al bajar la velocidad permitida. Todas las acciones usan esa posición, nunca la instantánea del personaje. |
| A3 | **Ciclo de vida del personaje de Roblox.** Con la configuración por defecto, cualquier jugador (sin exploits) puede usar «Reiniciar personaje» y Roblox lo reaparece a los pocos segundos con vida llena. Eso salta el estado Downed, la regla de no morir en la noche 1, el espectador y la aniquilación. Un personaje de espectador que sigue en el mapa además bloquea puertas y enemigos. | [jugador](jugador.md): `CharacterAutoLoads = false`, botón de reinicio desactivado, la vida del juego vive en PlayerService y el Humanoid no muere; si el personaje se pierde de forma inesperada, el servidor lo recarga en la última posición validada con el mismo estado vital y HP lógicos, sin pasar a Dead ni reaparecer con vida llena. Spectating no tiene personaje. |

### Severidad media

| # | Problema | Cómo quedó resuelto |
|---|---|---|
| M1 | **NaN en validaciones de rango.** La spec decía «sin NaN» pero no cómo comprobarlo. En Luau, `if x < 1 or x > 5 then rechazar` deja pasar NaN (toda comparación con NaN es falsa); `math.floor(inf) == inf` deja pasar infinito como entero. Un `count` NaN en `CraftItem` podía corromper cantidades de inventario. Tampoco se rechazaban argumentos extra. | Bloque «Reglas de validación de valores»: un solo argumento, `typeof` primero, NaN e infinito antes que todo, rango en forma positiva, componentes de Vector3 comprobadas una por una, longitud de strings antes del patrón. |
| M2 | **Posición de suelta en caída o desconexión.** Para soltar la pieza al caer o desconectar se usaba la posición del personaje, que controla el cliente. Un cliente modificado podía mover su personaje junto a la radio y desconectarse al instante: la pieza aparecía allí sin recorrer el camino peligroso. Lo mismo con la mochila. | Toda suelta automática y toda mochila usan la posición validada. Orden 5 y 6 de «Orden temporal y carreras»; actualizado en [objetivos](objetivos.md) y [jugador](jugador.md). |
| M3 | **Faltaba una matriz de fase y estado vital.** No estaba definido qué Remotes valen en Dawn, Result o Lobby, ni para Downed, espectadores o jugadores que entran tarde. `G` decía «participante cuando aplique» sin decir cuándo aplica. | Nueva «Matriz de fase, estado vital y participación» y regla de qué se permite con una interacción activa. |
| M4 | **El ruido de pasos salía del modo declarado.** El cliente elige `SetMovementMode`; alternando Crouch y Sprint entre muestras podía moverse rápido con ruido 0, que anula el núcleo del sigilo del GDD. | [estímulos](estimulos.md): el tipo de paso es el máximo entre el del modo declarado y el que corresponde a la velocidad horizontal medida en la última ventana de 0.5 s. |
| M5 | **Fuga de información de piezas y loot.** [objetivos](objetivos.md) prometía que el cliente no conoce la posición de piezas sin descubrir, pero el modelo se clonaba en `Workspace/Runtime` al comenzar la run y por tanto replicaba a todos los clientes; leerlo revela cuál de los 3 puntos se eligió. Lo mismo con los lotes de contenedores cerrados. | Regla 6 de «Autoridad física y replicación»: la pieza se mantiene en `ServerStorage` hasta que un participante entra en su zona o se acerca a 60 studs; los lotes se crean al abrir el contenedor. |
| M6 | **Griefing con `ExtinguishCampfire`.** Cualquier jugador podía apagar la fogata con 1 s de hold; volver a encenderla cuesta 5 s y hace ruido. Un jugador malicioso en un servidor público podía mantenerla apagada toda la noche y provocar la aniquilación del grupo. El GDD aprobado no pide que los jugadores puedan apagarla (solo los acechadores desde la noche 3). | Retirada del MVP: se quita de `InteractionAction` y de [construcción](construccion.md). **[pendiente de aprobar por Mario]** Si se quiere conservar para esconderse a oscuras, propuesta mínima: hold 3 s, cue visible y audible para todo el grupo al empezar, y solo de día o atardecer (nunca de noche, que es cuando decide una aniquilación). |
| M7 | **`Touched` como autoridad.** La spec de recolección ya lo prohibía para nodos, pero no había regla general; el daño de enemigos (F4) y las zonas (agua, nido, zona segura) podían acabar implementándose con `Touched`, que un cliente puede suprimir para su personaje (inmunidad). | Regla 3 de «Autoridad física y replicación» y requisito explícito para AIService en [arquitectura](arquitectura.md). |
| M8 | **Ancho de banda de snapshots.** 32 KiB a 5/s son hasta 160 KiB/s por jugador; durante un asedio (HP de estructuras cambiando a cada golpe) se alcanza el máximo y Roblox empieza a encolar y retrasar todos los Remotes, incluidos `ActionResult` e `InteractionState`. | Presupuesto de 24 KiB/s por destinatario con intervalo adaptativo y prioridad para `self` y objetivos. |
| M9 | **Carreras sin regla temporal.** No estaba definido quién gana entre bleedout y revive, daño y fin de hold, watchdog y reserva de pieza, soltar durante un hold, ni el orden de operaciones al desconectar. | Sección «Orden temporal y carreras» con 8 reglas; [arquitectura](arquitectura.md) remite a ella en el orden por tick. |

### Severidad baja

| # | Problema | Cómo quedó resuelto |
|---|---|---|
| B1 | **Radio exclusiva para instalar** (demasiado estricto). «Solo una reserva de radio» impedía que dos jugadores que vuelven juntos con piezas distintas instalen a la vez; el segundo recibía `Busy` en plena noche. | Claves de reserva por hueco (`radio:<PieceId>`) y `radio:control` para iniciar/reactivar. Actualizado en [objetivos](objetivos.md). |
| B2 | **Giro de linterna 720°/s** (demasiado estricto). Darse la vuelta de golpe al oír algo es un gesto normal en un juego de terror (180° en 0.1 s = 1800°/s). Limitarlo no aporta seguridad (apuntar en cualquier dirección es legítimo) y retrasaba la luz que percibe la IA. | 1800°/s en `NetworkConfig.FlashlightMaxTurnDegPerSecond`; bucket de aim de 10/12 a 10/15 para absorber jitter. Actualizado en [estímulos](estimulos.md). |
| B3 | **Cooldowns sin tolerancia de jitter** (demasiado estricto). Dos golpes enviados a 0.8 s pueden llegar a 0.7 s por la red y el segundo se rechazaba. Una tolerancia simple (`last + cooldown - 0.1`) en cambio acumula y sube la cadencia sostenida un 14 %. | Esquema `readyAt` con tolerancia 0.1 s sin acumulación, común a todos los cooldowns de gameplay. |
| B4 | **`EquipTool` 4/4** (demasiado estricto). Girar la rueda del ratón por 12 slots supera 4/s y deja al jugador con `RateLimited`. | Bucket 6/6 y el cliente envía solo el slot final tras 0.1 s sin cambios. |
| B5 | **Cache de deduplicación llenada por aim.** Aim a 10 Hz llenaba las 128 entradas en 13 s y desalojaba mutaciones reales. | La deduplicación solo aplica a Remotes con `ActionResult`, con desalojo FIFO; queda documentado que no es barrera de seguridad. |
| B6 | **Remotes S→C sin listener.** Un cliente que envía a un Remote S→C llena la cola de eventos sin listener de Roblox (avisos y memoria). | `OnServerEvent` de descarte que consume bucket global. |
| B7 | **Tools de Roblox y ProximityPrompts.** Usar `Tool` y Backpack da al cliente control replicado sobre equipar/soltar; conectar `Triggered` de un prompt crearía un camino paralelo sin validación. | Reglas 4 y 5 de «Autoridad física y replicación». |
| B8 | **Batería por ticks.** Si el consumo se aplica por tick entero solo cuando la linterna está encendida en ese instante, encender y apagar rápido entre ticks evita el gasto. | Consumo por tiempo encendido acumulado con reloj servidor. Actualizado en [jugador](jugador.md). |
| B9 | **Cerrar puerta sobre un enemigo** y **caído que se arrastra durante su revive.** El cierre solo comprobaba personajes; el caído podía salir del rango y cancelar su propio revive. | `CloseDoor` comprueba también enemigos ([construcción](construccion.md)); durante `RevivePlayer` el caído no se mueve. |
| B10 | **Cliente esperando un rechazo descartado.** Con errores limitados a 2/s, el cliente podía quedar esperando un `ActionResult` que no llega (preview de construcción bloqueado). | Las solicitudes pendientes caducan a los 3 s y se reconcilian con el snapshot. |
| B11 | **Errores de documento.** La tabla C→S tenía 7 columnas de separador para 6 encabezados (rompía el render) y [recolección](recoleccion-inventario.md) citaba un `SetDoor` que no existe. | Tabla corregida; `SetDoor` sustituido por `OpenDoor`/`CloseDoor`. |

### Riesgos aceptados para el MVP

- **Pieza secuestrada:** un jugador puede cargar una pieza y no instalarla nunca. No hay forma de quitársela sin crear otro vector de abuso (robar piezas). Roblox expulsa por inactividad a los 20 min; post-MVP se puede valorar una votación de expulsión.
- **Encerrar a un compañero con paredes:** sin desmontaje, un jugador puede rodear a otro con paredes sobre cimientos. Las paredes no se colocan encima de personajes y los enemigos las rompen desde la noche 2. Post-MVP: permitir que los jugadores dañen estructuras propias o un desmontaje con hold.
- **Golpear sin mirar:** `HitResource` no comprueba la orientación de la cámara (el cliente la controla y no es fiable). Solo cuentan distancia y LOS desde la posición validada.
- **Cámara libre de espectador:** un cliente modificado puede mover la cámara de espectador por el mapa. No da autoridad y la regla M5 evita que vea piezas no reveladas.
- **Aim automático contra acechadores:** un cliente puede apuntar la linterna con precisión perfecta. Es una dirección legítima; el coste (atraer a la criatura principal) se mantiene.
