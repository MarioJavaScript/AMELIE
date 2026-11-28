# Recolección, inventario, crafteo y consumibles — F0-3 (revisión F2, 2026-11-27)

Base: GDD §§1 (hambre), 2, 3, 6; plan F2. InventoryService es el único escritor de cantidades y dueño del crafteo. ResourceService decide nodos, impactos, contenedores y loot. PlayerService aplica efectos de consumibles y el hambre. El cliente muestra herramientas, animaciones, cantidades y recetas confirmadas. Los valores no definidos en GDD/plan son **decisión de spec**.

## ItemsConfig y RecipesConfig (data-driven)

Regla F2: **añadir un ítem o una receta que use mecánicas existentes es solo editar config**. Ningún servicio ni la UI tiene listas de ítems escritas a mano; los recorren desde `ItemsConfig.Items` y `RecipesConfig.Recipes`. `ItemId` en tipos es `string` validado contra `ItemsConfig` en servidor.

Definición de ítem (`ItemsConfig.Items[<ItemId>]`):

| Campo | Tipo | Notas |
|---|---|---|
| `Id` | string | Igual a la clave |
| `DisplayName` | string | Texto de UI |
| `Kind` | "Material" \| "Consumable" \| "Tool" | |
| `MaxStack` | number | |
| `Equippable` | boolean | true solo en herramientas |
| `IconKey` | string | Clave de icono en PresentationConfig (greybox: color + letras) |
| `Order` | number | Orden en UI |
| `Tool` | `{ResourceKinds: {string}, Damage: number, Yield: number, HitCooldownSeconds: number}?` | Solo herramientas. `ResourceKinds` son `NodeKind` que puede recolectar |
| `Use` | `{HoldSeconds: number, Health: number?, Hunger: number?, Battery: number?, CancelOnDamage: boolean}?` | Solo consumibles usables. Ver [jugador](jugador.md) |

| ItemId | Tipo | MaxStack | Uso |
|---|---|---:|---|
| `Madera` | Material | 50 | Herramientas, estructuras, combustible, reparación, vendas |
| `Piedra` | Material | 50 | Herramientas, cimiento y fogata |
| `Chatarra` | Material | 20 | MarcoPuerta, reparación de marco, botiquín, puente (Fase 3) |
| `Pila` | Consumable | 5 | `Use`: 2 s, +50 batería |
| `Venda` | Consumable | 10 | `Use`: 2 s, +35 HP, no se interrumpe por daño |
| `Botiquin` | Consumable | 3 | `Use`: 6 s, +80 HP, se interrumpe por daño |
| `Lata` | Consumable | 5 | `Use`: 2 s, +40 hambre |
| `Baya` | Consumable | 20 | `Use`: 0.5 s, +8 hambre |
| `Hacha` | Tool | 1 | `ResourceKinds = {"Arbol"}`, daño 10, producción 2, cooldown 0.8 s. Sin durabilidad en MVP |
| `Pico` | Tool | 1 | `ResourceKinds = {"Roca"}`, daño 10, producción 2, cooldown 1 s. Sin durabilidad en MVP |

`ItemsConfig.InventorySlots = 12`. Modelo: vector de 12 slots `{itemId, count}` o vacío; herramientas con count = 1. Entrada: primero completa stacks existentes, luego el primer slot libre. Sin peso, orden manual, descarte ni comercio en MVP. Las piezas de objetivo no ocupan slots (manos en ObjectiveService).

| RecipeId (`RecipesConfig.Recipes`) | Ingredientes | Salida |
|---|---|---|
| `Hacha` | 2 Madera + 2 Piedra | 1 Hacha |
| `Pico` | 2 Madera + 2 Piedra | 1 Pico |
| `Venda` | 3 Madera | 1 Venda |
| `Botiquin` | 2 Venda + 1 Chatarra | 1 Botiquin |

Receta: `{Id, Inputs: {[ItemId]: number}, Output: {ItemId: string, Count: number}, Order}`.

