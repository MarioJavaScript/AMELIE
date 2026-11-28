# Jugador — F0-3

Base: GDD §§1, 4–6. Contratos de red: [remotes](remotes.md). Servidor: PlayerService y servicios propietarios. Cliente: cámara, animación, input, HUD y espectador. Todos los valores siguientes que el GDD no fija son **decisión de spec**, con propietario `src/shared/config/PlayerConfig.luau` salvo indicación distinta.

## Cámara y movimiento

Primera persona durante juego; espectador puede seguir compañeros. Cámara y viewbobbing no afectan hitboxes. Config inicial: FOV 75°, bob amplitud 0.06 studs/frecuencia 8 Hz, reducción de movimiento opcional a amplitud 0. Agacharse baja offset visual 1 stud; en MVP no reduce la cápsula física ni permite atravesar huecos pequeños.

| Magnitud | Valor inicial |
|---|---:|
| Caminar / correr / agachado / arrastrarse | 12 / 20 / 6 / 2 studs/s |
| Caminar con antena | 8 studs/s |
| Estamina máxima | 100 |
| Gasto al correr moviéndose | 20/s |
| Regeneración | 15/s |
| Espera desde último gasto | 1.5 s (plan F1-3) |
| Umbral para volver a correr tras agotar | 20 |
| Salto | Deshabilitado en MVP; se usan rampas/escaleras de Studio |

`SetMovementMode` solicita Walk/Sprint/Crouch. El servidor deriva velocidad según vida, pieza y estamina; Sprint+Crouch no coexisten. Cargar pieza no pesada permite correr, pero no usar herramientas, construir ni acciones de inventario. Antena impide Sprint y escaleras (ver [objetivos](objetivos.md)). Escalar usa la velocidad Walk; pantano no modifica velocidad en MVP, sí ruido.

El cliente no envía estamina ni desplazamientos premiables. El servidor muestrea movimiento, limita desplazamiento horizontal según modo y tiempo y corrige a la última posición válida. `NetworkConfig`: muestreo 0.1 s, tolerancia de desplazamiento 3 studs, ventana 0.5 s; teleports de spawn/revive se registran como autorizados y reinician referencia. Acciones a distancia siempre usan posición validada y raycast servidor. La simulación física normal de Roblox no constituye autoridad de inventario.

### Validación de movimiento y posición validada (F0-4)

El personaje es el único ensamblaje cuya física simula el cliente (necesario para que el movimiento responda bien), así que cambiar `WalkSpeed` no basta. PlayerService mantiene por jugador una **posición validada**; todas las acciones con rango, LOS, sueltas de pieza, mochilas, ruido y percepción de IA usan esa posición, nunca la instantánea del `HumanoidRootPart`. En cada muestra (0.1 s) el servidor acepta la nueva posición solo si cumple todo lo siguiente; si no, devuelve el personaje a la última posición validada (anclando un instante y restaurando CFrame) y no la actualiza:

| Regla | Valor inicial (`NetworkConfig`) |
|---|---|
| Horizontal: distancia en la ventana ≤ velocidad permitida × ventana + tolerancia | ventana 0.5 s, tolerancia 3 studs |
| Gracia al bajar la velocidad permitida (se agota la estamina, se coge la antena, cae) | `SpeedDowngradeGraceSeconds = 0.3` con la velocidad anterior |
| Subida: ascenso por ventana ≤ `MaxClimbStudsPerSecond` × ventana + 1 stud | `MaxClimbStudsPerSecond = 12` (rampas y escaleras de Studio) |
| Suelo: raycast hacia abajo; sin suelo a ≤ `MaxHoverStuds` durante más de `MaxAirSeconds` y sin caer | `MaxHoverStuds = 6`, `MaxAirSeconds = 1.5` |
| Caída: descenso libre permitido, pero el desplazamiento horizontal sigue limitado | — |
| Sin atravesar: raycast entre la posición validada anterior y la nueva, a altura de cintura y de rodilla, contra geometría sólida (grupo de colisión del mapa, estructuras, puertas cerradas, radio) | Si choca, se corrige |
| Partes obligatorias: sin `HumanoidRootPart` o `Humanoid` válidos, el jugador no puede actuar hasta que el servidor recargue el personaje | — |

Salto deshabilitado en servidor y cliente (estado Jumping desactivado y altura de salto 0). Más de 5 correcciones en 10 s se registran en el log del servidor para revisión; no hay expulsión automática en MVP. Un Downed que se arrastra usa la velocidad de arrastre y las mismas reglas.

### Ciclo de vida del personaje de Roblox (F0-4)

