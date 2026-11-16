# Objetivos — F0-3

Base: GDD §2 y §4. ObjectiveService es dueño del estado compartido y del reloj de transmisión; SessionService es el único que concluye la run. Cliente muestra manos, brillo, panel X/4, progreso y prompts. Valores en `src/shared/config/ObjectivesConfig.luau`; cualquier ampliación es **decisión de spec**.

## Piezas y aparición

| PieceId | Nombre | Zona / distancia orientativa | Prefab | Pesada |
|---|---|---|---|---|
| `Bateria` | Batería | Gasolinera / 150 studs | PiezaBateria | No |
| `Antena` | Antena | Torre / 300 studs | PiezaAntena | Sí |
| `Transceptor` | Transceptor | Pantano / 450 studs | PiezaTransceptor | No |
| `Cristal` | Cristal de frecuencia | Mina / 600 studs | PiezaCristal | No |

World exige exactamente tres marcadores `ObjectiveSpawns/<PieceId>/01`, `02`, `03` por pieza, dentro de su zona. Servidor elige uniformemente uno al comenzar run y clona una única pieza. No se cambia punto por visita ni por reaparecer un jugador. RNG/elección no vienen del cliente. Distancias sirven para greybox, no para aceptar pickups; se validan accesibilidad y ausencia de encierros en playtest.

Estado por pieza: `World` (posición y spawn elegido), `Carried` (userId), `Installed` (socket de radio). Soltar vuelve a World conservando identidad. Solo una pieza por portador y un portador por pieza; Installed es irreversible en run. No se puede vender, craftear, destruir ni meter piezas en inventario/meta. Cliente conoce progreso y portadores, pero no coordenadas de piezas todavía sin descubrir; el servidor replica brillo/posición a todos solo después del primer pickup y de cada drop.

**F0-4 — la pieza no replica antes de tiempo:** si el modelo se clonara en `Workspace/Runtime` al empezar, replicaría a todos los clientes y cualquiera podría leer cuál de los 3 puntos salió. El servidor clona la pieza en una carpeta de `ServerStorage` y la mueve a `Workspace/Runtime` cuando un participante entra en el volumen de su zona o se acerca a ≤ `ObjectivesConfig.RevealRadius` (60 studs) por posición validada. Desde entonces se queda en Workspace el resto de la run. Pickup exige que la pieza ya esté revelada.

## Interacciones

Rango 8 studs y LOS en inicio y fin, chequeo continuo cada 0.1 s (`InteractionConfig`). Alive y manos libres para recoger. `PickupObjective` dura 2 s aprobados; reserva por pieza. Distancia al hitbox real, no a punto elegido por cliente. Al completar: cancela herramienta equipada, fija portador y retira collider físico de pickup. Visual transportado es un clon cosmético soldado al personaje, sin colisión, `CanTouch`/`CanQuery` falsos y sin masa; el servidor nunca lee su posición (el cliente controla su física). Dos jugadores que recogen la misma pieza: gana la primera reserva; el segundo recibe `Busy`.

**Decisión de spec:** `InstallObjective` requiere 2 s frente a radio; objetivo es RadioId registrado y pieza se deriva del portador. Verifica hueco correspondiente vacío; commit libera manos y marca Installed en la misma operación. Si el portador cae, muere, se desconecta o usa `DropObjective` durante el hold, la instalación se cancela sin commit. Emite feedback estática/luz de panel para todos. No consume materiales.

`DropObjective` es inmediato, sin hold, y cancela antes la interacción activa del portador. Servidor calcula suelo a 3 studs delante de la **posición validada** del personaje (ObjectivesConfig.DropForwardStuds), con raycast y espacio; nunca recibe posición ni usa la posición instantánea del personaje replicado. Si no hay suelo seguro, usa última posición válida de la pieza. Caída, muerte y desconexión sueltan automáticamente sin necesitar Remote, también en la posición validada (F0-4: evita teletransportarse junto a la radio y desconectarse para mover la pieza). Después de soltarse, anchoring en servidor evita pérdidas por física. Brillo tenue visible al grupo según PresentationConfig.