**Decisión de spec:** crafteo rápido instantáneo con `CraftItem {recipeId, count}`, count entero 1..5 (`RecipesConfig.MaxBatch`), cooldown 0.5 s. Solo Alive, manos libres y sin otra interacción; en cualquier lugar de la run. Simular consumo y espacio de salida sobre una copia (los huecos liberados por ingredientes cuentan), luego commit completo; si falta algo, no consume nada (`InsufficientItems` o `InventoryFull`). Sin ruido de crafteo. Hacha/Pico no dañan jugadores ni enemigos.

## Equipar

`EquipTool {slot}`: 0 desequipa; 1..12 debe contener un ítem con `Equippable = true`. El servidor guarda `equippedSlot`; si ese slot cambia de contenido (consumo, muerte), se desequipa. Cargar una pieza desequipa. El modelo visible en la mano lo suelda el servidor para todos (ver [jugador](jugador.md), «Herramienta en la mano»); el servidor nunca lee su posición.

## Nodos y golpe

### Contrato oficial de prefabs de nodo

Los prefabs de nodo viven en `ServerStorage/Prefabs` y los construye `tools/map/PrefabBuilder.luau`. Contrato (WorldService/ResourceService lo validan al empezar la run; si falla, error con el path y la run no arranca):

- `Model` con nombre igual a su `NodeKind` (`Arbol`, `Roca`, `Arbusto`).
- Atributo `NodeKind` (string) en el Model, igual al nombre y a una clave de `ResourcesConfig.Nodes`.
- `PrimaryPart` = Part `Base`, con la cara inferior en el suelo: el pivote del clon se pone en la posición del marcador.
- Part hija **`Hitbox`**: `Anchored = true`, `CanQuery = true`, `CanTouch = false`. Es la única parte que cuenta para el alcance (punto más cercano de la Hitbox a la posición validada) y el destino del raycast de LOS. `CanCollide`: `true` en Arbol y Roca, `false` en Arbusto.
- El resto de partes visuales: `CanQuery = false`, `CanTouch = false` (no bloquean el LOS hacia su propio nodo ni hacia otros).
- Sin Scripts.

Medidas actuales (greybox): Arbol Hitbox 2 x 12 x 2 (tronco); Roca Hitbox 5 x 4 x 5; Arbusto Hitbox 4 x 3 x 4.

### Nodos en runtime

Al empezar la run, ResourceService clona un prefab por cada marcador `ResourceSpawns/<Kind>_NNN` (el atributo `Kind` del marcador es el `NodeKind`) dentro de `Workspace/Runtime/Resources`, anclado. Cada clon lleva atributos de servidor: `ResourceId` (opaco, único en la run), `NodeKind`, `HP`, `MaxHP`, `Active` (boolean). El `targetId` de `HitResource` es el `ResourceId`; se resuelve solo en el registry del servidor, nunca por nombre o path. Los nodos no regeneran durante la run; al empezar otra se reconstruyen.

| `ResourcesConfig.Nodes[<NodeKind>]` | Arbol | Roca | Arbusto |
|---|---:|---:|---:|
| `MaxHealth` | 50 | 60 | 15 |
| `OutputItem` | Madera | Piedra | Baya |
| `HandOnly` | false | false | true |
| `NoiseKind` | ResourceHit (50) | ResourceHit (50) | Forage (15) |
| Mano vacía: daño / producción / cooldown | 5 / 1 / 1.2 s | 5 / 1 / 1.2 s | 5 / 1 / 1.2 s |

- Herramienta equipada cuyo `Tool.ResourceKinds` contiene el `NodeKind`: usa daño, producción y cooldown de la herramienta.
- Mano vacía: usa `ResourcesConfig.BareHand`.
- Herramienta equipada que no sirve para ese nodo: se rechaza (`WrongTool`), salvo en nodos `HandOnly`, donde cualquier herramienta cuenta como mano vacía.
- Un arbusto da 3 bayas en 3 golpes a mano (más escalado por roster).