- `Players.CharacterAutoLoads = false`. El servidor llama `LoadCharacter` solo al empezar la run, en la reaparición de Amanecer y en la recarga por pérdida inesperada (abajo). Nunca hay reaparición automática de Roblox.
- El cliente desactiva el botón de reinicio (`StarterGui:SetCore("ResetButtonCallback", false)`), reintentando hasta que el CoreGui esté listo.
- La vida del juego vive en PlayerService. El `Humanoid` del personaje no se usa como fuente de vida: `BreakJointsOnDeath = false`, `RequiresNeck = false` y el estado Dead desactivado en servidor y cliente.
- **Pérdida inesperada del personaje** (el Humanoid muere, se destruye la cabeza o el root, o el personaje desaparece): el servidor recarga el personaje en la última posición validada y conserva el estado vital y HP lógicos (Alive o Downed, mismo HP, mismo bleedout). No pasa a Dead, no crea mochila y no da vida llena. Así reiniciar o romper el personaje no aporta ninguna ventaja.
- Spectating no tiene personaje en el mapa: se destruye al pasar a Dead (después de soltar la pieza y crear la mochila con la posición validada). El espectador solo controla su cámara.

## Salud y curación

Máximo 100 HP, revive a 40 HP, respawn a 100. Humanoid no destruye personaje al llegar al estado Downed: PlayerService intercepta daño y controla estados; una muerte física imprevista se trata como pérdida inesperada del personaje (ver «Ciclo de vida del personaje de Roblox»), nunca con respawn automático de Roblox.

Consumibles (acción `BeginInteraction` con `action = "UseItem"` y `targetId = <ItemId>`, ver [remotes](remotes.md) y [recolección](recoleccion-inventario.md)). El servidor mide el hold, comprueba al final y consume 1 unidad junto al efecto. Solo sobre uno mismo, Alive y con manos libres. Interrumpir no consume. Ninguno revive ni sirve caído.

| Ítem | Hold | Efecto | Requisito | ¿Lo interrumpe recibir daño? |
|---|---:|---|---|---|
| `Venda` | 2 s | +35 HP | HP < máximo | No (rápida) |
| `Botiquin` | 6 s | +80 HP | HP < máximo | Sí |
| `Lata` | 2 s | +40 hambre | hambre < máximo | No |
| `Baya` | 0.5 s | +8 hambre | hambre < máximo | No |
| `Pila` | 2 s | +50 batería | batería < máximo | No |

**Decisión de spec:** los valores viven en `ItemsConfig.Items[<ItemId>].Use` (`HoldSeconds`, `Health`, `Hunger`, `Battery`, `CancelOnDamage`), no en PlayerConfig. Añadir un consumible con efectos existentes es solo config. `CancelOnDamage = false` es una excepción explícita a la regla común de cancelar por daño ([remotes](remotes.md)); moverse más de 1.5 studs sigue cancelando. Ningún efecto supera el máximo.

Fogata encendida regenera 2 HP/s dentro de 8 studs tras 5 s sin daño; solo Alive, no acumula varios fuegos, requiere línea de visión. Esos valores viven en `StructuresConfig.Fogata.Healing`. Sin regeneración pasiva adicional. Daño de enemigos se definirá en EnemiesConfig/F4; herramientas no hacen PvP. No hay daño por caída en MVP; salir de límites se trata como caída por entorno, no concede recursos.

## Hambre

Aprobada para el MVP (GDD sección 1). Valores en `PlayerConfig.Hunger`:

| Campo | Valor | Notas |
|---|---:|---|
| `Max` | 100 | |
| `Initial` | 100 | Al empezar la run |
| `RespawnValue` | 60 | Al reaparecer como Spectating al amanecer. Downed levantado y revivido conservan el suyo |
| `DrainPerSecond` | 0.0833 | 100 en 20 min. Baja en Day, Dusk, Night y Dawn mientras el jugador está Alive; no baja en Lobby, Result, Downed ni Spectating |
| `StarveDamagePerSecond` | 0.25 | Solo con hambre en 0 y Alive |
| `StarveHealthFloor` | 10 | El hambre no baja la vida por debajo de 10: nunca derriba por sí sola |

- Con hambre en 0 la estamina no se regenera (el gasto al correr sigue igual).
- Reloj de servidor, acumulado como la batería: no depende de ticks enteros ni del cliente.
- El daño por hambre no es daño de enemigo: no cancela interacciones (`CancelOnDamage`) ni reinicia el retraso de curación de la fogata. La fogata puede curar por encima del daño por hambre.
- Se replica solo al propio jugador en `SelfView.hunger` y `SelfView.maxHunger`.
- Noche 1 y excepciones de solo no cambian: como no derriba, no interactúa con ellas.

## Linterna

Linterna integrada no ocupa slot, no se pierde, puede encenderse cargando una pieza (montaje de pecho, **decisión de spec**). Batería máxima 100; inicial/respawn 50; consume 0.5/s encendida, calculado sobre el tiempo encendido acumulado con reloj servidor (encender y apagar rápido no evita el gasto, F0-4). A 0 se apaga en servidor. Una `Pila` restaura 50, cap 100; se usa con `UseItem` (2 s), requiere batería menor al máximo y manos libres. Se consume al finalizar y no recarga automáticamente. La pieza de radio `Bateria` no es una Pila de inventario.

