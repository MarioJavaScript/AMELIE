# Construcción — F0-3

Base: GDD §§3, 5, 6 y plan F3. BuildingService decide colocación, HP, puertas, combustible y reparación. BuildPreviewController solo propone y muestra. Todos los valores de esta spec viven en `src/shared/config/StructuresConfig.luau`, salvo referencias explícitas a otros configs; lo añadido al GDD/plan es **decisión de spec**.

## Las cuatro piezas

| StructureId / prefab | Dimensiones/collider nominal | Costo | HP base | Reparación por acción |
|---|---|---|---:|---|
| `Cimiento` | 8×1×8 studs | 6 Madera + 4 Piedra | 300 | 2 Madera + 1 Piedra: +75 HP |
| `Pared` | 8×8×1 studs | 6 Madera | 200 | 2 Madera: +50 HP |
| `MarcoPuerta` | Envolvente 8×8×1; apertura en prefab | 8 Madera + 2 Chatarra | 200 | 2 Madera + 1 Chatarra: +50 HP |
| `Fogata` | 4×2×4 studs | 6 Madera + 6 Piedra | 150 | 2 Madera + 1 Piedra: +50 HP |

HP máximo de Pared y MarcoPuerta usa factor de paredes de NightsConfig según roster, redondeo al entero más cercano. Cimiento/Fogata no escalan. MarcoPuerta incluye hoja, bisagra y colisionadores authorados; servidor mueve la hoja anclada entre dos poses predefinidas con transición 0.4 s, evitando autoridad física cliente. Nunca se genera una puerta por piezas en código. Interacción abre/cierra y rechaza cierre si el hueco tiene un personaje o un enemigo (consulta espacial servidor, F0-4).

Estructuras son del grupo, sin propiedad privada. No hay desmontaje, devolución, techos, segundo piso ni reparación por cliente. Máximo 120 estructuras por run. HP y máximo se replican; cliente dibuja barras/grietas. A 0 HP se destruye Pared/MarcoPuerta; Cimiento se destruye junto a sus dependientes, sin devolver materiales. Destrucción libera sockets en la misma transacción. Fogata conserva su estructura apagada/rota (ver abajo).

## Prefabs, grid y preview

Prefabs residen en ServerStorage/Prefabs y tienen pivote, hitboxes y Attachments. Cimiento tiene `EdgeN`, `EdgeE`, `EdgeS`, `EdgeW` en centro de sus bordes superiores; Pared/MarcoPuerta tienen `BottomCenter`. Fogata tiene pivote de suelo y socket de combustible visual. World valida estas convenciones antes de habilitar construir. Cimiento pivota en centro de cara superior; esto alinea BottomCenter exactamente con el borde. Las dimensiones son volúmenes de validación, no solo bounds artísticos.

- Raycast preview máximo 15 studs desde cámara, confirma también alcance máximo 15 desde jugador validado en servidor.
- Grid de cimientos: 8 studs en X/Z relativo al origen de `BuildZone`; yaw 0/90/180/270°. En MVP solo terreno plano autorizado, pendiente máxima 5°, cota única del BuildZone y soporte comprobado en cuatro esquinas, tolerancia vertical 0.25 studs.
- Pared/MarcoPuerta: solo un socket Edge de cimiento registrado, orientación derivada de ese borde, sin rotación libre; un borde compartido entre cimientos vecinos es una única arista canónica y no permite dos paredes.
- Fogata: solo `CampfireSocket` fijo de la base, una por run. **Decisión de spec:** no hay fogatas secundarias para evitar zonas seguras apiladas. La principal se construye por el grupo y comienza apagada, sin combustible.
- Preview verde/rojo es orientativo. Cliente calcula propuesta y usa copia visual saneada del prefab; servidor recalcula transform completo. No se acepta un CFrame arbitrario.

`PlaceStructure` propone `{pieceId, gridX, gridZ, quarterTurns}` para cimiento, `{pieceId, parentId, socketId}` para pared/marco o `{pieceId="Fogata"}`. Grid acotado por BuildZones. No existen otras variantes.

## Validación y commit

1. Envolvente de Remote válida, cooldown, Alive, manos libres, sin interacción y run activa.
2. ID en catálogo, parámetros enteros dentro de límites, parent existente de la misma run, socket libre, cap total y singleton de fogata.
3. Servidor deriva pose desde marcadores/grid; comprueba alcance 15, LOS al punto de colocación, terreno, soporte y volumen contenido en BuildZone. Rechaza intersección con NoBuildZones: radio, accesos, spawns, piezas, corredores de objetivos. Margen protegido 4 studs en torno a pickups/spawns y radio en WorldConfig; caseta mantiene entradas mediante volúmenes Studio.
4. Solapamiento con `GetPartsInPart` usando hitboxes del prefab; excluir preview, marcadores y solo contactos legítimos con soporte/socket. Reducir hitbox de consulta 0.02 studs evita rechazar caras adyacentes, pero no ignorar todo el padre ni geometría real que invada. Nunca colocar encima de personajes, loot, otra estructura o enemigo.
5. Comprobar materiales; reservar celda/socket; clonar prefab, fijar HP/ID/runId, parentar y consumir materiales como una transacción sin yield. Fallo revierte. Revalidar colisión al commit. Liberar reserva y publicar resultado.