**Decisión de spec:** extracción lenta a mano permitida para no bloquear tras perder herramientas. El servidor deriva herramienta y modo, no los recibe en `HitResource`. Cooldown por jugador con la tolerancia sin acumulación de [remotes](remotes.md). Alcance máximo 10 studs (`ResourcesConfig.HitRangeStuds`) desde la posición validada hasta el punto más cercano de la Hitbox; raycast LOS hacia ese punto que excluye el modelo del propio nodo y no atraviesa paredes ni terreno. Nodo activo, run actual, Alive y manos libres. Si se rechaza: ni daño, ni ruido, ni cooldown de gameplay (sí consume rate limit de red).

Producción: se entrega por golpe aceptado, incluido el último; sin bonus final. Escalado por roster con `NightsConfig.Scaling[n].ResourceYieldFactor`; para no perder decimales, residuo por jugador y material: `bruto = base * factor + residuo`, se entrega la parte entera y se guarda la fracción (solo en la run, se borra al morir). Si los enteros de ese golpe no caben, se rechaza (`InventoryFull`) sin dañar el nodo. Al llegar a HP 0 el nodo se desactiva una sola vez (`Active = false`), se emite `ResourceDepleted` y el modelo se destruye; dos impactos en el mismo tick no dan dos recompensas finales.

Ruido: `ResourceService` emite el `NoiseKind` del nodo en la posición del nodo mediante StimulusService. Feedback `ResourceHit` a los jugadores cercanos. La animación del cliente puede empezar antes; los cambios de HP e inventario esperan al servidor.

## Loot: contenedores, lotes y mochila

Cada marcador `LootSpawns/<ZoneId>_NN` recibe al empezar la run un clon del prefab `Contenedor` (caja greybox, contrato igual que los nodos: `PrimaryPart` `Base`, Part `Hitbox` con `CanQuery = true`) en `Workspace/Runtime/Containers`, con atributos `ContainerId` y `Open = false`. El contenido es una tabla de config por zona; no escala con roster ni respawnea.

`ResourcesConfig.LootTables[<ZoneId>]` = lista ordenada de contenidos, uno por contenedor (`_01`, `_02`, `_03`), más `OpenNoiseKind` opcional:

| ZoneId | _01 | _02 | _03 | Ruido al abrir |
|---|---|---|---|---|
| Base | 2 Pila | - | - | - |
| Ciudad | 1 Pila, 2 Chatarra, 1 Lata | 1 Pila, 2 Chatarra, 1 Lata | 1 Pila, 2 Chatarra, 1 Lata | MetalOpen (30) |
| Mina | 1 Pila, 2 Chatarra | 1 Pila, 2 Chatarra, 1 Venda | 1 Pila, 2 Chatarra | - |
| Industrial | 1 Pila, 2 Chatarra, 1 Lata | 1 Pila, 2 Chatarra, 1 Lata | 1 Pila, 2 Chatarra, 1 Lata | MetalOpen (30) |
| Complejo | 1 Pila, 2 Chatarra, 1 Venda | 1 Pila, 2 Chatarra, 1 Botiquin | 1 Pila, 2 Chatarra, 1 Venda | MetalOpen (30) |

Se mantiene el total aprobado de 3 Pila y 6 Chatarra por zona de pieza y 2 Pila en la base. Las latas solo están en Ciudad e Industrial. Si falta un marcador o sobra uno respecto a la tabla, la run no arranca (error con el path).

Flujo:
1. `SearchContainer` (hold 1.5 s, rango 8, LOS, reserva `container:<ContainerId>`): abre el contenedor para todos (`Open = true`), emite su ruido y crea en ese commit un **lote** por cada stack, con id `<ContainerId>:<n>`. **F0-4:** antes de abrirse, el contenido no existe en Workspace ni en ningún snapshot.
2. `PickupLoot` (hold 0.25 s, reserva `loot:<loteId>`): transfiere el lote completo. Si no cabe entero, no se transfiere nada (`InventoryFull`) y queda en el contenedor.
3. Los lotes no son modelos sueltos: se ven en el contenedor abierto a través de `ContainerView` (`kind = "LootContainer"`, `open = true`, `stacks` con `slot = n`) en el snapshot de quien esté a ≤ 30 studs. El cliente usa `<ContainerId>:<slot>` como `targetId` de `PickupLoot`.

