# Ciclo de partida — F0-3

Base: GDD §§1, 3, 4, 5. SessionService decide roster y resultado; DayNightService fases/reloj/director; ObjectiveService informa transmisión; PlayerService estados vitales. Cliente muestra cuenta atrás, presets de luz/niebla y resultado. Todos los relojes son servidor; no existe Remote de adelantar hora ni de declarar victoria.

## Lobby y roster

`SessionConfig`: MinPlayers=1, MaxPlayers=4, LobbySeconds=30, ResultSeconds=15 (**decisión de spec** salvo máximo de lobby/capacidad aprobados). El contador empieza con el primer perfil cargado; empieza antes si todos los elegibles marcan Ready. Sin elegibles no corre. Ready es booleano reversible y no permite empezar con perfil pendiente. Fallo de carga se muestra y no crea perfil vacío que sobreescriba datos.

**Decisión de spec:** roster y factores se congelan al comenzar Día 1. Entradas tardías/reconexiones espectan hasta próxima run; salidas no recalculan HP, loot ni segunda oportunidad. Participantes conectados son los que cuentan para aniquilación; si ninguno queda, se cancela y limpia la run sin anunciar victoria ni una tercera derrota. Los que abandonan conservan estadísticas ya ganadas, nunca una victoria posterior. No hay botón de reset/reintento individual.

La salida marca al miembro como retirado para el resto de esa run: reconectar no recupera elegibilidad para objetivos, estadísticas ni rescate. El roster inicial se conserva para escalado, mientras la lista de participantes elegibles excluye retirados. En los demás documentos «participante conectado» significa además no retirado; un espectador por muerte sí conserva elegibilidad.

## Reloj y NightsConfig

`src/shared/config/NightsConfig.luau`: `DaySeconds=270`, `FirstDaySeconds=360`, `DuskSeconds=45`, `DawnSeconds=15`, `MaxNights=5`. Secuencia Lobby → Día 1 → Atardecer 1 → Noche 1 → Amanecer 1 → Día 2 ... → Amanecer 5 (inicio del día 6) → resultado. Si hay rescate temprano no se generan días restantes. Amanecer es fase de 15 s de presentación: resultado se fija al entrar, luego se muestra pantalla final; si continúa la run, reaparece al entrar y comienza el próximo día tras esos 15 s.

Tabla aprobada del GDD §3, duraciones expresadas en segundos para config:

| Campo | Noche 1 | Noche 2 | Noche 3 | Noche 4 | Noche 5 |
|---|---:|---:|---:|---:|---:|
| `DurationSeconds` | 240 | 270 | 300 | 330 | 360 |
| `MainCreatureCount` | 1 | 1 | 1 | 1 | 1 |
| `MaxStalkers` | 0 | 0 | 2 | 3 | 4 |
| `BreakWalls` | No | Sí, lento | Sí | Sí, rápido | Sí, rápido |
| `BaseAttacks` | Ninguno, ronda | 1 asedio | 2 asedios | 2 largos | Constante |
| `VisibilityStuds` (aprox.) | 120 | 100 | 80 | 60 | 45 |
| `DetectionMultiplier` | 1.0 | 1.1 | 1.25 | 1.4 | 1.6 |
| `CampfireConsumption` | 1.0 | 1.0 | 1.25 | 1.5 | 1.5 |
| `SafeRadiusStuds` | 12 | 10 | 8 | 6 | 0 |
| `StalkersExtinguish` | No | No | Sí | Sí | Sí |

`BreakWalls` guarda capacidad y perfil Slow/Normal/Fast; EnemiesConfig/F4 fija los daños/cadencias correspondientes. VisibilityStuds es objetivo visual, no sustituto del raycast de percepción. PresentationConfig traduce a presets Lighting/Atmosphere tras playtest; no se inventa un valor de densidad equivalente exacto.

| Roster inicial | Factor MaxStalkers | Factor HP Pared/Marco | Factor recursos/golpe |
|---|---:|---:|---:|
| 1 | 0.5 | 1.25 | 1.5 |
| 2 | 0.75 | 1.0 | 1.2 |
| 3 | 1.0 | 1.0 | 1.0 |
| 4 | 1.0 | 1.0 | 1.0 |

**Decisión de spec:** redondear menores hacia abajo para todos los tamaños; caps efectivos noches 3/4/5: solo 1/1/2, dúo 1/2/3, tres/cuatro 2/3/4. Nunca escalar la criatura principal ni multiplicar caps durante frenesí.