Todas las partes autoritativas ancladas. Cliente no elige Health, costo, dueño, prefab path ni radio seguro.

## Reparación y fogata

`RepairStructure`: hold 2 s, rango 8, LOS, Alive y manos libres. Solo HP faltante, consume costo completo y cura hasta máximo; si ya está llena al terminar, no consume. Ruido 45 studs. No reconstruye piezas destruidas. Puede reparar fogata a 0 HP y dejarla apagada. Daño cancela reparación si lo recibe el reparador; cambios de HP del objetivo se revalidan al finalizar.

`FuelCampfire`: hold 1 s, consume exactamente 1 Madera y añade 30 s de combustible base; capacidad 180 s, rechazar si quedan menos de 30 s libres (sin desperdicio parcial). El combustible es unidad abstracta en segundos base: durante Noche se drena por el multiplicador de NightsConfig, fuera de Noche x1. Apagada no consume. Umbral de llama baja 30 s; visual deriva del servidor.

`IgniteCampfire`: requiere HP>0 y combustible>0, hold 5 s aprobado, manos libres, rango 8, emite ruido de encendido de 45 studs (StimuliConfig, **decisión de spec**). No genera madera. Los jugadores **no pueden apagar la fogata** en el MVP: la acción `ExtinguishCampfire` se retiró en F0-4 porque permitía a un jugador malicioso mantenerla apagada toda la noche (1 s para apagar contra 5 s para encender) y provocar la aniquilación; el GDD no la pide. **[pendiente de aprobar por Mario]** Un acechador autorizado desde noche 3 puede llamar `ExtinguishByEnemy` al contacto validado (alcance 4 studs, StructuresConfig); no destruye el modelo. A 0 HP por daño también se apaga y exige reparar antes de encender. Perder fogata nunca derrota.

Solo encendida y HP>0 registra luz, regeneración y zona segura. Radio seguro 12/10/8/6/0 desde NightsConfig; la curación usa su propio radio de 8 y continúa en noche 5. Estos radios no permiten bloquear daño mediante una propiedad del cliente. Fogata y radio se excluyen de propagación de destrucción de cimientos (se apoyan en terreno fijo).

## Puente (spec, implementación en Fase 3)

Estructura de mundo única, fuera del grid y de las 4 piezas: reconstruye el tramo central del puente volado entre los dos territorios ([mapa](mapa.md) 2.2). No cuenta para el máximo de 120 estructuras, no tiene HP en MVP y la IA no lo destruye.

- **Dónde:** solo en `Markers/BridgeSite` (`BridgeId = "Principal"`, `Segments = 3`). No usa `PlaceStructure` ni BuildZones; la Fase 3 añade una acción propia (`BuildBridgeSegment`, Remote a declarar entonces) con validación de servidor: Alive, manos libres, alcance 8 al borde activo (`BridgeEnds/Sur` o el último tramo hecho), LOS, cooldown y materiales.
- **Tramos:** 3, en orden desde la orilla sur. Cada tramo: hold de 5 s, ruido `BuildRepair` (45 studs) al inicio y cada segundo válido. Sin tramos parciales en el centro: el tramo 2 exige el 1, el 3 exige el 2. Varios jugadores no pueden construir el mismo tramo a la vez (reserva `bridge:<n>`).
- **Coste propuesto por tramo:** 10 Madera + 6 Piedra + 3 Chatarra (total 30 + 18 + 9). Está pensado para que el puente caiga hacia el día 3 con los recursos del acto 1 (88 de los 110 nodos están al sur del río) y la chatarra de la ciudad y la mina. Se ajusta en playtest; va en `StructuresConfig.Bridge`.
- **Resultado:** con el tramo 3 hecho, el servidor activa la variante construida (`BridgeBuilt = true`), la misma función que usa el comando de debug de Studio (objetivos.md). Antes de eso, los tramos 1 y 2 son visibles pero el hueco restante no se puede saltar.
- **Efectos de diseño:** el puente abre el acto 2 y deja pasar a los acechadores (GDD 2.0). No cambia la curva de noches.
- Se reinicia a roto en cada run. No se guarda en datos meta.

## Pruebas futuras en Studio

Verificar medidas y Attachments, snapping en bordes compartidos, rechazo de cimientos flotantes/pendientes, ocupación simultánea del mismo socket, cap, materiales insuficientes y construcción desde detrás de paredes. Comprobar HP escalado solo en paredes/marcos, puerta sin aplastar, reparación a full sin cobrar, destrucción de soportes, combustible máximo, apagado enemigo y reencendido en 5 s. Cerrar una puerta con un enemigo en el hueco debe rechazarse. Preview verde nunca obliga al servidor a aceptar.