Servidor mantiene on/off, carga y orientación validada de foco; cliente interpola HUD y dibuja la luz. El servidor no lee la intensidad de un SpotLight creado por cliente. Dirección, cono y alcance se exponen a StimulusService; parámetros ópticos en StimuliConfig. Al caer o morir se apaga; revivir no enciende automáticamente. Parpadeo de amenaza es visual y no evita consumo/detección, salvo futuros hechos explícitos de IA.

## Estado vital

`Alive → Downed → Alive` por revive o `Downed → Dead → Spectating → Alive` al amanecer. Dead es transición atómica que crea mochila y Spectating el estado estable posterior; no hay un frame jugable entre ambos. Inventario sigue en el jugador mientras Downed. La pieza de objetivo se suelta al caer, separada de la mochila.

- A 0 HP: Downed, gatea, no herramientas/objetivos/inventario; cámara monocroma y acción `Shout` (cooldown 5 s en StimuliConfig).
- Revivir: compañero Alive, manos libres, rango común de 8 studs, hold continuo 4 s. Una reserva por víctima; movimiento del revividor, daño al revividor, pérdida de rango/LOS o muerte de cualquiera cancelan. Mientras dura, el caído no puede arrastrarse (F0-4). Si el revive termina antes o a la vez que el bleedout, gana el revive (ver orden temporal en [remotes](remotes.md)). No requiere material. Ruido durante la acción.
- Bleedout a los 30 s desde caída. Un remate autorizado por IA puede matar antes. Al morir, todo inventario pasa atómicamente a una mochila persistente hasta fin de run; herramienta se desequipa. Compañeros pueden saquearla sin duplicar; el propietario no tiene prioridad especial.
- Amanecer: los Downed se levantan con 40 HP y conservan inventario; Spectating reaparece con 100 HP, linterna a 50 y cero ítems. No se repite kit inicial. Respawn ocurre después de evaluar victoria/derrota, nunca evita aniquilación previa.
- Desconexión: en un handler síncrono sin yield, cancela la interacción activa sin commit, libera reservas, suelta la pieza y crea la mochila con el inventario, ambas en la **posición validada** (no en la del personaje replicado, que un cliente modificado puede mover justo antes de salir), y borra el inventario en memoria. Regresar durante esa run deja al usuario espectando sin inventario (sin duplicar kit ni ítems).
- Caída o muerte con pieza: la pieza también se suelta en la posición validada, en la misma transacción que el cambio de estado.

## Excepciones y precedencia

**Decisión de spec — noche 1:** no bleedout ni remate, permanece Downed hasta revive/amanecer. Esto evita muertes individuales como pide el GDD; no elimina la derrota por todos caídos, que es una condición de run. En solo sigue aplicando la segunda oportunidad y una segunda caída pierde la run sin ejecutar una muerte individual. Esta precedencia también se aplica si se transmite en la noche 1.

**Decisión de spec — solo:** el modo solo se fija con roster inicial de 1. En cada entrada a Noche se dispone de 1 segunda oportunidad; también se refleja su recarga al amanecer. Primera caída nocturna la consume, suprime remate/bleedout y reserva auto-revive tras 10 s a 40 HP. Mientras la reserva esté activa, aniquilación se suspende. No hay inmunidad una vez levantado. Una segunda caída esa noche derrota inmediatamente. Si amanece antes de 10 s, se levanta en Amanecer y puede contar como rescatado por la excepción activa; es la única excepción al requisito de Alive previo a respawn. Un grupo de 2+ que queda con un conectado no obtiene este beneficio.

**Decisión de spec — peligro diurno:** caída de día/atardecer usa bleedout normal y no consume oportunidad nocturna. No se declara aniquilación diurna. Si todos siguen incapacitados al empezar Noche, se evalúa entonces la derrota; en solo Downed recibe la oportunidad de esa noche, pero Spectating ya muerto no. La mina puede así causar una derrota al alcanzar la noche sin añadir una tercera condición de derrota. No hay auto-revive diurno.

Durante final de run se bloquean daño e interacción. Participantes muertos o caídos también reciben rescate si se cumplió la condición del grupo. Espectadores que entraron tarde no son participantes ni reciben resultado meta.

## Kit inicial y pruebas futuras

`PlayerConfig.InitialItems`: 4 Madera y 4 Piedra por participante, linterna a 50, hambre a 100, sin herramienta (decisión de spec para poder fabricar hacha/pico). Recolección manual también garantiza recuperación tras perder herramientas.

En Studio: probar dos clientes, agotamiento y recuperación, crouch silencioso, bloqueo con antena, batería vacía y recambio cancelado; caer, revivir en 4 s y romper LOS; mochila única al rematar/desconectar; noche 1 sin muerte; en solo una oportunidad cada noche y segunda caída derrotando; día sin auto-revive y amanecer con inventario vacío del muerto. Intentar velocidad falsa y acción desde posición inválida no debe dar ventajas. Con cliente modificado: volar, atravesar una pared de la base o de la mina, teletransportarse y desconectarse con una pieza, reiniciar el personaje de noche y destruir el Humanoid; ninguno debe mover la posición validada, cambiar el estado vital ni restaurar vida.