**Decisión de spec:** watchdog servidor cada 1 s (`ObjectivesConfig.RecoveryInterval`) comprueba pieza World dentro de límites WorldConfig y sobre superficie accesible registrada; si queda bajo mapa o en volumen inválido, vuelve a último punto válido o su marcador elegido al inicio. Mantiene ID, no clona otra copia. Si la pieza tiene una reserva de pickup activa, el watchdog la cancela antes de moverla. Soltar/teleport no permite instalar desde lejos.

Con manos ocupadas se puede mover, agachar, gritar si se cae y usar linterna integrada, pero no golpear, craftear, colocar/reparar, saquear, recargar, curar, revivir ni operar fogata/puertas/transmisión. Instalar/soltar son excepciones explícitas. Antena limita velocidad según PlayerConfig. Puertas necesitan compañero o soltar primero.

## Radio y transmisión

Radio es instancia fija de Studio con ID registrado y cuatro sockets visuales; no tiene HP destructible. API servidor `ApplyRadioHit(enemyId)` solo desde IA, con enemigo vivo, contacto/rango y cooldown definidos en EnemiesConfig/F4; nunca accesible por Remote cliente. Un golpe no desinstala piezas ni borra progreso.

Estados: `Incomplete`, `Ready`, `Transmitting`, `Paused`, `Complete`. `InstalledCount=4` habilita Ready. `StartTransmission`: hold 3 s (**decisión de spec**), nocturno, Alive/manos libres/LOS/rango 8. `ResumeTransmission`: hold 3 s aprobado, mismo requisito. Si comienza de noche pero finaliza de día, se cancela sin iniciar. Reservas de radio (F0-4): `InstallObjective` reserva solo el hueco de su pieza (`radio:<PieceId>`), así dos portadores con piezas distintas instalan a la vez; `StartTransmission` y `ResumeTransmission` comparten `radio:control`.

`TransmissionSeconds=180` aprobados. Tiempo acumulado solo en estado Transmitting durante Noche. Golpe cambia a Paused y conserva segundos; reactivar no reinicia el contador. Una nueva agresión durante hold cancela reactivación; múltiples golpes en Paused no quitan progreso. Golpe contra radio Incomplete/Ready/Complete no cambia estado.

**Decisión de spec — frontera de noche:** una transmisión incompleta al amanecer queda Paused, conserva progreso, cesa ruido y no permite reanudación diurna. La siguiente noche se reactiva manualmente. No se extiende una noche para permitir transmitir. Si está incompleta al amanecer tras noche 5 se pierde por tiempo. Los 180 s se cuentan de tiempo activo total, pueden abarcar varias noches. Completar dentro de una noche fija `completedNight`; sobrevivir hasta su amanecer gana. Conservar acumulado no equivale a completar.

**Decisión de spec — ruido/frenesí:** radio emite fuente global continua mientras Transmitting, no mientras Paused/Complete. Frenzy del director persiste desde el primer inicio/reanudación de esa noche hasta el amanecer, aunque el ruido cese por pausa o finalización; así reactivar es necesario y terminar no elimina la defensa restante. Una noche posterior no entra en Frenzy por sí sola solo porque haya progreso previo. Emisión global no se modela como número infinito enviado por red.

`ObjectiveService` publica eventos internos `PiecePicked`, `PieceDropped`, `PieceInstalled`, `TransmissionChanged`, `TransmissionCompleted`; Session escucha este último pero espera amanecer. Estadística de pieza recuperada se acredita una vez por pieza/run al grupo participante conectado al instalarla, no por repetir pickup/drop (ver datos).

## Pruebas futuras en Studio

Verificar 12 marcadores y cuatro piezas por run, distribución al reiniciar, recogida simultánea, cancelación de hold, bloqueo de manos, antena y drop en desconexión/caída. Instalar dos veces no suma dos. Probar pérdida bajo mapa, radio inmutable, inicio diurno rechazado, golpe que pausa, 3 s de reactivación, 180 s activos, progreso entre noches, finalización exacta en frontera y rescate temprano sin saltar la noche restante.
