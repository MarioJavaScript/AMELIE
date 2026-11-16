# Datos persistentes — F0-3, D2 = A

Base: GDD §0 y §6. Se guarda solo progreso meta por usuario. DataService es el único escritor y solo consume hechos del servidor; cliente únicamente ve estadísticas y estado de carga/guardado. Esta spec fija esquema y semántica. El protocolo detallado de session locking, reintentos, migraciones y presupuesto de DataStore se especificará y aprobará en F6-1; esta entrega no declara resuelta la persistencia concurrente.

## Esquema lógico

Store y versión en `src/shared/config/DataConfig.luau`: `StoreName="PlayerMeta_v1"`, `SchemaVersion=1`, clave `u:<UserId decimal>`. Separar entorno Studio de producción con `StudioStoreName="PlayerMeta_dev_v1"`. No activar acceso a datos productivos para probar. Números estadísticos enteros, finitos, ≥0, máximo `MaxCounter=2147483647` (**decisión de spec**, saturación).

```luau
type MetaStats = {
    runsPlayed: number,
    wins: number,
    highestNightReached: number,
    piecesRecovered: number,
    earlyRescues: number,
    bestRescueNight: number?,
}
type PlayerMeta = {
    schemaVersion: number,
    userId: number,
    revision: number,
    stats: MetaStats,
    createdAtUnix: number,
    updatedAtUnix: number,
}
```

Valores iniciales: contadores y highestNightReached a 0; bestRescueNight ausente (`nil` no se serializa). No se almacena un inventario vacío como placeholder de una futura base persistente. `userId` coincide con clave; timestamps UTC son metadatos técnicos de servidor. `revision` aumenta con commit persistente exitoso, no con cada frame.

## Semántica de estadísticas

| Campo | Hecho servidor que lo actualiza |
|---|---|
| runsPlayed | +1 cuando el usuario entra al roster al empezar Día 1, aunque abandone después. No cuenta lobby/entrada tardía. |
| wins | +1 por participante del roster conectado al resultado Rescued, incluso caído/espectando por muerte. |
| highestNightReached | Máximo de noche iniciada mientras ese participante sigue conectado; rango 0–5. |
| piecesRecovered | +1 por cada instalación nueva para todos los participantes conectados del roster en ese instante; máximo 4 por run/usuario. Es cooperación, no pickups personales. |
| earlyRescues | +1 si recibió victoria en noche 1–4. |
| bestRescueNight | Mínimo de las noches de victoria 1–5; ausente si nunca ganó. |

Semántica grupal de piezas, crédito al inicio, earlyRescues y bestRescueNight son **decisiones de spec**; rescate temprano ya es una estadística prevista por GDD. Una desconexión no resta datos obtenidos ni añade una derrota como contador nuevo. Ganar el mismo runId dos veces no suma dos. Presentación puede derivar tasa de victoria; no se persiste ese cociente.

No se guardan: base, HP de estructuras, ubicación, fase/reloj, estamina, salud, linterna/batería, inventario, mochila, herramientas, piezas de la run, RNG, enemigos, combustible ni transmisión. Cosméticos están fuera del MVP: no existe Remote de desbloqueo ni lista de cosméticos comprables. Una futura versión añadirá ese campo con migración explícita.

## Contrato y requisitos para F6-1

`LoadProfile(userId)` produce Loading/Ready/Unavailable. Session solo admite perfiles Ready. Error de lectura nunca equivale a «usuario nuevo»: solo ausencia confirmada crea defaults. Esquema desconocido, UserId incorrecto o datos corruptos bloquean escritura y devuelven diagnóstico; no se sobrescribe con defaults.

`RecordRunStarted`, `RecordNightReached`, `RecordPieceInstalled`, `RecordRunResult` reciben IDs y hechos internos; actualizan acumulador meta en memoria y marcan dirty. Se exige idempotencia por `(runId, eventKind, pieceId/night según evento)` y orden consistente. `RequestFlush(userId, reason)` solicita commit al final, en checkpoints definidos por F6-1, al salir y en cierre de servidor. Nunca se expone un endpoint cliente para modificar stats o forzar flush.

**Decisión de spec:** usar `UpdateAsync` con propiedad exclusiva de sesión, sin `SetAsync` ciego ni merge por máximo de contadores aditivos. F6-1 debe concretar un sobre técnico separado del esquema meta (token/lease de sesión, versión de commit e identificadores de operaciones necesarias para idempotencia); ese sobre no contiene estado jugable. Debe definir retención acotada de deduplicación, recuperación tras crash, toma de locks, TTL/renovación, backoff con jitter, budgets, límite de flush y migración v1. No conservar lista ilimitada de runIds.

Una victoria se muestra por hecho del juego aunque el flush siga pendiente. UI muestra `Pending`, `Saved` o `Unavailable` a partir del servidor, sin prometer datos guardados antes del éxito. Si pierde propiedad del perfil, el servidor deja de aceptar nuevos cambios para él y lo retira de participación de forma controlada; F6-1 debe precisar recuperación/mensaje. Hasta aprobar e implementar esa tarea, no se puede garantizar guardado ante fallos del proceso.

Valores operativos (frecuencia de autosave, TTL, reintentos y deadlines) pertenecen exclusivamente a DataConfig y se fijarán en F6-1, no aquí ni en scripts. Resultado puede volver a lobby con perfil todavía dirty solo mientras conserve propiedad y el acumulador; no se recarga encima de cambios pendientes.

## Validación futura

En store de desarrollo: perfil nuevo, dos runs con retorno al lobby, derrota, rescate temprano, abandono, muerte/espectador y entrada tardía. Inspeccionar que ninguna propiedad de run llega al store. Repetir hechos y flush sin doble crédito. F6-1 debe añadir pruebas de dos servidores concurrentes, timeout con escritura sí aplicada, pérdida de lock, fallo de lectura, shutdown y migraciones. Studio de un solo servidor no prueba session locking.