**Rediseño en dos actos (2026-11-27):** la tabla no cambia. `MaxStalkers` sigue siendo el tope global de acechadores vivos; nacen en el territorio avanzado ([mapa](mapa.md) 6.1) y solo pueden llegar a la base si el puente está construido (`BridgeBuilt`). El director no lee el puente ni ajusta su agenda por él: si el puente sigue roto, un Peak con acechadores solo afecta a quien esté al norte del río. La criatura principal cruza a nado en cualquier noche. No hay tiempos ligados al puente. Fijar HP al construir con factor congelado, no curar al cambiar noche. Producción usa residuos según inventario; no redondear 1.2 a 1 cada golpe.

## Director simple

Publica contrato interno `DirectorContext` con `runId`, `night`, `mode` (BuildUp/Peak/Rest/Frenzy), `endsAt`, `canBreakWalls`, `attackProfile`, `maxStalkers`, `preferWeakestWall`, `preferIsolatedPlayer`. Es una agenda temporal del servidor, no estados de cada enemigo. F4-2 decidirá cómo AIService ejecuta órdenes, navegación y percepción.

**Decisión de spec:** descansos base de 50 s, dentro de los 45–60 s del GDD. Agenda inicial en `NightsConfig.Director`, offsets desde inicio de Noche:

| Noche | Agenda normal, en segundos |
|---|---|
| 1 | BuildUp 0–80, Rest 80–130, BuildUp 130–190, Rest 190–240; sin Peak de asedio |
| 2 | BuildUp 0–60, Peak 60–120, Rest 120–170, BuildUp 170–270 |
| 3 | BuildUp 0–45, Peak 45–95, Rest 95–145, BuildUp 145–190, Peak 190–240, Rest 240–300 |
| 4 | BuildUp 0–40, Peak 40–120, Rest 120–170, BuildUp 170–200, Peak 200–280, Rest 280–330 |
| 5 | BuildUp 0–30, Peak 30–360 |

Tras una caída fuera de frenesí, fuerza Rest al menos 50 s (puede terminar antes por amanecer); entradas de agenda vencidas se saltan, nunca se comprimen para recuperar ataques. En noche 5, «constante» significa Peak sin descansos programados, pero conserva ese respiro reactivo aprobado. La cuota de asedios es máxima si la noche fue interrumpida por caídas. `preferWeakestWall` y `preferIsolatedPlayer` se activan desde noche 4; el director no busca rutas ni elige blancos individuales.

Transmitir activa Frenzy, incluso mientras esté pausada por golpe; termina al amanecer/final. **Decisión de spec:** Frenzy suspende descansos y cuota de asedios; conserva cantidad de enemigos, safe radius y protección de noche 1. En noche 1 puede haber presión sobre la radio y pausas por golpe, pero no rotura de paredes ni muerte individual. La IA debe seguir dando aviso previo al ataque; F4-1/F4-2 define señales, sin bypass por frenesí.

De día no hay caza normal; la excepción del nido (sótanos del complejo científico) se comunica por StimulusService (F4 determina despertar/retorno). Desde día 3 se activan marcadores de rastros y desde día 4 un avistamiento visual sin ataque: `NightsConfig.DayTracesFrom=3`, `DaySightingsFrom=4`; ubicación y assets en World/PresentationConfig. No se crea una segunda criatura para el avistamiento.

## Resolución terminal

1. Durante Noche, si todos los participantes conectados están Downed/Spectating, declarar `Annihilation`, salvo reserva de auto-revive solo activa (ver jugador). La noche 1 no suspende esta condición.
2. Al alcanzar fin de Noche, procesar progreso de transmisión hasta ese instante. Si completada y existe Alive (o reserva solo protegida que se resuelve al amanecer), `Rescued`. Caídos/espectadores del roster conectado también se rescatan.
3. Si no se rescató y termina Noche 5, `OutOfTime`; no hay Día 6 jugable.
4. Si no es terminal, Amanecer levanta/reaparece jugadores y continúa siguiente ciclo. La transmisión incompleta se pausa y conserva acumulado; necesita reanudarse otra noche (ver objetivos).

Una finalización atómica por runId impide doble victoria/derrota. Alive se evalúa antes del respawn; matar al último jugador justo antes de amanecer no se oculta con respawn. Salir de partida cancela reservas y reevalúa aniquilación nocturna. Resultado se replica con causa, noche, duración, estadísticas y estado del guardado, nunca con estadísticas proporcionadas por cliente.

## Pruebas futuras en Studio

Con reloj acelerado solo mediante configuración/harness servidor de prueba (no Remote de producción), recorrer cinco ciclos, frontera exacta de transmisión y amanecer, derrota de último jugador, rescate temprano y noche 5 sin señal. Probar roster 1–4, desconexiones y entrada tardía. Registrar agenda, descanso tras caída y frenesí; comparar cada valor con tabla aprobada. La suma de fases completa es 54 min incluidos cinco amaneceres, antes de lobby/pantalla final.