Mochila: contenedor distinto creado por muerte/desconexión, con todo el inventario. `LootBackpack`, hold 1 s: transfiere en orden estable lo que cabe, completando stacks, y deja el resto (transferencia parcial atómica). Se destruye vacía o al terminar la run. Nunca incluye piezas. Implementación de la mochila: con el ciclo de muerte (fuera de F2 si PlayerService aún no tiene Dead).

## Consumibles

`BeginInteraction {action = "UseItem", targetId = <ItemId>}`: reserva `self:<jugador>`, hold de `Use.HoldSeconds`, sin LOS ni rango. Al empezar: el ítem existe en el inventario, tiene `Use`, el jugador está Alive con manos libres y el efecto no se desperdicia entero (HP, hambre o batería por debajo del máximo según los campos de `Use`). Al completar: revalida, consume 1 y aplica el efecto en la misma operación. Cancela: moverse > 1.5 studs, caer, cambiar de run y, si `CancelOnDamage = true`, recibir daño de un enemigo. Valores y tabla en [jugador](jugador.md). Sustituye a las acciones `UseBandage` y `ReplaceBattery`.

## Contrato interno y consistencia

InventoryService:
- `CanApplyDelta(userId, delta): boolean`, `TryApplyDelta(userId, delta, reason): (boolean, ResultCode)`, `GetSnapshot(userId): {Stack}`, `GetEquipped(userId): ItemId?`, `Count(userId, itemId): number`, `Craft(userId, recipeId, count)`, `Equip(userId, slot)`, `ResetForRun()`, `GiveInitialKit(userId)`, `TakeAll(userId)` (para mochila).
- `delta` es `{[ItemId]: number}` (positivos entran, negativos salen); solo se construye en servidor; cantidades enteras no negativas tras el commit. Cada operación sube la revisión del jugador y registra `reason`.
- Reservar una acción no descuenta materiales; al completar se revalidan y consumen junto al efecto.

No hay DataStore por ítem. Cada cliente recibe solo su inventario (`SelfView.inventory`, slots ocupados, y `SelfView.equippedSlot`). Repetir un `requestId` no repite un craft ni un golpe (dedupe de [remotes](remotes.md)).

## Pendientes (fuera de F2)

- **Ruido de recolección:** `ResourceService` ya llama a `StimulusService.EmitNoise` con el `NoiseKind` del nodo y del contenedor, pero StimulusService es un stub. Se implementa en la Fase 4 (IA y estímulos).
- **Mochila al morir o desconectarse:** `InventoryService.TakeAll` está listo, pero falta el estado Dead y la creación de la mochila. Hoy el inventario se descarta al desconectar. Va con la tarea de caer/revivir.
- **Hambre por fases:** el hambre baja durante toda la run porque aún no hay ciclo de fases (DayNightService es stub). Se ajusta a Day/Dusk/Night/Dawn cuando exista el ciclo de partida, junto con caer/revivir.
- El `Fragmento` de la Roca no colisiona: aceptado.

## Pruebas en Studio

Talar y picar con y sin herramienta; herramienta equivocada (`WrongTool`); alcance 10 / 10.1; pared interpuesta; spam (cooldown); inventario lleno; dos clientes sobre el último HP; arbusto con hacha equipada (cuenta como mano). Abrir contenedor, ver sus lotes solo después, recoger con inventario lleno. Craftear hacha, pico, venda y botiquín; batch 0, 6, decimal y receta desconocida. Comer lata y baya, vendarse, usar botiquín y recibir daño durante el hold (cancela), usar con el máximo lleno (rechazo). Hambre en 0: sin regeneración de estamina, vida bajando hasta 10 y no más.
